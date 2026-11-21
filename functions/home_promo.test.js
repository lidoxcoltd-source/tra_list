const test = require("node:test");
const assert = require("node:assert/strict");
const homePromo = require("./home_promo");

function database() {
  const docs = new Map();
  return {
    doc: (path) => path,
    runTransaction: async (run) => run({
      get: async (ref) => ({ data: () => docs.get(ref) }),
      set: (ref, value) => docs.set(ref, value),
    }),
    docs,
  };
}

test("promo cards are validated, bounded, and include both brands", () => {
  const cards = homePromo.parseCards(JSON.stringify({
    cards: [
      { brand: "MJASI", headline: "Sell smarter", body: "Track sales and stock." },
      { brand: "ISHER AI", headline: "Ask Isher", body: "Get clear business summaries." },
      { brand: "MJASI", headline: "Stay organized", body: "Manage invoices in one place." },
    ],
  }));
  assert.equal(cards.length, 3);
  assert.equal(cards[1].brand, "ISHER AI");
});

test("promo card responses reject missing brands, empty copy, and malformed JSON", () => {
  assert.throws(() => homePromo.parseCards("{"), /invalid-promo-response/);
  assert.throws(() => homePromo.parseCards(JSON.stringify({ cards: [] })), /invalid-promo-response/);
  assert.throws(() => homePromo.parseCards(JSON.stringify({
    cards: [
      { brand: "MJASI", headline: "", body: "Description." },
      { brand: "MJASI", headline: "Title", body: "Description." },
      { brand: "MJASI", headline: "Title", body: "Description." },
    ],
  })), /invalid-promo-response/);
});

test("promo generation attempts are limited per user and day", async () => {
  const db = database();
  const now = Date.UTC(2026, 10, 20, 12);
  for (let i = 0; i < homePromo.DAILY_ATTEMPT_LIMIT; i++) {
    await homePromo.reserve(db, "user", now);
  }
  await assert.rejects(homePromo.reserve(db, "user", now), /quota-exhausted/);
  await homePromo.reserve(db, "another-user", now);
  await homePromo.reserve(db, "user", now + 24 * 60 * 60 * 1000);
});
