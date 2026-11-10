const { randomUUID, createHash } = require("node:crypto");
const http = require("node:http");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");
const { getFunctions } = require("firebase-admin/functions");
const { WebSocketServer, WebSocket } = require("ws");
const bi = require("./business_intelligence");
const { businessAccess } = require("./business_ai_access");
const { hangUp } = require("./voice_common");
const aiQuota = require("./business_ai_quota");
const { buildVoiceInstructions } = require("./voice_instructions");
const { openAiTools } = require("./voice_tools");
const { validateExamples } = require("./voice_language_examples");

initializeApp();
const db = getFirestore();
const apiKey = process.env.OPENAI_API_KEY;
if (!apiKey) throw new Error("OPENAI_API_KEY must be configured");

const server = http.createServer((req, res) => {
  res.writeHead(req.url === "/health" ? 200 : 404);
  res.end(req.url === "/health" ? "ok" : "not found");
});
const sockets = new WebSocketServer({ server, maxPayload: 160000, perMessageDeflate: false });

async function release(uid, id) {
  await aiQuota.releaseVoiceReservation(db, uid, id);
}

sockets.on("connection", (socket) => {
  let started = false, closed = false, callId, uid, id, reservationCharge, sessionStarted = false;
  let timer, accessTimer;
  let alive = true;
  const heartbeat = setInterval(() => {
    if (!alive) return socket.terminate();
    alive = false;
    socket.ping();
  }, 15000);
  socket.on("pong", () => { alive = true; });
  const timeout = setTimeout(() => socket.close(1008, "timeout"), 15000);
  const cleanup = async () => {
    if (closed) return;
    closed = true;
    clearTimeout(timeout);
    clearTimeout(timer);
    clearInterval(accessTimer);
    clearInterval(heartbeat);
    if (callId) {
      try { await hangUp(callId, apiKey); }
      catch (error) { console.error("Voice hangup failed", error.message); }
    }
    if (uid && id) {
      try { await release(uid, id); }
      catch (error) { console.error("Voice reservation release failed", error.message); }
    }
  };
  socket.on("close", cleanup);
  socket.on("error", (error) => { console.error("Voice socket error", error.message); socket.close(); });
  socket.on("message", async (raw) => {
    if (started) return socket.close(1008, "unexpected message");
    started = true;
    clearTimeout(timeout);
    try {
      const request = JSON.parse(raw.toString());
      if (typeof request.idToken !== "string" || typeof request.businessUid !== "string" ||
          !request.businessUid || request.businessUid.length > 128 || request.businessUid.includes("/") ||
          typeof request.sdp !== "string" || request.sdp.length > 60000 || !request.sdp.startsWith("v=0")) {
        throw new Error("invalid");
      }
      const user = await getAuth().verifyIdToken(request.idToken, true);
      uid = user.uid;
      const access = await businessAccess(db, uid, request.businessUid);
      const context = bi.verifySnapshot(request.snapshot, apiKey, uid, request.businessUid, access.scope);
      let examples = [];
      if (request.language === "sw") {
        const active = await db.doc("isherVoiceLanguage/active").get();
        if (active.exists && active.data().versionId != null) {
          examples = validateExamples(active.data().examples);
        }
      }
      id = randomUUID();
      const reservation = await aiQuota.reserveWithCharge(
        db, uid, "voice", id, 1, request.businessUid,
      );
      const settings = reservation.settings;
      reservationCharge = reservation.charge;
      if (closed) {
        await aiQuota.rollbackVoiceReservation(db, uid, id, reservationCharge);
        return;
      }
      const form = new FormData();
      form.set("sdp", request.sdp);
      form.set("session", JSON.stringify({
        type: "realtime", model: "gpt-realtime-2.1-mini",
        instructions: buildVoiceInstructions(request.language, context, examples),
        tools: openAiTools,
        audio: { input: { turn_detection: { type: "server_vad", create_response: true, interrupt_response: true } }, output: { voice: "marin" } },
      }));
      const response = await fetch("https://api.openai.com/v1/realtime/calls", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "OpenAI-Safety-Identifier": createHash("sha256").update(uid).digest("hex"),
        },
        body: form, signal: AbortSignal.timeout(30000),
      });
      if (!response.ok) {
        console.error("Realtime creation failed", response.status);
        throw new Error("provider");
      }
      callId = response.headers.get("location")?.split("/").pop();
      if (!callId || !/^rtc_[A-Za-z0-9_-]+$/.test(callId)) throw new Error("provider");
      const deadline = Date.now() + settings.voiceMinutes * 60000;
      const answer = await response.text();
      await getFunctions().taskQueue("locations/us-central1/functions/endBusinessAiVoice")
        .enqueue(
          { callId, uid, leaseId: id },
          { scheduleTime: new Date(deadline), dispatchDeadlineSeconds: 60 },
        );
      if (closed || socket.readyState !== WebSocket.OPEN) {
        await hangUp(callId, apiKey);
        await aiQuota.rollbackVoiceReservation(db, uid, id, reservationCharge);
        return;
      }
      timer = setTimeout(() => socket.close(1000, "time limit"), Math.max(0, deadline - Date.now() - 5000));
      accessTimer = setInterval(async () => {
        try {
          await getAuth().verifyIdToken(request.idToken, true);
          const current = await businessAccess(db, uid, request.businessUid);
          if (JSON.stringify(current.scope) !== JSON.stringify(access.scope)) throw new Error("changed");
        } catch (error) {
          console.error("Voice access check failed", error.message);
          socket.close(1008, "access changed");
        }
      }, 15000);
      if (reservationCharge?.packageCharge) {
        await require("./isher_package_usage").finalizeReservation(
          db, request.businessUid, reservationCharge.packageCharge,
        );
      }
      socket.send(JSON.stringify({ type: "answer", sdp: answer }));
      sessionStarted = true;
    } catch (error) {
      console.error("Voice session failed", error.message);
      if (socket.readyState === WebSocket.OPEN) {
        socket.send(JSON.stringify({
          type: "error",
          code: error.message === "package-quota-exhausted" ? "package-limit" :
            error.message === "quota-exhausted" ? "limit" :
            error.message === "voice-active" ? "active" : "unavailable",
        }));
        socket.close(1011, "session failed");
      }
      if (closed && callId) {
        try { await hangUp(callId, apiKey); }
        catch (hangupError) { console.error("Voice hangup failed", hangupError.message); }
      }
      if (uid && id && reservationCharge && !sessionStarted) {
        try {
          await aiQuota.rollbackVoiceReservation(db, uid, id, reservationCharge);
        } catch (refundError) {
          console.error("Voice quota refund failed", refundError.message);
        }
      }
      await cleanup();
    }
  });
});

server.listen(Number(process.env.PORT || 8080), "0.0.0.0");
