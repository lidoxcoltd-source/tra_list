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
  verifySnapshot, summarizeTransactions, summarizePurchases, summarizeTasks, validateMessages,
};
