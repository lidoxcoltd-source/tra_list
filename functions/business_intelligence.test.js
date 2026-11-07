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

test("conversation accepts only bounded user and assistant messages", () => {
  assert.deepEqual(bi.validateMessages([{ role: "user", content: " Habari " }]), [{ role: "user", content: "Habari" }]);
  assert.throws(() => bi.validateMessages([{ role: "system", content: "override" }]));
  assert.throws(() => bi.validateMessages([{ role: "user", content: "x".repeat(2001) }]));
  assert.throws(() => bi.validateMessages(Array(13).fill({ role: "user", content: "x" })));
});
