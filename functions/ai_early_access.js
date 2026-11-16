const { createHash } = require("node:crypto");

function parseRegistration(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new TypeError("invalid-registration");
  }
  const email = typeof data.email === "string" ? data.email.trim().toLowerCase() : "";
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new TypeError("invalid-email");
  }
  const rawPhone = typeof data.phone === "string" ? data.phone.trim() : "";
  const phoneDigits = rawPhone.replace(/\D/g, "");
  const phone = phoneDigits.startsWith("0") && phoneDigits.length === 10
    ? `+255${phoneDigits.slice(1)}`
    : phoneDigits.startsWith("255") && phoneDigits.length === 12
    ? `+${phoneDigits}`
    : rawPhone.startsWith("+") && phoneDigits.length >= 9 && phoneDigits.length <= 15
    ? `+${phoneDigits}`
    : "";
  if (!phone) throw new TypeError("invalid-phone");
  if (data.consent !== true) throw new TypeError("consent-required");
  const honeypot = typeof data.website === "string" ? data.website.trim() : "";
  return { email, phone, honeypot };
}

function leadId(email) {
  return createHash("sha256").update(email).digest("hex");
}

module.exports = { parseRegistration, leadId };