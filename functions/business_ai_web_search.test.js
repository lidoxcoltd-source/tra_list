const test = require("node:test");
const assert = require("node:assert/strict");
const {
  isOnlineResearchRequest,
  publicBusinessResearchProfile,
  buildGroundedResearchRequest,
  appendGroundedSources,
} = require("./business_ai_web_search");

test("online research is enabled only for explicit public-web requests", () => {
  assert.equal(isOnlineResearchRequest("Look up businesses like mine online"), true);
  assert.equal(isOnlineResearchRequest("Tafuta biashara zinazofanana na yangu mtandaoni"), true);
  assert.equal(isOnlineResearchRequest("Nipe report ya mwezi huu"), false);
  assert.equal(isOnlineResearchRequest("rekodi matumizi 30000"), false);
});

test("grounded Gemini requests contain only the latest question and public category", () => {
  const request = buildGroundedResearchRequest({
    language: "Swahili",
    question: "Nipe biashara zinazofanana na yangu mtandaoni",
    context: {
      businessName: "Private Shop",
      businessProfile: {
        businessType: "Retail",
        businessDescription: "Household goods",
        address: "Private address",
        phone: "+255700000000",
      },
      transactions: { income: 1000000, expenses: 200000 },
    },
  });
  assert.deepEqual(request.tools, [{ googleSearch: {} }]);
  assert.deepEqual(request.contents, [{
    role: "user",
    parts: [{ text: "Nipe biashara zinazofanana na yangu mtandaoni" }],
  }]);
  const serialized = JSON.stringify(request);
  assert.match(serialized, /Retail/);
  assert.doesNotMatch(serialized, /Private Shop|Private address|255700000000|1000000|200000/);
});

test("only business category details are shared as web-research context", () => {
  assert.deepEqual(publicBusinessResearchProfile({
    businessProfile: {
      businessType: "Retail",
      businessDescription: "Household goods",
      address: "Private address",
      phone: "+255700000000",
    },
    businessName: "Private business name",
    transactions: { income: 1000000 },
  }), {
    businessType: "Retail",
    businessDescription: "Household goods",
  });
  assert.deepEqual(publicBusinessResearchProfile({ businessProfile: null }), {});
});

test("grounded answers include a bounded, deduplicated list of safe source URLs", () => {
  const answer = appendGroundedSources("Market research summary", {
    groundingChunks: [
      { web: { title: "Example", uri: "https://example.com/report" } },
      { web: { title: "Duplicate", uri: "https://example.com/report" } },
      { web: { title: "Unsafe", uri: "javascript:alert(1)" } },
      { web: { uri: "http://example.org/stats" } },
    ],
  }, "Swahili");
  assert.match(answer, /Vyanzo vya mtandaoni/);
  assert.match(answer, /Example: https:\/\/example\.com\/report/);
  assert.match(answer, /example\.org/);
  assert.doesNotMatch(answer, /javascript:/);
  assert.doesNotMatch(answer, /Duplicate/);
});
