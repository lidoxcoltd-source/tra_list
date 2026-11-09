const test = require("node:test");
const assert = require("node:assert/strict");
const voice = require("./gemini_voice");

test("enabledProviders defaults to both and filters invalid values", () => {
  assert.deepEqual(voice.enabledProviders(undefined), ["openai", "gemini"]);
  assert.deepEqual(voice.enabledProviders({ voiceProviders: ["gemini", "x", "gemini"] }), ["gemini"]);
  assert.deepEqual(voice.enabledProviders({ voiceProviders: [] }), ["openai", "gemini"]);
});

test("createToken requests a single-use token locked to the live model", async () => {
  let call;
  const fetchImpl = async (url, options) => {
    call = { url, options };
    return { ok: true, json: async () => ({ name: "auth_tokens/abc" }) };
  };
  const token = await voice.createToken({ apiKey: "k", minutes: 5, fetchImpl, now: 0 });
  assert.equal(token, "auth_tokens/abc");
  assert.equal(call.options.headers["x-goog-api-key"], "k");
  const body = JSON.parse(call.options.body);
  assert.equal(body.uses, 1);
  assert.deepEqual(body.bidiGenerateContentSetup, {
    model: `models/${voice.LIVE_MODEL}`,
    generationConfig: { responseModalities: ["AUDIO"] },
  });
  assert.equal(body.expireTime, new Date(6 * 60000).toISOString());
});

test("createToken fails when the API rejects the request", async () => {
  const fetchImpl = async () => ({ ok: false, status: 403 });
  await assert.rejects(voice.createToken({ apiKey: "k", minutes: 1, fetchImpl }), /token-status-403/);
});
