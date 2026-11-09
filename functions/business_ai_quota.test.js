const test = require("node:test");
const assert = require("node:assert/strict");
const quota = require("./business_ai_quota");

test("daily limits reset at midnight in Tanzania and extras persist", () => {
  const before = Date.parse("2026-11-07T20:59:30Z");
  const after = Date.parse("2026-11-07T21:00:00Z");
  assert.equal(quota.dayInTanzania(before), "2026-11-07");
  assert.equal(quota.dayInTanzania(after), "2026-11-08");
  const settings = { ...quota.DEFAULTS, dailyVoice: 1, dailyMessages: 1 };
  let usage = quota.consume({ extraVoice: 1, extraMessages: 1 }, settings, "voice", before, "one");
  assert.throws(() => quota.consume(usage, settings, "voice", before, "two"), /voice-active/);
  assert.throws(() => quota.consume(usage, settings, "voice", before + 1000, "two"),
    (error) => error.message === "voice-active" && error.retryAfterSeconds === 359);
  usage.activeUntil = 0;
  usage = quota.consume(usage, settings, "voice", before, "two");
  usage.activeUntil = 0;
  assert.throws(() => quota.consume(usage, settings, "voice", before, "three"), /quota-exhausted/);
  usage = quota.consume(usage, settings, "message", before);
  assert.throws(() => quota.consume(usage, settings, "message", before + 1), /rate-limited/);
  usage = quota.consume(usage, settings, "message", before + 10000);
  assert.equal(usage.extraMessages, 0);
  assert.equal(quota.consume(usage, settings, "voice", after, "next").voiceUsed, 1);
});

test("rejects malformed or out-of-range settings and usage", () => {
  assert.throws(() => quota.validateSettings({ ...quota.DEFAULTS, voiceMinutes: 0 }), /invalid-settings/);
  assert.throws(() => quota.validateSettings({ ...quota.DEFAULTS, voicePrice: 1.5 }), /invalid-settings/);
  assert.throws(() => quota.usageForDay({ extraVoice: -1 }, Date.now()), /invalid-usage/);
  assert.deepEqual(quota.settingsFromDocument(undefined), quota.DEFAULTS);
});

function fakeDb(initial) {
  let state = { ...initial };
  return {
    doc: () => ({}),
    runTransaction: (run) => run({
      get: async () => ({ data: () => state }),
      update: (_, update) => { state = { ...state, ...update }; },
    }),
    get state() { return state; },
  };
}

test("failed voice reservation refunds only its own daily charge", async () => {
  const now = Date.parse("2026-11-07T12:00:00Z");
  const usage = quota.consume({}, quota.DEFAULTS, "voice", now, "first");
  const afterMessage = quota.consume(usage, quota.DEFAULTS, "message", now + 10000);
  const db = fakeDb(afterMessage);
  const charge = { source: "daily", day: usage.day };
  assert.equal(await quota.rollbackVoiceReservation(db, "user", "other", charge), false);
  assert.equal(db.state.voiceUsed, 1);
  assert.equal(await quota.rollbackVoiceReservation(db, "user", "first", charge), true);
  assert.equal(db.state.voiceUsed, 0);
  assert.equal(db.state.messagesUsed, 1);
  assert.equal(db.state.activeUntil, 0);
  assert.equal(await quota.rollbackVoiceReservation(db, "user", "first", charge), false);
});

test("failed extra voice reservation refunds across the daily reset", async () => {
  const now = Date.parse("2026-11-07T20:59:30Z");
  const usage = quota.consume({ extraVoice: 1 }, { ...quota.DEFAULTS, dailyVoice: 0 }, "voice", now, "extra");
  const nextDay = quota.usageForDay(usage, now + 60000);
  const db = fakeDb(nextDay);
  assert.equal(await quota.rollbackVoiceReservation(db, "user", "extra", { source: "extra", day: usage.day }), true);
  assert.equal(db.state.extraVoice, 1);
  assert.equal(db.state.voiceUsed, 0);
});

test("daily voice reservation does not refund a different day's usage", async () => {
  const now = Date.parse("2026-11-07T20:59:30Z");
  const usage = quota.consume({}, quota.DEFAULTS, "voice", now, "daily");
  const db = fakeDb({ ...quota.usageForDay(usage, now + 60000), voiceUsed: 1 });
  assert.equal(await quota.rollbackVoiceReservation(db, "user", "daily", { source: "daily", day: usage.day }), true);
  assert.equal(db.state.voiceUsed, 1);
});
