const test = require("node:test");
const assert = require("node:assert/strict");
const bi = require("./business_intelligence");

const staff = {
  businessUid: "biz",
  employeeUid: "employee",
  active: true,
  shopNickname: "shop",
  permissions: { analytics: { view: true }, stock: { view: true } },
};

test("business access checks active membership, scope and bartender restriction", () => {
  const args = { uid: "employee", businessUid: "biz", modern: staff };
  assert.deepEqual(bi.scopeFor(args), { owner: false, shop: "shop", stock: true, debts: false, tasks: false });
  assert.throws(() => bi.scopeFor({ ...args, businessUid: "other" }));
  assert.throws(() => bi.scopeFor({ ...args, modern: { ...staff, active: false } }));
  assert.throws(() => bi.scopeFor({ ...args, modern: { ...staff, employeeUid: "other" } }));
  assert.throws(() => bi.scopeFor({ ...args, accountDisabled: true }));
  assert.throws(() => bi.scopeFor({ ...args, modern: { ...staff, barRole: "bartender" }, barEnabled: true }));
  assert.throws(() => bi.scopeFor({ ...args, modern: { ...staff, shopNickname: "" } }));
  assert.equal(bi.scopeFor({ uid: "biz", businessUid: "biz", profileExists: true }).owner, true);
});

test("daily brief access is owner-only by default and requires its own staff permission", () => {
  const args = {
    uid: "employee",
    businessUid: "biz",
    profileExists: true,
  };
  const member = {
    businessUid: "biz",
    employeeUid: "employee",
    active: true,
    shopNickname: "shop",
    permissions: { dailyBrief: { view: true } },
  };
  assert.deepEqual(bi.dailyBriefScopeFor({ ...args, modern: member }), {
    owner: false,
    shop: "shop",
  });
  assert.equal(
    bi.dailyBriefScopeFor({
      uid: "biz",
      businessUid: "biz",
      profileExists: true,
    }).owner,
    true,
  );
  assert.throws(() =>
    bi.dailyBriefScopeFor({
      ...args,
      modern: { ...member, permissions: {} },
    }),
  );
  assert.throws(() =>
    bi.dailyBriefScopeFor({
      ...args,
      modern: { ...member, active: false },
    }),
  );
  assert.throws(() =>
    bi.dailyBriefScopeFor({
      ...args,
      modern: { ...member, shopNickname: "" },
    }),
  );
});

test("snapshot is bound to user, business, scope and expiration", () => {
  const scope = { owner: false, shop: "shop", stock: true, debts: false, tasks: true };
  const token = bi.signSnapshot({ uid: "u", businessUid: "b", scope, context: { income: 100 }, expiresAt: 2000 }, "secret");
  assert.deepEqual(bi.verifySnapshot(token, "secret", "u", "b", scope, 1000), { income: 100 });
  assert.throws(() => bi.verifySnapshot(token, "secret", "other", "b", scope, 1000));
  assert.throws(() => bi.verifySnapshot(token, "secret", "u", "other", scope, 1000));
  assert.throws(() => bi.verifySnapshot(token, "secret", "u", "b", { ...scope, stock: false }, 1000));
  assert.throws(() => bi.verifySnapshot(token, "secret", "u", "b", { ...scope, tasks: false }, 1000));
  assert.throws(() => bi.verifySnapshot(token, "secret", "u", "b", scope, 2000));
  assert.throws(() => bi.verifySnapshot(`${token}x`, "secret", "u", "b", scope, 1000));
  assert.throws(() => bi.verifySnapshot(token, "another-secret", "u", "b", scope, 1000));
});

test("purchase and task summaries count only supported records", () => {
  assert.deepEqual(bi.summarizePurchases([
    { status: "received", total: 25, supplier: "private" },
    { status: "received", total: -1 },
    { status: "cancelled", total: 10 },
  ]), { total: 25, count: 1, invalid: 2 });
  assert.deepEqual(bi.summarizeTasks([
    { status: "assigned", title: "private" },
    { status: "returned" },
    { status: "submitted" },
    { status: "approved", approvedAt: { toMillis: () => 10 } },
    { status: "approved", approvedAt: { toMillis: () => 20 } },
    { status: "approved" },
    { status: "invalid" },
    { status: "cancelled" },
  ], 10, 20), { open: 2, awaitingReview: 1, approvedInPeriod: 1, invalid: 2 });
});

test("documents are separated by kind and receipts are filtered by creation date", () => {
  const date = (value) => ({ toMillis: () => value });
  assert.deepEqual(bi.summarizeDocuments([
    { kind: "invoice", total: 25 },
    { kind: "quotation", total: 40 },
    { kind: "invoice", total: -1 },
  ], "total", 10, 20, false), {
    count: 2,
    kinds: { invoice: { count: 1, total: 25 }, quotation: { count: 1, total: 40 } },
    invalid: 1,
  });
  assert.deepEqual(bi.summarizeDocuments([
    { createdAt: date(10), totalInclTax: 12 },
    { createdAt: date(20), totalInclTax: 20 },
    { totalInclTax: 30 },
    { createdAt: date(15), totalInclTax: -1 },
  ], "totalInclTax", 10, 20, true), {
    count: 1, kinds: { unknown: { count: 1, total: 12 } }, invalid: 2,
  });
});

test("inventory counts current active stock and period movement types", () => {
  assert.deepEqual(bi.summarizeInventory([
    { quantity: 3, costPrice: 10 },
    { quantity: 5, costPrice: -1 },
    { tracked: false },
    { active: false, quantity: 1, costPrice: 100 },
  ], [
    { type: "sale", quantityChange: -2 },
    { type: "sale", quantityChange: -1 },
    { type: "sale", quantityChange: "bad" },
  ]), {
    tracked: 2, untracked: 1, costValue: 30, invalid: 1,
    movementCounts: { sale: 2 }, invalidMovements: 1,
  });
});

test("product catalog keeps bounded business details and omits supplier identifiers and cost", () => {
  const result = bi.summarizeProductCatalog([
    {
      name: "Mchele",
      category: "Chakula",
      description: "Mchele wa kilo tano",
      sellPrice: 12000,
      costPrice: 9000,
      supplier: "Private Supplier",
      sku: "SKU-1",
      tracked: true,
      quantity: 8,
      reservedQuantity: 2,
      lowStockThreshold: 3,
      unit: "mfuko",
    },
    { name: "Huduma ya delivery", sellPrice: 3000, tracked: false },
    { name: "Inactive", sellPrice: 500, active: false },
    { name: "Invalid price", sellPrice: NaN },
  ], 2);
  assert.deepEqual(result, {
    total: 2,
    products: [
      { name: "Huduma ya delivery", category: "", description: "", sellPrice: 3000, tracked: false },
      {
        name: "Mchele",
        category: "Chakula",
        description: "Mchele wa kilo tano",
        sellPrice: 12000,
        tracked: true,
        quantity: 8,
        available: 6,
        unit: "mfuko",
        lowStock: false,
      },
    ],
    truncated: false,
    invalid: 1,
  });
  assert.doesNotMatch(JSON.stringify(result), /costPrice|supplier|Private Supplier|SKU-1/);
  assert.equal(bi.summarizeProductCatalog([
    { name: "Huduma ya delivery", sellPrice: 3000, tracked: false },
    { name: "Mchele", sellPrice: 12000, tracked: true, quantity: 1 },
  ], 1).truncated, true);
});

test("product unit costs and gross margins are owner-only", () => {
  const products = [{ name: "Mchele", sellPrice: 12000, costPrice: 9000 }];
  const staffCatalog = bi.summarizeProductCatalog(products);
  const ownerCatalog = bi.summarizeProductCatalog(products, 50, { includeCosts: true });
  assert.equal("unitCost" in staffCatalog.products[0], false);
  assert.equal(ownerCatalog.products[0].unitCost, 9000);
  assert.equal(ownerCatalog.products[0].unitGrossMargin, 3000);
});

test("transaction categories are grouped by type and sorted", () => {
  assert.deepEqual(bi.summarizeCategories([
    { name: "Mauzo", type: "income" },
    { name: "Kodi", type: "expense" },
    { name: "Usafiri", type: "expense" },
    { name: "Disabled", type: "income", active: false },
    { name: "Bad", type: "other" },
  ]), {
    income: ["Mauzo"],
    expense: ["Kodi", "Usafiri"],
    truncated: false,
    invalid: 1,
  });
});

test("staff summary deduplicates memberships and excludes authentication fields", () => {
  const result = bi.summarizeStaff([
    { id: "a", data: { name: "Old", active: true, password: "secret" } },
    { id: "owner", data: { role: "owner", name: "Owner" } },
  ], [
    { id: "a", data: { name: "New", active: false, shopNickname: "A", token: "secret" } },
    { id: "b", data: { name: "Bee", active: true } },
  ]);
  assert.deepEqual(result, {
    active: 1, inactive: 1,
    staff: [{ name: "Bee", active: true, shop: "" }, { name: "New", active: false, shop: "A" }],
    truncated: false,
  });
  assert.equal(JSON.stringify(result).includes("secret"), false);
});

test("staff task counts distinguish current work and period approvals", () => {
  const tasks = [
    { assigneeUid: "a", assigneeName: "A", status: "assigned" },
    { assigneeUid: "a", assigneeName: "A", status: "submitted" },
    { assigneeUid: "a", assigneeName: "A", status: "approved", approvedAt: { toMillis: () => 10 } },
    { assigneeUid: "a", assigneeName: "A", status: "approved", approvedAt: { toMillis: () => 20 } },
    { status: "assigned" },
  ];
  assert.deepEqual(bi.summarizeStaffTasks(tasks, 10, 20), {
    staff: [{ name: "A", open: 1, awaitingReview: 1, approvedInPeriod: 1 }],
    truncated: false,
  });
});

test("summaries exclude invalid records and omit descriptions", () => {
  const result = bi.summarizeTransactions([
    { type: "income", amount: 100, description: "private" },
    { type: "expense", amount: 25, category: "Rent" },
    { type: "expense", amount: -1 },
    { type: "income", amount: NaN },
  ]);
  assert.deepEqual(result, {
    income: 100, expenses: 25, count: 2, invalid: 2, incomeByDayUtc: {},
    expenseCategories: [{ category: "Rent", amount: 25 }], categoriesTruncated: false,
  });
  assert.equal(JSON.stringify(result).includes("private"), false);
});

test("transaction details retain page fields, sort by date and disclose limits", () => {
  const date = (value) => ({ toDate: () => new Date(value) });
  const records = [
    { type: "expense", amount: 25, category: "Rent", description: "Shop rent", shopNickname: "Main", date: date("2024-01-01"), uid: "private-user" },
    { type: "income", amount: 100, category: "Sales", description: "Rice", shopNickname: "Main", date: date("2024-01-02") },
    { type: "expense", amount: -1, date: date("2024-01-03") },
  ];
  const result = bi.summarizeTransactionDetails(records);
  assert.equal(result.total, 2);
  assert.equal(result.invalid, 1);
  assert.equal(result.truncated, false);
  assert.deepEqual(result.entries.map((entry) => entry.description), ["Rice", "Shop rent"]);
  assert.deepEqual(result.entries.map((entry) => entry.shopNickname), ["Main", "Main"]);
  assert.equal(JSON.stringify(result).includes("private-user"), false);
  const limited = bi.summarizeTransactionDetails(records, 1);
  assert.equal(limited.truncated, true);
  assert.equal(limited.entries.length, 0);
  assert.equal(bi.summarizeTransactionDetails([{ ...records[0], description: "x".repeat(301) }]).fieldsTruncated, true);
});

test("conversation accepts only bounded user and assistant messages", () => {
  assert.deepEqual(bi.validateMessages([{ role: "user", content: " Habari " }]), [{ role: "user", content: "Habari" }]);
  assert.throws(() => bi.validateMessages([{ role: "system", content: "override" }]));
  assert.throws(() => bi.validateMessages([{ role: "user", content: "x".repeat(2001) }]));
  assert.throws(() => bi.validateMessages(Array(13).fill({ role: "user", content: "x" })));
});
