const summary = {
  name: "get_business_summary",
  description: "Retrieve an authorized business summary for the requested period. Use when a question refers to a different or current period. The last day of a custom range is inclusive. Never guess unavailable figures.",
  parameters: {
    type: "object",
    properties: {
      period: { type: "string", enum: ["selected", "today", "yesterday", "seven", "thirty", "month", "previous", "custom"] },
      start_date: { type: "string", description: "Custom range start in YYYY-MM-DD." },
      end_date: { type: "string", description: "Custom range inclusive end in YYYY-MM-DD." },
    },
    required: ["period"],
  },
};
const details = {
  name: "get_document_details",
  description: "Retrieve authorized invoice or receipt details only when explicitly requested. Use the user's document question verbatim, including whether they asked for customer names or the latest document. Do not invent details. Say if records are truncated or unavailable.",
  parameters: {
    type: "object",
    properties: {
      ...summary.parameters.properties,
      question: { type: "string", description: "The user's explicit question about invoices, receipts, or customers." },
    },
    required: ["period", "question"],
  },
};
const transaction = {
  name: "review_transaction_draft",
  description: "After the user explicitly asks to record income or expense, collect the type, exact whole-TZS amount, existing category and description one at a time. Repeat each answer and ask for confirmation. Open a review of the draft only; it is not saved. The user must finish saving in text chat.",
  parameters: {
    type: "object",
    properties: {
      type: { type: "string", enum: ["income", "expense"] },
      amount: { type: "integer", description: "Positive whole TZS amount confirmed by the user." },
      category: { type: "string", description: "The existing category named by the user." },
      description: { type: "string", description: "Transaction description provided by the user." },
    },
    required: ["type", "amount", "category", "description"],
  },
};
const navigation = {
  name: "open_app_page",
  description: "Only when the user explicitly asks to open an app page, request that page. The user must confirm on screen. Never claim a page opened without confirmation; never use this to create or change records.",
  parameters: {
    type: "object",
    properties: {
      destination: { type: "string", enum: ["transactions", "invoices", "receipts", "quotation", "analytics", "jobs", "tasks", "staff", "pos"] },
    },
    required: ["destination"],
  },
};
const document = {
  name: "open_document_draft",
  description: "Only after the user explicitly asks to create a document and provides its details, open an editable draft for manual review and saving. Invoice, proforma, and quotation may include up to 30 items; receipts support one item only and advance invoices have no items. This ends the voice session. Never invent details or claim it was saved. Items are not linked to stock.",
  parameters: {
    type: "object",
    properties: {
      kind: { type: "string", enum: ["invoice", "receipt", "quotation", "proforma", "advance"] },
      customer: { type: "string", description: "Customer name only if the user provided it." },
      description: { type: "string", description: "One item or service provided by the user." },
      quantity: { type: "number", description: "Item quantity explicitly provided by the user." },
      unit_price: { type: "number", description: "Unit price explicitly provided by the user." },
      subtotal: { type: "number", description: "Advance invoice subtotal if explicitly provided." },
      tax: { type: "number", description: "Tax if explicitly provided." },
      advance_paid: { type: "number", description: "Advance payment if explicitly provided." },
      items: {
        type: "array",
        description: "All confirmed items for invoice, proforma, or quotation; omit the single-item fields when using this list.",
        items: {
          type: "object",
          properties: {
            description: { type: "string" },
            quantity: { type: "number" },
            unit_price: { type: "number" },
          },
          required: ["description", "quantity", "unit_price"],
        },
      },
    },
    required: ["kind"],
  },
};

function geminiSchema(schema) {
  return {
    ...schema,
    type: schema.type.toUpperCase(),
    ...(schema.properties ? { properties: Object.fromEntries(
      Object.entries(schema.properties).map(([name, property]) => [name, geminiSchema(property)]),
    ) } : {}),
    ...(schema.items ? { items: geminiSchema(schema.items) } : {}),
  };
}
function geminiDeclaration(tool) {
  const { parameters, ...rest } = tool;
  return {
    ...rest,
    parameters: geminiSchema(parameters),
  };
}

module.exports = {
  geminiTools: [{ functionDeclarations: [summary, details, document, transaction, navigation].map(geminiDeclaration) }],
  openAiTools: [summary, details, document, transaction, navigation].map((tool) => ({ type: "function", ...tool })),
};
