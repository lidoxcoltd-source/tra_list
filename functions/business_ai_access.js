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
  return { scope, name: String(profile.data()?.name || "").trim().slice(0, 120) };
}

module.exports = { businessAccess };
