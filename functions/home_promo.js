const { dayInTanzania } = require("./business_ai_quota");

const DAILY_ATTEMPT_LIMIT = 5;
const ALLOWED_BRANDS = new Set(["MJASI", "ISHER AI"]);

function parseCards(content) {
  let result;
  try {
    result = JSON.parse(content);
  } catch (_) {
    throw new Error("invalid-promo-response");
  }
  if (!Array.isArray(result?.cards) || result.cards.length !== 3) {
    throw new Error("invalid-promo-response");
  }
  const cards = result.cards.map((card) => {
    if (!card || !ALLOWED_BRANDS.has(card.brand)) {
      throw new Error("invalid-promo-response");
    }
    const clean = (value, limit) => typeof value === "string"
      ? value.replace(/[\r\n\t]+/g, " ").trim().slice(0, limit)
      : "";
    const headline = clean(card.headline, 60);
    const body = clean(card.body, 120);
    if (!headline || !body) throw new Error("invalid-promo-response");
    return { brand: card.brand, headline, body };
  });
  if (!cards.some((card) => card.brand === "MJASI") ||
      !cards.some((card) => card.brand === "ISHER AI")) {
    throw new Error("invalid-promo-response");
  }
  return cards;
}

async function reserve(db, uid, now = Date.now()) {
  if (typeof uid !== "string" || !uid || uid.includes("/")) {
    throw new Error("invalid-user");
  }
  const ref = db.doc(`homePromoUsage/${uid}`);
  const day = dayInTanzania(now);
  await db.runTransaction(async (tx) => {
    const data = (await tx.get(ref)).data() || {};
    const attempts = data.day === day ? data.attempts : 0;
    if (!Number.isSafeInteger(attempts) || attempts < 0) {
      throw new Error("invalid-usage");
    }
    if (attempts >= DAILY_ATTEMPT_LIMIT) throw new Error("quota-exhausted");
    tx.set(ref, { day, attempts: attempts + 1, updatedAt: now });
  });
}

module.exports = { parseCards, reserve, DAILY_ATTEMPT_LIMIT };
