const test = require("node:test");
const assert = require("node:assert/strict");
const { historyScopeId, validateHistoryMessage } = require("./business_ai_history");

test("history is separated when business permission scope changes", () => {
  const scope = { owner: false, shop: "A", stock: true, debts: false, tasks: false };
  assert.equal(historyScopeId(scope), historyScopeId({ ...scope }));
  assert.notEqual(historyScopeId(scope), historyScopeId({ ...scope, stock: false }));
  assert.notEqual(historyScopeId(scope), historyScopeId({ ...scope, shop: "B" }));
});

test("stored messages are bounded and roles are restricted", () => {
  assert.deepEqual(validateHistoryMessage({ role: "user", content: " hello " }),
    { role: "user", content: "hello" });
  assert.throws(() => validateHistoryMessage({ role: "system", content: "hello" }));
  assert.throws(() => validateHistoryMessage({ role: "user", content: " " }));
  assert.throws(() => validateHistoryMessage({ role: "assistant", content: "x".repeat(12001) }));
});
