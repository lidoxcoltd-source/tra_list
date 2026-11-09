const test = require("node:test");
const assert = require("node:assert/strict");
const { loadSelection, preview, contentPart, review } = require("./business_ai_staff_review_service");

function fixture() {
  const bytes = Buffer.from("%PDF-1.7 reviewed content");
  const data = {
    text: "Taarifa ya mauzo",
    attachments: [{
      storagePath: "chatAttachments/business/conversation/doc.pdf",
      contentType: "application/pdf",
      size: bytes.length,
    }],
  };
  const paths = [];
  const db = {
    collection(value) { paths.push(value); return this; },
    doc(value) { paths.push(value); return this; },
    async get() { return { exists: true, data: () => data }; },
  };
  const storage = [];
  const bucket = {
    file(path, options) {
      storage.push({ path, options });
      return {
        async getMetadata() { return [{ size: String(bytes.length), contentType: "application/pdf", generation: "7" }]; },
        async download() { return [bytes]; },
      };
    },
  };
  return { bytes, data, paths, storage, db, bucket };
}

test("selection reads message from the chosen business and previews only the chosen text", async () => {
  const f = fixture();
  const selection = [{ conversationId: "conversation", messageId: "message", kind: "text", text: "injected" }];
  const items = await loadSelection({ ...f, businessUid: "business", selection });
  assert.deepEqual(f.paths, ["users", "business", "chats", "conversation", "messages", "message"]);
  assert.deepEqual(preview(items[0]), { kind: "text", text: f.data.text });
  assert.deepEqual(contentPart(items[0]), { type: "text", text: f.data.text });
  assert.equal(f.storage.length, 0);
});

test("attachment uses only stored path and pins the Storage generation", async () => {
  const f = fixture();
  const selection = [{ conversationId: "conversation", messageId: "message", kind: "attachment", attachmentIndex: 0, storagePath: "attacker" }];
  const items = await loadSelection({ ...f, businessUid: "business", selection });
  assert.deepEqual(f.storage, [
    { path: "chatAttachments/business/conversation/doc.pdf", options: undefined },
    { path: "chatAttachments/business/conversation/doc.pdf", options: { generation: "7" } },
  ]);
  assert.equal(preview(items[0]).data, f.bytes.toString("base64"));
  assert.deepEqual(contentPart(items[0]), {
    type: "file", file: { filename: "reviewed.pdf", file_data: `data:application/pdf;base64,${f.bytes.toString("base64")}` },
  });
  const args = { uid: "owner", businessUid: "business", scope: { owner: true }, secret: "test", now: 1000 };
  const token = review.signReview({ ...args, items });
  f.data.attachments[0].storagePath = "chatAttachments/other/conversation/doc.pdf";
  await assert.rejects(loadSelection({ ...f, businessUid: "business", selection }));
  assert.throws(() => review.verifyReview({ ...args, token, items: [{ ...items[0], bytes: Buffer.from("%PDF-1.7 another content!") }] }));
});

test("rejects malformed or multiple selections before accessing storage", async () => {
  const f = fixture();
  for (const selection of [
    [], [{ conversationId: "../other", messageId: "x", kind: "text" }],
    [{ conversationId: "conversation", messageId: "message", kind: "attachment", attachmentIndex: 5 }],
    [{ conversationId: "conversation", messageId: "message", kind: "text" }, { conversationId: "conversation", messageId: "message", kind: "text" }],
  ]) {
    await assert.rejects(loadSelection({ ...f, businessUid: "business", selection }));
  }
  assert.equal(f.storage.length, 0);
});
