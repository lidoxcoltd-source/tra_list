# MJASI POS - Google Play release pack

Status values: **PASS**, **NEEDS ATTENTION**, **BLOCKED**, **NOT VERIFIED**.
Nothing here has been uploaded or published. Placeholders in `<angle brackets>` must be filled in by the account owner.

## 1. Audit summary

| # | Area | Status | Finding |
|---|------|--------|---------|
| 1 | INTERNET permission in release | **PASS** (fixed) | Only the debug manifest declared it. Added `INTERNET` and `ACCESS_NETWORK_STATE` to the main manifest. |
| 2 | Release build compiles | **PASS** (fixed) | Failed: `firebase_auth` needs Kotlin 2.3 but the project used 2.1.0. Upgraded the plugin to 2.3.0 and migrated `kotlinOptions` to the `compilerOptions` DSL. `flutter build appbundle --release` now produces a 56 MB `.aab`. |
| 3 | Release signing | **BLOCKED** (needs you) | Release used the debug key. Now reads `android/key.properties`; no keystore exists yet. The current `.aab` is debug-signed and Play will reject it. |
| 4 | Application ID | **BLOCKED** (needs you) | `com.example.tra_list` is rejected by Play. Chosen new ID: `com.lidox.mjasipos`. Not applied yet, see section 3. |
| 5 | Target / min SDK | **PASS** | target 36, compile 36, min 24 (Flutter 3.35.7 defaults). Meets the API 36 requirement for new apps and updates from 31 Aug 2026 (from a web search, not checked in Play Console: **NOT VERIFIED**). |
| 6 | Version | **PASS** | `1.0.0+1`. Increase the `+N` for every upload. |
| 7 | Account deletion | **NEEDS ATTENTION** | Account creation exists. Added in-app **Delete account** (menu) and the `deleteMyAccount` Cloud Function. **Function is not deployed**; Play also needs a web deletion-request URL (section 6). |
| 8 | Password recovery | **NEEDS ATTENTION** | No "forgot password" flow exists. Not a Play blocker, but users who forget their password are locked out. |
| 9 | Photo/video/audio permissions | **NEEDS ATTENTION** | Merged manifest contains `READ_MEDIA_IMAGES/VIDEO/AUDIO` (from a picker plugin). Play restricts these. The app only picks a logo and files via system pickers, which do not need them. Recommended: remove with `tools:node="remove"` after testing logo upload on a device. Not changed. |
| 10 | Firestore rules | **NEEDS ATTENTION** | Rules are strict and per-business with staff permissions and shop scoping. Risk: `subscriptions/{uid}` can be created/updated by the owner, so a modified client could grant itself a subscription. Fix needs server-side billing; not changed. `receipts/{id}` is readable by anyone who knows the id (intended for verification). |
| 11 | Storage rules | **PASS** | Access limited to `users/{businessUid}/...` by permission. |
| 12 | Hardcoded secrets | **PASS** | Only Firebase client API keys (not secrets). Restrict them by package name + SHA-1 in Google Cloud Console (**NOT VERIFIED**). |
| 13 | QR link | **NEEDS ATTENTION** | `ReceiptViewPage.dart` builds `http://localhost:8080/receipt/<id>` for the QR dialog. Wrong for production. Needs your real verification URL. |
| 14 | `allowBackup` / R8 | **NOT VERIFIED** | Defaults used. Release build works; test the release app on a device. |
| 15 | Analyzer / tests | **PASS** | `flutter analyze`: 0 errors, 254 infos/warnings (existing style/deprecation items). `flutter test`: 16 passed. |
| 16 | Manual device tests | **NOT VERIFIED** | None performed. See section 8. |

### Files changed

- `android/app/src/main/AndroidManifest.xml`: internet and network-state permissions.
- `android/app/build.gradle.kts`: `key.properties` signing, Kotlin `compilerOptions`.
- `android/settings.gradle.kts`: Kotlin plugin 2.1.0 to 2.3.0.
- `android/key.properties.example`: template (real `key.properties` is git-ignored).
- `functions/index.js`: new `deleteMyAccount` callable.
- `lib/services/account_deletion_service.dart` and `lib/HomePage.dart`: in-app delete account.

### Effect on existing users / production data

- Kotlin upgrade and manifest changes: no data impact.
- `deleteMyAccount` **permanently deletes** an owner's business data, staff logins, receipts and files. A staff member only removes their own login and membership. Super admins are blocked. It does nothing until deployed.

## 2. Release signing and build

1. Create the upload key once (keep it and its passwords private and backed up):
   `keytool -genkey -v -keystore C:\keys\mjasi-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
2. Copy `android/key.properties.example` to `android/key.properties` and fill in passwords and the `storeFile` path.
3. Enrol in Play App Signing when creating the app in Play Console.
4. Build: `flutter build appbundle --release`
5. Output: `build\app\outputs\bundle\release\app-release.aab`. Verify the signer is **not** "Android Debug":
   `keytool -printcert -jarfile build\app\outputs\bundle\release\app-release.aab`

## 3. Changing the application ID to `com.lidox.mjasipos`

The ID is permanent once published. It is not applied yet because `google-services.json` only contains `com.example.tra_list`, and the build fails without a matching Firebase app.

1. Firebase Console, project `tra-verify`, Project settings, **Add app**, Android, package `com.lidox.mjasipos`. Add the SHA-1 and SHA-256 of your upload key and of the Play App Signing key (Play Console, App integrity).
2. Download the new `google-services.json` into `android/app/`.
3. Change `applicationId` in `android/app/build.gradle.kts` (keep `namespace` as is).
4. Update `lib/firebase_options.dart` (`flutterfire configure`) and rebuild.

The Firebase project stays the same, so existing users and data are unaffected.

## Super Admin app version enforcement

The Super Admin menu includes **App version control**. It stores a minimum version, minimum build number, update URL, and message for Android, Windows, and Web in `app_config/version_policy`.

- Enable only the platforms that already have a working update URL. The URL must use HTTPS.
- A user's app is blocked after sign-in when its version/build is below that platform's minimum. Super Admin accounts bypass the gate so they can correct a policy.
- The current policy is cached locally. If the service is unavailable, a cached policy is still enforced; without a cached policy the app allows access rather than locking users out on first launch.
- This is a client-side access gate, not a security boundary. Keep sensitive data protected by Firestore/Storage rules; an old or modified client must not be trusted for authorization.
- Deploy the updated Firestore rules before using the page: `firebase deploy --only firestore:rules`. Verify the selected Firebase project first.
- Increase `version:` in `pubspec.yaml` for each app release and build/publish the corresponding platform. The gate cannot affect already-installed builds until a build containing the gate has been distributed.
- Windows users need a hosted installer or downloadable release archive at the configured URL. The current Windows output is a folder, not a self-installing package.

## 4. Data inventory (from the code)

| Data | Source | Where stored | Shared |
|------|--------|--------------|--------|
| Name, business name, phone, email, password | Account creation | Firebase Auth and Firestore `users/{uid}/profile` | Firebase only |
| Staff name, email/phone, permissions | Staff management | Firestore `employeeMemberships` | Firebase only |
| Income, expenses, categories, debts, jobs, invoices, quotations, receipts | User entry | Firestore `users/{uid}/...`, `receipts` | Firebase only |
| Company logo / uploaded images | User upload | Firebase Storage `users/{uid}/...` | Firebase only |
| Document designs and terms | User entry | Firestore profile | Firebase only |
| Subscription status | App | Firestore `subscriptions/{uid}` | Firebase only |
| Language / local settings | App | On-device storage | No |

Not found in the code: ads, analytics, crash reporting, location, contacts, payment processing, advertising ID. Firebase processes device/network data as part of normal operation (**NOT VERIFIED** against Firebase's privacy documentation).

Third-party SDKs: Firebase (Auth, Firestore, Storage, Functions, Core), Syncfusion Charts, `pdf`/`printing`, `share_plus`, `image_picker`, `file_picker`, `url_launcher`, `connectivity_plus`, `get_storage`.

## 5. Data safety worksheet (draft, verify before submitting)

| Question | Draft answer |
|----------|--------------|
| Collects data | Yes |
| Shares data with third parties | No (Firebase acts as a service provider; confirm) |
| Encrypted in transit | Yes (HTTPS) |
| Users can request deletion | Yes, in-app and web (after the function is deployed and the web page exists) |
| Personal info: name, email, phone | Collected, app functionality, linked to user, no ads use |
| Financial info: user-entered records | Collected, app functionality, linked to user |
| Photos: logo upload | Optional, only if the user uploads one |
| App activity / diagnostics / device IDs | Only if you add analytics or Crashlytics; none in code |
| Ads | None in code |

## 6. Account deletion for Play

- In app: menu, **Delete account** (re-enter password, type DELETE).
- Web route required by Play: publish `<https://your-domain/delete-account>` naming the app and developer, explaining the in-app steps, and giving `<support email>` for email requests. Enter this URL in Play Console.
- Deploy only after review: `firebase deploy --only functions:deleteMyAccount`.
- Retention: owner data is removed completely. If you must keep financial records for legal reasons, change this before deploying (**needs your decision**).

## 7. Privacy policy draft

> Replace `<...>`, host at a public HTTPS URL, and have a legal adviser review it.
>
> **MJASI POS Privacy Policy** (last updated `<date>`)
>
> **Who we are.** MJASI POS is provided by `<legal name>`, `<address>`, contact `<email>`.
>
> **What we collect.** Account details (name, business name, phone, email, password); business records you enter (income, expenses, categories, debts, jobs, invoices, quotations, receipts, document designs and terms); staff names, contact details and permissions you add; images you upload such as a logo; subscription status.
>
> **How we use it.** To provide the app: sign you in, store and show your records and reports, let your staff access what you allow, and generate documents you request. We do not sell your data and show no ads.
>
> **Where it is stored.** On Google Firebase (Authentication, Firestore, Cloud Storage, Cloud Functions), encrypted in transit. Some preferences stay on your device.
>
> **Sharing.** Only with Google Firebase as our service provider, and where required by law. Documents you share go where you send them.
>
> **Staff.** Owners control what staff can see; staff only access data allowed by their permissions.
>
> **Retention and deletion.** Data is kept while your account is active. Delete your account in the app (Menu, Delete account), by emailing `<email>`, or at `<deletion URL>`. Deleting an owner account permanently removes business records, staff logins and uploaded files.
>
> **Children.** Not directed at children under `<age>`.
>
> **Contact.** `<email>` to access, correct or delete your data.
>
> **Changes.** We will update this page and its date when the policy changes.

A terms-of-service document is recommended (subscriptions, staff accounts, responsibility for records). Not drafted because it needs your legal details.

## 8. Test plan (none run yet, all **NOT VERIFIED**)

Fresh install and first launch; register, login, logout; edit/delete a transaction; add a second business and switch; staff invite and each permission per module; confirm staff cannot read another business or another shop; report totals, dates and TZS formatting; airplane mode and slow network; session expiry; restart persistence; Delete account (staff and owner, on a test project first); document PDFs (invoice, quotation, advance, delivery) and Share as image on a real phone; Android 13/14/15/16 and a tablet; rotation and large screens; the release build on a device.

## 9. Store listing draft

- App name (max 30): **MJASI POS**. Category: Business. Tags: bookkeeping, income, expenses.
- Contact `<support email>`; website `<optional>`; privacy policy `<URL>`.

**Short description (max 80)**
- EN: Record income and expenses, manage staff and track your business reports.
- SW: Rekodi mapato na matumizi, simamia wafanyakazi na fuatilia ripoti za biashara.

**Full description EN**
MJASI POS helps entrepreneurs keep clear records of their business money.

- Record business income
- Record business expenses
- Manage multiple businesses from one account
- Connect staff and give each person only the permissions they need
- Review business performance with reports and charts
- Create invoices, quotations, proformas, delivery notes and advance-payment documents with your own logo, colours and terms, and share them as PDF or image

Your data is stored in your account and protected by sign-in.

**Full description SW**
MJASI POS inamsaidia mjasiriamali kutunza kumbukumbu za fedha za biashara yake kwa uwazi.

- Rekodi mapato ya biashara
- Rekodi matumizi ya biashara
- Simamia biashara nyingi kwa akaunti moja
- Unganisha wafanyakazi na uwape ruhusa wanazohitaji tu
- Angalia utendaji wa biashara kupitia ripoti na chati
- Tengeneza ankara, nukuu, proforma, hati ya uwasilishaji na ya malipo ya awali kwa nembo, rangi na masharti yako, kisha zitume kama PDF au picha

Taarifa zako zinahifadhiwa kwenye akaunti yako na zinalindwa kwa kuingia.

Claims are limited to features found in the code. The app does not process payments or provide tax filing or automated accounting, so do not claim them.

### Assets to create (not in the repo)
- App icon 512x512 PNG. The launcher icons in the project are the Flutter defaults: replace them with branded icons.
- Feature graphic 1024x500.
- 2 to 8 phone screenshots (320 to 3840 px per side, 16:9 or 9:16), taken from the release build with demo data only.
- Optional 7-inch and 10-inch tablet screenshots.

## 10. Play Console checklist

- [ ] Create the app: name MJASI POS, default language, free/paid, declarations.
- [ ] Enrol in Play App Signing.
- [ ] App access: reviewers need login. Supply a **test owner account and a test staff account** with demo data (you create them; never real users).
- [ ] Ads: No.
- [ ] Target audience and content rating questionnaire, answered from actual behaviour.
- [ ] Data safety (section 5) and privacy policy URL (section 7).
- [ ] Account deletion URL (section 6).
- [ ] Permissions declarations if photo/media permissions remain (finding 9).
- [ ] Financial features declaration, if shown: ordinary bookkeeping is not automatically a regulated financial service, but confirm for your subscription features.
- [ ] Store listing and graphics (section 9).
- [ ] Countries/regions.
- [ ] Upload the signed `.aab` to Internal testing and review the Pre-launch report (crashes, ANRs, accessibility).
- [ ] If your developer account is personal and was created after 13 Nov 2023, Play requires a closed test with at least 12 opted-in testers for 14 continuous days before production access. Organization and older accounts differ: check Play Console, Test and release (**NOT VERIFIED** for your account).
- [ ] Production with a staged rollout (for example 10%, 50%, 100%). To roll back, halt the rollout and ship a higher version code; a published version cannot be deleted.

## 11. Final status

| Item | Status |
|------|--------|
| Release build compiles | PASS |
| Signed with a production key | BLOCKED (no keystore yet) |
| Application ID valid for Play | BLOCKED (section 3) |
| Internet permission | PASS |
| Target API 36 | PASS |
| Account deletion in app | PASS (code); NEEDS ATTENTION (function not deployed, web URL missing) |
| Privacy policy | NEEDS ATTENTION (draft, not hosted) |
| Data safety | NEEDS ATTENTION (draft) |
| Store assets | NEEDS ATTENTION (none created) |
| Manual device testing | NOT VERIFIED |
| Closed-testing requirement | NOT VERIFIED |
