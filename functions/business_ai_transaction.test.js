const test = require("node:test");
const assert = require("node:assert/strict");
const { parseTransactionCommand, parseConversation, FOLLOWUP_SW } = require("./business_ai_transaction");

test("parses explicit income and expense without inventing fields", () => {
  assert.deepEqual(parseTransactionCommand(
    "rekodi matumizi ya 30,000; kundi: Kodi; maelezo: Kodi ya duka",
  ), { type: "expense", amount: 30000, category: "Kodi", description: "Kodi ya duka" });
  assert.deepEqual(parseTransactionCommand(
    "record income 25000; category: Sales; description: Cash sale",
  ), { type: "income", amount: 25000, category: "Sales", description: "Cash sale" });
  for (const text of [
    "record expense 12,34; category: Rent; description: Rent",
    "record expense 0; category: Rent; description: Rent",
    "record expense 300; category: Rent; description: Rent; date: yesterday",
  ]) assert.deepEqual(parseTransactionCommand(text), { incomplete: true });
  assert.equal(parseTransactionCommand("How do I record an expense?"), null);
  assert.deepEqual(parseTransactionCommand("rekodi matumizi ya 30,000"), {
    incomplete: true, type: "expense", amount: 30000,
  });
});

test("a specific follow-up completes the immediately preceding amount request", () => {
  const initial = { role: "user", content: "rekodi matumizi ya 30,000" };
  const prompt = { role: "assistant", content: FOLLOWUP_SW };
  const reply = { role: "user", content: "kundi: Kodi; maelezo: Kodi ya duka" };
  assert.deepEqual(parseConversation([initial, prompt, reply]), {
    type: "expense", amount: 30000, category: "Kodi", description: "Kodi ya duka",
  });
  assert.equal(parseConversation([initial, { ...prompt, content: "other" }, reply]), null);
  assert.equal(parseConversation([initial, prompt, { ...reply, content: "kundi: Kodi" }]), null);
  assert.equal(parseConversation([initial, prompt, { ...reply, content: "how is my business?" }]), null);
});
