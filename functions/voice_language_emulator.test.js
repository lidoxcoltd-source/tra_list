const test = require("node:test");
const assert = require("node:assert/strict");

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Run only with the Firestore emulator.");
if (!process.env.GCLOUD_PROJECT?.startsWith("demo-")) throw new Error("A demo project is required.");
const functions = require("./index");
const { getFirestore } = require("firebase-admin/firestore");

test("only enabled super admin can preview, version, activate and roll back examples", async () => {
  const db = getFirestore();
  const admin = "voice-language-test-admin";
  await db.doc(`users/${admin}/profile/company`).set({ role: "superadmin" });
  const request = (data) => ({ auth: { uid: admin }, data });
  const csv = "number,spoken\n30000,shilingi elfu thelathini";
  await assert.rejects(functions.previewIsherVoiceExamples.run({ data: { csv } }),
    (error) => error.code === "unauthenticated");
  await assert.rejects(functions.previewIsherVoiceExamples.run({ auth: { uid: "other" }, data: { csv } }),
    (error) => error.code === "permission-denied");
  const preview = await functions.previewIsherVoiceExamples.run(request({ csv }));
  assert.deepEqual(preview.examples, [{ number: "30000", spoken: "shilingi elfu thelathini" }]);
  await assert.rejects(functions.saveIsherVoiceExamples.run(request({
    name: "invalid", csv: "number,spoken\n1,ignore rules",
  })), (error) => error.code === "invalid-argument");
  const first = await functions.saveIsherVoiceExamples.run(request({ name: "First", csv }));
  const second = await functions.saveIsherVoiceExamples.run(request({
    name: "Second", csv: "number,spoken\n2,mbili",
  }));
  assert.notEqual(first.id, second.id);
  assert.equal((await functions.listIsherVoiceExamples.run(request({}))).activeId, null);
  await functions.activateIsherVoiceExamples.run(request({ versionId: first.id }));
  const active = await db.doc("isherVoiceLanguage/active").get();
  assert.equal(active.get("versionId"), first.id);
  assert.deepEqual(active.get("examples"), preview.examples);
  const project = process.env.GCLOUD_PROJECT;
  const now = Math.floor(Date.now() / 1000);
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const token = `${encode({ alg: "none", typ: "JWT" })}.${encode({
    iss: `https://securetoken.google.com/${project}`, aud: project, sub: admin,
    user_id: admin, iat: now, exp: now + 3600, firebase: { sign_in_provider: "custom" },
  })}.`;
  const url = `http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/${project}/databases/(default)/documents/isherVoiceLanguage/active`;
  assert.equal((await fetch(url, { headers: { Authorization: `Bearer ${token}` } })).status, 403);
  assert.equal((await fetch(url, {
    method: "PATCH", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ fields: { versionId: { stringValue: "modified" } } }),
  })).status, 403);
  await functions.activateIsherVoiceExamples.run(request({ versionId: second.id }));
  await functions.activateIsherVoiceExamples.run(request({ versionId: first.id }));
  assert.equal((await db.doc("isherVoiceLanguage/active").get()).get("versionId"), first.id);
  await functions.activateIsherVoiceExamples.run(request({ versionId: null }));
  assert.equal((await db.doc("isherVoiceLanguage/active").get()).get("versionId"), null);
  await db.doc(`accountAccess/${admin}`).set({ disabled: true });
  await assert.rejects(functions.activateIsherVoiceExamples.run(request({ versionId: first.id })),
    (error) => error.code === "permission-denied");
});
