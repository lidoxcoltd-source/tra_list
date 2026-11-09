const DEFAULTS = Object.freeze({
  dailyVoice: 2,
  dailyMessages: 20,
  voiceMinutes: 5,
  voicePrice: 0,
  messagePrice: 0,
});

function validateSettings(settings) {
  const limits = {
    dailyVoice: [0, 1000],
    dailyMessages: [0, 10000],
    voiceMinutes: [1, 30],
    voicePrice: [0, 100000000],
    messagePrice: [0, 100000000],
  };
  if (!settings || typeof settings !== "object" || Array.isArray(settings) ||
      Object.keys(settings).length !== Object.keys(limits).length) {
    throw new Error("invalid-settings");
  }
  for (const [key, [min, max]] of Object.entries(limits)) {
    if (!Number.isSafeInteger(settings[key]) || settings[key] < min || settings[key] > max) {
      throw new Error("invalid-settings");
    }
  }
  return { ...settings };
}

function settingsFromDocument(data) {
  return data == null ? { ...DEFAULTS } : validateSettings(data.settings);
}

function dayInTanzania(now) {
  return new Date(now + 3 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

function nonnegative(value) {
  if (value == null) return 0;
  if (!Number.isSafeInteger(value) || value < 0) throw new Error("invalid-usage");
  return value;
}

function usageForDay(data, now) {
  const day = dayInTanzania(now);
  return {
    day,
    voiceUsed: data.day === day ? nonnegative(data.voiceUsed) : 0,
    messagesUsed: data.day === day ? nonnegative(data.messagesUsed) : 0,
    extraVoice: nonnegative(data.extraVoice),
    extraMessages: nonnegative(data.extraMessages),
    activeId: typeof data.activeId === "string" ? data.activeId : "",
    activeUntil: nonnegative(data.activeUntil),
    lastMessageAt: nonnegative(data.lastMessageAt),
  };
}

function consume(data, settings, kind, now, id, cost = 1) {
  const usage = usageForDay(data, now);
  if (kind === "voice") {
    if (usage.activeUntil > now) {
      const error = new Error("voice-active");
      error.retryAfterSeconds = Math.ceil((usage.activeUntil - now) / 1000);
      throw error;
    }
    if (usage.voiceUsed < settings.dailyVoice) {
      usage.voiceUsed++;
    } else if (usage.extraVoice > 0) {
      usage.extraVoice--;
    }
    else throw new Error("quota-exhausted");
    usage.activeId = id;
    usage.activeUntil = now + settings.voiceMinutes * 60000 + 60000;
  } else if (kind === "message") {
    if (usage.lastMessageAt > now - 10000) throw new Error("rate-limited");
    if (!Number.isSafeInteger(cost) || cost < 1) throw new Error("invalid-cost");
    const daily = Math.max(0, settings.dailyMessages - usage.messagesUsed);
    if (daily + usage.extraMessages < cost) throw new Error("quota-exhausted");
    const fromDaily = Math.min(daily, cost);
    usage.messagesUsed += fromDaily;
    usage.extraMessages -= cost - fromDaily;
    usage.lastMessageAt = now;
  } else {
    throw new Error("invalid-kind");
  }
  return usage;
}

async function reserveWithCharge(db, uid, kind, id = "", cost = 1) {
  const settingsRef = db.doc("businessAiConfig/settings");
  const usageRef = db.doc(`businessAiQuota/${uid}`);
  return db.runTransaction(async (tx) => {
    const [config, current] = await Promise.all([tx.get(settingsRef), tx.get(usageRef)]);
    const settings = settingsFromDocument(config.data());
    const now = Date.now();
    const previous = usageForDay(current.data() || {}, now);
    const usage = consume(current.data() || {}, settings, kind, now, id, cost);
    tx.set(usageRef, usage);
    const charge = kind === "voice"
      ? { source: usage.voiceUsed > previous.voiceUsed ? "daily" : "extra", day: usage.day }
      : null;
    return { settings, charge };
  });
}

async function reserve(db, uid, kind, id = "", cost = 1) {
  return (await reserveWithCharge(db, uid, kind, id, cost)).settings;
}

async function rollbackVoiceReservation(db, uid, id, charge) {
  const ref = db.doc(`businessAiQuota/${uid}`);
  return db.runTransaction(async (tx) => {
    const data = (await tx.get(ref)).data();
    if (!data || data.activeId !== id) return false;
    if (!charge || !["daily", "extra"].includes(charge.source) ||
        typeof charge.day !== "string") {
      throw new Error("invalid-voice-reservation");
    }
    const update = { activeId: "", activeUntil: 0 };
    if (charge.source === "extra") {
      update.extraVoice = nonnegative(data.extraVoice) + 1;
    } else if (data.day === charge.day) {
      const used = nonnegative(data.voiceUsed);
      if (used < 1) throw new Error("invalid-voice-reservation");
      update.voiceUsed = used - 1;
    }
    tx.update(ref, update);
    return true;
  });
}

module.exports = { DEFAULTS, validateSettings, settingsFromDocument, dayInTanzania, usageForDay, consume, reserve, reserveWithCharge, rollbackVoiceReservation };
