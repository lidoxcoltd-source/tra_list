const test = require("node:test");
const assert = require("node:assert/strict");
const {
  parseTransactionCommand,
  parseConversation,
  FOLLOWUP_SW,
  TYPE_FOLLOWUP_SW,
  amountFollowup,
} = require("./business_ai_transaction");

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
  assert.deepEqual(parseTransactionCommand("Naomba urekodi mapato"), {
    incomplete: true, type: "income",
  });
  assert.deepEqual(parseTransactionCommand("Nataka kurekodi mapato"), {
    incomplete: true, type: "income",
  });
  assert.deepEqual(parseTransactionCommand("Tafadhali rekodi matumizi 30,000"), {
    incomplete: true, type: "expense", amount: 30000,
  });
  assert.deepEqual(parseTransactionCommand("rekodi mapato na matumizi"), {
    incomplete: true,
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

test("income recording can continue from type to amount to details", () => {
  const typeRequest = { role: "user", content: "Naomba urekodi mapato" };
  const amountPrompt = {
    role: "assistant",
    content: amountFollowup("income", "Swahili"),
  };
  const amountReplyMessage = { role: "user", content: "30,000" };
  assert.deepEqual(parseConversation([
    typeRequest,
    amountPrompt,
    amountReplyMessage,
  ]), { incomplete: true, type: "income", amount: 30000 });

  const details = {
    role: "user",
    content: "kundi: Mauzo; maelezo: Mauzo ya bidhaa",
  };
  assert.deepEqual(parseConversation([
    typeRequest,
    amountPrompt,
    amountReplyMessage,
    { role: "assistant", content: FOLLOWUP_SW },
    details,
  ]), {
    type: "income",
    amount: 30000,
    category: "Mauzo",
    description: "Mauzo ya bidhaa",
  });

  const ambiguous = { role: "user", content: "rekodi mapato na matumizi" };
  const typePrompt = { role: "assistant", content: TYPE_FOLLOWUP_SW };
  const typeReply = { role: "user", content: "mapato" };
  assert.deepEqual(parseConversation([
    ambiguous,
    typePrompt,
    typeReply,
  ]), { incomplete: true, type: "income" });
  const selectedAmountPrompt = {
    role: "assistant",
    content: amountFollowup("income", "Swahili"),
  };
  const selectedAmount = { role: "user", content: "45,000" };
  assert.deepEqual(parseConversation([
    ambiguous,
    typePrompt,
    typeReply,
    selectedAmountPrompt,
    selectedAmount,
  ]), { incomplete: true, type: "income", amount: 45000 });
  assert.deepEqual(parseConversation([
    ambiguous,
    typePrompt,
    typeReply,
    selectedAmountPrompt,
    selectedAmount,
    { role: "assistant", content: FOLLOWUP_SW },
    details,
  ]), {
    type: "income",
    amount: 45000,
    category: "Mauzo",
    description: "Mauzo ya bidhaa",
  });
});
