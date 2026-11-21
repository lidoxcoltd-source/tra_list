const test = require("node:test");
const assert = require("node:assert/strict");
const { dailyBriefFacts, dailyBriefQuestion } = require("./business_daily_brief");

const startMillis = Date.parse("2026-11-21T00:00:00+03:00");
const endMillis = startMillis + 86400000;
const timestamp = (value) => ({ toMillis: () => Date.parse(value) });

test("daily brief facts summarize recorded totals and only actionable items", () => {
  const facts = dailyBriefFacts({
    businessName: "Shop",
    startMillis,
    endMillis,
    nowMillis: startMillis + 12 * 60 * 60 * 1000,
    transactions: [
      { type: "income", amount: 100 },
      { type: "expense", amount: 30 },
      { type: "income", amount: -1 },
    ],
    debts: [
      {
        debtorName: "Late customer",
        principal: 80,
        amountPaid: 20,
        direction: "customerOwesShop",
        dueDate: timestamp("2026-11-20T00:00:00+03:00"),
        phone: "private",
      },
      {
        debtorName: "Paid debt",
        principal: 50,
        amountPaid: 50,
        direction: "customerOwesShop",
        dueDate: timestamp("2026-11-21T00:00:00+03:00"),
      },
      {
        debtorName: "Today",
        principal: 40,
        amountPaid: 0,
        direction: "shopOwesOther",
        dueDate: timestamp("2026-11-21T12:00:00+03:00"),
      },
    ],
    products: [
      { name: "Out", quantity: 0, lowStockThreshold: 2, tracked: true },
      { name: "Healthy", quantity: 10, lowStockThreshold: 2, tracked: true },
      { name: "Service", quantity: 0, lowStockThreshold: 0, tracked: false },
    ],
    tasks: [
      {
        title: "Late task",
        status: "assigned",
        dueDate: timestamp("2026-11-20T00:00:00+03:00"),
      },
      {
        title: "Done task",
        status: "approved",
        dueDate: timestamp("2026-11-21T00:00:00+03:00"),
      },
      {
        title: "Submitted task",
        status: "submitted",
        dueDate: timestamp("2026-11-20T00:00:00+03:00"),
      },
    ],
  });

  assert.equal(facts.income, 100);
  assert.equal(facts.date, "2026-11-21");
  assert.equal(facts.expenses, 30);
  assert.equal(facts.cashFlow, 70);
  assert.equal(facts.receivable, 60);
  assert.equal(facts.payable, 40);
  assert.equal(facts.overdueDebtCount, 1);
  assert.equal(facts.debtsDueTodayCount, 1);
  assert.equal(facts.stockIssueCount, 1);
  assert.equal(facts.stockIssues[0].out, true);
  assert.equal(facts.overdueTaskCount, 1);
  assert.equal(facts.dueTaskCount, 1);
  assert.equal(facts.awaitingReviewTaskCount, 1);
  assert.equal(facts.openTaskCount, 2);
  assert.equal(JSON.stringify(facts).includes("private"), false);
});

test("daily brief question sets language and guards against invented facts", () => {
  const question = dailyBriefQuestion({
    facts: { income: 100 },
    weather: null,
    timeOfDay: "morning",
    language: "Swahili",
  });
  assert.match(question, /Swahili/);
  assert.match(question, /morning greeting/);
  assert.match(question, /Do not invent data/);
});

test("daily brief asks for a local weather explanation and concrete action", () => {
  const question = dailyBriefQuestion({
    facts: { income: 100 },
    weather: {
      temperatureC: 28,
      feelsLikeC: 30,
      maxTemperatureC: 32,
      precipitationChance: 60,
      weatherCode: 61,
    },
    timeOfDay: "afternoon",
    language: "Swahili",
  });
  assert.match(question, /Explain the local weather in plain language/);
  assert.match(question, /umbrella\/raincoat/);
  assert.match(question, /A rain chance is not a guarantee/);
});
