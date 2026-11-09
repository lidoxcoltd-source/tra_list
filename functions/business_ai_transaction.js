const PREFIX = String.raw`^(?:(?:please|tafadhali|naomba|nataka|i\s+want\s+to)\s+)*(?:u?(?:record|rekodi|sajili|hifadhi|andika)|kurekodi|weka)\s+`;
const TYPE = String.raw`(?:ya\s+)?(matumizi|mapato|expense|income)\b`;
const COMMAND = new RegExp(String.raw`${PREFIX}${TYPE}`, "i");
const FORMAT = new RegExp(
  String.raw`${PREFIX}${TYPE}\s+(?:ya\s+)?(?:tsh\s*|tzs\s*)?(\d{1,3}(?:,\d{3})+|\d+)\s*;\s*(?:category|kundi)\s*:\s*([^;]{1,100})\s*;\s*(?:description|maelezo)\s*:\s*([^;]{1,300})\s*$`,
  "i",
);
const AMOUNT_ONLY = new RegExp(
  String.raw`${PREFIX}${TYPE}\s+(?:ya\s+)?(?:tsh\s*|tzs\s*)?(\d{1,3}(?:,\d{3})+|\d+)\s*$`,
  "i",
);
const DETAILS = /^(?:category|kundi)\s*:\s*([^;]{1,100})\s*;\s*(?:description|maelezo)\s*:\s*([^;]{1,300})\s*$/i;
const FOLLOWUP_SW = "Tafadhali tuma kundi na maelezo kwa muundo: kundi: Kodi; maelezo: Kodi ya duka. Tumia kundi lililopo; tarehe itakuwa leo.";
const FOLLOWUP_EN = "Please send the category and description in this format: category: Rent; description: Shop rent. Use an existing category; the date will be today.";
const TYPE_FOLLOWUP_SW = "Unataka kurekodi mapato au matumizi? Chagua aina moja kwanza.";
const TYPE_FOLLOWUP_EN = "Would you like to record income or an expense? Please choose one first.";

function amountFollowup(type, language) {
  return language === "Swahili"
    ? `Tuma kiasi cha ${type === "income" ? "mapato" : "matumizi"} unachotaka kurekodi.`
    : `Send the amount of ${type} you want to record.`;
}

function amountReply(text) {
  const match = /^(?:(?:tsh|tzs)\s*)?(\d{1,3}(?:,\d{3})+|\d+)$/i.exec(text.trim());
  if (!match) return null;
  const amount = Number(match[1].replace(/,/g, ""));
  return Number.isSafeInteger(amount) && amount > 0 ? amount : null;
}

function typeReply(text) {
  if (/^(?:mapato|income)$/i.test(text.trim())) return "income";
  if (/^(?:matumizi|expense)$/i.test(text.trim())) return "expense";
  return null;
}

function typeForAmountReply(messages, promptIndex) {
  const prompt = messages[promptIndex];
  const request = messages[promptIndex - 1];
  if (prompt?.role !== "assistant" || request?.role !== "user") return null;
  const direct = parseTransactionCommand(request.content);
  if (direct?.incomplete && direct.type && !direct.amount) return direct.type;
  const typePrompt = messages[promptIndex - 2];
  const ambiguousRequest = parseTransactionCommand(messages[promptIndex - 3]?.content);
  if (typePrompt?.role !== "assistant" ||
      ![TYPE_FOLLOWUP_SW, TYPE_FOLLOWUP_EN].includes(typePrompt.content) ||
      !ambiguousRequest?.incomplete || ambiguousRequest.type) return null;
  return typeReply(request.content);
}

function amountCommand(match) {
  const amount = Number(match[2].replace(/,/g, ""));
  if (!Number.isSafeInteger(amount) || amount <= 0) return null;
  return {
    type: /^(matumizi|expense)$/i.test(match[1]) ? "expense" : "income",
    amount,
  };
}

function parseTransactionCommand(text) {
  if (typeof text !== "string" || !COMMAND.test(text.trim())) return null;
  const commandText = text.trim();
  const match = FORMAT.exec(commandText);
  if (!match) {
    const partial = AMOUNT_ONLY.exec(commandText);
    const value = partial && amountCommand(partial);
    if (value) return { incomplete: true, ...value };
    const hasIncome = /\b(?:mapato|income)\b/i.test(commandText);
    const hasExpense = /\b(?:matumizi|expense)\b/i.test(commandText);
    if (hasIncome && hasExpense) return { incomplete: true };
    const typeMatch = COMMAND.exec(commandText);
    const remaining = typeMatch
      ? commandText.slice(typeMatch[0].length)
      : "";
    if (/^\s*(?:ya\s+)?(?:(?:tsh|tzs)\s*)?\d/i.test(remaining)) {
      return { incomplete: true };
    }
    return {
      incomplete: true,
      ...(typeMatch
        ? { type: /^(matumizi|expense)$/i.test(typeMatch[1]) ? "expense" : "income" }
        : {}),
    };
  }
  const value = amountCommand(match);
  const category = match[3].trim();
  const description = match[4].trim();
  if (!value || !category || !description) return { incomplete: true };
  return { ...value, category, description };
}

function parseConversation(messages) {
  const last = messages[messages.length - 1];
  const direct = parseTransactionCommand(last?.content);
  if (direct) return direct;
  if (messages.length < 3 || last?.role !== "user") return null;
  const previous = messages[messages.length - 2];
  const original = messages[messages.length - 3];
  if (previous?.role !== "assistant" || original?.role !== "user") return null;
  const partial = parseTransactionCommand(original.content);
  if ([TYPE_FOLLOWUP_SW, TYPE_FOLLOWUP_EN].includes(previous.content)) {
    if (!partial?.incomplete || partial.type) return null;
    const type = typeReply(last.content);
    return type ? { incomplete: true, type } : null;
  }
  const amountPrompts = [
    amountFollowup("income", "Swahili"),
    amountFollowup("expense", "Swahili"),
    amountFollowup("income", "English"),
    amountFollowup("expense", "English"),
  ];
  if (amountPrompts.includes(previous.content)) {
    const type = typeForAmountReply(messages, messages.length - 2);
    if (!type) return null;
    const amount = amountReply(last.content);
    return amount ? { incomplete: true, type, amount } : null;
  }
  if (![FOLLOWUP_SW, FOLLOWUP_EN].includes(previous.content)) return null;

  let transaction = partial;
  if (!transaction?.type || !transaction.amount) {
    const amount = amountReply(original.content);
    const amountPromptIndex = messages.length - 4;
    const amountAssistant = messages[amountPromptIndex];
    const type = amountPrompts.includes(amountAssistant?.content)
      ? typeForAmountReply(messages, amountPromptIndex)
      : null;
    if (!type || !amount) return null;
    transaction = { type, amount };
  }
  const details = DETAILS.exec(last.content.trim());
  if (!details || !details[1].trim() || !details[2].trim()) return null;
  return {
    type: transaction.type, amount: transaction.amount,
    category: details[1].trim(), description: details[2].trim(),
  };
}

async function saveOwnerTransaction({ db, uid, businessUid, scope, command, messageId, questionRef, questionText }) {
  const business = db.collection("users").doc(businessUid);
  const record = business.collection("transactions").doc(`ai_${uid}_${messageId}`);
  const profile = business.collection("profile").doc("company");
  const modern = db.doc(`businessMemberships/${businessUid}/members/${uid}`);
  const legacy = db.doc(`employeeMemberships/${uid}`);
  const account = db.doc(`accountAccess/${uid}`);
  const businessAccount = db.doc(`accountAccess/${businessUid}`);
  const bar = business.collection("barSettings").doc("config");
  const categories = business.collection("categories").where("name", "==", command.category).limit(101);
  const now = Timestamp.now();
  await db.runTransaction(async (tx) => {
    const [old, savedQuestion, profileDoc, modernDoc, legacyDoc, accountDoc, businessAccountDoc, barDoc, categoryDocs] =
      await Promise.all([
        tx.get(record), tx.get(questionRef), tx.get(profile), tx.get(modern), tx.get(legacy),
        tx.get(account), tx.get(businessAccount), tx.get(bar), tx.get(categories),
      ]);
    let currentScope;
    try {
      currentScope = bi.scopeFor({
        uid, businessUid, profileExists: profileDoc.exists,
        accountDisabled: accountDoc.data()?.disabled === true,
        businessDisabled: businessAccountDoc.data()?.disabled === true,
        modern: modernDoc.data(), legacy: legacyDoc.data(),
        barEnabled: barDoc.data()?.enabled === true,
      });
    } catch (error) {
      if (!["disabled", "permission-denied", "missing-shop"].includes(error.message)) throw error;
      throw new HttpsError("permission-denied", "Business access changed.");
    }
    if (!currentScope.owner || JSON.stringify(currentScope) !== JSON.stringify(scope)) {
      throw new HttpsError("permission-denied", "Business access changed.");
    }
    if (!savedQuestion.exists || savedQuestion.get("role") !== "user" ||
        savedQuestion.get("content") !== questionText) {
      throw new HttpsError("failed-precondition", "Save the question before recording the transaction.");
    }
    if (old.exists) {
      const previous = old.data();
      if (previous.uid !== uid || previous.type !== command.type ||
          previous.amount !== command.amount || previous.category !== command.category ||
          previous.description !== command.description) {
        throw new HttpsError("already-exists", "Transaction request identifier already used.");
      }
      return;
    }
    if (categoryDocs.size > 100 ||
        !categoryDocs.docs.some((doc) => doc.get("type") === command.type)) {
      throw new HttpsError(
        "failed-precondition", "Choose an existing category of the matching transaction type.",
        { reason: "ai-transaction-category" },
      );
    }
    const profileData = profileDoc.data() || {};
    const shop = String(profileData.shopNickname || profileData.name || "").trim();
    tx.create(record, {
      uid, type: command.type, amount: command.amount,
      category: command.category, description: command.description,
      shopNickname: shop, date: now,
    });
  });
}

module.exports = {
  parseTransactionCommand, parseConversation, FOLLOWUP_SW, FOLLOWUP_EN,
  TYPE_FOLLOWUP_SW, TYPE_FOLLOWUP_EN, amountFollowup, saveOwnerTransaction,
};
const { Timestamp } = require("firebase-admin/firestore");
const { HttpsError } = require("firebase-functions/v2/https");
const bi = require("./business_intelligence");
