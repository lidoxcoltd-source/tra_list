const { createHash } = require("node:crypto");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { HttpsError, onCall } = require("firebase-functions/v2/https");

initializeApp();

const db = getFirestore();

exports.deleteMyAccount = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to delete your account.");
  }
  if (request.data?.confirm !== "DELETE") {
    throw new HttpsError("invalid-argument", "Deletion was not confirmed.");
  }
  // Require a fresh sign-in so a stolen session cannot delete the account.
  const authTime = request.auth.token.auth_time ?? 0;
  if (Date.now() / 1000 - authTime > 5 * 60) {
    throw new HttpsError(
      "failed-precondition",
      "Please sign in again before deleting your account.",
    );
  }

  const membershipRef = db.collection("employeeMemberships").doc(uid);
  const membership = await membershipRef.get();

  // A staff member only removes their own access; the business data stays.
  if (membership.exists) {
    await membershipRef.delete();
    await getAuth().deleteUser(uid);
    return { success: true, role: "staff" };
  }

  const company = await db.doc(`users/${uid}/profile/company`).get();
  const role = String(company.data()?.role ?? "").toLowerCase();
  if (["superadmin", "super_admin", "super-admin", "super admin"].includes(role)) {
    throw new HttpsError(
      "permission-denied",
      "Administrator accounts cannot be deleted here.",
    );
  }

  // Business owner: remove staff logins, business data, files, then the login.
  const staffSnap = await db
    .collection("employeeMemberships")
    .where("businessUid", "==", uid)
    .get();
  for (const staffDoc of staffSnap.docs) {
    try {
      await getAuth().deleteUser(staffDoc.id);
    } catch (error) {
      if (error.code !== "auth/user-not-found") throw error;
    }
    await staffDoc.ref.delete();
  }

  const receipts = await db
    .collection("receipts")
    .where("businessUid", "==", uid)
    .get();
  for (const receipt of receipts.docs) {
    await db.recursiveDelete(receipt.ref);
  }

  await db.recursiveDelete(db.doc(`users/${uid}`));
  await db.recursiveDelete(db.doc(`subscriptions/${uid}`));
  await db.recursiveDelete(db.doc(`accountAccess/${uid}`));
  await getStorage().bucket().deleteFiles({ prefix: `users/${uid}/` });
  await getAuth().deleteUser(uid);

  return { success: true, role: "owner" };
});

exports.updateStaffPassword = onCall(async (request) => {
  const ownerUid = request.auth?.uid;
  if (!ownerUid) {
    throw new HttpsError("unauthenticated", "Sign in to change staff passwords.");
  }

  const { employeeUid, newPassword } = request.data ?? {};
  if (typeof employeeUid !== "string" || employeeUid.length === 0) {
    throw new HttpsError("invalid-argument", "A staff account is required.");
  }
  if (employeeUid === ownerUid) {
    throw new HttpsError(
      "permission-denied",
      "Business owners cannot change their own password here.",
    );
  }
  if (typeof newPassword !== "string" || newPassword.length < 6) {
    throw new HttpsError(
      "invalid-argument",
      "The password must be at least 6 characters.",
    );
  }

  const ownerMembershipRef = db.collection("employeeMemberships").doc(ownerUid);
  const staffMembershipRef = db
    .collection("employeeMemberships")
    .doc(employeeUid);
  const accessRef = db.collection("accountAccess").doc(ownerUid);
  const [ownerMembership, staffMembership, accountAccess] = await Promise.all([
    ownerMembershipRef.get(),
    staffMembershipRef.get(),
    accessRef.get(),
  ]);

  if (ownerMembership.exists) {
    throw new HttpsError(
      "permission-denied",
      "Only the business owner can change staff passwords.",
    );
  }
  if (accountAccess.data()?.disabled === true) {
    throw new HttpsError(
      "permission-denied",
      "This business account is disabled.",
    );
  }

  const staffData = staffMembership.data();
  if (!staffMembership.exists || staffData.businessUid !== ownerUid) {
    throw new HttpsError(
      "not-found",
      "The staff account does not belong to this business.",
    );
  }

  let businessEmail =
    typeof staffData.businessEmail === "string"
      ? staffData.businessEmail.trim().toLowerCase()
      : "";
  if (!businessEmail) {
    const owner = await getAuth().getUser(ownerUid);
    businessEmail = owner.email?.trim().toLowerCase() ?? "";
  }
  if (!businessEmail) {
    throw new HttpsError(
      "failed-precondition",
      "The business owner account must have an email address.",
    );
  }

  const digest = createHash("sha256")
    .update(`${businessEmail}|${newPassword}`, "utf8")
    .digest("hex");
  const staffAuthEmail = `staff.${digest}@staff.tra-list.invalid`;

  await getAuth().updateUser(employeeUid, {
    email: staffAuthEmail,
    password: newPassword,
  });

  return { success: true };
});
