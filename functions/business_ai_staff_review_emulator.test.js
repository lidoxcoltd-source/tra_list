const test = require("node:test");
const assert = require("node:assert/strict");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error("Run only with the Firestore emulator.");
}
process.env.OPENAI_API_KEY = "local-test-only";
const functions = require("./index");
const { getFirestore } = require("firebase-admin/firestore");

test("owner review callables verify identity, selection, changes and revoked access", async () => {
  const db = getFirestore();
  const business = "review-test-business";
  const owner = business;
  const selection = [{ conversationId: "chat", messageId: "message", kind: "text" }];
  const message = db.doc(`users/${business}/chats/chat/messages/message`);
  await Promise.all([
    db.doc(`users/${business}/profile/company`).set({ name: "Test business" }),
    db.doc(`users/${business}/chats/chat`).set({ title: "Test chat" }),
    message.set({ text: "Sales discussion" }),
    db.doc(`users/other-business/profile/company`).set({ name: "Other" }),
  ]);
  const request = { auth: { uid: owner }, data: { businessUid: business, selection } };
  const prepared = await functions.prepareStaffAiReview.run(request);
  assert.equal(prepared.item.text, "Sales discussion");
  assert.equal(typeof prepared.token, "string");
  await assert.rejects(functions.prepareStaffAiReview.run({
    ...request, auth: { uid: "staff" },
  }), (error) => error.code === "permission-denied");
  await assert.rejects(functions.prepareStaffAiReview.run({
    ...request, data: { ...request.data, businessUid: "other-business" },
  }), (error) => error.code === "permission-denied");

  const analyze = { ...request, data: {
    ...request.data, token: prepared.token, question: "Summarize", language: "sw",
  } };
  await message.update({ text: "Changed after review" });
  await assert.rejects(functions.analyzeStaffAiReview.run(analyze),
    (error) => error.code === "failed-precondition");
  await message.update({ text: "Sales discussion" });
  await db.doc(`accountAccess/${owner}`).set({ disabled: true });
  await assert.rejects(functions.analyzeStaffAiReview.run(analyze),
    (error) => error.code === "permission-denied");
  await db.doc(`accountAccess/${owner}`).set({ disabled: false });

  const originalFetch = global.fetch;
  let sent;
  global.fetch = async (url, options) => {
    assert.equal(url, "https://api.openai.com/v1/chat/completions");
    sent = JSON.parse(options.body);
    return { ok: true, async json() { return { choices: [{ message: { content: "Answer" } }] }; } };
  };
  try {
    const answer = await functions.analyzeStaffAiReview.run(analyze);
    assert.equal(answer.answer, "Answer");
    assert.equal(sent.model, "gpt-6-luna");
    assert.equal(sent.reasoning_effort, "none");
    assert.equal(sent.messages[1].content[1].text, "Sales discussion");
    assert.equal(sent.messages[1].content[0].text.includes("Summarize"), true);
  } finally {
    global.fetch = originalFetch;
  }
});
