const test = require("node:test");
const assert = require("node:assert/strict");
const { EventEmitter } = require("node:events");
const greeting = require("./isher_greeting");

function database() {
  const docs = new Map();
  return {
    doc: (path) => path,
    runTransaction: async (run) => run({
      get: async (ref) => ({ data: () => docs.get(ref) }),
      set: (ref, value) => docs.set(ref, value),
    }),
  };
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

test("greeting variants are localized, personalized, and distinct", () => {
  const sw = [0, 1, 2].map((variant) => greeting.greetingText("sw", "Duka Asha", variant));
  const en = [0, 1, 2].map((variant) => greeting.greetingText("en", "Duka Asha", variant));
  assert.equal(new Set(sw).size, 3);
  assert.equal(new Set(en).size, 3);
  assert.ok(sw.every((text) => text.includes("Duka Asha")));
  assert.ok(en.every((text) => text.includes("Duka Asha")));
  assert.throws(() => greeting.greetingText("sw", "", 3), /invalid-greeting/);
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
