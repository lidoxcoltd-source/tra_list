const test = require("node:test");
const assert = require("node:assert/strict");
const { MAX_FILE_BYTES, validateAttachmentMetadata, matchesFileSignature } = require("./business_ai_staff_attachments");

test("attachment metadata must belong to the requested business and conversation", () => {
  const attachment = {
    storagePath: "chatAttachments/business/conversation/abc-image.png",
    contentType: "image/png", size: 100,
  };
  assert.deepEqual(validateAttachmentMetadata({ businessUid: "business", conversationId: "conversation", attachment }), {
    path: attachment.storagePath, contentType: "image/png", size: 100,
  });
  for (const invalid of [
    { ...attachment, storagePath: "chatAttachments/other/conversation/a.png" },
    { ...attachment, storagePath: "chatAttachments/business/other/a.png" },
    { ...attachment, storagePath: "chatAttachments/business/conversation/../a.png" },
    { ...attachment, size: MAX_FILE_BYTES + 1 },
    { ...attachment, contentType: "audio/mpeg" },
  ]) {
    assert.throws(() => validateAttachmentMetadata({ businessUid: "business", conversationId: "conversation", attachment: invalid }));
  }
});

test("file signatures must agree with the declared image or PDF type", () => {
  assert.equal(matchesFileSignature(Buffer.from("%PDF-1.7"), "application/pdf"), true);
  assert.equal(matchesFileSignature(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), "image/png"), true);
  assert.equal(matchesFileSignature(Buffer.from([0xff, 0xd8, 0xff]), "image/jpeg"), true);
  assert.equal(matchesFileSignature(Buffer.from("RIFF0000WEBP"), "image/webp"), true);
  assert.equal(matchesFileSignature(Buffer.from("not a pdf"), "application/pdf"), false);
  assert.equal(matchesFileSignature(Buffer.from("%PDF-1.7"), "image/jpeg"), false);
});
