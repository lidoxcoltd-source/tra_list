const test = require("node:test");
const assert = require("node:assert/strict");
const { parseRegistration, leadId } = require("./ai_early_access");

test("normalizes and validates beta registration details and consent", () => {
  assert.deepEqual(parseRegistration({
    email: "  Tester@Example.com ",
    phone: "0712 345 678",
    consent: true,
    website: "",
  }), {
    email: "tester@example.com",
    phone: "+255712345678",
    honeypot: "",
  });
  assert.equal(leadId("tester@example.com"), leadId("tester@example.com"));
  assert.notEqual(leadId("tester@example.com"), leadId("other@example.com"));
  assert.throws(() => parseRegistration({ email: "bad", phone: "0712345678", consent: true }), /invalid-email/);
  assert.throws(() => parseRegistration({ email: "a@b.co", phone: "12", consent: true }), /invalid-phone/);
  assert.throws(() => parseRegistration({ email: "a@b.co", phone: "0712345678", consent: false }), /consent-required/);
});

test("flags the hidden website honeypot", () => {
  assert.equal(parseRegistration({
    email: "bot@example.com",
    phone: "+14155552671",
    consent: true,
    website: "spam",
  }).honeypot, "spam");
});