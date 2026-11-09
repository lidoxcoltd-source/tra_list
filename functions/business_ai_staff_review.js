const { createHash, createHmac, timingSafeEqual } = require("node:crypto");
const { looksSensitive } = require("./business_ai_staff_chat");
const {
  MAX_FILE_BYTES,
  validateAttachmentMetadata,
  matchesFileSignature,
} = require("./business_ai_staff_attachments");

const MAX_ITEMS = 10;
const MAX_TOTAL_FILE_BYTES = 5 * 1024 * 1024;
const REVIEW_LIFETIME_MS = 5 * 60 * 1000;

function validId(value) {
  return typeof value === "string" && value.length > 0 && value.length <= 128 &&
    value !== "." && value !== ".." && !value.includes("/") && !value.includes("\\");
}

function digest(value) {
  return createHash("sha256").update(value).digest("hex");
}

// Items must be loaded from Firestore and Storage, never from request data.
function manifestFor({ uid, businessUid, scope, items }) {
  if (!validId(uid) || !validId(businessUid) || scope?.owner !== true) {
    throw new Error("owner-required");
  }
  if (!Array.isArray(items) || items.length === 0 || items.length > MAX_ITEMS) {
    throw new Error("invalid-selection");
  }
  const seen = new Set();
  let totalFileBytes = 0;
  const manifest = items.map((item) => {
    if (!item || !validId(item.conversationId) || !validId(item.messageId)) {
      throw new Error("invalid-selection");
    }
    const base = { conversationId: item.conversationId, messageId: item.messageId };
    if (item.kind === "text") {
      if (typeof item.text !== "string" || !item.text.trim() ||
          Buffer.byteLength(item.text, "utf8") > 12000 || looksSensitive(item.text)) {
        throw new Error("invalid-or-sensitive-text");
      }
      const key = `${item.conversationId}/${item.messageId}/text`;
      if (seen.has(key)) throw new Error("duplicate-selection");
      seen.add(key);
      return { ...base, kind: "text", hash: digest(item.text) };
    }
    if (item.kind !== "attachment" || !Number.isSafeInteger(item.attachmentIndex) ||
        item.attachmentIndex < 0 || item.attachmentIndex >= 5) {
      throw new Error("invalid-selection");
    }
    const key = `${item.conversationId}/${item.messageId}/${item.attachmentIndex}`;
    if (seen.has(key)) throw new Error("duplicate-selection");
    seen.add(key);
    const meta = validateAttachmentMetadata({ businessUid, conversationId: item.conversationId, attachment: item.attachment });
    if (!Buffer.isBuffer(item.bytes) || item.bytes.length !== meta.size ||
        item.bytes.length > MAX_FILE_BYTES || !matchesFileSignature(item.bytes, meta.contentType)) {
      throw new Error("invalid-attachment-content");
    }
    totalFileBytes += item.bytes.length;
    if (totalFileBytes > MAX_TOTAL_FILE_BYTES) throw new Error("selection-too-large");
    return {
      ...base, kind: "attachment", attachmentIndex: item.attachmentIndex,
      path: meta.path, contentType: meta.contentType, size: meta.size,
      hash: digest(item.bytes),
    };
  });
  return manifest;
}

function signReview({ uid, businessUid, scope, items, secret, now = Date.now() }) {
  if (typeof secret !== "string" || !secret || !Number.isSafeInteger(now) ||
      !Number.isSafeInteger(now + REVIEW_LIFETIME_MS)) {
    throw new Error("invalid-review-configuration");
  }
  const manifest = manifestFor({ uid, businessUid, scope, items });
  const payload = { uid, businessUid, manifest, expiresAt: now + REVIEW_LIFETIME_MS };
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const signature = createHmac("sha256", secret).update(body).digest("base64url");
  return `${body}.${signature}`;
}

function verifyReview({ token, uid, businessUid, scope, items, secret, now = Date.now() }) {
  if (typeof token !== "string" || token.length > 16000 ||
      typeof secret !== "string" || !secret || !Number.isSafeInteger(now)) {
    throw new Error("invalid-review");
  }
  const parts = token.split(".");
  if (parts.length !== 2 || !/^[A-Za-z0-9_-]+$/.test(parts[0]) ||
      !/^[A-Za-z0-9_-]+$/.test(parts[1])) throw new Error("invalid-review");
  const expected = createHmac("sha256", secret).update(parts[0]).digest();
  const actual = Buffer.from(parts[1], "base64url");
  if (actual.length !== expected.length || actual.toString("base64url") !== parts[1] ||
      !timingSafeEqual(actual, expected)) {
    throw new Error("invalid-review");
  }
  let payload;
  try {
    payload = JSON.parse(Buffer.from(parts[0], "base64url").toString("utf8"));
  } catch (error) {
    throw new Error("invalid-review", { cause: error });
  }
  if (!payload || payload.uid !== uid || payload.businessUid !== businessUid ||
      !Number.isSafeInteger(payload.expiresAt) || payload.expiresAt <= now ||
      payload.expiresAt > now + REVIEW_LIFETIME_MS) {
    throw new Error("expired-or-changed-review");
  }
  const current = manifestFor({ uid, businessUid, scope, items });
  if (JSON.stringify(current) !== JSON.stringify(payload.manifest)) {
    throw new Error("expired-or-changed-review");
  }
}

module.exports = { MAX_ITEMS, MAX_TOTAL_FILE_BYTES, REVIEW_LIFETIME_MS, signReview, verifyReview };
