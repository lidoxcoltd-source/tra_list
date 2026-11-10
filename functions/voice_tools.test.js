const test = require("node:test");
const assert = require("node:assert/strict");
const { geminiTools, openAiTools } = require("./voice_tools");
const { instruction } = require("./gemini_voice");

test("both providers receive matching bounded voice tools", () => {
  const gemini = geminiTools[0].functionDeclarations;
  assert.deepEqual(gemini.map((tool) => tool.name), [
    "get_business_summary", "get_document_details", "open_document_draft", "review_transaction_draft", "open_app_page",
  ]);
  assert.deepEqual(openAiTools.map((tool) => tool.name), gemini.map((tool) => tool.name));
  assert.ok(openAiTools.every((tool) => tool.type === "function"));
  assert.equal(gemini[0].parameters.type, "OBJECT");
  assert.equal(gemini[0].parameters.properties.period.type, "STRING");
  assert.ok(gemini[0].parameters.properties.period.enum.includes("yesterday"));
  for (const tool of [gemini[0], openAiTools[0]]) {
    assert.match(tool.description, /nipe report ya biashara yangu/);
    assert.match(tool.description, /biashara yangu inaendaje/);
    assert.match(tool.description, /duka langu limefanya biashara gani leo.*period 'today'/);
    assert.match(tool.description, /report za biashara za jana.*period 'yesterday'/);
    assert.match(tool.description, /za wiki nzima.*period 'seven'/);
    assert.match(tool.description, /same YYYY-MM-DD start_date and end_date/);
    assert.match(tool.description, /most recently requested period/);
    assert.match(tool.description, /period 'selected' when no period is specified/);
  }
  assert.ok(gemini[2].parameters.properties.kind.enum.includes("receipt"));
  assert.match(gemini[3].description, /on-screen confirmation/);
  assert.match(openAiTools[3].description, /check chat for the result/);
  assert.equal(gemini[2].parameters.properties.items.items.type, "OBJECT");
  assert.deepEqual(gemini[4].parameters.properties.destination.enum,
    ["transactions", "invoices", "receipts", "quotation", "analytics", "jobs", "tasks", "staff", "pos"]);
  assert.match(instruction("Swahili", {}), /get_business_summary/);
  assert.match(instruction("Swahili", {}), /user must review and save manually/);
});
