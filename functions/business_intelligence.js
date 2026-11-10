const { createHmac, timingSafeEqual } = require("node:crypto");

const MAX_RECORDS = 5000;
const MAX_SNAPSHOT_BYTES = 50000;

function scopeFor({ uid, businessUid, profileExists, accountDisabled, businessDisabled, modern, legacy, barEnabled }) {
  if (accountDisabled || businessDisabled) throw new Error("disabled");
  const member = modern?.businessUid === businessUid && modern?.employeeUid === uid
    ? modern
    : legacy?.businessUid === businessUid ? legacy : null;
  const owner = (uid === businessUid && profileExists && !member) ||
    (member?.active === true && member?.role === "owner" &&
      modern?.businessUid === businessUid && modern?.employeeUid === uid);
  if (!owner && (!member || member.active !== true ||
      (barEnabled && member.barRole === "bartender") ||
      member.permissions?.analytics?.view !== true)) {
    throw new Error("permission-denied");
  }
  const shop = owner ? "" : String(member.shopNickname || "").trim();
  if (!owner && !shop) throw new Error("missing-shop");
  return {
    owner,
    shop,
    stock: owner || member.permissions?.stock?.view === true,
    debts: owner || member.permissions?.jobs?.view === true,
    tasks: owner || member.permissions?.tasks?.view === true,
  };
}

function summarizePurchases(records) {
  let total = 0, count = 0, invalid = 0;
  for (const record of records) {
    if (record.status !== "received" || !Number.isFinite(record.total) || record.total < 0) {
      invalid++;
      continue;
    }
    total += record.total;
    count++;
  }
  return { total, count, invalid };
}

function summarizeTasks(records, start, end) {
  let open = 0, awaitingReview = 0, approvedInPeriod = 0, invalid = 0;
  for (const record of records) {
    if (["assigned", "inProgress", "returned"].includes(record.status)) open++;
    else if (record.status === "submitted") awaitingReview++;
    else if (record.status === "approved") {
      if (typeof record.approvedAt?.toMillis !== "function") {
        invalid++;
        continue;
      }
      const time = record.approvedAt.toMillis();
      if (time >= start && time < end) approvedInPeriod++;
    } else if (record.status !== "cancelled") invalid++;
  }
  return { open, awaitingReview, approvedInPeriod, invalid };
}

function summarizeDocuments(records, totalField, start, end, filterDate) {
  const kinds = new Map();
  let count = 0, invalid = 0;
  for (const record of records) {
    if (filterDate) {
      if (typeof record.createdAt?.toMillis !== "function") {
        invalid++;
        continue;
      }
      const date = record.createdAt.toMillis();
      if (date < start || date >= end) continue;
    }
    const amount = record[totalField];
    if (!Number.isFinite(amount) || amount < 0) {
      invalid++;
      continue;
    }
    const kind = typeof record.kind === "string" && record.kind.trim()
      ? record.kind.trim().slice(0, 40) : "unknown";
    const aggregate = kinds.get(kind) || { count: 0, total: 0 };
    aggregate.count++;
    aggregate.total += amount;
    kinds.set(kind, aggregate);
    count++;
  }
  return { count, kinds: Object.fromEntries(kinds), invalid };
}

function summarizeInventory(products, movements) {
  let tracked = 0, untracked = 0, costValue = 0, invalid = 0;
  for (const product of products) {
    if (product.active === false) continue;
    if (product.tracked === false) {
      untracked++;
      continue;
    }
    tracked++;
    if (!Number.isFinite(product.quantity) || !Number.isFinite(product.costPrice) ||
        product.costPrice < 0) {
      invalid++;
      continue;
    }
    costValue += product.quantity * product.costPrice;
  }
  const byType = new Map();
  let invalidMovements = 0;
  for (const movement of movements) {
    if (typeof movement.type !== "string" || !movement.type.trim() ||
        !Number.isFinite(movement.quantityChange)) {
      invalidMovements++;
      continue;
    }
    const type = movement.type.trim().slice(0, 40);
    byType.set(type, (byType.get(type) || 0) + 1);
  }
  return { tracked, untracked, costValue, invalid, movementCounts: Object.fromEntries(byType), invalidMovements };
}

function summarizeProductCatalog(records, limit = 50, { includeCosts = false } = {}) {
  const products = [];
  let invalid = 0;
  for (const data of records) {
    if (data.active === false) continue;
    if (typeof data.name !== "string" || !data.name.trim() ||
        typeof data.sellPrice !== "number" || !Number.isFinite(data.sellPrice) || data.sellPrice < 0) {
      invalid++;
      continue;
    }
    const tracked = data.tracked !== false;
    const quantity = typeof data.quantity === "number" && Number.isFinite(data.quantity)
      ? data.quantity
      : null;
    const reservedQuantity = typeof data.reservedQuantity === "number" && Number.isFinite(data.reservedQuantity)
      ? Math.max(0, data.reservedQuantity)
      : 0;
    const threshold = typeof data.lowStockThreshold === "number" && Number.isFinite(data.lowStockThreshold)
      ? data.lowStockThreshold
      : null;
    const costPrice = typeof data.costPrice === "number" && Number.isFinite(data.costPrice) && data.costPrice >= 0
      ? data.costPrice
      : null;
    products.push({
      name: data.name.trim().slice(0, 100),
      category: typeof data.category === "string" ? data.category.trim().slice(0, 80) : "",
      description: typeof data.description === "string" ? data.description.trim().slice(0, 200) : "",
      sellPrice: data.sellPrice,
      ...(includeCosts && costPrice !== null ? {
        unitCost: costPrice,
        unitGrossMargin: data.sellPrice - costPrice,
      } : {}),
      tracked,
      ...(tracked && quantity !== null ? {
        quantity,
        available: Math.max(0, quantity - reservedQuantity),
        unit: typeof data.unit === "string" ? data.unit.trim().slice(0, 30) : "",
        lowStock: threshold === null ? null : quantity <= 0 || quantity <= threshold,
      } : {}),
    });
  }
  products.sort((a, b) => a.name.localeCompare(b.name));
  return {
    total: products.length,
    products: products.slice(0, limit),
    truncated: products.length > limit,
    invalid,
  };
}

function summarizeCategories(records, limit = 50) {
  const categories = { income: new Set(), expense: new Set() };
  let invalid = 0;
  for (const data of records) {
    if (data.active === false) continue;
    if ((data.type !== "income" && data.type !== "expense") ||
        typeof data.name !== "string" || !data.name.trim()) {
      invalid++;
      continue;
    }
    categories[data.type].add(data.name.trim().slice(0, 100));
  }
  const income = [...categories.income].sort((a, b) => a.localeCompare(b));
  const expenses = [...categories.expense].sort((a, b) => a.localeCompare(b));
  return {
    income: income.slice(0, limit),
    expense: expenses.slice(0, limit),
    truncated: income.length > limit || expenses.length > limit,
    invalid,
  };
}

function summarizeStaff(legacy, modern) {
  const members = new Map();
  for (const entry of [...legacy, ...modern]) {
    if (entry.data.role === "owner") {
      members.delete(entry.id);
      continue;
    }
    members.set(entry.id, entry.data);
  }
  let active = 0, inactive = 0;
  const staff = [];
  for (const data of members.values()) {
    if (data.active === true) active++;
    else inactive++;
    staff.push({
      name: typeof data.name === "string" ? data.name.trim().slice(0, 100) : "",
      active: data.active === true,
      shop: typeof data.shopNickname === "string" ? data.shopNickname.trim().slice(0, 100) : "",
    });
  }
  staff.sort((a, b) => a.name.localeCompare(b.name) || a.shop.localeCompare(b.shop));
  return { active, inactive, staff: staff.slice(0, 50), truncated: staff.length > 50 };
}

function summarizeStaffTasks(tasks, start, end) {
  const grouped = new Map();
  for (const task of tasks) {
    if (typeof task.assigneeUid !== "string" || !task.assigneeUid.trim()) continue;
    const summary = grouped.get(task.assigneeUid) || {
      name: typeof task.assigneeName === "string" ? task.assigneeName.trim().slice(0, 100) : "",
      open: 0, awaitingReview: 0, approvedInPeriod: 0,
    };
    if (["assigned", "inProgress", "returned"].includes(task.status)) summary.open++;
    else if (task.status === "submitted") summary.awaitingReview++;
    else if (task.status === "approved" && typeof task.approvedAt?.toMillis === "function") {
      const time = task.approvedAt.toMillis();
      if (time >= start && time < end) summary.approvedInPeriod++;
    }
    grouped.set(task.assigneeUid, summary);
  }
  const staff = [...grouped.values()].sort((a, b) => a.name.localeCompare(b.name));
  return { staff: staff.slice(0, 50), truncated: staff.length > 50 };
}

function signSnapshot(payload, secret) {
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const signature = createHmac("sha256", secret).update(body).digest("base64url");
  return `${body}.${signature}`;
}

function verifySnapshot(token, secret, uid, businessUid, scope, now = Date.now()) {
  if (typeof token !== "string" || token.length > MAX_SNAPSHOT_BYTES * 2) throw new Error("invalid-snapshot");
  const parts = token.split(".");
  if (parts.length !== 2) throw new Error("invalid-snapshot");
  const expected = createHmac("sha256", secret).update(parts[0]).digest();
  const actual = Buffer.from(parts[1], "base64url");
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) throw new Error("invalid-snapshot");
  const payload = JSON.parse(Buffer.from(parts[0], "base64url").toString("utf8"));
  if (payload.uid !== uid || payload.businessUid !== businessUid ||
      payload.expiresAt <= now || JSON.stringify(payload.scope) !== JSON.stringify(scope)) {
    throw new Error("expired-or-changed-snapshot");
  }
  return payload.context;
}

function summarizeTransactions(records) {
  let income = 0, expenses = 0, count = 0, invalid = 0;
  const categories = new Map();
  const incomeByDayUtc = {};
  for (const data of records) {
    if (typeof data.amount !== "number" || !Number.isFinite(data.amount) ||
        data.amount < 0 || !["income", "expense"].includes(data.type)) {
      invalid++;
      continue;
    }
    count++;
    if (data.type === "income") {
      income += data.amount;
      if (typeof data.date?.toDate === "function") {
        const day = data.date.toDate().toISOString().slice(0, 10);
        incomeByDayUtc[day] = (incomeByDayUtc[day] || 0) + data.amount;
      }
    }
    else {
      expenses += data.amount;
      const category = String(data.category || "Uncategorized").trim().slice(0, 100) || "Uncategorized";
      categories.set(category, (categories.get(category) || 0) + data.amount);
    }
  }
  return {
    income, expenses, count, invalid, incomeByDayUtc,
    expenseCategories: [...categories].sort((a, b) => b[1] - a[1]).slice(0, 30)
      .map(([category, amount]) => ({ category, amount })),
    categoriesTruncated: categories.size > 30,
  };
}

function summarizeTransactionDetails(records, maxBytes = 20000) {
  const valid = records.filter((record) =>
    ["income", "expense"].includes(record.type) &&
    typeof record.amount === "number" && Number.isFinite(record.amount) &&
    record.amount >= 0 && typeof record.date?.toDate === "function",
  ).sort((left, right) => right.date.toDate().getTime() - left.date.toDate().getTime());
  const entries = [];
  let bytes = 2;
  let descriptionsTruncated = false;
  for (const record of valid) {
    const description = typeof record.description === "string" ? record.description : "";
    const category = typeof record.category === "string" ? record.category : "";
    const shopNickname = typeof record.shopNickname === "string" ? record.shopNickname : "";
    const entry = {
      type: record.type,
      amount: record.amount,
      date: record.date.toDate().toISOString(),
      category: category.slice(0, 100),
      description: description.slice(0, 300),
      shopNickname: shopNickname.slice(0, 100),
    };
    const entryBytes = Buffer.byteLength(JSON.stringify(entry)) + (entries.length ? 1 : 0);
    if (bytes + entryBytes > maxBytes) break;
    bytes += entryBytes;
    entries.push(entry);
    if (description.length > 300 || category.length > 100 || shopNickname.length > 100) {
      descriptionsTruncated = true;
    }
  }
  return {
    entries,
    total: valid.length,
    truncated: entries.length < valid.length,
    fieldsTruncated: descriptionsTruncated,
    invalid: records.length - valid.length,
  };
}

function validateMessages(messages) {
  if (!Array.isArray(messages) || messages.length < 1 || messages.length > 12) throw new Error("invalid-messages");
  return messages.map((message) => {
    if (!message || !["user", "assistant"].includes(message.role) ||
        typeof message.content !== "string" || !message.content.trim() ||
        message.content.length > 2000) throw new Error("invalid-messages");
    return { role: message.role, content: message.content.trim() };
  });
}

module.exports = {
  MAX_RECORDS, MAX_SNAPSHOT_BYTES, scopeFor, signSnapshot,
  verifySnapshot, summarizeTransactions, summarizeTransactionDetails, summarizePurchases, summarizeTasks,
  summarizeDocuments, summarizeInventory, summarizeStaff, summarizeStaffTasks, validateMessages,
  summarizeProductCatalog, summarizeCategories,
};
