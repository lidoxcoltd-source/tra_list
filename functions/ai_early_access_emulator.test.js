const test = require("node:test");
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Run only with the Firestore emulator.");
const functions = require("./index");
const { getFirestore } = require("firebase-admin/firestore");

test("early access accepts once, hides honeypot submissions, and limits IP volume", async () => {
  const db = getFirestore();
  const ip = `early-access-${randomUUID()}`;
  const submit = (data) => functions.registerAiEarlyAccess.run({
    data,
    rawRequest: { ip },
  });
  const first = await submit({
    email: " Tester@Example.com ",
    phone: "0712345678",
    consent: true,
    website: "",
  });
  assert.deepEqual(first, { accepted: true, alreadyRegistered: false });
  assert.deepEqual(await submit({
    email: "tester@example.com",
    phone: "+255712345678",
    consent: true,
    website: "",
  }), { accepted: true, alreadyRegistered: true });
  const leads = await db.collection("aiEarlyAccessLeads").get();
  const lead = leads.docs.find((doc) => doc.get("email") === "tester@example.com");
  assert.ok(lead);
  assert.equal(lead.get("phone"), "+255712345678");
  assert.equal(lead.get("consent"), true);

  const honey = await submit({
    email: "bot@example.com",
    phone: "+14155552671",
    consent: true,
    website: "filled-by-bot",
  });
  assert.deepEqual(honey, { accepted: true });
  assert.equal((await db.collection("aiEarlyAccessLeads").where("email", "==", "bot@example.com").get()).empty, true);

  for (let index = 0; index < 9; index++) {
    await submit({
      email: `tester-${index}@example.com`,
      phone: "+1415555" + String(1000 + index),
      consent: true,
      website: "",
    });
  }
  await assert.rejects(
    submit({ email: "limit@example.com", phone: "+14155559999", consent: true, website: "" }),
    (error) => error.code === "resource-exhausted",
  );
});