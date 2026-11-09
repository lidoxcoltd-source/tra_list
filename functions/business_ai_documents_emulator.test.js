const test = require("node:test");
const assert = require("node:assert/strict");

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Run only with the Firestore emulator.");
process.env.OPENAI_API_KEY = "local-test-only";
const functions = require("./index");
const bi = require("./business_intelligence");
const { businessAccess } = require("./business_ai_access");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

test("owner reviews scoped document data before the AI request", async () => {
  const db = getFirestore();
  const uid = "documents-owner";
  const other = "documents-other";
  const now = Date.now();
  await Promise.all([
    db.doc(`users/${uid}/profile/company`).set({ name: "Test" }),
    db.doc(`users/${other}/profile/company`).set({ name: "Other" }),
    db.doc(`users/${uid}/invoices/old`).set({
      kind: "invoice", invoice: { number: "INV-OLD" }, client: { name: "A", phone: "private" },
      createdAt: Timestamp.fromMillis(now - 200000),
    }),
    db.doc(`users/${uid}/invoices/new`).set({
      kind: "invoice", invoice: { number: "INV-NEW" }, client: { name: "B" },
      createdAt: Timestamp.fromMillis(now - 100000),
    }),
    db.doc(`users/${uid}/invoices/quote`).set({
      kind: "quotation", invoice: { number: "QUOTE" }, createdAt: Timestamp.fromMillis(now - 1000),
    }),
    db.doc(`users/${other}/invoices/foreign`).set({
      kind: "invoice", invoice: { number: "FOREIGN" }, createdAt: Timestamp.fromMillis(now),
    }),
    db.doc("receipts/customer").set({
      businessUid: uid, customer: { name: "B", mobile: "private" },
      meta: { receiptNo: "R1" }, createdAt: Timestamp.fromMillis(now - 1000),
    }),
  ]);
  const { scope } = await businessAccess(db, uid, uid);
  const context = {
    periodStart: new Date(now - 500000).toISOString(),
    periodEndExclusive: new Date(now + 1000).toISOString(),
    limitations: [],
  };
  const token = bi.signSnapshot({ uid, businessUid: uid, scope, context, expiresAt: now + 600000 }, process.env.OPENAI_API_KEY);
  const question = "nipe jina la invoice ya mwisho";
  const request = { auth: { uid }, data: { businessUid: uid, token, question } };
  const prepared = await functions.prepareBusinessAiDocuments.run(request);
  assert.equal(prepared.details.invoices.length, 1);
  assert.equal(prepared.details.invoices[0].number, "INV-NEW");
  assert.equal("clientName" in prepared.details.invoices[0], false);
  await assert.rejects(functions.prepareBusinessAiDocuments.run({
    ...request, data: { ...request.data, businessUid: other },
  }), (error) => error.code === "permission-denied");
  await assert.rejects(functions.prepareBusinessAiDocuments.run({
    ...request, auth: { uid: "stranger" },
  }), (error) => error.code === "permission-denied");
  const ask = (snapshot, text) => functions.askBusinessAiV2.run({
    auth: { uid }, data: { businessUid: uid, token: snapshot, messages: [{ role: "user", content: text }] },
  });
  await assert.rejects(ask(token, question), (error) => error.code === "failed-precondition");
  await assert.rejects(ask(prepared.token, "invoice ya jana"), (error) => error.code === "failed-precondition");
  const customer = await functions.prepareBusinessAiDocuments.run({
    ...request, data: { ...request.data, question: "historia ya wateja" },
  });
  assert.equal(customer.details.invoices.some((doc) => doc.clientName === "B"), true);
  assert.equal(customer.details.receipts[0].customerName, "B");
  assert.doesNotMatch(JSON.stringify(customer.details), /private|FOREIGN/);
  const originalFetch = global.fetch;
  let sent;
  global.fetch = async (_, options) => {
    sent = JSON.parse(options.body);
    return { ok: true, async json() { return { choices: [{ message: { content: "INV-NEW" } }] }; } };
  };
  try {
    const response = await ask(prepared.token, question);
    assert.equal(response.answer, "INV-NEW");
    assert.equal(sent.model, "gpt-4o-mini");
    assert.match(sent.messages[1].content, /INV-NEW/);
    assert.doesNotMatch(sent.messages[1].content, /QUOTE|FOREIGN|private/);
  } finally {
    global.fetch = originalFetch;
  }
  await db.doc(`accountAccess/${uid}`).set({ disabled: true });
  await assert.rejects(ask(prepared.token, question), (error) => error.code === "permission-denied");
});
