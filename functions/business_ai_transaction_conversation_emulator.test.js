const test = require("node:test");
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Run only with the Firestore emulator.");
process.env.OPENAI_API_KEY = "local-test-only";
const functions = require("./index");
const bi = require("./business_intelligence");
const history = require("./business_ai_history");
const { businessAccess } = require("./business_ai_access");
const { getFirestore } = require("firebase-admin/firestore");

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
