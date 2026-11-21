const bi = require("./business_intelligence");

async function businessAccess(db, uid, businessUid) {
  const [account, businessAccount, profile, modern, legacy, bar] = await Promise.all([
    db.doc(`accountAccess/${uid}`).get(),
    db.doc(`accountAccess/${businessUid}`).get(),
    db.doc(`users/${businessUid}/profile/company`).get(),
    db.doc(`businessMemberships/${businessUid}/members/${uid}`).get(),
    db.doc(`employeeMemberships/${uid}`).get(),
    db.doc(`users/${businessUid}/barSettings/config`).get(),
  ]);
  const scope = bi.scopeFor({
    uid, businessUid, profileExists: profile.exists,
    accountDisabled: account.data()?.disabled === true,
    businessDisabled: businessAccount.data()?.disabled === true,
    modern: modern.data(), legacy: legacy.data(),
    barEnabled: bar.data()?.enabled === true,
  });
  const data = profile.data() || {};
  const profileText = (key, maxLength) => typeof data[key] === "string"
    ? data[key].trim().slice(0, maxLength)
    : "";
  return {
    scope,
    name: profileText("name", 120),
    businessProfile: {
      businessType: profileText("businessType", 120),
      businessDescription: profileText("businessDescription", 1000),
      address: profileText("address", 300),
      phone: profileText("phone", 80),
      website: profileText("website", 200),
      socialHandle: profileText("handle", 120),
    },
  };
}

async function dailyBriefAccess(db, uid, businessUid) {
  const [account, businessAccount, profile, modern, legacy, bar] = await Promise.all([
    db.doc(`accountAccess/${uid}`).get(),
    db.doc(`accountAccess/${businessUid}`).get(),
    db.doc(`users/${businessUid}/profile/company`).get(),
    db.doc(`businessMemberships/${businessUid}/members/${uid}`).get(),
    db.doc(`employeeMemberships/${uid}`).get(),
    db.doc(`users/${businessUid}/barSettings/config`).get(),
  ]);
  const scope = bi.dailyBriefScopeFor({
    uid,
    businessUid,
    profileExists: profile.exists,
    accountDisabled: account.data()?.disabled === true,
    businessDisabled: businessAccount.data()?.disabled === true,
    modern: modern.data(),
    legacy: legacy.data(),
    barEnabled: bar.data()?.enabled === true,
  });
  const data = profile.data() || {};
  const name = typeof data.name === "string" ? data.name.trim().slice(0, 120) : "";
  return { scope, name: name || "Business" };
}

module.exports = { businessAccess, dailyBriefAccess };
