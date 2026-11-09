const { randomUUID } = require("node:crypto");
const { hasDepletedUsageQuota } = require("./isher_packages");

function addMonth(timestamp) {
  const date = new Date(timestamp);
  const day = date.getUTCDate();
  date.setUTCDate(1);
  date.setUTCMonth(date.getUTCMonth() + 1);
  const lastDay = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0)).getUTCDate();
  date.setUTCDate(Math.min(day, lastDay));
  return date.getTime();
}

function packageReferences(db, businessUid, schedule) {
  const activeId = typeof schedule?.activeId === "string" ? schedule.activeId : "";
  const queuedIds = Array.isArray(schedule?.queuedIds)
    ? schedule.queuedIds.filter((id) => typeof id === "string" && id.length > 0).slice(0, 6)
    : [];
  const ids = [...new Set([activeId, ...queuedIds])].filter((id) => id.length > 0);
  return {
    ids,
    refs: ids.map((id) => db.doc(`isherTestSubscriptions/${id}`)),
    activeId,
    queuedIds,
  };
}

async function reserve(tx, db, businessUid, kind, now, reservationId = randomUUID()) {
  const writes = [];
  const update = (ref, data) => writes.push(() => tx.update(ref, data));
  const create = (ref, data) => writes.push(() => tx.create(ref, data));
  const commitWrites = () => writes.forEach((write) => write());
  const scheduleRef = db.doc(`isherTestSchedules/${businessUid}`);
  const scheduleSnapshot = await tx.get(scheduleRef);
  if (!scheduleSnapshot.exists) return null;

  const schedule = scheduleSnapshot.data();
  const refs = packageReferences(db, businessUid, schedule);
  if (!refs.ids.length) {
    return schedule.packageRequired ? { exhausted: true } : null;
  }
  const snapshots = await Promise.all(refs.refs.map((ref) => tx.get(ref)));
  const byId = new Map(refs.ids.map((id, index) => [id, snapshots[index]]));

  const activeRef = refs.activeId
    ? db.doc(`isherTestSubscriptions/${refs.activeId}`)
    : null;
  const activeSnapshot = refs.activeId ? byId.get(refs.activeId) : null;
  const active = activeSnapshot?.exists ? activeSnapshot.data() : null;
  let activeId = refs.activeId;
  let queuedIds = refs.queuedIds.slice();

  if (!active || active.status !== "active" || active.endsAt <= now) {
    if (active && active.status === "active") {
      update(activeRef, { status: "expired", expiredAt: now });
    }
    activeId = "";
  } else if (queuedIds.length && hasDepletedUsageQuota(active, kind)) {
    update(activeRef, { status: "exhausted", exhaustedAt: now });
    activeId = "";
  }

  if (!activeId && queuedIds.length) {
    while (queuedIds.length) {
      const nextId = queuedIds.shift();
      const nextSnapshot = byId.get(nextId);
      if (!nextSnapshot?.exists || nextSnapshot.data().status !== "queued") continue;
      const nextRef = db.doc(`isherTestSubscriptions/${nextId}`);
      const next = nextSnapshot.data();
      const startsAt = now;
      const endsAt = addMonth(startsAt);
      update(nextRef, {
        status: "active", startsAt, endsAt,
        remainingChats: next.package.chats,
        remainingVoiceSessions: next.package.voiceSessions,
      });
      activeId = nextId;
      let queueStart = endsAt;
      for (const queuedId of queuedIds) {
        const queuedSnapshot = byId.get(queuedId);
        if (!queuedSnapshot?.exists || queuedSnapshot.data().status !== "queued") continue;
        const start = queueStart;
        queueStart = addMonth(start);
        update(db.doc(`isherTestSubscriptions/${queuedId}`), {
          startsAt: start, endsAt: queueStart,
        });
      }
      update(scheduleRef, { activeId, endAt: queueStart, queuedIds });
      break;
    }
  }

  if (!activeId) {
    if (refs.activeId || queuedIds.length !== refs.queuedIds.length) {
      update(scheduleRef, { activeId: null, queuedIds });
    }
    commitWrites();
    return schedule.packageRequired ? { exhausted: true } : null;
  }

  const subscriptionRef = db.doc(`isherTestSubscriptions/${activeId}`);
  const subscription = byId.get(activeId).data();
  if (subscription.businessUid !== businessUid) {
    throw new Error("invalid-package-owner");
  }
  const chargeRef = db.doc(`isherTestSubscriptions/${activeId}/charges/${reservationId}`);
  const existingCharge = await tx.get(chargeRef);
  if (existingCharge.exists) {
    const data = existingCharge.data();
    if (data.businessUid !== businessUid || data.kind !== kind || data.status !== "reserved") {
      throw new Error("reservation-conflict");
    }
    commitWrites();
    return {
      subscriptionId: activeId,
      reservationId,
      exhausted: false,
      voiceMinutes: subscription.package.voiceMinutes,
    };
  }

  const field = kind === "message" ? "remainingChats" : "remainingVoiceSessions";
  if (kind === "voice" && subscription.package.voiceMinutes < 1) {
    commitWrites();
    return { exhausted: true, subscriptionId: activeId };
  }
  const remaining = subscription[field];
  if (!Number.isSafeInteger(remaining) || remaining < 1) {
    const otherField = kind === "message" ? "remainingVoiceSessions" : "remainingChats";
    if (subscription[otherField] < 1) {
      update(subscriptionRef, { status: "exhausted", exhaustedAt: now });
    }
    commitWrites();
    return { exhausted: true, subscriptionId: activeId };
  }
  const nextRemaining = remaining - 1;
  const otherField = kind === "message" ? "remainingVoiceSessions" : "remainingChats";
  const fullyExhausted = nextRemaining === 0 && subscription[otherField] === 0;
  update(subscriptionRef, {
    [field]: nextRemaining,
    ...(fullyExhausted ? { status: "exhausted", exhaustedAt: now } : {}),
  });
  create(chargeRef, {
    businessUid, kind, field, createdAt: now, status: "reserved",
  });
  commitWrites();
  return {
    subscriptionId: activeId,
    reservationId,
    exhausted: false,
    willExhaust: fullyExhausted,
    voiceMinutes: subscription.package.voiceMinutes,
  };
}

async function refund(tx, db, businessUid, charge) {
  if (!charge?.subscriptionId || !charge?.reservationId) return false;
  const scheduleRef = db.doc(`isherTestSchedules/${businessUid}`);
  const subscriptionRef = db.doc(`isherTestSubscriptions/${charge.subscriptionId}`);
  const chargeRef = db.doc(`isherTestSubscriptions/${charge.subscriptionId}/charges/${charge.reservationId}`);
  const [scheduleSnapshot, subscriptionSnapshot, chargeSnapshot] = await Promise.all([
    tx.get(scheduleRef), tx.get(subscriptionRef), tx.get(chargeRef),
  ]);
  if (!subscriptionSnapshot.exists || !chargeSnapshot.exists ||
      chargeSnapshot.data().status !== "reserved") return false;
  const subscription = subscriptionSnapshot.data();
  const chargeData = chargeSnapshot.data();
  const current = subscription[chargeData.field];
  if (!Number.isSafeInteger(current)) throw new Error("invalid-package-balance");
  tx.update(chargeRef, { status: "refunded", refundedAt: Date.now() });
  tx.update(subscriptionRef, {
    [chargeData.field]: current + 1,
    ...(subscription.status === "exhausted" &&
        scheduleSnapshot.data()?.activeId === charge.subscriptionId
      ? { status: "active", exhaustedAt: null }
      : {}),
  });
  return true;
}

async function finalize(tx, db, businessUid, charge) {
  if (!charge?.subscriptionId || !charge?.reservationId) return false;
  const ref = db.doc(`isherTestSubscriptions/${charge.subscriptionId}/charges/${charge.reservationId}`);
  const snapshot = await tx.get(ref);
  if (!snapshot.exists || snapshot.data().status !== "reserved") return false;
  tx.update(ref, { status: "consumed", consumedAt: Date.now() });
  return true;
}

async function refundReservation(db, businessUid, charge) {
  if (!charge?.subscriptionId || !charge?.reservationId) return false;
  return db.runTransaction((tx) => refund(tx, db, businessUid, charge));
}

async function finalizeReservation(db, businessUid, charge) {
  if (!charge?.subscriptionId || !charge?.reservationId) return false;
  return db.runTransaction((tx) => finalize(tx, db, businessUid, charge));
}

module.exports = { reserve, refund, finalize, refundReservation, finalizeReservation, addMonth };
