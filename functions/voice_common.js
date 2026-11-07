function nextReservation(data, now, id) {
  const day = new Date(now).toISOString().slice(0, 10);
  if ((data.day === day && (data.count || 0) >= 2) || (data.activeUntil || 0) > now) {
    throw new Error("limit");
  }
  return {
    day, count: data.day === day ? (data.count || 0) + 1 : 1,
    activeId: id, activeUntil: now + 360000,
  };
}

async function hangUp(callId, apiKey) {
  if (!/^rtc_[A-Za-z0-9_-]+$/.test(callId)) throw new Error("Invalid call ID");
  const response = await fetch(`https://api.openai.com/v1/realtime/calls/${callId}/hangup`, {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}` },
    signal: AbortSignal.timeout(10000),
  });
  if (!response.ok && response.status !== 404 && response.status !== 409) {
    throw new Error(`Realtime hangup failed: ${response.status}`);
  }
}

module.exports = { hangUp, nextReservation };
