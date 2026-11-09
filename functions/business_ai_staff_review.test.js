const test = require("node:test");
const assert = require("node:assert/strict");
const { MAX_ITEMS, REVIEW_LIFETIME_MS, signReview, verifyReview } = require("./business_ai_staff_review");

const bytes = Buffer.from("%PDF-1.7 reviewed content");
const text = { kind: "text", conversationId: "conversation", messageId: "one", text: "Mauzo ya leo" };
const file = {
  kind: "attachment", conversationId: "conversation", messageId: "two", attachmentIndex: 0,
  attachment: { storagePath: "chatAttachments/business/conversation/doc.pdf", contentType: "application/pdf", size: bytes.length },
  bytes,
};
const base = { uid: "owner", businessUid: "business", scope: { owner: true }, items: [text, file], secret: "test-secret", now: 1000 };

test("review binds exact selected content without putting it into the token", () => {
  const token = signReview(base);
  const payload = Buffer.from(token.split(".")[0], "base64url").toString();
  assert.equal(payload.includes(text.text), false);
  assert.equal(payload.includes(bytes.toString()), false);
  assert.doesNotThrow(() => verifyReview({ ...base, token }));
  for (const items of [
    [{ ...text, text: "Mauzo ya jana" }, file],
    [text, { ...file, bytes: Buffer.from("%PDF-1.7 changed content!") }],
    [text],
    [file, text],
    [text, { ...file, attachmentIndex: 1 }],
    [text, { ...file, attachment: { ...file.attachment, storagePath: "chatAttachments/business/conversation/other.pdf" } }],
  ]) {
    assert.throws(() => verifyReview({ ...base, token, items }));
  }
});

test("review rejects tampering, expiration, changed user, business, and owner access", () => {
  const token = signReview(base);
  assert.throws(() => verifyReview({ ...base, token: `${token}x` }));
  assert.throws(() => verifyReview({ ...base, token: `${token}!` }));
  assert.throws(() => verifyReview({ ...base, token, now: base.now + REVIEW_LIFETIME_MS }));
  assert.throws(() => verifyReview({ ...base, token, uid: "other" }));
  assert.throws(() => verifyReview({ ...base, token, businessUid: "other" }));
  assert.throws(() => verifyReview({ ...base, token, scope: { owner: false } }));
  assert.throws(() => signReview({ ...base, scope: { owner: false } }));
});

test("review rejects duplicates, sensitive text, unsupported and invalid files", () => {
  assert.throws(() => signReview({ ...base, items: [text, text] }), /duplicate-selection/);
  assert.throws(() => signReview({ ...base, items: [{ ...text, text: "password: abc" }] }), /sensitive/);
  assert.throws(() => signReview({ ...base, items: [{ ...file, attachment: { ...file.attachment, contentType: "audio/mpeg" } }] }));
  assert.throws(() => signReview({ ...base, items: [{ ...file, bytes: Buffer.alloc(bytes.length) }] }));
  assert.throws(() => signReview({ ...base, items: [{ ...file, attachment: { ...file.attachment, size: bytes.length + 1 } }] }));
  assert.throws(() => signReview({ ...base, items: [{ ...file, attachment: { ...file.attachment, storagePath: "chatAttachments/other/conversation/doc.pdf" } }] }));
  assert.throws(() => signReview({ ...base, items: [{ ...text, conversationId: ".." }] }));
  assert.throws(() => signReview({ ...base, items: Array(MAX_ITEMS + 1).fill(text) }));
});

test("review rejects selections whose combined file bytes exceed the limit", () => {
  const largeBytes = Buffer.alloc(3 * 1024 * 1024);
  largeBytes.write("%PDF-");
  const first = { ...file, bytes: largeBytes, attachment: { ...file.attachment, size: largeBytes.length } };
  const second = { ...first, messageId: "three" };
  assert.throws(() => signReview({ ...base, items: [first, second] }), /selection-too-large/);
});
