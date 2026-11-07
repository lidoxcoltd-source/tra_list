# tra_list

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Document terms

Users with business profile edit access can open **Document terms and versions**
from the documents list. Create named versions of the payment/completion note, delivery terms, and terms
and conditions, then select an active version separately for invoices,
proformas, quotations, and advance payment invoices. Saving changes creates a
new version, preserving older wording for future use. The active version is
applied whenever one of these PDFs is generated, including when regenerating a
document after work is complete.

## MJASI AI business report

The MJASI AI shortcut is available to business users with analytics view
permission. It reads recorded transaction income and expenses for the selected
business and period, and includes current stock and debt summaries only when
the user has the corresponding permissions. Staff transaction and debt data
is restricted to their assigned shop. Owners can also see POS invoice totals
and leading products separately. Income is not necessarily POS revenue,
and income minus expenses is cash flow, not accounting profit. Transactions
without a valid date are excluded. The screen identifies additional data
limitations and fails rather than displaying a partial report on read errors.
Stock-view permission also includes business-wide received stock purchases by
purchase date. These can overlap expenses and are not added to them. Users
with tasks-view permission receive business-wide counts of open and
awaiting-review tasks as of now, and tasks approved during the selected
period. These summaries omit supplier names, task descriptions and assignees.

Review the report before copying or sharing it. ChatGPT and Gemini open without
a prefilled prompt; copy and paste the reviewed report, then manually send it.
Product names and expense categories are user-entered and may themselves
contain sensitive information. The device share sheet can send the report to
other applications.

In-app chat uses OpenAI through Firebase callable functions, not a key in the
Flutter app. Deploy the functions and configure the Firebase secret
`OPENAI_API_KEY` using `firebase functions:secrets:set OPENAI_API_KEY`; secret
creation and deployment require administrator access and an OpenAI account
with API billing. The default model is `gpt-6-luna`. The function verifies the
authenticated business membership and module permissions, aggregates records
on the server, and requires review of the exact signed snapshot and recent
conversation before every request. Snapshots expire after ten minutes and
become invalid when access scope changes. Chat periods are limited to 366 days
and 5,000 records per collection; requests are limited to 30 per user per UTC
day and one every 10 seconds. Failed upstream requests also count toward the
limit. Preparing reports is limited to 120 per user per UTC day and one every
two seconds. OpenAI usage may incur charges.

The app and report follow the selected English or Swahili language; chat
requests instruct the AI to answer in that language, unless the user asks
otherwise. User-entered product names, expense categories and chat messages
are shared when approved and may themselves contain personal information.
Customers' names, contact details and payment credentials are not intentionally
included in the generated snapshot.

The assistant has separate chat and call tabs. Chat messages
are loaded from Firebase in pages for the signed-in user and selected business. History
is stored under a server-managed permission scope; changing a role, shop or
data permissions opens a separate history so previously accessible information
is not exposed under a narrower scope. Existing history is not deleted. Chat
messages and AI answers may contain sensitive business information and remain
stored in Firestore; avoid sharing personal customer details and credentials.
Every chat request still requires review of the business snapshot and recent
messages before sending to OpenAI. If an answer cannot be saved, it remains
visible only until the screen is closed and must be retried before continuing.
Deploy `loadBusinessAiHistory` and `saveBusinessAiMessage` before using this UI;
without them, history loading fails visibly and sending is disabled.

Chat recognizes today, yesterday, this month, last month, full dates in
`YYYY-MM-DD` or `DD/MM/YYYY` format, and day + English or Swahili month name +
year. Incomplete or unsupported date expressions open a date-range picker
instead of assuming a date; for example, "tarehe 2" requires confirmation of
the month and year. The exact local-calendar period and server snapshot are
shown for review before each request. Follow-up questions without a new date
use the last saved chat period, including after reopening the chat; older
messages created before period metadata exists fall back to the dashboard
period. Historical stock and debt values remain current balances, not
historical snapshots. Comparing separate periods in one answer is not yet
supported; ask about each period separately. Reports remain subject to the
existing 366-day and record-count limits.

### Android live voice (deployment required)

Live voice is Android-only and is separate from the text conversation. Before
each session the user must review the signed business summary and explicitly
agree to send it and live microphone audio to OpenAI. Audio is not reviewed
sentence by sentence. The assistant speaks in the selected app language unless
asked otherwise; Swahili recognition and voice quality must be tested on real
devices. The voice is AI-generated. The user can mute or end the session; it
also stops when the app is backgrounded or its business context changes.
Do not speak customer personal details or credentials. Product and category
names in the reviewed summary may also contain sensitive information.

The voice service authenticates Firebase users, rechecks business permissions,
verifies the existing signed snapshot, and limits each user to two session
attempts per UTC day. Attempts count even if the OpenAI connection fails.
It closes sessions at approximately five minutes and uses a Cloud Tasks
hangup as a backup. Cloud Tasks may be delayed or fail; configure monitoring
and OpenAI project spending limits, since this is not a guaranteed billing
cap. A network or service failure can interrupt a session. OpenAI Realtime
audio and Google Cloud services incur additional charges.

Deploy `endBusinessAiVoice` as a Firebase task queue function and deploy the
`functions` directory as a separate Cloud Run service, whose `npm start` runs
`voice_server.js`. Configure Cloud Run with the same `OPENAI_API_KEY` secret
used by the Firebase functions, Firebase Admin application-default credentials,
and a request timeout above five minutes. Its service identity needs permission
to read Firestore and Firebase Auth, access the secret, enqueue Cloud Tasks,
and invoke the task function as described in the Firebase task queue IAM
documentation. The WebSocket endpoint must be reachable over TLS; it verifies
Firebase ID tokens itself. Set `MJASI_VOICE_URL` via `--dart-define` to the
service's `wss://` URL when building Android. Never put the OpenAI key in
the app. Deploying or enabling voice requires a separate operational review,
including task queue IAM, quotas, network behavior, permissions changes,
microphone privacy, real-device tests, and an OpenAI project with realtime
model access and billing. Without this configuration voice is unavailable.
