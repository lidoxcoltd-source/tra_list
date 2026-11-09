const test = require("node:test");
const assert = require("node:assert/strict");
const {
  purchase,
  purchaseExists,
  addMonth,
  validateSettings,
  activateQueuedIfDepleted,
} = require("./isher_test_payment");
const { DEFAULT_PACKAGES } = require("./isher_packages");

function fakeDb(initial) {
  const docs = new Map(Object.entries(initial));
  return {
    docs,
    doc: (path) => path,
    async runTransaction(work) {
      const writes = [];
      const tx = {
        get: async (ref) => ({
          exists: docs.has(ref),
          data: () => docs.get(ref),
        }),
        create: (ref, value) => writes.push(() => {
          if (docs.has(ref)) throw new Error("already-exists");
          docs.set(ref, value);
        }),
        update: (ref, value) => writes.push(() => docs.set(ref, { ...docs.get(ref), ...value })),
        set: (ref, value) => writes.push(() => docs.set(ref, value)),
      };
      const result = await work(tx);
      writes.forEach((write) => write());
      return result;
    },
  };
}

function args(db, overrides = {}) {
  return {
    db, uid: "owner", businessUid: "shop", packageId: "starter",
    expectedPackage: { ...DEFAULT_PACKAGES[0] },
    requestId: "first", timestamp: () => Date.UTC(2026, 0, 31),
    ...overrides,
  };
}

test("test payment requires explicit global TEST MODE but no user allowlist", async () => {
  const db = fakeDb({});
  await assert.rejects(purchase(args(db)), /test-disabled/);
  db.docs.set("businessAiConfig/testPayment", { settings: { enabled: true } });
  const record = await purchase(args(db, { uid: "any-signed-in-owner" }));
  assert.equal(record.uid, "any-signed-in-owner");
  assert.deepEqual(validateSettings({ enabled: true, allowedUids: ["legacy-user"] }), { enabled: true });
});

test("purchase records test-only amounts, idempotency, and a queued next package", async () => {
  const db = fakeDb({ "businessAiConfig/testPayment": { settings: { enabled: true } } });
  const first = await purchase(args(db));
  assert.equal(first.actualCollected, 0);
  assert.equal(first.quotasEnforced, true);
  assert.equal(first.status, "active");
  assert.equal(first.remainingChats, 60);
  assert.equal(first.remainingVoiceSessions, 5);
  assert.equal(first.endsAt, Date.UTC(2026, 1, 28));
  assert.deepEqual(await purchase(args(db)), first);
  assert.equal(db.docs.size, 4);
  const second = await purchase(args(db, {
    requestId: "second", packageId: "business", expectedPackage: { ...DEFAULT_PACKAGES[1] },
  }));
  assert.equal(second.startsAt, first.endsAt);
  assert.equal(second.endsAt, Date.UTC(2026, 2, 28));
  await assert.rejects(purchase(args(db, { businessUid: "different" })), /request-conflict/);
});

test("purchase status only recognizes a transaction for its owner and business", async () => {
  const db = fakeDb({
    "isherTestTransactions/known-request": {
      uid: "owner",
      businessUid: "shop",
    },
  });
  assert.equal(await purchaseExists({
    db, uid: "owner", businessUid: "shop", requestId: "known-request",
  }), true);
  assert.equal(await purchaseExists({
    db, uid: "other", businessUid: "shop", requestId: "known-request",
  }), false);
  assert.equal(await purchaseExists({
    db, uid: "owner", businessUid: "other", requestId: "known-request",
  }), false);
  assert.equal(await purchaseExists({
    db, uid: "owner", businessUid: "shop", requestId: "not-found",
  }), false);
});

test("purchase activates immediately when the active package quota is depleted", async () => {
  for (const remaining of [
    { remainingChats: 0, remainingVoiceSessions: 2 },
    { remainingChats: 5, remainingVoiceSessions: 0 },
  ]) {
    const active = {
      uid: "owner",
      businessUid: "shop",
      package: { ...DEFAULT_PACKAGES[0] },
      startsAt: Date.UTC(2026, 0, 1),
      endsAt: Date.UTC(2026, 1, 1),
      status: "active",
      remainingChats: remaining.remainingChats,
      remainingVoiceSessions: remaining.remainingVoiceSessions,
    };
    const db = fakeDb({
      "businessAiConfig/testPayment": { settings: { enabled: true } },
      "isherTestSchedules/shop": {
        activeId: "previous",
        endAt: active.endsAt,
        queuedIds: [],
        packageRequired: true,
      },
      "isherTestSubscriptions/previous": active,
    });

    const next = await purchase(args(db, {
      requestId: "replacement",
      packageId: "business",
      expectedPackage: { ...DEFAULT_PACKAGES[1] },
    }));

    assert.equal(next.status, "active");
    assert.equal(next.startsAt, Date.UTC(2026, 0, 31));
    assert.equal(db.docs.get("isherTestSchedules/shop").activeId, "replacement");
    assert.equal(db.docs.get("isherTestSubscriptions/previous").status, "exhausted");
  }
});

test("zero-quota package features do not mark a usable subscription exhausted", async () => {
  const active = {
    uid: "owner",
    businessUid: "shop",
    package: { ...DEFAULT_PACKAGES[0], chats: 0 },
    startsAt: Date.UTC(2026, 0, 1),
    endsAt: Date.UTC(2026, 1, 1),
    status: "active",
    remainingChats: 0,
    remainingVoiceSessions: 2,
  };
  const db = fakeDb({
    "businessAiConfig/testPayment": { settings: { enabled: true } },
    "isherTestSchedules/shop": {
      activeId: "voice-only",
      endAt: active.endsAt,
      queuedIds: [],
      packageRequired: true,
    },
    "isherTestSubscriptions/voice-only": active,
  });

  const next = await purchase(args(db, { requestId: "queued-next" }));

  assert.equal(next.status, "queued");
  assert.equal(db.docs.get("isherTestSchedules/shop").activeId, "voice-only");
});

test("existing queued package is activated on subscription refresh after quota depletion", async () => {
  const queuedId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
  const exhaustedByChat = {
    uid: "owner",
    businessUid: "shop",
    package: { ...DEFAULT_PACKAGES[0] },
    startsAt: Date.UTC(2026, 0, 1),
    endsAt: Date.UTC(2026, 1, 1),
    status: "active",
    remainingChats: 0,
    remainingVoiceSessions: 2,
  };
  const queued = {
    uid: "owner",
    businessUid: "shop",
    package: { ...DEFAULT_PACKAGES[1] },
    startsAt: exhaustedByChat.endsAt,
    endsAt: Date.UTC(2026, 2, 1),
    status: "queued",
    remainingChats: DEFAULT_PACKAGES[1].chats,
    remainingVoiceSessions: DEFAULT_PACKAGES[1].voiceSessions,
  };
  const db = fakeDb({
    "isherTestSchedules/shop": {
      activeId: "previous",
      endAt: queued.endsAt,
      queuedIds: [queuedId],
      latestId: queuedId,
      packageRequired: true,
    },
    "isherTestSubscriptions/previous": exhaustedByChat,
    [`isherTestSubscriptions/${queuedId}`]: queued,
  });

  const changed = await activateQueuedIfDepleted({
    db,
    businessUid: "shop",
    timestamp: () => Date.UTC(2026, 0, 31),
  });

  assert.equal(changed, true);
  assert.equal(db.docs.get("isherTestSubscriptions/previous").status, "exhausted");
  assert.equal(db.docs.get(`isherTestSubscriptions/${queuedId}`).status, "active");
  assert.equal(db.docs.get(`isherTestSubscriptions/${queuedId}`).startsAt, Date.UTC(2026, 0, 31));
  assert.equal(db.docs.get("isherTestSchedules/shop").activeId, queuedId);
  assert.deepEqual(db.docs.get("isherTestSchedules/shop").queuedIds, []);
});

test("queued package activates after the active package expires by date", async () => {
  const active = {
    uid: "owner",
    businessUid: "shop",
    package: { ...DEFAULT_PACKAGES[0] },
    startsAt: Date.UTC(2026, 0, 1),
    endsAt: Date.UTC(2026, 1, 1),
    status: "active",
    remainingChats: 12,
    remainingVoiceSessions: 2,
  };
  const queuedId = "cccccccc-cccc-cccc-cccc-cccccccccccc";
  const queued = {
    uid: "owner",
    businessUid: "shop",
    package: { ...DEFAULT_PACKAGES[1] },
    startsAt: active.endsAt,
    endsAt: Date.UTC(2026, 2, 1),
    status: "queued",
    remainingChats: DEFAULT_PACKAGES[1].chats,
    remainingVoiceSessions: DEFAULT_PACKAGES[1].voiceSessions,
  };
  const db = fakeDb({
    "isherTestSchedules/shop": {
      activeId: "previous",
      endAt: queued.endsAt,
      queuedIds: [queuedId],
      latestId: queuedId,
      packageRequired: true,
    },
    "isherTestSubscriptions/previous": active,
    [`isherTestSubscriptions/${queuedId}`]: queued,
  });

  const changed = await activateQueuedIfDepleted({
    db,
    businessUid: "shop",
    timestamp: () => Date.UTC(2026, 1, 2),
  });

  assert.equal(changed, true);
  assert.equal(db.docs.get("isherTestSubscriptions/previous").status, "expired");
  assert.equal(db.docs.get(`isherTestSubscriptions/${queuedId}`).status, "active");
  assert.equal(
    db.docs.get(`isherTestSubscriptions/${queuedId}`).startsAt,
    Date.UTC(2026, 1, 2),
  );
  assert.equal(db.docs.get("isherTestSchedules/shop").activeId, queuedId);
  assert.deepEqual(db.docs.get("isherTestSchedules/shop").queuedIds, []);
});

test("queued package activates when expiry was already marked", async () => {
  const expired = {
    uid: "owner",
    businessUid: "business",
    package: { ...DEFAULT_PACKAGES[0] },
    startsAt: Date.UTC(2026, 0, 1),
    endsAt: Date.UTC(2026, 1, 1),
    status: "expired",
    remainingChats: 12,
    remainingVoiceSessions: 2,
  };
  const queuedId = "dddddddd-dddd-dddd-dddd-dddddddddddd";
  const queued = {
    uid: "owner",
    businessUid: "business",
    startsAt: expired.endsAt,
    endsAt: Date.UTC(2026, 2, 1),
    status: "queued",
    package: { ...DEFAULT_PACKAGES[1] },
    remainingChats: DEFAULT_PACKAGES[1].chats,
    remainingVoiceSessions: DEFAULT_PACKAGES[1].voiceSessions,
  };
  const db = fakeDb({
    "isherTestSchedules/business": {
      activeId: "test-one",
      endAt: queued.endsAt,
      queuedIds: [queuedId],
      latestId: queuedId,
      packageRequired: true,
    },
    "isherTestSubscriptions/test-one": expired,
    [`isherTestSubscriptions/${queuedId}`]: queued,
  });

  const changed = await activateQueuedIfDepleted({
    db,
    businessUid: "business",
    timestamp: () => 1000,
  });

  assert.equal(changed, true);
  assert.equal(db.docs.get(`isherTestSubscriptions/${queuedId}`).status, "active");
  assert.equal(db.docs.get("isherTestSchedules/business").activeId, queuedId);
});

test("existing queued package is activated by a request for its depleted quota", async () => {
  const active = {
    uid: "owner",
    businessUid: "business",
    package: { ...DEFAULT_PACKAGES[0] },
    startsAt: 100,
    endsAt: Date.UTC(2027, 0, 1),
    status: "active",
    remainingChats: 0,
    remainingVoiceSessions: 2,
  };
  const queued = {
    uid: "owner",
    businessUid: "business",
    package: { ...DEFAULT_PACKAGES[1] },
    startsAt: active.endsAt,
    endsAt: Date.UTC(2027, 1, 1),
    status: "queued",
    remainingChats: DEFAULT_PACKAGES[1].chats,
    remainingVoiceSessions: DEFAULT_PACKAGES[1].voiceSessions,
  };
  const db = fakeDb({
    "isherTestSchedules/business": {
      activeId: "previous",
      endAt: queued.endsAt,
      queuedIds: ["purchased"],
      packageRequired: true,
    },
    "isherTestSubscriptions/previous": active,
    "isherTestSubscriptions/purchased": queued,
  });

  const reservation = await db.runTransaction((tx) =>
    require("./isher_package_usage").reserve(
      tx,
      db,
      "business",
      "message",
      1000,
      "chat-after-purchase",
    ));

  assert.equal(reservation.subscriptionId, "purchased");
  assert.equal(reservation.exhausted, false);
  assert.equal(db.docs.get("isherTestSubscriptions/previous").status, "exhausted");
  assert.equal(db.docs.get("isherTestSubscriptions/purchased").status, "active");
});

test("purchase rejects changed or disabled package and does not create records", async () => {
  const db = fakeDb({
    "businessAiConfig/testPayment": { settings: { enabled: true } },
    "businessAiConfig/packages": { packages: [{ ...DEFAULT_PACKAGES[0], price: 2500 }] },
  });
  await assert.rejects(purchase(args(db)), /price-changed/);
  db.docs.set("businessAiConfig/packages", { packages: [{ ...DEFAULT_PACKAGES[0], enabled: false }] });
  await assert.rejects(purchase(args(db)), /package-unavailable/);
  assert.equal(db.docs.has("isherTestSubscriptions/first"), false);
  assert.equal(addMonth(Date.UTC(2028, 0, 31)), Date.UTC(2028, 1, 29));
});
