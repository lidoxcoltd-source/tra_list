const OPENAI_IMAGE_ENDPOINT = "https://api.openai.com/v1/images/generations";
const OPENAI_IMAGE_EDIT_ENDPOINT = "https://api.openai.com/v1/images/edits";

class OpenAiImageProvider {
  constructor({ apiKey, model = "gpt-image-2.5-sunburst" }) {
    if (!apiKey) throw new Error("OPENAI_API_KEY is not configured.");
    this.apiKey = apiKey;
    this.model = model;
  }

  async generate({ prompt, aspect = "square", transparent = false, referenceImage }) {
    const size = aspect === "portrait"
      ? "1024x1536"
      : aspect === "landscape" ? "1536x1024" : "1024x1024";
    const body = {
      model: this.model,
      prompt,
      size,
      quality: "medium",
      output_format: "png",
      n: 1,
      ...(transparent ? { background: "transparent" } : {}),
    };
    let response;
    if (referenceImage) {
      const form = new FormData();
      form.append("model", body.model);
      form.append("prompt", body.prompt);
      form.append("size", body.size);
      form.append("quality", body.quality);
      form.append("output_format", body.output_format);
      form.append("n", String(body.n));
      const imageBlob = new Blob([referenceImage.bytes], { type: referenceImage.contentType });
      form.append("image", imageBlob, referenceImage.filename);
      response = await fetch(OPENAI_IMAGE_EDIT_ENDPOINT, {
        method: "POST",
        headers: { Authorization: `Bearer ${this.apiKey}` },
        signal: AbortSignal.timeout(100000),
        body: form,
      });
    } else {
      response = await fetch(OPENAI_IMAGE_ENDPOINT, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${this.apiKey}`,
        },
        signal: AbortSignal.timeout(100000),
        body: JSON.stringify(body),
      });
    }
    if (!response.ok) {
      let providerError;
      try {
        const payload = await response.json();
        providerError = payload?.error || payload;
      } catch (_) {
        providerError = {};
      }
      const details = {
        status: response.status,
        type: typeof providerError.type === "string" ? providerError.type : undefined,
        code: typeof providerError.code === "string" ? providerError.code : undefined,
        param: typeof providerError.param === "string" ? providerError.param : undefined,
        message: typeof providerError.message === "string"
          ? providerError.message.slice(0, 300) : undefined,
      };
      console.error("OpenAI image generation failed", JSON.stringify(details));
      const error = new Error("image-provider-unavailable");
      error.status = response.status;
      error.providerCode = details.code;
      throw error;
    }
    const result = await response.json();
    const encoded = result.data?.[0]?.b64_json;
    if (typeof encoded !== "string" || !encoded) {
      throw new Error("image-provider-empty-response");
    }
    return Buffer.from(encoded, "base64");
  }
}

function createImageProvider({ provider, apiKey, model }) {
  switch (provider) {
    case "openai":
      return new OpenAiImageProvider({ apiKey, model });
    default:
      throw new Error("image-provider-not-configured");
  }
}

module.exports = { OpenAiImageProvider, createImageProvider };
