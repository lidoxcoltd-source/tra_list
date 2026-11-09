const test = require("node:test");
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { initializeApp, deleteApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const bi = require("./business_intelligence");
const { saveOwnerTransaction, parseTransactionCommand } = require("./business_ai_transaction");

test("owner transaction writes once, validates category and rejects lost access", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async () => {
  const app = initializeApp({ projectId: "demo-isher-transaction" }, randomUUID());
  const db = getFirestore(app);
  const uid = `owner-${randomUUID()}`;
  const businessUid = uid;
  const business = db.collection("users").doc(uid);
  const scope = bi.scopeFor({ uid, businessUid, profileExists: true });
  const text = "rekodi matumizi 30000; kundi: Kodi; maelezo: Kodi ya duka";
  const command = parseTransactionCommand(text);
  const messageId = randomUUID();
  const questionRef = db.doc(`businessAiHistory/${uid}/businesses/${uid}/scopes/test/messages/${messageId}`);
  const args = { db, uid, businessUid, scope, command, messageId, questionRef, questionText: text };
  try {
    await business.collection("profile").doc("company").set({ name: "Duka" });
    await business.collection("categories").doc("rent").set({ name: "Kodi", type: "expense" });
    await questionRef.set({ role: "user", content: text });
    await Promise.all([saveOwnerTransaction(args), saveOwnerTransaction(args)]);
    const records = await business.collection("transactions").get();
    assert.equal(records.size, 1);
    assert.equal(records.docs[0].get("amount"), 30000);
    assert.equal(records.docs[0].get("shopNickname"), "Duka");
    assert.equal(records.docs[0].get("type"), "expense");
    assert.ok(records.docs[0].get("date").toMillis() <= Date.now());
    await assert.rejects(
      saveOwnerTransaction({ ...args, command: { ...command, amount: 1 } }),
      (error) => error.code === "already-exists",
    );
    await assert.rejects(
      saveOwnerTransaction({ ...args, questionText: "different question" }),
      (error) => error.code === "failed-precondition",
    );
    const missingId = randomUUID();
    const missingQuestion = questionRef.parent.doc(missingId);
    await missingQuestion.set({ role: "user", content: text });
    await assert.rejects(
      saveOwnerTransaction({
        ...args, messageId: missingId, questionRef: missingQuestion,
        command: { ...command, category: "Missing" },
      }),
      (error) => error.code === "failed-precondition",
    );
    await assert.rejects(
      saveOwnerTransaction({
        ...args, messageId: missingId, questionRef: missingQuestion,
        command: { ...command, type: "income" },
      }),
      (error) => error.code === "failed-precondition",
    );
    await db.doc(`accountAccess/${uid}`).set({ disabled: true });
    await assert.rejects(saveOwnerTransaction(args), (error) => error.code === "permission-denied");
    assert.equal((await business.collection("transactions").get()).size, 1);
  } finally {
    await deleteApp(app);
  }
});
