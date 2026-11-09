const test = require("node:test");
const assert = require("node:assert/strict");
const packages = require("./isher_packages");

test("initial packages contain the requested quotas and the 5-chat, 2-call test package", () => {
  assert.deepEqual(packages.packagesFromDocument().map(({ id, price, chats, voiceSessions }) =>
    [id, price, chats, voiceSessions]), [
    ["starter", 2000, 60, 5],
    ["business", 5000, 200, 20],
    ["professional", 10000, 500, 45],
    ["premium", 20000, 1200, 120],
    ["test", 0, 5, 2],
  ]);
});

test("package configuration rejects duplicates and invalid limits", () => {
  const starter = packages.DEFAULT_PACKAGES[0];
  assert.throws(() => packages.packagesFromDocument({ packages: [starter, starter] }), /duplicate-package/);
  assert.throws(() => packages.validatePackage({ ...starter, price: -1 }), /invalid-package/);
  assert.throws(() => packages.validatePackage({ ...starter, chats: 1.5 }), /invalid-package/);
  assert.throws(() => packages.validatePackage({ ...starter, voiceSessions: -1 }), /invalid-package/);
  assert.throws(() => packages.validatePackage({ ...starter, id: "../unsafe" }), /invalid-package/);
});

test("saved catalogs from before voice session quotas remain readable", () => {
  const { voiceSessions, ...legacy } = packages.DEFAULT_PACKAGES[0];
  assert.equal(packages.validatePackage(legacy).voiceSessions, legacy.voiceMinutes);
});

test("saved catalogs gain the default test package if it is missing", () => {
  const saved = packages.packagesFromDocument({
    packages: [{
      id: "custom", name: "Custom", price: 100, chats: 10, voiceMinutes: 5,
      analyses: 0, research: 0, credits: 0, enabled: true,
    }],
  });
  assert.deepEqual(saved.map((item) => item.id), ["custom", "test"]);
  assert.equal(saved[1].chats, 5);
  assert.equal(saved[1].voiceSessions, 2);
});
