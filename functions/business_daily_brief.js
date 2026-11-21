const ACTIVE_TASK_STATUSES = new Set([
  "assigned",
  "inProgress",
  "returned",
  "submitted",
]);

function timestampMillis(value) {
  if (typeof value?.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return null;
}

function dateInOffset(millis, timezoneOffsetMinutes) {
  return new Date(millis + timezoneOffsetMinutes * 60 * 1000)
    .toISOString()
    .slice(0, 10);
}

function dailyBriefFacts({
  businessName,
  transactions = [],
  debts = [],
  products = [],
  tasks = [],
  startMillis,
  endMillis,
  nowMillis,
  timezoneOffsetMinutes = 180,
}) {
  let income = 0;
  let expenses = 0;
  let transactionCount = 0;
  for (const record of transactions) {
    if (!Number.isFinite(record.amount) || record.amount < 0 ||
        (record.type !== "income" && record.type !== "expense")) continue;
    transactionCount++;
    if (record.type === "income") income += record.amount;
    else expenses += record.amount;
  }

  let receivable = 0;
  let payable = 0;
  const overdueDebts = [];
  const debtsDueToday = [];
  const upcomingDebts = [];
  for (const debt of debts) {
    if (!Number.isFinite(debt.principal) || !Number.isFinite(debt.amountPaid) ||
        debt.principal < 0 || debt.amountPaid < 0) continue;
    const balance = Math.max(0, debt.principal - debt.amountPaid);
    if (balance <= 0) continue;
    if (debt.direction === "customerOwesShop") receivable += balance;
    else if (debt.direction === "shopOwesOther") payable += balance;
    else continue;

    const due = timestampMillis(debt.dueDate);
    if (due == null) continue;
    const item = {
      name: String(debt.debtorName || "Unnamed").trim().slice(0, 80),
      balance,
      direction: debt.direction,
      dueDate: dateInOffset(due, timezoneOffsetMinutes),
    };
    if (due < startMillis) overdueDebts.push(item);
    else if (due < endMillis) debtsDueToday.push(item);
    else if (due <= endMillis + 7 * 86400000) upcomingDebts.push(item);
  }
  const oldestDueFirst = (a, b) => a.dueDate.localeCompare(b.dueDate);
  overdueDebts.sort(oldestDueFirst);
  debtsDueToday.sort(oldestDueFirst);
  upcomingDebts.sort(oldestDueFirst);

  const stockIssues = [];
  for (const product of products) {
    if (product.active === false || product.tracked === false ||
        !Number.isFinite(product.quantity) ||
        !Number.isFinite(product.lowStockThreshold) ||
        product.quantity > product.lowStockThreshold) continue;
    stockIssues.push({
      name: String(product.name || "Unnamed").trim().slice(0, 80),
      quantity: product.quantity,
      unit: String(product.unit || "").slice(0, 20),
      out: product.quantity <= 0,
    });
  }
  stockIssues.sort((a, b) => Number(b.out) - Number(a.out));

  const dueTasks = [];
  const openTasks = [];
  for (const task of tasks) {
    if (!ACTIVE_TASK_STATUSES.has(task.status)) continue;
    const due = timestampMillis(task.dueDate);
    const item = {
      title: String(task.title || "Untitled task").trim().slice(0, 100),
      dueDate: due == null ? null : dateInOffset(due, timezoneOffsetMinutes),
      status: task.status,
      priority: String(task.priority || "normal").slice(0, 20),
      awaitingReview: task.status === "submitted",
      overdue: task.status !== "submitted" && due != null && due < startMillis,
      dueToday: task.status !== "submitted" &&
        due != null && due >= startMillis && due < endMillis,
    };
    openTasks.push(item);
    if (task.status !== "submitted" &&
        due != null && due <= endMillis + 7 * 86400000) {
      dueTasks.push(item);
    }
  }
  const taskOrder = (a, b) =>
    Number(b.overdue) - Number(a.overdue) ||
    (a.dueDate || "9999-12-31").localeCompare(b.dueDate || "9999-12-31");
  dueTasks.sort(taskOrder);
  openTasks.sort(taskOrder);

  return {
    businessName: String(businessName || "Business").slice(0, 120),
    date: dateInOffset(startMillis, timezoneOffsetMinutes),
    income,
    expenses,
    cashFlow: income - expenses,
    transactionCount,
    receivable,
    payable,
    overdueDebts: overdueDebts.slice(0, 10),
    overdueDebtCount: overdueDebts.length,
    debtsDueToday: debtsDueToday.slice(0, 10),
    debtsDueTodayCount: debtsDueToday.length,
    upcomingDebts: upcomingDebts.slice(0, 10),
    upcomingDebtCount: upcomingDebts.length,
    stockIssues: stockIssues.slice(0, 20),
    stockIssueCount: stockIssues.length,
    openTasks: openTasks.slice(0, 12),
    openTaskCount: openTasks.length,
    dueTasks: dueTasks.slice(0, 12),
    dueTaskCount: dueTasks.length,
    overdueTaskCount: dueTasks.filter((task) => task.overdue).length,
    tasksDueTodayCount: dueTasks.filter((task) => task.dueToday).length,
    awaitingReviewTaskCount: openTasks.filter((task) => task.awaitingReview).length,
    asOf: new Date(nowMillis).toISOString(),
  };
}

function dailyBriefQuestion({ facts, weather, timeOfDay, language }) {
  const greeting = {
    morning: "morning",
    afternoon: "afternoon",
    evening: "evening",
  }[timeOfDay] || "day";
  return [
    `Prepare a short daily business briefing in ${language}.`,
    `Use a ${greeting} greeting.`,
    "Summarize today's recorded income and expenses as cash flow, never call it profit.",
    "Prioritize overdue and due-today debts, stockouts and low stock, then overdue and due-today tasks.",
    "Mention tasks awaiting review and upcoming debts or tasks only when useful. Give one practical next action.",
    weather
      ? "Explain the local weather in plain language using the current temperature, feels-like temperature, today's high, and rain chance when available. weatherCode is WMO: 0 clear, 1 mostly clear, 2 partly cloudy, 3 overcast, 45/48 fog, 51-67 drizzle/freezing rain, 71-77 snow, 80-82 rain showers, 85/86 snow showers, 95+ thunderstorm. Give at least one specific action: umbrella/raincoat for likely rain, water and shade when the high is 30 C or more, and cautious travel in fog or storms. A rain chance is not a guarantee."
      : "Weather is unavailable; do not guess or mention local conditions.",
    "Do not invent data, contact details, causes, or forecasts. Keep the answer concise and use only these facts.",
    `Facts: ${JSON.stringify(facts)}`,
    `Weather: ${JSON.stringify(weather)}`,
  ].join("\n");
}

module.exports = { dailyBriefFacts, dailyBriefQuestion };
