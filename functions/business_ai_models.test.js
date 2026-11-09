const test = require("node:test");
const assert = require("node:assert/strict");
const models = require("./business_ai_models");
const quota = require("./business_ai_quota");

test("defaults and resolution", () => {
  const list = models.modelsFromDocument(undefined);
  assert.equal(models.resolveModel(list, undefined).id, "gemini-3.8-flash");
  assert.equal(models.resolveModel(list, "gpt-6-luna").creditCost, 2);
  assert.throws(() => models.resolveModel(list, "other"), /model-unavailable/);
});

test("default respects disabled models, but explicit selections never silently change", () => {
  const list = models.modelsFromDocument(undefined);
  list.find((m) => m.id === "gemini-3.8-flash").enabled = false;
  assert.equal(models.resolveModel(list, undefined).id, "gemini-3.1-pro-preview");
  assert.throws(() => models.resolveModel(list, "gemini-3.8-flash"), /model-unavailable/);
  list.find((m) => m.id === "gemini-3.1-pro-preview").enabled = false;
  assert.equal(models.resolveModel(list, undefined).id, "gpt-4o-mini");
});

test("disabled model is rejected and validation enforces rules", () => {
  const list = models.modelsFromDocument(undefined).map((m) => ({ ...m }));
  list[1].enabled = false;
  assert.throws(() => models.resolveModel(models.validateModels(list), "gpt-6-luna"));
  list.forEach((m) => { m.enabled = false; });
  assert.throws(() => models.modelsFromDocument({ models: list }), /invalid-models/);
  assert.throws(() => models.validateModels([{ id: "x" }]), /invalid-models/);
});

test("new models merge into older saved settings", () => {
  const saved = models.validateModels([{ id: "gpt-4o-mini", label: "X", enabled: true, messagePrice: 5, creditCost: 1 }]);
  const merged = models.modelsFromDocument({ models: saved });
  assert.equal(merged.length, models.DEFAULT_MODELS.length - 2);
  assert.equal(merged[0].messagePrice, 5);
  assert.equal(models.resolveModel(merged, "gemini-3.8-flash").provider, "gemini");
});

test("nicknames are optional, bounded and do not change provider routing", () => {
  const saved = models.validateModels([{
    id: "gpt-4o-mini", label: "GPT-4o mini", nickname: "  Msaidizi  ",
    enabled: true, messagePrice: 0, creditCost: 1,
  }]);
  assert.equal(saved[0].nickname, "Msaidizi");
  assert.equal(saved[0].provider, "openai");
  assert.equal(models.modelsFromDocument({ models: saved })[0].nickname, "Msaidizi");
  assert.deepEqual(models.providerNicknames({ gemini: "  Mwangaza  ", openai: "" }),
    { gemini: "Mwangaza", openai: "" });
  assert.throws(() => models.providerNicknames({ unknown: "X" }), /invalid-nickname/);
  assert.throws(() => models.providerNicknames({ gemini: "x\nbad" }), /invalid-nickname/);
  assert.throws(() => models.validateModels([{ ...saved[0], nickname: "x".repeat(41) }]), /invalid-nickname/);
});

test("replaces retired Gemini models while preserving saved pricing and availability", () => {
  const saved = [
    { id: "gpt-4o-mini", label: "OpenAI", enabled: true, messagePrice: 0, creditCost: 1 },
    { id: "gemini-2.5-flash", label: "Flash", enabled: true, messagePrice: 12, creditCost: 4 },
    { id: "gemini-2.5-pro", label: "Pro", enabled: false, messagePrice: 19, creditCost: 7 },
  ];
  const merged = models.modelsFromDocument({ models: saved });
  assert.throws(() => models.resolveModel(merged, "gemini-2.5-flash"), /model-unavailable/);
  const flash = models.resolveModel(merged, "gemini-3.8-flash");
  assert.equal(flash.creditCost, 4);
  assert.equal(flash.messagePrice, 12);
  assert.equal(merged.find((m) => m.id === "gemini-3.1-pro-preview").enabled, false);
  assert.equal(merged.find((m) => m.id === "gemini-3.1-pro-preview").creditCost, 7);
  const updated = merged.map((m) => m.id === "gemini-3.8-flash" ? { ...m, creditCost: 2 } : m);
  assert.equal(models.modelsFromDocument({ models: updated }).find((m) => m.id === "gemini-3.8-flash").creditCost, 2);
});

test("gemini tts returns wav audio", async () => {
  const greeting = require("./isher_greeting");
  const pcm = Buffer.alloc(480);
  const audio = await greeting.synthesizeGemini({
    apiKey: "k", text: "Hi",
    fetchImpl: async () => ({ ok: true, json: async () => ({ candidates: [{ content: { parts: [{ inlineData: { data: pcm.toString("base64") } }] } }] }) }),
  });
  assert.equal(audio.length, 44 + 480);
  assert.equal(audio.toString("ascii", 0, 4), "RIFF");
  await assert.rejects(greeting.synthesizeGemini({ apiKey: "k", text: "Hi", fetchImpl: async () => ({ ok: false }) }));
});

test("credit cost consumes daily then extra quota", () => {
  const settings = { ...quota.DEFAULTS, dailyMessages: 3 };
  const usage = quota.consume({ extraMessages: 2 }, settings, "message", Date.now(), "", 4);
  assert.equal(usage.messagesUsed, 3);
  assert.equal(usage.extraMessages, 1);
  assert.throws(() => quota.consume({}, settings, "message", Date.now(), "", 4), /quota-exhausted/);
});
