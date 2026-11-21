const test = require("node:test");
const assert = require("node:assert/strict");
const { EventEmitter } = require("node:events");
const greeting = require("./isher_greeting");
const { dayInTanzania } = require("./business_ai_quota");

function database(initial = {}) {
  const docs = new Map(Object.entries(initial));
  return {
    docs,
    doc: (path) => path,
    runTransaction: async (run) => run({
      get: async (ref) => ({
        exists: docs.has(ref),
        data: () => docs.get(ref),
      }),
      set: (ref, value) => docs.set(ref, value),
      update: (ref, value) => {
        if (!docs.has(ref)) throw new Error("not-found");
        docs.set(ref, { ...docs.get(ref), ...value });
      },
      create: (ref, value) => {
        if (docs.has(ref)) throw new Error("already-exists");
        docs.set(ref, value);
      },
    }),
  };
}

function packageDatabase() {
  const now = Date.now();
  return database({
    "isherTestSchedules/business": {
      activeId: "subscription",
      queuedIds: [],
      packageRequired: true,
    },
    "isherTestSubscriptions/subscription": {
      businessUid: "business",
      status: "active",
      endsAt: now + 86400000,
      package: { chats: 10, voiceSessions: 2, voiceMinutes: 5 },
      remainingChats: 10,
      remainingVoiceSessions: 2,
    },
  });
}

test("three successful greetings per user, failures release reservations", async () => {
  const db = database();
  const failed = await greeting.reserve(db, "user");
  await greeting.finish(db, failed, false);
  for (let i = 0; i < 3; i++) {
    const reservation = await greeting.reserve(db, "user");
    await greeting.finish(db, reservation, true);
  }
  await assert.rejects(greeting.reserve(db, "user"), /quota-exhausted/);
  await greeting.reserve(db, "another-user");
});

test("active package voice sessions cover greetings after the free daily quota", async () => {
  const db = packageDatabase();
  for (let i = 0; i < 3; i++) {
    const freeReservation = await greeting.reserve(db, "user");
    await greeting.finish(db, freeReservation, true);
  }

  const packageReservation = await greeting.reserve(db, "user", "business");
  assert.equal(packageReservation.packageCharge.subscriptionId, "subscription");
  assert.equal(
    db.docs.get("isherTestSubscriptions/subscription").remainingVoiceSessions,
    1,
  );
  await greeting.finish(db, packageReservation, true);
  assert.equal(
    db.docs.get("isherTestSubscriptions/subscription/charges/" + packageReservation.packageCharge.reservationId).status,
    "consumed",
  );
});

test("available package voice sessions bypass the daily free-attempt cap", async () => {
  const db = packageDatabase();
  db.docs.set(`isherGreetingUsage/user`, {
    day: dayInTanzania(Date.now()),
    used: 3,
    attempts: 12,
    leases: {},
  });

  const reservation = await greeting.reserve(db, "user", "business");

  assert.equal(reservation.packageCharge.subscriptionId, "subscription");
  assert.equal(
    db.docs.get("isherTestSubscriptions/subscription").remainingVoiceSessions,
    1,
  );
  assert.equal(db.docs.get("isherGreetingUsage/user").attempts, 0);
});

test("failed package greeting generation refunds its voice session", async () => {
  const db = packageDatabase();
  const reservation = await greeting.reserve(db, "user", "business");
  await greeting.finish(db, reservation, false);
  assert.equal(
    db.docs.get("isherTestSubscriptions/subscription").remainingVoiceSessions,
    2,
  );
  assert.equal(
    db.docs.get("isherTestSubscriptions/subscription/charges/" + reservation.packageCharge.reservationId).status,
    "refunded",
  );
});

test("greeting variants are localized, personalized, and distinct", () => {
  const sw = [0, 1, 2].map((variant) => greeting.greetingText("sw", "Duka Asha", variant));
  const en = [0, 1, 2].map((variant) => greeting.greetingText("en", "Duka Asha", variant));
  assert.equal(new Set(sw).size, 3);
  assert.equal(new Set(en).size, 3);
  assert.ok(sw.every((text) => text.includes("Duka Asha")));
  assert.ok(en.every((text) => text.includes("Duka Asha")));
  assert.throws(() => greeting.greetingText("sw", "", 3), /invalid-greeting/);
});

test("Gemini is the default greeting provider while explicit OpenAI remains supported", () => {
  assert.equal(greeting.providerFromSettings(undefined), "gemini");
  assert.equal(greeting.providerFromSettings({}), "gemini");
  assert.equal(greeting.providerFromSettings({ greetingProvider: "openai" }), "openai");
  assert.equal(greeting.providerFromSettings({ greetingProvider: "gemini" }), "gemini");
});

test("requested greeting provider takes priority over the admin default", () => {
  assert.deepEqual(
    greeting.providersForRequest(
      "openai",
      { greetingProvider: "gemini" },
      ["gemini", "openai"],
    ),
    ["openai", "gemini"],
  );
  assert.deepEqual(
    greeting.providersForRequest(
      undefined,
      { greetingProvider: "openai" },
      ["gemini", "openai"],
    ),
    ["openai", "gemini"],
  );
  assert.deepEqual(
    greeting.providersForRequest(
      "gemini",
      { greetingProvider: "gemini" },
      ["openai"],
    ),
    ["openai"],
  );
  assert.throws(
    () => greeting.providersForRequest("unknown", {}, ["gemini"]),
    /invalid-voice-provider/,
  );
});

test("greeting synthesis tries the preferred AI provider then an enabled fallback", async () => {
  const attempts = [];
  const audio = await greeting.synthesizeWithFallback(
    ["gemini", "openai"],
    async (provider) => {
      attempts.push(provider);
      if (provider === "gemini") throw new Error("Gemini unavailable");
      return Buffer.from("audio");
    },
  );
  assert.deepEqual(attempts, ["gemini", "openai"]);
  assert.equal(audio.toString(), "audio");
});

test("generated business greeting text is bounded and validated", () => {
  const text = "Habari Lidox, za asubuhi. Mapato yaliyorekodiwa ni TZS 120,000.";
  assert.equal(greeting.greetingText("sw", "Lidox", 0, text), text);
  assert.throws(() => greeting.greetingText("sw", "Lidox", 0, " "), /invalid-greeting-text/);
  assert.throws(() => greeting.greetingText("sw", "Lidox", 0, "bad\ntext"), /invalid-greeting-text/);
  assert.throws(() => greeting.greetingText("sw", "Lidox", 0, "x".repeat(1601)), /invalid-greeting-text/);
});

test("outstanding reservations count toward the daily limit", async () => {
  const db = database();
  for (let i = 0; i < 3; i++) await greeting.reserve(db, "user");
  await assert.rejects(greeting.reserve(db, "user"), /quota-exhausted/);
});

test("repeated failed attempts are capped independently", async () => {
  const db = database();
  for (let i = 0; i < 12; i++) {
    const reservation = await greeting.reserve(db, "user");
    await greeting.finish(db, reservation, false);
  }
  await assert.rejects(greeting.reserve(db, "user"), /quota-exhausted/);
});

test("realtime audio is returned as valid mono PCM WAV", async () => {
  class Socket extends EventEmitter {
    constructor(url, options) {
      super();
      assert.match(url, /gpt-realtime-2\.1-mini/);
      assert.equal(options.headers.Authorization, "Bearer test");
      this.events = [];
      process.nextTick(() => this.emit("open"));
    }
    send(raw) {
      const event = JSON.parse(raw);
      this.events.push(event);
      if (event.type === "session.update") {
        process.nextTick(() => this.emit("message", JSON.stringify({ type: "session.updated" })));
      } else if (event.type === "response.create") {
        assert.equal(this.events[1].item.content[0].text, "Habari");
        process.nextTick(() => {
          this.emit("message", JSON.stringify({ type: "response.output_audio.delta", delta: Buffer.from([1, 2]).toString("base64") }));
          this.emit("message", JSON.stringify({ type: "response.done", response: { status: "completed" } }));
        });
      }
    }
    terminate() {}
  }
  const result = await greeting.synthesize({ apiKey: "test", text: "Habari", Socket });
  assert.equal(result.toString("ascii", 0, 4), "RIFF");
  assert.equal(result.readUInt32LE(24), 24000);
  assert.equal(result.readUInt32LE(40), 2);
  assert.deepEqual(result.subarray(44), Buffer.from([1, 2]));
});

test("incomplete realtime response fails", async () => {
  class Socket extends EventEmitter {
    constructor() {
      super();
      process.nextTick(() => this.emit("message", JSON.stringify({ type: "response.done", response: { status: "failed" } })));
    }
    terminate() {}
  }
  await assert.rejects(greeting.synthesize({ apiKey: "test", text: "Habari", Socket }), /speech-incomplete/);
});
