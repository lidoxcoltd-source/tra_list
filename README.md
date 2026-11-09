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

In Isher chat, swipe a message right or use its reply button to quote it in a
new question. The quoted excerpt is sent to the AI with that question; review
it for sensitive data. Your regular messages can be edited without sending a
new question, and individual messages can be deleted after confirmation.
Edits do not change previous AI answers; document events and messages linked
to saved transactions cannot be edited. Deleting a chat message does not
delete business records. These history actions require the updated callable
function and app.

Super admins can set optional provider nicknames and individual chat
model/version nicknames on the AI models and prices page. The model picker uses
these names for chat and voice; blank names use generic Isher labels. Nicknames
are display labels only: provider and model identifiers, availability, pricing
and routing do not change. Privacy disclosures still identify the real AI
provider. The updated callable functions and app must both be deployed before
the feature is available.

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

In-app chat uses OpenAI or Google Gemini through Firebase callable functions,
not keys in the Flutter app. Configure the `OPENAI_API_KEY` and
`GEMINI_API_KEY` Firebase secrets; secret creation and deployment require
administrator access and accounts with appropriate API access and billing.
For users without a saved selection, chat prefers Gemini 3.8 Flash and live
voice prefers Gemini, when enabled by the administrator. Existing selections
are preserved; users can switch providers. If the preferred default is disabled,
another enabled option is used. The function verifies the
authenticated business membership and module permissions and aggregates records
on the server. Sending a chat message sends the signed business snapshot and
recent conversation to the selected provider without a separate confirmation for each message.
Snapshots expire after ten minutes and
become invalid when access scope changes. Chat periods are limited to 366 days
and 5,000 records per collection. AI usage is limited per user as described
below, with an additional minimum interval of 10 seconds between chat requests.
Failed upstream requests also count toward the limit. Preparing reports is
limited to 120 per user per UTC day and one every
two seconds. Provider usage may incur charges.

The app and report follow the selected English or Swahili language; chat
requests instruct the AI to answer in that language, unless the user asks
otherwise. User-entered product names, expense categories and chat messages
are shared with OpenAI and may themselves contain personal information.
Customers' names, contact details and payment credentials are not intentionally
included in the generated snapshot.

The server snapshot also includes current inventory cost value and stock movement
counts for accounts with stock permission. Business owners receive staff names,
shop assignments and active status (up to 50 entries), plus invoice and receipt
totals grouped by document kind and task counts per assignee. Receipts are scoped to the business and filtered
by their creation time; device-only receipts are not included. These document
totals can overlap transactions or POS sales and must not be added together.
Automatic staff chat sharing remains disabled. The owner can instead open
**Review staff chat** from Isher, select one message or attachment at a time,
review its full contents, and explicitly send it with a question to OpenAI.
Chats and messages are loaded in batches of 50 and 100; use “Load older items”
to see more. Records without the required ordering timestamps are unavailable.
Supported
attachments are JPEG, PNG, WebP and PDF, up to 5 MB; PDF previews are limited
to 20 pages and 32 MB of rendered images. The server verifies
owner access and binds the previewed text or file bytes to a five-minute
review token, reloading and comparing the content before sending. The result
is displayed on the review page, not stored in Isher chat history. Each
request uses the existing message quota and can incur OpenAI charges.
The review endpoint uses `gpt-6-luna`; access to this model depends on the
configured OpenAI account.

The owner must not share credentials, private payment information, or
unnecessary personal data. Text filtering recognizes only some credential
terms; it cannot detect every secret, nor inspect images or PDF content for
secrets. PDF files may contain text or metadata not visible in the preview.
Do not share a file unless its complete contents are safe to transmit.

An owner can record a transaction in text chat with an explicit command such as
`rekodi matumizi 30000; kundi: Kodi; maelezo: Kodi ya duka` or
`record income 30000; category: Sales; description: Cash sale`. The category
can also be supplied in a follow-up: after `rekodi matumizi 30000`, respond
to Isher's prompt by choosing or searching for an existing category and entering a description,
or send `kundi: Kodi; maelezo: Kodi ya duka`. Suggestions use server categories
for the selected business and the correct transaction type. The displayed date
is the device's current date; the record uses server time when saved. Other follow-up
formats are not supported; repeat the full command if necessary. The category
must already exist with the matching type. The recorded date is the current
server time, and the server verifies owner access and the saved question before
creating the existing transaction record. An incomplete command is not saved.
The same message ID is idempotent, but manually sending a new message creates a
new request; if the connection fails, check the transaction list before retrying.
Recording through Isher is not available to staff or in voice sessions.
The chat can also open a document form without saving automatically. For
example, `niandalie invoice; mteja: Asha; bidhaa: Mchele; idadi: 2; bei: 5000`.
For a bare `nitengenezee invoice` request, a local step-by-step guide collects
the customer, optional invoice name and number, dates, up to 30 line items,
and optional terms. Skipped dates and number use the existing form defaults.
The guide shows a summary and allows saving from chat or by typing `save` or
`hifadhi`. Select tracked products from stock in the guide to deduct stock;
manually named items do not deduct stock. Saving uses the existing invoice
collection and stock transaction. The request, completed invoice summary and
PDF actions are saved to the user's scoped chat history. Opening or saving a
PDF retrieves the current invoice and checks current invoice view permission.
On Android and iOS, device files are saved in the app's documents directory.
The edit action opens the existing editor only for invoices without stock
links; stock-linked invoices cannot safely be edited from this action yet.
The guide requires invoice create and view permissions
and access to the business profile. If the save result is uncertain, check the
invoice list before starting another request; retrying the same guide reuses
its document ID. A new guide after leaving the screen is a new request.
Saving creates the invoice record, not a PDF; use the PDF actions in chat to
preview or save a separate file. Typed guided invoice steps
are not voice commands.
Isher can open selected app pages from explicit chat commands such as
`fungua miamala` or `open invoices`. Supported pages are transactions,
invoices, receipts, quotation, reports, jobs, tasks, staff and POS; stock is
not included. Chat also accepts polite requests such as `tafadhali nifungulie
page ya miamala` or `could you open staff?`. Requests naming multiple pages or
asking for a specific record are not treated as page navigation. Voice requests require confirmation on screen before opening a
page. Existing business permissions, receipt restrictions and subscription
checks still apply. Gemini voice is paused and attempts to resume on return
while its connection remains available; OpenAI voice ends and must be started
again. Voice navigation requires deployment of the updated voice tool
declarations to both the Gemini callable functions and the OpenAI voice service.
Individual guide steps remain in memory and are discarded if the guide is
cancelled or the screen is closed. A saved invoice's summary, including the
customer name and item descriptions, is stored in chat history; document events
are excluded from later AI requests. For other document forms, chat records the
request and that the form opened, not whether the document was saved.
Supported forms are invoice, quotation, proforma, advance payment invoice and
receipt. The labelled item fields must be supplied together; for advance use
`subtotal`, `kodi`/`tax`, and `advance`. The parser only accepts the documented
command format and one item; it does not infer extra fields or interpret
arbitrary natural language. The phrase `sawa tengeneza receipt ya 30,000` opens
a receipt draft displaying the requested amount as a reminder; it does not
assume an item amount or tax, which the user must enter. The user must review
and save in the existing form.
For other draft commands, item names are not linked to stock: select actual
stock products in the invoice form if stock must be deducted. Receipt drafting does not issue or
verify an official fiscal receipt; inspect company and fiscal details before
saving. Drafts are not sent to an AI service or persisted until saved in the form.
When an owner asks about customers, invoices or receipts, the server prepares
up to 20 recent records per document type in the selected period, with at most
30 line items per document. The owner reviews the exact details in the chat
and explicitly confirms before sending them to OpenAI; there is no review
pop-up. Customer questions include names from those documents; other
document questions omit them. Contact details, identity numbers and payment
credentials are excluded from the selected fields, but free-text descriptions
may contain sensitive information and must be reviewed. Customer history is
limited to these records, not a complete customer directory; invoice and receipt
records can overlap. A request for the latest invoice without a date searches
all periods, using creation time and excluding quotations. Records missing
creation times and local-only receipts are unavailable. Staff accounts cannot
access this extra document detail through Isher. The updated app uses
`prepareBusinessAiContextV2`, `prepareBusinessAiDocuments`, and
`askBusinessAiV2`, leaving the existing endpoints for older app versions.
The V2 text endpoint uses the existing production model `gpt-4o-mini`;
availability and billing must be verified with the configured account.

The welcome screen shows Isher's three capabilities and automatically
requests a spoken greeting with the selected business name. Only the greeting text,
including the business name, is sent to OpenAI. The authenticated server checks
business access and limits generated greetings to three per user per Tanzania
calendar day, separately from chat and call quotas. If OpenAI is unavailable or the limit is reached,
the app tries an installed offline Android text-to-speech voice. Failed
generation attempts do not consume the three-greeting allowance, but a
separate safety limit of twelve attempts per day prevents repeated failures
from causing unbounded provider requests.
The greeting starts once access is ready, without waiting for the business
report to finish loading; chat and call still wait for that report.
If neither OpenAI nor an offline voice is available, the screen shows an error.
The greeting does not start a voice call or microphone;
the device voice is not Isher's live
AI voice. Audio stops when leaving the welcome screen or backgrounding the app.
In the Android voice call, the orb's eye moves gently while idle. It responds
to the local microphone level while unmuted, and changes color and pulses
when the selected provider plays AI speech (the pulse is decorative, not a
measurement of speech volume). If the microphone level is unavailable, the
app indicates this. Reduced-motion settings disable the movement. After the voice data channel
opens, the app requests a short spoken greeting from Isher. The microphone is
enabled after that request, so the greeting can be interrupted by the user.
The assistant has separate chat and call tabs. Chat messages
are loaded from Firebase in pages for the signed-in user and selected business. History
is stored under a server-managed permission scope; changing a role, shop or
data permissions opens a separate history so previously accessible information
is not exposed under a narrower scope. Existing history is not deleted. Chat
messages and AI answers may contain sensitive business information and remain
stored in Firestore; avoid sharing personal customer details and credentials.
If an answer cannot be saved, it remains
visible only until the screen is closed and must be retried before continuing.
The chat accepts emoji from the device keyboard or its emoji picker. It also
offers editing and resending a previous user message as a new message;
the original conversation remains unchanged. Existing unsent text requires
confirmation before it is replaced. The server asks Isher to answer concisely
in plain text, with occasional relevant emoji;
response formatting still depends on the AI model and older saved messages are
not altered. Chat displays the Isher avatar and a waiting indicator while the
response request is in progress. The call button opens the separate voice view;
returning to chat preserves its current draft.
Within the same business-intelligence screen, previously loaded chat history is
kept in memory and displayed while it refreshes. Sending remains disabled until
the refresh succeeds. The cache is cleared when business context or access
changes, on access denial, and when the business-intelligence screen closes;
the first open still needs to load history from the server.
Deploy `loadBusinessAiHistory` and `saveBusinessAiMessage` before using this UI;
without them, history loading fails visibly and sending is disabled.

Chat recognizes today, yesterday, this month, last month, full dates in
`YYYY-MM-DD` or `DD/MM/YYYY` format, and day + English or Swahili month name +
year. Incomplete or unsupported date expressions open a date-range picker
instead of assuming a date; for example, "tarehe 2" requires confirmation of
the month and year. The selected local-calendar period determines the server
snapshot sent with each request. Follow-up questions without a new date
use the last saved chat period, including after reopening the chat; older
messages created before period metadata exists fall back to the dashboard
period. Historical stock and debt values remain current balances, not
historical snapshots. Comparing separate periods in one answer is not yet
supported; ask about each period separately. Reports remain subject to the
existing 366-day and record-count limits.

### AI usage and test credits

The super admin hub contains MJASI AI settings: daily voice sessions, daily
messages, maximum voice minutes (1–30), and indicative whole-TZS prices per
session and per message. Defaults are two voice attempts, 20 messages, five
minutes per session and zero prices until configured. Each authenticated user
has an individual quota shared across businesses. Daily allowances reset at
midnight Africa/Dar_es_Salaam; extra test credits persist until used. A request
consumes an allowance when accepted for an AI attempt, even if the provider
subsequently fails. The AI usage screen shows the remaining balance and prices.

Super admins can grant test credits to a Firebase user UID without payment.
There is no checkout, payment verification or automatic paid top-up; prices
are informational and payment integration must be separately designed and
verified before activation. Settings and balances are server-managed; only
verified, enabled super admins may change settings or grant credits. Grant
records are retained for audit. The old UTC usage counters are separate and
are not migrated; deploying the new quota starts a fresh allowance.

Deploy `getBusinessAiQuota`, `getBusinessAiAdminSettings`,
`saveBusinessAiAdminSettings`, `grantBusinessAiQuota`, `askBusinessAi` and the
voice Cloud Run service together with a compatible app version. A partial
deployment can show limits that are not enforced by an older backend.

### Android live voice (deployment required)

Live voice is Android-only and is separate from the text conversation. Before
each session the user must review the signed business summary and explicitly
agree to send it and live microphone audio to the selected voice provider.
During the session, the assistant can fetch and send authorized summaries for
other requested periods without another review. The server verifies business
access on each summary request; unavailable or oversized reports return an
error instead of figures. Audio is not reviewed
sentence by sentence. The assistant speaks in the selected app language unless
asked otherwise; Swahili recognition and voice quality must be tested on real
devices. The voice is AI-generated. Gemini voice can be paused and resumed
after switching to chat or leaving and reopening the assistant, while the app
process and provider connection remain available. Pausing stops recording and
keeps the Gemini connection open until its time limit; provider charges may
apply. The session is discarded on account or business access changes, and
access is checked again before resuming. Closing the app, changing the
reporting period, network interruptions, or provider disconnects can still
prevent resuming; the reservation can block a new session until it expires.
OpenAI voice ends when switching tabs or backgrounding the app. A business
context change closes the session.
Voice can collect information for an invoice, receipt, quotation, proforma or
advance invoice and open the existing editable form. This pauses Gemini voice
or ends an OpenAI call.
The user must confirm opening, review the form and save manually, subject to
the existing permissions. Voice-prefilled invoice, proforma and quotation forms support up to 30 named
items; receipt drafts support one item. Select stock products in the form if
stock needs to be deducted. A receipt draft does not issue or
verify a fiscal receipt. Requested invoice and receipt details can be sent to
the selected voice provider during the session, including customer names when
specifically requested, subject to owner access and the same coverage limits as
chat. Voice can collect an income or expense draft and show an animated review;
continuing places the command in chat for the user to review and send. The voice
dialog itself never saves, and spoken confirmation is not yet supported for
saving. The existing server validates owner access and the category when chat
sends the transaction. Say a customer name only when
necessary and authorized; do not speak credentials, contact details or private
payment details. Product and category names in summaries may also be sensitive.
Deploy `startGeminiVoice` for Gemini tool declarations and the voice Cloud Run
service for OpenAI tools, along with a compatible app. Voice tool calling and
recognition must be verified with the configured provider and on a real device.

For Swahili speech, the voice service instructs the model to say amounts
in words while preserving their values, and includes examples for Tanzanian
currency, decimals and identifiers. This is guidance, not a deterministic
number converter or a guarantee of correct pronunciation. English remains the
default for non-Swahili app locales, and the user may request another language.

Super admins can open **MJASI AI settings → Isher voice language examples** to
download an example CSV, edit it and upload a UTF-8 CSV (`number,spoken`, up to
16 KB and 50 examples). Use ungrouped
numbers such as `30000`, and only Swahili number words; the preview validates
format, not whether the words mathematically match the number. Review every row
before saving. Saved versions are inactive until explicitly activated; selecting
an older displayed version or built-in examples rolls back future sessions.
The screen lists the latest 50 versions. The preview lookup does not generate
audio: to test pronunciation, activate a version and start a new Swahili voice
session, then use the evaluation cases below. Existing sessions are unchanged.
Never upload real personal data or credentials. Examples are sent with the
voice prompt to OpenAI. They guide the model but do not fine-tune it or guarantee
correct pronunciation. The app uses server-only callable functions:
`previewIsherVoiceExamples`, `listIsherVoiceExamples`,
`saveIsherVoiceExamples`, and `activateIsherVoiceExamples`; the Cloud Run voice
service must also be updated before active examples can affect voice sessions.

To evaluate number pronunciation, compare the deployed baseline and the
candidate voice service on the same Android device, network and language.
Use a test business and synthetic prompts only; do not use customer information
or credentials. Ask Isher to repeat each value in Swahili without calculating
or rounding it. Listen to the audio, not just a transcript:

| Input | Expected value / words |
| --- | --- |
| TZS 0 | shilingi sifuri |
| TZS 15 | shilingi kumi na tano |
| TZS 99 | shilingi tisini na tisa |
| TZS 100 | shilingi mia moja |
| TZS 1,005 | shilingi elfu moja na tano |
| TZS 30,000 | shilingi elfu thelathini |
| TZS 30,500 | shilingi elfu thelathini na mia tano |
| TZS 99,999 | shilingi elfu tisini na tisa na mia tisa na tisini na tisa |
| TZS 100,000 | shilingi laki moja |
| TZS 125,000 | shilingi laki moja na elfu ishirini na tano |
| TZS 1,250,000 | shilingi milioni moja na laki mbili na elfu hamsini |
| TZS 10,000,000 | shilingi milioni kumi |
| 12.5% | asilimia kumi na mbili nukta tano |
| -30 | hasi thelathini |
| invoice number 0015 | preserve all digits, including leading zeroes |
| 15/01/2026 | the fifteenth of January 2026, without changing the date |

For each value, record whether the spoken value is exactly correct, whether the
pronunciation is understandable, and the time from the end of the question to
the start of the response. Repeat each case at least three times and record the
locale, device, model, voice and network; include a follow-up question and an
English-language session to check that conversation and language switching
still work. Report exact-value accuracy and median start latency separately for
baseline and candidate. Any changed value, wrong sign, omitted digit, invented
figure or altered identifier is a failure even if pronunciation sounds fluent.
Use the results to decide whether a deterministic number converter or a
different speech pipeline is needed. No recording is required; obtain consent
before recording anyone's voice.

The voice service authenticates Firebase users, rechecks business permissions,
verifies the existing signed snapshot, and applies the configured per-user
session quota. Attempts count even if the OpenAI connection fails.
It closes sessions at approximately the configured duration and uses a Cloud Tasks
hangup as a backup. Cloud Tasks may be delayed or fail; configure monitoring
and OpenAI project spending limits, since this is not a guaranteed billing
cap. A network or service failure can interrupt a session. OpenAI Realtime
audio and Google Cloud services incur additional charges.

Deploy `endBusinessAiVoice` as a Firebase task queue function and deploy the
`functions` directory as a separate Cloud Run service, whose `npm start` runs
`voice_server.js`. Configure Cloud Run with the same `OPENAI_API_KEY` secret
used by the Firebase functions, Firebase Admin application-default credentials,
and a request timeout above the configured maximum of 30 minutes. Its service identity needs permission
to read Firestore and Firebase Auth, access the secret, enqueue Cloud Tasks,
and invoke the task function as described in the Firebase task queue IAM
documentation. The WebSocket endpoint must be reachable over TLS; it verifies
Firebase ID tokens itself. Android builds targeting `tra-verify` use the
deployed MJASI voice service by default. Set `MJASI_VOICE_URL` via
`--dart-define` to override that endpoint, or to configure voice for another
Firebase project; it must point to a `wss://` URL for the same project.
Never put the OpenAI key in
the app. Deploying or enabling voice requires a separate operational review,
including task queue IAM, quotas, network behavior, permissions changes,
microphone privacy, real-device tests, and an OpenAI project with realtime
model access and billing. Without this configuration voice is unavailable.

The Isher AI voice interface shows the connection and microphone state from the
existing session. Voice transcripts and AI speaking/thinking indicators are
not currently available. Switching to text chat ends the voice session; text
history remains separate from voice conversations.
