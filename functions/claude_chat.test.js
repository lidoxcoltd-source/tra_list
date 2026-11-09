const test = require("node:test");
const assert = require("node:assert/strict");
const claude = require("./claude_chat");

test("generate sends a system prompt and returns the text blocks", async () => {
  let call;
  const fetchImpl = async (url, options) => {
    call = { url, options };
    return { ok: true, json: async () => ({ content: [{ type: "text", text: " Hello " }] }) };
  };
  const answer = await claude.generate({
    apiKey: "k", model: "claude-haiku-4-5", system: "sys",
    messages: [{ role: "user", content: "hi" }], fetchImpl,
  });
  assert.equal(answer, "Hello");
  assert.equal(call.options.headers["x-api-key"], "k");
  const body = JSON.parse(call.options.body);
  assert.equal(body.system, "sys");
  assert.deepEqual(body.messages, [{ role: "user", content: "hi" }]);
});

test("generate fails on API errors and empty answers", async () => {
  await assert.rejects(
    claude.generate({ apiKey: "k", model: "m", system: "s", messages: [], fetchImpl: async () => ({ ok: false, status: 401 }) }),
    /claude-status-401/,
  );
  await assert.rejects(
    claude.generate({ apiKey: "k", model: "m", system: "s", messages: [], fetchImpl: async () => ({ ok: true, json: async () => ({ content: [] }) }) }),
    /claude-empty/,
  );
});
