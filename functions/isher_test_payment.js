const { packagesFromDocument, hasDepletedUsageQuota } = require("./isher_packages");

function validateSettings(settings) {
  if (!settings || typeof settings !== "object" || Array.isArray(settings) ||
      typeof settings.enabled !== "boolean") {
    throw new Error("invalid-settings");
  }
  return { enabled: settings.enabled };
}

function addMonth(timestamp) {
  const date = new Date(timestamp);
  const day = date.getUTCDate();
  date.setUTCDate(1);
  date.setUTCMonth(date.getUTCMonth() + 1);
  const lastDay = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0)).getUTCDate();
  date.setUTCDate(Math.min(day, lastDay));
  return date.getTime();
}

function samePackage(a, b) {
  return ["id", "name", "price", "chats", "voiceSessions", "voiceMinutes", "analyses", "research", "credits", "enabled"]
    .every((key) => a[key] === b[key]);
}

async function purchase({ db, uid, businessUid, packageId, expectedPackage, requestId, timestamp }) {
  const transactionRef = db.doc(`isherTestTransactions/${requestId}`);
  const paymentRef = db.doc("businessAiConfig/testPayment");
  const packageRef = db.doc("businessAiConfig/packages");
  const scheduleRef = db.doc(`isherTestSchedules/${businessUid}`);
  const subscriptionRef = db.doc(`isherTestSubscriptions/${requestId}`);
  return db.runTransaction(async (tx) => {
    const [existing, payment, catalog, schedule] = await Promise.all([
      tx.get(transactionRef), tx.get(paymentRef), tx.get(packageRef), tx.get(scheduleRef),
    ]);
    if (existing.exists) {
      const old = existing.data();
      if (old.uid !== uid || old.businessUid !== businessUid ||
          !samePackage(old.package, expectedPackage)) {
        throw new Error("request-conflict");
      }
      return old;
    }
    const settings = payment.exists ? validateSettings(payment.data().settings) : { enabled: false };
    if (!settings.enabled) throw new Error("test-disabled");
    const selected = packagesFromDocument(catalog.data()).find((item) => item.id === packageId && item.enabled);
    if (!selected) throw new Error("package-unavailable");
    if (!samePackage(selected, expectedPackage)) throw new Error("price-changed");
    const now = timestamp();
    const oldSchedule = schedule.data() || {};
    const priorEnd = oldSchedule.endAt ?? 0;
    if (!Number.isSafeInteger(priorEnd) || priorEnd < 0) throw new Error("invalid-schedule");
    const activeId = typeof oldSchedule.activeId === "string" ? oldSchedule.activeId : "";
    const activeSnapshot = activeId
      ? await tx.get(db.doc(`isherTestSubscriptions/${activeId}`))
      : null;
    let hasActive = activeSnapshot?.exists &&
      activeSnapshot.data().status === "active" &&
      activeSnapshot.data().endsAt > now;
    if (hasActive) {
      const active = activeSnapshot.data();
      if (hasDepletedUsageQuota(active)) {
        tx.update(db.doc(`isherTestSubscriptions/${activeId}`), {
          status: "exhausted",
          exhaustedAt: now,
        });
        hasActive = false;
      }
    }
    const queuedIds = Array.isArray(oldSchedule.queuedIds) ? [...oldSchedule.queuedIds] : [];
    if (queuedIds.length >= 6) throw new Error("queue-limit");
    const startsAt = hasActive ? Math.max(now, priorEnd) : now;
    if (startsAt > addMonth(addMonth(addMonth(addMonth(addMonth(addMonth(now))))))) {
      throw new Error("queue-limit");
    }
    const endsAt = addMonth(startsAt);
    const status = hasActive ? "queued" : "active";
    const record = {
      uid, businessUid, package: selected, startsAt, endsAt,
      createdAt: now, type: "test", status,
      actualCollected: 0, currency: "TZS",
      quotasEnforced: true,
      remainingChats: selected.chats,
      remainingVoiceSessions: selected.voiceSessions,
    };
    tx.create(transactionRef, record);
    tx.create(subscriptionRef, record);
    if (hasActive) {
      queuedIds.push(requestId);
      tx.set(scheduleRef, { activeId, endAt: endsAt, queuedIds, latestId: requestId, packageRequired: true });
    } else {
      tx.set(scheduleRef, {
        activeId: requestId,
        endAt: queuedIds.length ? Math.max(endsAt, priorEnd) : endsAt,
        queuedIds,
        latestId: requestId,
        packageRequired: true,
      });
    }
    return record;
  });
}

async function purchaseExists({ db, uid, businessUid, requestId }) {
  return db.runTransaction(async (tx) => {
    const snapshot = await tx.get(
      db.doc(`isherTestTransactions/${requestId}`),
    );
    if (!snapshot.exists) return false;
    const transaction = snapshot.data();
    return transaction.uid === uid && transaction.businessUid === businessUid;
  });
}

async function activateQueuedIfDepleted({ db, businessUid, timestamp = Date.now }) {
  const scheduleRef = db.doc(`isherTestSchedules/${businessUid}`);
  return db.runTransaction(async (tx) => {
    const scheduleSnapshot = await tx.get(scheduleRef);
    if (!scheduleSnapshot.exists) return false;
    const schedule = scheduleSnapshot.data();
    const activeId = typeof schedule.activeId === "string" ? schedule.activeId : "";
    const queuedIds = Array.isArray(schedule.queuedIds)
      ? [...new Set(schedule.queuedIds.filter(
        (id) => typeof id === "string" && /^[a-f0-9-]{1,48}$/.test(id),
      ))].slice(0, 6)
      : [];
    if (!queuedIds.length) return false;

    const now = timestamp();
    const activeRef = activeId
      ? db.doc(`isherTestSubscriptions/${activeId}`)
      : null;
    const activeSnapshot = activeRef ? await tx.get(activeRef) : null;
    const active = activeSnapshot?.exists ? activeSnapshot.data() : null;
    let activeStatus = null;
    if (active?.status === "active") {
      if (active.endsAt <= now) {
        activeStatus = "expired";
      } else if (hasDepletedUsageQuota(active)) {
        activeStatus = "exhausted";
      } else {
        return false;
      }
    } else if (active && !["expired", "exhausted"].includes(active.status)) {
      return false;
    }

    const queuedRefs = queuedIds.map((id) => db.doc(`isherTestSubscriptions/${id}`));
    const queuedSnapshots = await Promise.all(queuedRefs.map((ref) => tx.get(ref)));
    const queued = queuedSnapshots
      .map((snapshot, index) => ({ id: queuedIds[index], ref: queuedRefs[index], snapshot }))
      .filter(({ snapshot }) =>
        snapshot.exists &&
        snapshot.data().status === "queued" &&
        snapshot.data().businessUid === businessUid,
      );
    if (activeStatus === "expired") {
      tx.update(activeRef, { status: "expired", expiredAt: now });
    } else if (activeStatus === "exhausted") {
      tx.update(activeRef, { status: "exhausted", exhaustedAt: now });
    }
    const [next, ...remaining] = queued;
    if (!next) {
      tx.set(scheduleRef, {
        activeId: null,
        endAt: now,
        queuedIds: [],
        latestId: schedule.latestId ?? activeId,
        packageRequired: true,
      });
      return true;
    }

    const startsAt = now;
    const endsAt = addMonth(startsAt);
    const nextSubscription = next.snapshot.data();
    tx.update(next.ref, {
      status: "active",
      startsAt,
      endsAt,
      remainingChats: nextSubscription.package.chats,
      remainingVoiceSessions:
        nextSubscription.package.voiceSessions ??
        nextSubscription.package.voiceMinutes,
    });
    let queueEnd = endsAt;
    for (const queuedSubscription of remaining) {
      const start = queueEnd;
      queueEnd = addMonth(start);
      const details = queuedSubscription.snapshot.data();
      tx.update(queuedSubscription.ref, { startsAt: start, endsAt: queueEnd });
      if (!Number.isSafeInteger(details.package?.chats) ||
          !Number.isSafeInteger(
            details.package?.voiceSessions ?? details.package?.voiceMinutes,
          )) {
        throw new Error("invalid-queued-package");
      }
    }
    tx.set(scheduleRef, {
      activeId: next.id,
      endAt: queueEnd,
      queuedIds: remaining.map(({ id }) => id),
      latestId: schedule.latestId ?? next.id,
      packageRequired: true,
    });
    return true;
  });
}

module.exports = {
  validateSettings,
  addMonth,
  purchase,
  purchaseExists,
  activateQueuedIfDepleted,
};
