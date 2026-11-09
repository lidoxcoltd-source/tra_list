const test = require("node:test");
const assert = require("node:assert/strict");
const documents = require("./business_ai_documents");

test("recognizes invoice and receipt requests without matching incidental words", () => {
  assert.deepEqual(documents.documentRequest("Nionyeshe ankara na risiti"), {
    invoices: true, receipts: true, customers: false, includeNames: false, latestAllTime: false,
  });
  assert.deepEqual(documents.documentRequest("How is my business?"), {
    invoices: false, receipts: false, customers: false, includeNames: false, latestAllTime: false,
  });
  assert.equal(documents.documentRequest("nipe jina la invoice ya mwisho").latestAllTime, true);
  assert.equal(documents.documentRequest("invoice ya mwisho mwezi huu").latestAllTime, false);
  assert.deepEqual(documents.documentRequest("nipe historia ya wateja"), {
    invoices: true, receipts: true, customers: true, includeNames: true, latestAllTime: false,
  });
});

test("selects only documented invoice fields and bounds line items", () => {
  const data = {
    kind: "invoice",
    invoice: { number: "INV-1", issueDate: "2026-01-01", paymentMethod: "secret" },
    client: { name: "Client", phone: "private" },
    total: 40,
    items: Array.from({ length: 31 }, () => ({
      description: "Product", qty: 2, amount: 40, password: "secret",
    })),
    apiKey: "secret",
  };
  const result = documents.invoice(data, true);
  assert.equal(result.number, "INV-1");
  assert.equal(result.clientName, "Client");
  assert.equal(result.items.length, 30);
  assert.equal(result.itemsTruncated, true);
  assert.equal(JSON.stringify(result).includes("secret"), false);
  assert.equal(JSON.stringify(result).includes("private"), false);
  assert.equal("clientName" in documents.invoice(data), false);
});

test("selects receipt details without customer identity numbers", () => {
  const result = documents.receipt({
    meta: { receiptNo: "R1", receiptDate: "2026-01-01" },
    customer: { name: "Customer", idNo: "private", mobile: "private" },
    totalInclTax: 50, tax: 5, items: [{ description: "A", qty: 1, amount: 50 }],
  }, true);
  assert.equal(result.number, "R1");
  assert.equal(result.customerName, "Customer");
  assert.equal(result.totalInclTax, 50);
  assert.equal(result.items[0].description, "A");
  assert.equal(JSON.stringify(result).includes("private"), false);
  assert.equal(documents.receipt({}).itemsUnavailable, true);
});

test("latest invoice is scoped to the business, kind and all periods", async () => {
  const queries = [];
  function query(path) {
    const calls = [];
    queries.push({ path, calls });
    const q = {
      collection: (name) => query(`${path}/${name}`),
      doc: (id) => query(`${path}/${id}`),
      where: (...args) => { calls.push(["where", ...args]); return q; },
      orderBy: (...args) => { calls.push(["orderBy", ...args]); return q; },
      limit: (...args) => { calls.push(["limit", ...args]); return q; },
      select: (...args) => { calls.push(["select", ...args]); return q; },
      get: async () => ({ size: 1, docs: [{ data: () => ({
        kind: "invoice", invoice: { number: "INV-LATEST" }, client: { name: "private" },
      }) }] }),
    };
    return q;
  }
  const result = await documents.loadDetails({
    db: { collection: query }, businessUid: "biz",
    request: documents.documentRequest("nipe jina la invoice ya mwisho"),
    start: 10, end: 20, timestamp: (value) => value,
  });
  const invoiceQuery = queries.find((entry) => entry.path === "users/biz/invoices");
  assert.deepEqual(invoiceQuery.calls.filter((call) => call[0] === "where"), [["where", "kind", "==", "invoice"]]);
  assert.deepEqual(invoiceQuery.calls.find((call) => call[0] === "orderBy"), ["orderBy", "createdAt", "desc"]);
  assert.equal(result.invoices[0].number, "INV-LATEST");
  assert.equal("clientName" in result.invoices[0], false);
  assert.equal(queries.some((entry) => entry.path === "receipts"), false);
});

test("customer history includes named, bounded records and discloses overlap", async () => {
  const calls = [];
  function query(path) {
    const q = {
      collection: (name) => query(`${path}/${name}`),
      doc: (id) => query(`${path}/${id}`),
      where: (...args) => { calls.push([path, "where", ...args]); return q; },
      orderBy: () => q,
      limit: (n) => { calls.push([path, "limit", n]); return q; },
      select: () => q,
      get: async () => ({ size: 21, docs: Array.from({ length: 21 }, () => ({
        data: () => path === "receipts"
          ? { customer: { name: "Mteja", mobile: "private" } }
          : { client: { name: "Mteja", phone: "private" } },
      })) }),
    };
    return q;
  }
  const result = await documents.loadDetails({
    db: { collection: query }, businessUid: "biz",
    request: documents.documentRequest("nipe historia ya wateja"),
    start: 10, end: 20, timestamp: (value) => value,
  });
  assert.deepEqual(calls.find((v) => v[0] === "receipts" && v[2] === "businessUid"), ["receipts", "where", "businessUid", "==", "biz"]);
  assert.equal(result.invoices.length, 20);
  assert.equal(result.receipts.length, 20);
  assert.equal(result.invoicesTruncated, true);
  assert.equal(result.receiptsTruncated, true);
  assert.equal(result.invoices[0].clientName, "Mteja");
  assert.equal(result.receipts[0].customerName, "Mteja");
  assert.match(result.coverage, /same sale/);
  assert.doesNotMatch(JSON.stringify(result), /private/);
});
