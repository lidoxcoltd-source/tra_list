const MAX_FILE_BYTES = 5 * 1024 * 1024;
const ALLOWED_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "application/pdf"]);

function validateAttachmentMetadata({ businessUid, conversationId, attachment }) {
  if (typeof businessUid !== "string" || !businessUid || businessUid.includes("/") || businessUid.includes("\\") ||
      typeof conversationId !== "string" || !conversationId || conversationId.includes("/") || conversationId.includes("\\") ||
      !attachment || typeof attachment.storagePath !== "string" ||
      typeof attachment.contentType !== "string" || !ALLOWED_TYPES.has(attachment.contentType) ||
      !Number.isSafeInteger(attachment.size) || attachment.size <= 0 ||
      attachment.size > MAX_FILE_BYTES) {
    throw new Error("invalid-attachment");
  }
  const prefix = `chatAttachments/${businessUid}/${conversationId}/`;
  const name = attachment.storagePath.slice(prefix.length);
  if (!attachment.storagePath.startsWith(prefix) ||
      !name || name.includes("/") || name.includes("\\") || name === "." || name === "..") {
    throw new Error("invalid-attachment-path");
  }
  return { path: attachment.storagePath, contentType: attachment.contentType, size: attachment.size };
}

function matchesFileSignature(bytes, contentType) {
  if (!Buffer.isBuffer(bytes)) return false;
  switch (contentType) {
    case "application/pdf":
      return bytes.length >= 5 && bytes.subarray(0, 5).equals(Buffer.from("%PDF-"));
    case "image/jpeg":
      return bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
    case "image/png":
      return bytes.length >= 8 && bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
    case "image/webp":
      return bytes.length >= 12 && bytes.subarray(0, 4).equals(Buffer.from("RIFF")) &&
        bytes.subarray(8, 12).equals(Buffer.from("WEBP"));
    default:
      return false;
  }
}

module.exports = { MAX_FILE_BYTES, validateAttachmentMetadata, matchesFileSignature };
