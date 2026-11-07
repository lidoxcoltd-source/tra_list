const test = require("node:test");
const assert = require("node:assert/strict");
const { nextReservation, hangUp } = require("./voice_common");

test("voice limit rejects concurrent and third daily session", () => {
  const now = Date.parse("2026-11-07T10:00:00Z");
  const first = nextReservation({}, now, "first");
  assert.equal(first.count, 1);
  assert.throws(() => nextReservation(first, now + 1000, "other"), /limit/);
  const second = nextReservation({ ...first, activeUntil: 0 }, now + 1000, "second");
  assert.equal(second.count, 2);
  assert.throws(() => nextReservation({ ...second, activeUntil: 0 }, now + 2000, "third"), /limit/);
  assert.equal(nextReservation({ ...second, activeUntil: 0 }, now + 86400000, "tomorrow").count, 1);
});

test("hangup rejects invalid call ids before sending", async () => {
  await assert.rejects(hangUp("../not-a-call", "secret"), /Invalid call ID/);
});
