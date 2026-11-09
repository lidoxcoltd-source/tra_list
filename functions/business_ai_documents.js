const MAX_DOCUMENTS = 20;
const MAX_ITEMS = 30;

function documentRequest(text) {
  const prompt = typeof text === "string" ? text.toLowerCase() : "";
  const customers = /\b(customer|customers|client|clients|mteja|wateja)\b/.test(prompt);
  const latest = /\b(last|latest|most recent|recent|mwisho|karibuni)\b/.test(prompt);
  const hasPeriod = /\b(today|yesterday|week|weeks|month|months|year|years|date|leo|jana|wiki|mwezi|mwaka|tarehe|juzi|kipindi)\b|\b\d{4}-\d{1,2}-\d{1,2}\b|\b\d{1,2}[/-]\d{1,2}/.test(prompt);
  return {
    invoices: customers || /\b(invoice|invoices|ankara|proforma|quotation|quotations)\b/.test(prompt),
    receipts: customers || /\b(receipt|receipts|risiti|stakabadhi)\b/.test(prompt),
    customers,
    includeNames: customers,
    latestAllTime: latest && !hasPeriod && !customers,
  };
}

function string(value, limit = 100) {
  return typeof value === "string" ? value.trim().slice(0, limit) : "";
}

function amount(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function items(value) {
  if (!Array.isArray(value)) return { items: [], itemsUnavailable: true, itemsTruncated: false };
  return {
    items: value.slice(0, MAX_ITEMS).map((item) => ({
      description: string(item?.description),
      quantity: amount(item?.qty),
      amount: amount(item?.amount),
    })),
    itemsUnavailable: false,
    itemsTruncated: value.length > MAX_ITEMS,
  };
}

function invoice(data, includeNames = false) {
  return {
    kind: string(data.kind, 40),
    number: string(data.invoice?.number),
    issueDate: string(data.invoice?.issueDate, 40),
    dueDate: string(data.invoice?.dueDate, 40),
    ...(includeNames ? { clientName: string(data.client?.name) } : {}),
    total: amount(data.total),
    ...items(data.items),
  };
}

function receipt(data, includeNames = false) {
  return {
    number: string(data.meta?.receiptNo),
    receiptDate: string(data.meta?.receiptDate, 40),
    ...(includeNames ? { customerName: string(data.customer?.name) } : {}),
    totalExclTax: amount(data.totalExclTax),
    tax: amount(data.tax),
    totalInclTax: amount(data.totalInclTax),
    ...items(data.items),
  };
}

async function loadDetails({ db, businessUid, request, start, end, timestamp }) {
  const limit = request.latestAllTime ? 1 : MAX_DOCUMENTS;
  const range = (query) => {
    if (!request.latestAllTime) {
      query = query.where("createdAt", ">=", timestamp(start))
        .where("createdAt", "<", timestamp(end));
    }
    return query.orderBy("createdAt", "desc").limit(limit + 1);
  };
  let invoiceQuery = db.collection("users").doc(businessUid).collection("invoices");
  if (request.latestAllTime) invoiceQuery = invoiceQuery.where("kind", "==", "invoice");
  const [invoices, receipts] = await Promise.all([
    request.invoices ? range(invoiceQuery).select("kind", "invoice", "client.name", "total", "items").get() : null,
    request.receipts ? range(db.collection("receipts").where("businessUid", "==", businessUid))
      .select("meta.receiptNo", "meta.receiptDate", "customer.name", "totalExclTax", "tax", "totalInclTax", "items").get() : null,
  ]);
  return {
    ...(invoices ? {
      invoices: invoices.docs.slice(0, limit).map((doc) => invoice(doc.data(), request.includeNames)),
      invoicesTruncated: !request.latestAllTime && invoices.size > limit,
    } : {}),
    ...(receipts ? {
      receipts: receipts.docs.slice(0, limit).map((doc) => receipt(doc.data(), request.includeNames)),
      receiptsTruncated: !request.latestAllTime && receipts.size > limit,
    } : {}),
    coverage: request.latestAllTime
      ? "Most recent document by creation time across all periods. Documents without creation timestamps are unavailable; the invoice query excludes quotations. Up to 30 items per document."
      : "Most recent 20 documents of each requested type created during the reporting period; at most 30 items per document. Customer names are from document records, not a complete customer directory or verified identity. Documents with missing timestamps and local-only receipts are unavailable. Invoices and receipts may describe the same sale; do not combine totals or infer unique customers. Quotations are not sales. State when records or items are truncated.",
  };
}

module.exports = { MAX_DOCUMENTS, documentRequest, invoice, receipt, loadDetails };
