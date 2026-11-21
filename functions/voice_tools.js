const summary = {
  name: "get_business_summary",
  description: "Retrieve the selected business's authorized report. Call for business reports, summaries, income, expenses, or business performance, including conversational questions such as 'biashara yangu inaendaje?' and requests such as 'nipe report ya biashara yangu'. For 'duka langu limefanya biashara gani leo' use period 'today' and answer from recorded transactions and sales, disclosing any missing details. For 'report za biashara za jana' use period 'yesterday'; for leo use 'today', mwezi huu use 'month', and mwezi uliopita use 'previous'. If a user follows a yesterday report with 'za wiki nzima', call this tool again with period 'seven' for the last seven days; do not assume the previous one-day report covers the week. For an explicit calendar date use 'custom' with the same YYYY-MM-DD start_date and end_date. Use period 'selected' when no period is specified, or the requested period when specified. For follow-up questions retain the most recently requested period unless the user changes it. The last day of a custom range is inclusive. Never guess unavailable figures or ambiguous dates.",
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
  description: "After the user explicitly asks to record income or expense, collect the type, exact whole-TZS amount, existing category and description one at a time. Repeat each answer and ask for confirmation. Open the draft for on-screen confirmation. If confirmed, it is sent to chat for saving; check chat for the result. Never claim it was saved by voice.",
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
      destination: { type: "string", enum: ["transactions", "invoices", "receipts", "quotation", "analytics", "jobs", "tasks", "staff", "pos", "creativeStudio"] },
    },
    required: ["destination"],
  },
};
const debts = {
  name: "get_current_debts",
  description: "When the user asks who owes the business, which debts are overdue, or which deadlines are coming, retrieve current debt records. Use due_within_days for upcoming deadlines, 0 for today, and overdue_only for overdue debts. Results may be truncated; disclose the truncated field and do not claim they are complete. The result is limited to debts the signed-in user can view. Never guess or expose phone numbers.",
  parameters: {
    type: "object",
    properties: {
      due_within_days: { type: "integer", description: "Optional look-ahead from 0 to 365 days." },
      overdue_only: { type: "boolean", description: "Set true only when the user asks specifically for overdue debts." },
    },
    required: [],
  },
};
const debtReminder = {
  name: "review_whatsapp_debt_reminder",
  description: "Only after the user asks to remind a specific debtor. First retrieve current debts, identify one exact debt by its returned id, and draft a brief message using its verified balance and due date. Pass the debt id and complete proposed message. This opens an editable approval screen; WhatsApp opens only after the user approves. Never claim the reminder was sent.",
  parameters: {
    type: "object",
    properties: {
      debt_id: { type: "string", description: "Exact id from get_current_debts." },
      message: { type: "string", description: "Complete reminder text to show for review, at most 1000 characters." },
    },
    required: ["debt_id", "message"],
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
  geminiTools: [{ functionDeclarations: [summary, details, document, transaction, navigation, debts, debtReminder].map(geminiDeclaration) }],
  openAiTools: [summary, details, document, transaction, navigation, debts, debtReminder].map((tool) => ({ type: "function", ...tool })),
};
