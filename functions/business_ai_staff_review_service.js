const { validateAttachmentMetadata, MAX_FILE_BYTES } = require("./business_ai_staff_attachments");
const review = require("./business_ai_staff_review");

function validId(value) {
  return typeof value === "string" && value.length > 0 && value.length <= 128 &&
    value !== "." && value !== ".." && !value.includes("/") && !value.includes("\\");
}

async function loadSelection({ db, bucket, businessUid, selection }) {
  if (!validId(businessUid) || !Array.isArray(selection) || selection.length !== 1) {
    throw new Error("invalid-selection");
  }
  const entry = selection[0];
  if (!entry || !validId(entry.conversationId) || !validId(entry.messageId) ||
      !["text", "attachment"].includes(entry.kind)) throw new Error("invalid-selection");
  const conversation = db.collection("users").doc(businessUid).collection("chats")
    .doc(entry.conversationId);
  const [chat, document] = await Promise.all([
    conversation.get(),
    conversation.collection("messages").doc(entry.messageId).get(),
  ]);
  if (!chat.exists || !document.exists) throw new Error("missing-message");
  const data = document.data();
  const item = { conversationId: entry.conversationId, messageId: entry.messageId, kind: entry.kind };
  if (entry.kind === "text") {
    item.text = data.text;
  } else {
    if (!Number.isSafeInteger(entry.attachmentIndex) || entry.attachmentIndex < 0 ||
        entry.attachmentIndex >= 5 || !Array.isArray(data.attachments)) throw new Error("invalid-selection");
    item.attachmentIndex = entry.attachmentIndex;
    item.attachment = data.attachments[entry.attachmentIndex];
    const meta = validateAttachmentMetadata({ businessUid, conversationId: entry.conversationId, attachment: item.attachment });
    const object = bucket.file(meta.path);
    const [storageMeta] = await object.getMetadata();
    if (Number(storageMeta.size) !== meta.size || Number(storageMeta.size) > MAX_FILE_BYTES ||
        !storageMeta.generation || storageMeta.contentType !== meta.contentType) {
      throw new Error("invalid-attachment-content");
    }
    const [bytes] = await bucket.file(meta.path, { generation: storageMeta.generation }).download();
    item.bytes = bytes;
  }
  return [item];
}

function preview(item) {
  if (item.kind === "text") return { kind: "text", text: item.text };
  return {
    kind: "attachment",
    contentType: item.attachment.contentType,
    data: item.bytes.toString("base64"),
  };
}

function contentPart(item) {
  if (item.kind === "text") return { type: "text", text: item.text };
  const data = `data:${item.attachment.contentType};base64,${item.bytes.toString("base64")}`;
  if (item.attachment.contentType === "application/pdf") {
    return { type: "file", file: { filename: "reviewed.pdf", file_data: data } };
  }
  return { type: "image_url", image_url: { url: data } };
}

module.exports = { loadSelection, preview, contentPart, review };
