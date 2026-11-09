const test = require("node:test");
const assert = require("node:assert/strict");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Run only with the Firestore emulator and project rules.");
const projectId = process.env.GCLOUD_PROJECT;
if (!projectId || !projectId.startsWith("demo-")) throw new Error("A demo project is required.");
initializeApp({ projectId });
const db = getFirestore();

function token(uid) {
  const now = Math.floor(Date.now() / 1000);
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  return `${encode({ alg: "none", typ: "JWT" })}.${encode({
    iss: `https://securetoken.google.com/${projectId}`, aud: projectId,
    sub: uid, user_id: uid, iat: now, exp: now + 3600,
    firebase: { sign_in_provider: "custom" },
  })}.`;
}

async function read(path, uid) {
  const url = `http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/${projectId}/databases/(default)/documents/${path}`;
  const response = await fetch(url, { headers: uid ? { Authorization: `Bearer ${token(uid)}` } : {} });
  return response.status;
}

test("chat rules enforce owner and membership access", async () => {
  const business = "business";
  await Promise.all([
    db.doc(`users/${business}/profile/company`).set({ name: "Example" }),
    db.doc(`users/${business}/chats/chat`).set({ memberUids: ["member"] }),
    db.doc(`users/${business}/chats/chat/messages/message`).set({ text: "example" }),
    db.doc(`businessMemberships/${business}/members/member`).set({
      businessUid: business, employeeUid: "member", active: true, role: "staff",
    }),
    db.doc(`businessMemberships/${business}/members/outsider`).set({
      businessUid: business, employeeUid: "outsider", active: true, role: "staff",
    }),
  ]);
  const path = `users/${business}/chats/chat/messages/message`;
  assert.equal(await read(path, business), 200);
  assert.equal(await read(path, "member"), 200);
  assert.equal(await read(path, "outsider"), 403);
  assert.equal(await read(path, "another-business"), 403);
  assert.equal(await read(path), 403);
  await db.doc(`accountAccess/${business}`).set({ disabled: true });
  assert.equal(await read(path, business), 403);
});
