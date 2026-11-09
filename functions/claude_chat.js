// Anthropic Claude chat adapter. The API key stays server-side.
async function generate({ apiKey, model, system, messages, fetchImpl = fetch }) {
  const response = await fetchImpl("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    signal: AbortSignal.timeout(45000),
    body: JSON.stringify({
      model,
      max_tokens: 1024,
      system,
      messages: messages.map((item) => ({
        role: item.role === "assistant" ? "assistant" : "user",
        content: item.content,
      })),
    }),
  });
  if (!response.ok) throw new Error(`claude-status-${response.status}`);
  const data = await response.json();
  const text = (data.content || [])
    .map((part) => (part?.type === "text" && typeof part.text === "string" ? part.text : ""))
    .join("");
  if (!text.trim()) throw new Error("claude-empty");
  return text.trim();
}

module.exports = { generate };
