const MAX_CONVERSATIONS = 20;
const MAX_MESSAGES_PER_CONVERSATION = 5;
const MAX_MESSAGES = 40;
const MAX_TEXT_BYTES = 16000;
const SHARING_ENABLED = false;

function isStaffChatRequest(text) {
  return typeof text === "string" &&
    /\b(staff|employee|employees|wafanyakazi|mfanyakazi|team)\b/i.test(text) &&
    /\b(chat|chats|message|messages|conversation|conversations|ujumbe|mazungumzo)\b/i.test(text);
}

function looksSensitive(text) {
  return /\b(password|passcode|secret|api[\s_-]*key|access[\s_-]*token|bearer|otp|pin|nywila|neno la siri)\b/i.test(text) ||
    /-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(text);
}

async function loadStaffMessages(business, start, end) {
  const conversations = await business.collection("chats")
    .orderBy("updatedAt", "desc").limit(MAX_CONVERSATIONS + 1).get();
  const selected = conversations.docs.slice(0, MAX_CONVERSATIONS);
  const pages = await Promise.all(selected.map((conversation) =>
    conversation.ref.collection("messages")
      .where("createdAt", ">=", start)
      .where("createdAt", "<", end)
      .orderBy("createdAt", "desc")
      .limit(MAX_MESSAGES_PER_CONVERSATION + 1)
      .select("senderName", "text", "createdAt", "attachments").get()));
  const candidates = [];
  let attachments = 0, sensitiveMessages = 0;
  for (const page of pages) {
    for (const doc of page.docs.slice(0, MAX_MESSAGES_PER_CONVERSATION)) {
      const data = doc.data();
      attachments += Array.isArray(data.attachments) ? data.attachments.length : 0;
      if (typeof data.text !== "string" || !data.text.trim()) continue;
      if (looksSensitive(data.text)) {
        sensitiveMessages++;
        continue;
      }
      if (typeof data.createdAt?.toMillis !== "function") continue;
      candidates.push({
        sender: typeof data.senderName === "string" ? data.senderName.trim().slice(0, 100) : "",
        text: data.text.trim().slice(0, 3000),
        createdAt: data.createdAt.toMillis(),
      });
    }
  }
  candidates.sort((a, b) => b.createdAt - a.createdAt);
  const messages = [];
  let bytes = 0, truncatedBySize = false;
  for (const message of candidates.slice(0, MAX_MESSAGES)) {
    const size = Buffer.byteLength(JSON.stringify(message));
    if (bytes + size > MAX_TEXT_BYTES) {
      truncatedBySize = true;
      break;
    }
    bytes += size;
    messages.push(message);
  }
  return {
    messages,
    truncated: conversations.size > MAX_CONVERSATIONS ||
      pages.some((page) => page.size > MAX_MESSAGES_PER_CONVERSATION) ||
      candidates.length > MAX_MESSAGES || truncatedBySize,
    omittedSensitiveMessages: sensitiveMessages,
    unreadAttachments: attachments,
    coverage: "Most recent 20 conversations by update time, up to 5 messages per conversation during the reporting period, and at most 40 messages. Messages may be omitted or truncated; do not infer missing conversations or claim attachments were read. Messages flagged as potentially containing credentials are omitted; this is not a guarantee that remaining messages contain no sensitive data.",
  };
}

module.exports = { SHARING_ENABLED, isStaffChatRequest, looksSensitive, loadStaffMessages };
