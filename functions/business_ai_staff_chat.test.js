const test = require("node:test");
const assert = require("node:assert/strict");
const staffChat = require("./business_ai_staff_chat");

test("staff conversation sharing remains disabled until review is implemented", () => {
  assert.equal(staffChat.SHARING_ENABLED, false);
});

test("staff conversation retrieval is explicit", () => {
  assert.equal(staffChat.isStaffChatRequest("Onyesha ujumbe wa wafanyakazi"), true);
  assert.equal(staffChat.isStaffChatRequest("Summarize employee conversations"), true);
  assert.equal(staffChat.isStaffChatRequest("Chambua wafanyakazi"), false);
  assert.equal(staffChat.isStaffChatRequest("Habari chat"), false);
});

test("bounded staff messages omit flagged credentials and do not send attachments", async () => {
  const stamp = { toMillis: () => 10 };
  const docs = [
    { data: () => ({ senderName: "A", text: "Habari", createdAt: stamp, attachments: [{ url: "private" }] }) },
    { data: () => ({ senderName: "B", text: "password is private", createdAt: stamp }) },
  ];
  const calls = [];
  const page = { docs, size: docs.length };
  const messageQuery = {
    where(...args) { calls.push(args); return this; },
    orderBy() { return this; },
    limit() { return this; },
    select() { return this; },
    async get() { return page; },
  };
  const business = {
    collection(name) {
      assert.equal(name, "chats");
      return {
        orderBy() { return this; },
        limit() { return this; },
        async get() {
          return { size: 1, docs: [{ ref: { collection: () => messageQuery } }] };
        },
      };
    },
  };
  const result = await staffChat.loadStaffMessages(business, "start", "end");
  assert.deepEqual(result.messages, [{ sender: "A", text: "Habari", createdAt: 10 }]);
  assert.equal(result.unreadAttachments, 1);
  assert.equal(result.omittedSensitiveMessages, 1);
  assert.equal(JSON.stringify(result).includes("private"), false);
  assert.deepEqual(calls, [["createdAt", ">=", "start"], ["createdAt", "<", "end"]]);
});
