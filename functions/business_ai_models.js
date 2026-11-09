// Allowed chat models. Ids are fixed server-side; admins only adjust label, availability and prices.
const DEFAULT_MODELS = Object.freeze([
  { id: "gpt-4o-mini", provider: "openai", label: "GPT-4o mini", enabled: true, messagePrice: 0, creditCost: 1 },
  { id: "gpt-6-luna", provider: "openai", label: "GPT-6 Luna", enabled: true, messagePrice: 0, creditCost: 2 },
  { id: "gemini-2.5-flash", provider: "gemini", label: "Gemini 2.5 Flash", enabled: false, messagePrice: 0, creditCost: 1 },
  { id: "gemini-2.5-pro", provider: "gemini", label: "Gemini 2.5 Pro", enabled: false, messagePrice: 0, creditCost: 3 },
  { id: "gemini-3.8-flash", provider: "gemini", label: "Gemini 3.8 Flash", enabled: true, messagePrice: 0, creditCost: 1 },
  { id: "gemini-3.1-pro-preview", provider: "gemini", label: "Gemini 3.1 Pro Preview", enabled: true, messagePrice: 0, creditCost: 3 },
]);
const REPLACEMENTS = Object.freeze({
  "gemini-2.5-flash": "gemini-3.8-flash",
  "gemini-2.5-pro": "gemini-3.1-pro-preview",
});
const REASONING = Object.freeze({ "gpt-6-luna": "none" });
const DEFAULT_MODEL_ID = "gemini-3.8-flash";
const PROVIDERS = Object.freeze(["openai", "gemini", "claude"]);

function nickname(value) {
  if (typeof value !== "string" || value.length > 40 ||
      /[\u0000-\u001f\u007f]/.test(value)) throw new Error("invalid-nickname");
  return value.trim();
}

function providerNicknames(value) {
  if (value == null) return {};
  if (typeof value !== "object" || Array.isArray(value) ||
      Object.keys(value).some((key) => !PROVIDERS.includes(key))) {
    throw new Error("invalid-nickname");
  }
  return Object.fromEntries(Object.entries(value).map(([key, name]) => [key, nickname(name)]));
}

function validateModels(models) {
  if (!Array.isArray(models) || models.length > DEFAULT_MODELS.length) {
    throw new Error("invalid-models");
  }
  const seen = new Set();
  const result = models.map((model) => {
    const known = DEFAULT_MODELS.find((item) => item.id === model?.id);
    if (!known || seen.has(known.id)) throw new Error("invalid-models");
    seen.add(known.id);
    const label = typeof model.label === "string" ? model.label.trim() : "";
    if (!label || label.length > 40 || typeof model.enabled !== "boolean" ||
        !Number.isSafeInteger(model.messagePrice) || model.messagePrice < 0 || model.messagePrice > 100000000 ||
        !Number.isSafeInteger(model.creditCost) || model.creditCost < 1 || model.creditCost > 100) {
      throw new Error("invalid-models");
    }
    return {
      id: known.id, provider: known.provider, label, enabled: model.enabled,
      messagePrice: model.messagePrice, creditCost: model.creditCost,
      ...(model.nickname === undefined ? {} : { nickname: nickname(model.nickname) }),
    };
  });
  return result;
}

// Saved settings override defaults; models added later fall back to their defaults.
function modelsFromDocument(data) {
  const saved = data == null ? [] : validateModels(data.models);
  const merged = DEFAULT_MODELS.filter((model) => !REPLACEMENTS[model.id]).map((model) => {
    const stored = saved.find((item) => item.id === model.id);
    if (stored) return stored;
    const oldId = Object.keys(REPLACEMENTS).find((id) => REPLACEMENTS[id] === model.id);
    const previous = saved.find((item) => item.id === oldId);
    return previous
      ? { ...model, enabled: previous.enabled, messagePrice: previous.messagePrice, creditCost: previous.creditCost }
      : { ...model };
  });
  if (!merged.some((model) => model.enabled)) throw new Error("invalid-models");
  return merged;
}

function resolveModel(models, requestedId) {
  const model = requestedId == null
    ? models.find((item) => item.id === DEFAULT_MODEL_ID && item.enabled) ||
      models.find((item) => item.provider === "gemini" && item.enabled) ||
      models.find((item) => item.enabled)
    : models.find((item) => item.id === requestedId && item.enabled);
  if (!model) throw new Error("model-unavailable");
  return model;
}

module.exports = { DEFAULT_MODELS, DEFAULT_MODEL_ID, REASONING, validateModels, modelsFromDocument, resolveModel, providerNicknames };
