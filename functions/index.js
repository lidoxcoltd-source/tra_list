const { createHash } = require("node:crypto");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { getStorage } = require("firebase-admin/storage");
const { HttpsError, onCall } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const db = getFirestore();

async function sendToTokens(tokens, title, body, data, imageUrl) {
  let success = 0;
  let failure = 0;
  for (let i = 0; i < tokens.length; i += 500) {
    const chunk = tokens.slice(i, i + 500);
    const result = await getMessaging().sendEachForMulticast({
      tokens: chunk,
      notification: imageUrl ? { title, body, imageUrl } : { title, body },
      data,
      android: {
        priority: "high",
        notification: imageUrl
          ? { channelId: "default", imageUrl }
          : { channelId: "default" },
      },
    });
    success += result.successCount;
    failure += result.failureCount;
    // Drop tokens that are no longer valid.
    const stale = [];
    result.responses.forEach((r, idx) => {
      const code = r.error?.code;
      if (
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token"
      ) {
        stale.push(chunk[idx]);
      }
    });
    await Promise.all(
      stale.map((t) => db.collection("deviceTokens").doc(t).delete()),
    );
  }
  return { success, failure };
}

// users/{businessUid}/notifications/{id} -> push to the business owner's devices.
exports.pushStaffActivity = onDocumentCreated(
  "users/{businessUid}/notifications/{id}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const snap = await db
      .collection("deviceTokens")
      .where("uid", "==", event.params.businessUid)
      .get();
    const tokens = snap.docs.map((d) => d.id);
    if (!tokens.length) return;
    await sendToTokens(tokens, String(data.actorName || "Staff"), String(data.summary || ""), {
      type: "activity",
    });
  },
);

// Writes an in-app inbox item and pushes to the user's devices.
async function notifyUser(uid, body, taskId, kind) {
  await db.collection("userNotifications").doc(uid).collection("items").add({
    body,
    taskId,
    kind,
    read: false,
    createdAt: FieldValue.serverTimestamp(),
  });
  const snap = await db.collection("deviceTokens").where("uid", "==", uid).get();
  const tokens = snap.docs.map((d) => d.id);
  if (tokens.length) {
    await sendToTokens(tokens, "Kazi", body, { type: "task", taskId });
  }
}

// Task changes -> push to the assignee, or notify the owner via the activity feed.
exports.pushTaskChanges = onDocumentWritten(
  "users/{businessUid}/tasks/{taskId}",
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after) return;
    const { businessUid } = event.params;
    const title = String(after.title || "Task");

    let toAssignee = null;
    let toOwner = null;
    if (!before) {
      toAssignee = `Kazi mpya: ${title}`;
    } else if (before.status !== after.status) {
      if (after.status === "returned") toAssignee = `Kazi imerudishwa: ${title}`;
      else if (after.status === "approved") toAssignee = `Kazi imeidhinishwa: ${title}`;
      else if (after.status === "cancelled") toAssignee = `Kazi imeghairiwa: ${title}`;
      else if (after.status === "inProgress" && before.status === "assigned")
        toOwner = `Ameanza kazi: ${title}`;
      else if (after.status === "submitted") {
        const amt = after.collectedAmount;
        toOwner = `Amewasilisha kazi: ${title}` +
          (typeof amt === "number" ? ` (TZS ${amt})` : "");
      }
    } else if (
      before.dueDate?.toMillis?.() !== after.dueDate?.toMillis?.() &&
      after.status !== "approved" && after.status !== "cancelled"
    ) {
      toAssignee = `Muda wa kazi umebadilishwa: ${title}`;
    }

    if (toAssignee && after.assigneeUid) {
      await notifyUser(after.assigneeUid, toAssignee, event.params.taskId, "task");
    }
    if (toOwner) {
      // pushStaffActivity delivers this to the owner's devices.
      await db.collection("users").doc(businessUid).collection("notifications").add({
        actorUid: after.assigneeUid || "",
        actorName: String(after.assigneeName || "Staff"),
        action: "task",
        taskId: event.params.taskId,
        summary: toOwner,
        createdAt: FieldValue.serverTimestamp(),
        read: false,
      });
    }
  },
);

// Hourly: remind assignees (and the owner) about tasks past their deadline, once per deadline.
exports.notifyOverdueTasks = onSchedule("every 60 minutes", async () => {
  const now = Date.now();
  const snap = await db
    .collectionGroup("tasks")
    .where("dueDate", "<", Timestamp.fromMillis(now))
    .where("dueDate", ">", Timestamp.fromMillis(now - 14 * 24 * 3600 * 1000))
    .limit(500)
    .get();
  for (const doc of snap.docs) {
    const t = doc.data();
    if (!["assigned", "inProgress", "returned"].includes(t.status)) continue;
    const due = t.dueDate.toMillis();
    if (t.overdueNotifiedFor === due) continue;
    await doc.ref.update({ overdueNotifiedFor: due });
    const title = String(t.title || "Task");
    if (t.assigneeUid) {
      await notifyUser(t.assigneeUid, `Kazi imechelewa: ${title}`, doc.id, "overdue");
    }
    const businessUid = doc.ref.parent.parent.id;
    await db.collection("users").doc(businessUid).collection("notifications").add({
      actorUid: t.assigneeUid || "",
      actorName: String(t.assigneeName || "Staff"),
      action: "task",
      taskId: doc.id,
      summary: `Kazi imechelewa: ${title}`,
      createdAt: FieldValue.serverTimestamp(),
      read: false,
    });
  }
});

// Super Admin announcement -> push to every registered device.
exports.pushAnnouncement = onDocumentCreated("announcements/{id}", async (event) => {
  const data = event.data?.data();
  if (!data) return;
  const snap = await db.collection("deviceTokens").get();
  const tokens = snap.docs.map((d) => d.id);
  if (!tokens.length) {
    await event.data.ref.update({ sentCount: 0, failureCount: 0 });
    return;
  }
  const { success, failure } = await sendToTokens(
    tokens,
    String(data.title || "Mjasi POS"),
    String(data.body || ""),
    { type: "announcement" },
    data.imageUrl || undefined,
  );
  await event.data.ref.update({ sentCount: success, failureCount: failure });
});

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
