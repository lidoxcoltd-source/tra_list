const DEFAULT_PACKAGES = Object.freeze([
  { id: "starter", name: "Starter", price: 2000, chats: 60, voiceSessions: 5, voiceMinutes: 5, analyses: 2, research: 1, credits: 2000, enabled: true },
  { id: "business", name: "Business", price: 5000, chats: 200, voiceSessions: 20, voiceMinutes: 20, analyses: 5, research: 3, credits: 3000, enabled: true },
  { id: "professional", name: "Professional", price: 10000, chats: 500, voiceSessions: 45, voiceMinutes: 45, analyses: 15, research: 8, credits: 6000, enabled: true },
  { id: "premium", name: "Premium", price: 20000, chats: 1200, voiceSessions: 120, voiceMinutes: 120, analyses: 30, research: 20, credits: 10000, enabled: true },
  { id: "test", name: "AI Test", price: 0, chats: 5, voiceSessions: 2, voiceMinutes: 5, analyses: 0, research: 0, credits: 0, enabled: true },
]);

function validatePackage(value) {
  const fields = ["id", "name", "price", "chats", "voiceMinutes", "analyses", "research", "credits", "enabled"];
  const optionalFields = ["voiceSessions"];
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      !fields.every((field) => Object.hasOwn(value, field)) ||
      Object.keys(value).some((field) => !fields.includes(field) && !optionalFields.includes(field)) ||
      (Object.hasOwn(value, "voiceSessions") && !Number.isSafeInteger(value.voiceSessions)) ||
      typeof value.id !== "string" || !/^[a-z0-9_-]{1,48}$/.test(value.id) ||
      typeof value.name !== "string" || !value.name.trim() || value.name.trim().length > 80 ||
      typeof value.enabled !== "boolean") {
    throw new Error("invalid-package");
  }
  const voiceSessions = value.voiceSessions ?? value.voiceMinutes;
  for (const key of ["price", "chats", "voiceMinutes", "analyses", "research", "credits"]) {
    if (!Number.isSafeInteger(value[key]) || value[key] < 0 || value[key] > 100000000) {
      throw new Error("invalid-package");
    }
  }
  if (!Number.isSafeInteger(voiceSessions) || voiceSessions < 0 || voiceSessions > 100000000) {
    throw new Error("invalid-package");
  }
  return {
    ...value,
    name: value.name.trim(),
    voiceSessions,
  };
}

function packagesFromDocument(data) {
  const packages = data == null ? DEFAULT_PACKAGES : data.packages;
  if (!Array.isArray(packages) || packages.length > 50) throw new Error("invalid-packages");
  const result = packages.map(validatePackage);
  if (data != null && !result.some((item) => item.id === "test")) {
    result.push(validatePackage(DEFAULT_PACKAGES.find((item) => item.id === "test")));
  }
  if (new Set(result.map((item) => item.id)).size !== result.length) {
    throw new Error("duplicate-package");
  }
  return result;
}

function hasDepletedUsageQuota(subscription, kind) {
  const packageDetails = subscription.package || {};
  const hasDepletedChats = packageDetails.chats > 0 &&
    Number.isSafeInteger(subscription.remainingChats) &&
    subscription.remainingChats < 1;
  const voiceQuota = packageDetails.voiceSessions ?? packageDetails.voiceMinutes;
  const hasDepletedVoice = voiceQuota > 0 &&
    Number.isSafeInteger(subscription.remainingVoiceSessions) &&
    subscription.remainingVoiceSessions < 1;
  if (kind === "message") return hasDepletedChats;
  if (kind === "voice") return hasDepletedVoice;
  return hasDepletedChats || hasDepletedVoice;
}

module.exports = {
  DEFAULT_PACKAGES,
  validatePackage,
  packagesFromDocument,
  hasDepletedUsageQuota,
};
