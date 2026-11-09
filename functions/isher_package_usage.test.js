const test = require("node:test");
const assert = require("node:assert/strict");
const usage = require("./isher_package_usage");

function fakeDb(initial) {
  const docs = new Map(Object.entries(initial));
  return {
    docs,
    doc: (path) => {
      if (!path || path.split("/").length % 2 !== 0) {
        throw new Error(`invalid-document-path:${path}`);
      }
      return path;
    },
    async runTransaction(work) {
      const tx = {
        get: async (ref) => ({
          exists: docs.has(ref),
          data: () => docs.get(ref),
        }),
        update: (ref, value) => docs.set(ref, { ...docs.get(ref), ...value }),
        create: (ref, value) => {
          if (docs.has(ref)) throw new Error("already-exists");
          docs.set(ref, value);
        },
      };
      return work(tx);
    },
  };
}

function subscription({ id = "test-one", status = "active", chats = 5, voices = 2 } = {}) {
  return {
    businessUid: "business",
    status,
    startsAt: 100,
    endsAt: Date.UTC(2027, 0, 1),
    package: { chats, voiceSessions: voices, voiceMinutes: 5 },
    remainingChats: chats,
    remainingVoiceSessions: voices,
  };
}

function dbWithPackage(current = subscription(), queue = []) {
  return fakeDb({
    "isherTestSchedules/business": {
      activeId: current ? "test-one" : null,
      endAt: current?.endsAt ?? 0,
      queuedIds: queue,
      packageRequired: true,
    },
    ...(current ? { "isherTestSubscriptions/test-one": current } : {}),
    ...queue.reduce((docs, id, index) => {
      docs[`isherTestSubscriptions/${id}`] = subscription({
        id, status: "queued", chats: 5 + index, voices: 2 + index,
      });
      return docs;
    }, {}),
  });
}

async function reserve(db, kind, id, now = 1000) {
  return db.runTransaction((tx) =>
    usage.reserve(tx, db, "business", kind, now, id));
}

test("test package permits five chats and two voice sessions, then expires", async () => {
  const db = dbWithPackage();
  for (let index = 0; index < 5; index++) {
    const result = await reserve(db, "message", `chat-${index}`);
    assert.equal(result.subscriptionId, "test-one");
    assert.equal(result.exhausted, false);
    assert.equal(result.willExhaust, false);
  }
  const active = db.docs.get("isherTestSubscriptions/test-one");
  assert.equal(active.remainingChats, 0);
  assert.equal(active.remainingVoiceSessions, 2);
  assert.equal(active.status, "active");
  assert.equal((await reserve(db, "message", "chat-six")).exhausted, true);

  assert.equal((await reserve(db, "voice", "voice-one")).exhausted, false);
  const finalVoice = await reserve(db, "voice", "voice-two");
  assert.equal(finalVoice.exhausted, false);
  assert.equal(finalVoice.willExhaust, true);
  assert.equal(db.docs.get("isherTestSubscriptions/test-one").status, "exhausted");
  assert.equal((await reserve(db, "voice", "voice-three")).exhausted, true);
});

test("failed AI response refunds its package chat exactly once", async () => {
  const db = dbWithPackage();
  const reservation = await reserve(db, "message", "chat-failed");
  const charge = {
    subscriptionId: reservation.subscriptionId,
    reservationId: reservation.reservationId,
  };
  assert.equal(db.docs.get("isherTestSubscriptions/test-one").remainingChats, 4);
  assert.equal(await usage.refundReservation(db, "business", charge), true);
  assert.equal(await usage.refundReservation(db, "business", charge), false);
  assert.equal(db.docs.get("isherTestSubscriptions/test-one").remainingChats, 5);
});

test("next queued package activates after the prior package is exhausted", async () => {
  const expired = subscription({ chats: 0, voices: 0 });
  expired.status = "exhausted";
  const db = dbWithPackage(expired, ["test-two"]);
  const reservation = await reserve(db, "message", "next-chat");
  assert.equal(reservation.subscriptionId, "test-two");
  assert.equal(db.docs.get("isherTestSubscriptions/test-two").status, "active");
  assert.equal(db.docs.get("isherTestSubscriptions/test-two").remainingChats, 4);
  assert.equal(db.docs.get("isherTestSchedules/business").activeId, "test-two");
  assert.deepEqual(db.docs.get("isherTestSchedules/business").queuedIds, []);
});

test("empty schedules do not create an invalid Firestore document reference", async () => {
  const required = fakeDb({
    "isherTestSchedules/business": {
      activeId: null,
      queuedIds: [],
      packageRequired: true,
    },
  });
  assert.equal((await reserve(required, "voice", "no-active-package")).exhausted, true);

  const legacy = fakeDb({
    "isherTestSchedules/business": {
      activeId: null,
      queuedIds: [],
      packageRequired: false,
    },
  });
  assert.equal(await reserve(legacy, "voice", "legacy-business"), null);
});
