const test = require("node:test");
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Run only with the Firestore emulator.");
process.env.OPENAI_API_KEY = "local-test-only";
const functions = require("./index");
const bi = require("./business_intelligence");
const history = require("./business_ai_history");
const { businessAccess } = require("./business_ai_access");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

test("amount and follow-up record exactly once without an AI provider call", async () => {
  const db = getFirestore();
  const uid = `owner-${randomUUID()}`;
  const business = db.collection("users").doc(uid);
  await business.collection("profile").doc("company").set({ name: "Duka" });
  await business.collection("categories").doc("rent").set({ name: "Kodi", type: "expense" });
  const { scope } = await businessAccess(db, uid, uid);
  const token = bi.signSnapshot({
    uid, businessUid: uid, scope, context: {}, expiresAt: Date.now() + 600000,
  }, process.env.OPENAI_API_KEY);
  const initial = { role: "user", content: "rekodi matumizi ya 30,000" };
  const initialRequest = { auth: { uid }, data: {
    businessUid: uid, token, language: "sw", messages: [initial],
  } };
  const prompt = await functions.askBusinessAiV2.run(initialRequest);
  assert.match(prompt.answer, /kundi na maelezo/);
  assert.equal((await business.collection("transactions").get()).size, 0);
  const last = { role: "user", content: "kundi: Kodi; maelezo: Kodi ya duka" };
  const messageId = randomUUID();
  const question = db.doc(`businessAiHistory/${uid}/businesses/${uid}/scopes/${history.historyScopeId(scope)}/messages/${messageId}`);
  await question.set({ role: "user", content: last.content });
  const request = { ...initialRequest, data: {
    ...initialRequest.data, messageId,
    messages: [initial, { role: "assistant", content: prompt.answer }, last],
  } };
  const beforeSave = Date.now();
  const result = await functions.askBusinessAiV2.run(request);
  const afterSave = Date.now();
  assert.match(result.answer, /30,000/);
  let records = await business.collection("transactions").get();
  assert.equal(records.size, 1);
  assert.equal(records.docs[0].get("amount"), 30000);
  assert.equal(records.docs[0].get("category"), "Kodi");
  const savedTime = records.docs[0].get("date").toMillis();
  assert.ok(savedTime >= beforeSave && savedTime <= afterSave);
  await functions.askBusinessAiV2.run(request);
  records = await business.collection("transactions").get();
  assert.equal(records.size, 1);
  assert.equal(records.docs[0].get("date").toMillis(), savedTime);
  await db.doc(`accountAccess/${uid}`).set({ disabled: true });
  await assert.rejects(functions.askBusinessAiV2.run(request), (error) => error.code === "permission-denied");
});

test("business snapshot includes owner transaction details and scopes staff to their shop", async () => {
  const db = getFirestore();
  const owner = `owner-${randomUUID()}`;
  const staff = `staff-${randomUUID()}`;
  const business = db.collection("users").doc(owner);
  const now = Date.now();
  await Promise.all([
    business.collection("profile").doc("company").set({ name: "Duka" }),
    business.collection("transactions").doc("main").set({
      type: "income", amount: 100, category: "Sales", description: "Rice sale",
      shopNickname: "Main", uid: "private-user", date: Timestamp.fromMillis(now - 1000),
    }),
    business.collection("transactions").doc("other").set({
      type: "expense", amount: 40, category: "Rent", description: "Other shop rent",
      shopNickname: "Other", uid: "private-user", date: Timestamp.fromMillis(now - 2000),
    }),
    business.collection("transactions").doc("outside").set({
      type: "income", amount: 999, description: "Outside period",
      shopNickname: "Main", date: Timestamp.fromMillis(now - 20000),
    }),
    db.doc(`businessMemberships/${owner}/members/${staff}`).set({
      businessUid: owner, employeeUid: staff, active: true, role: "employee",
      shopNickname: "Main", permissions: { analytics: { view: true } },
    }),
  ]);
  const request = (uid) => ({
    auth: { uid },
    data: { businessUid: owner, startMillis: now - 10000, endMillis: now + 1000 },
  });
  const ownerResult = await functions.prepareBusinessAiContextV2.run(request(owner));
  assert.equal(ownerResult.context.transactions.income, 100);
  assert.equal(ownerResult.context.transactions.expenses, 40);
  assert.equal(ownerResult.context.transactionDetails.total, 2);
  assert.equal(ownerResult.context.transactionDetails.truncated, false);
  assert.deepEqual(ownerResult.context.transactionDetails.entries.map((entry) => entry.description), ["Rice sale", "Other shop rent"]);
  assert.doesNotMatch(JSON.stringify(ownerResult.context.transactionDetails), /private-user|Outside period/);
  const ownerScope = (await businessAccess(db, owner, owner)).scope;
  assert.deepEqual(
    bi.verifySnapshot(ownerResult.token, process.env.OPENAI_API_KEY, owner, owner, ownerScope),
    ownerResult.context,
  );
  const staffResult = await functions.prepareBusinessAiContextV2.run(request(staff));
  assert.equal(staffResult.context.transactions.income, 100);
  assert.equal(staffResult.context.transactions.expenses, 0);
  assert.equal(staffResult.context.transactionDetails, undefined);
  assert.doesNotMatch(JSON.stringify(staffResult.context), /Rice sale|Other shop rent|Outside period/);
});

test("large transaction snapshots disclose truncated details and retain complete totals", async () => {
  const db = getFirestore();
  const owner = `owner-${randomUUID()}`;
  const business = db.collection("users").doc(owner);
  const now = Date.now();
  const batch = db.batch();
  batch.set(business.collection("profile").doc("company"), { name: "Duka" });
  for (let index = 0; index < 200; index++) {
    batch.set(business.collection("transactions").doc(`item-${index}`), {
      type: "income", amount: 100, category: "Sales", description: "x".repeat(300),
      shopNickname: "Main", date: Timestamp.fromMillis(now - index - 1),
    });
  }
  await batch.commit();
  const result = await functions.prepareBusinessAiContextV2.run({
    auth: { uid: owner },
    data: { businessUid: owner, startMillis: now - 10000, endMillis: now + 1000 },
  });
  assert.equal(result.context.transactions.income, 20000);
  assert.equal(result.context.transactions.count, 200);
  assert.equal(result.context.transactionDetails.total, 200);
  assert.equal(result.context.transactionDetails.truncated, true);
  assert.ok(result.context.transactionDetails.entries.length < 200);
  assert.match(result.context.limitations[0], /only the most recent records/);
  assert.ok(Buffer.byteLength(JSON.stringify(result.context)) <= bi.MAX_SNAPSHOT_BYTES);
});
