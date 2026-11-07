const { createHash } = require("node:crypto");

function historyScopeId(scope) {
  return createHash("sha256").update(JSON.stringify(scope)).digest("hex");
}

function validateHistoryMessage(value) {
  if (!value || !["user", "assistant"].includes(value.role) ||
      typeof value.content !== "string" || !value.content.trim() ||
      value.content.length > 12000) {
    throw new Error("invalid-message");
  }
  return { role: value.role, content: value.content.trim() };
}

module.exports = { historyScopeId, validateHistoryMessage };
