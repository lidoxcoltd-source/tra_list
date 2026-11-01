import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum LegalKind {
  privacy('legal_privacy', '/privacy'),
  terms('legal_terms', '/terms');

  const LegalKind(this.docId, this.path);
  final String docId;
  final String path;
}

class LegalContent {
  const LegalContent({
    required this.titleEn,
    required this.titleSw,
    required this.bodyEn,
    required this.bodySw,
    this.updatedAt,
    this.isDefault = false,
  });

  final String titleEn;
  final String titleSw;
  final String bodyEn;
  final String bodySw;
  final DateTime? updatedAt;
  final bool isDefault;

  String title(bool sw) => sw ? titleSw : titleEn;
  String body(bool sw) => sw ? bodySw : bodyEn;

  factory LegalContent.fromMap(Map<String, dynamic> data, LegalKind kind) {
    final fallback = LegalDefaults.of(kind);
    String text(String key, String alt) {
      final value = data[key];
      return value is String && value.trim().isNotEmpty ? value : alt;
    }

    final updated = data['updatedAt'];
    return LegalContent(
      titleEn: text('titleEn', fallback.titleEn),
      titleSw: text('titleSw', fallback.titleSw),
      bodyEn: text('bodyEn', fallback.bodyEn),
      bodySw: text('bodySw', fallback.bodySw),
      updatedAt: updated is Timestamp ? updated.toDate() : null,
    );
  }
}

class LegalContact {
  const LegalContact({
    this.companyName = '',
    this.email = '',
    this.phone = '',
    this.address = '',
  });

  final String companyName;
  final String email;
  final String phone;
  final String address;

  bool get isEmpty =>
      companyName.isEmpty && email.isEmpty && phone.isEmpty && address.isEmpty;

  factory LegalContact.fromMap(Map<String, dynamic>? data) {
    String text(String key) => (data?[key] as String? ?? '').trim();
    return LegalContact(
      companyName: text('companyName'),
      email: text('email'),
      phone: text('phone'),
      address: text('address'),
    );
  }

  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static bool isValidEmail(String value) =>
      value.isEmpty || _emailPattern.hasMatch(value);
}

class LegalService {
  LegalService._();

  static const maxBodyLength = 40000;

  static DocumentReference<Map<String, dynamic>> get _contactRef =>
      FirebaseFirestore.instance.collection('app_config').doc('legal_contact');

  static Future<LegalContact> loadContact() async {
    try {
      final snapshot = await _contactRef.get().timeout(
        const Duration(seconds: 10),
      );
      return LegalContact.fromMap(snapshot.data());
    } catch (_) {
      return const LegalContact();
    }
  }

  static Future<void> saveContact(LegalContact contact) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to edit contact details.');
    if (!LegalContact.isValidEmail(contact.email.trim())) {
      throw ArgumentError('Enter a valid email address.');
    }
    await _contactRef.set({
      'companyName': contact.companyName.trim(),
      'email': contact.email.trim(),
      'phone': contact.phone.trim(),
      'address': contact.address.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
    });
  }

  static DocumentReference<Map<String, dynamic>> _ref(LegalKind kind) =>
      FirebaseFirestore.instance.collection('app_config').doc(kind.docId);

  // Falls back to the built-in text when nothing was published yet or the
  // network is unavailable, so the public page is never empty.
  static Future<LegalContent> load(LegalKind kind) async {
    try {
      final snapshot = await _ref(
        kind,
      ).get().timeout(const Duration(seconds: 10));
      final data = snapshot.data();
      if (data == null) return LegalDefaults.of(kind);
      return LegalContent.fromMap(data, kind);
    } catch (_) {
      return LegalDefaults.of(kind);
    }
  }

  static Future<void> save(LegalKind kind, LegalContent content) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to edit legal pages.');
    for (final body in [content.bodyEn, content.bodySw]) {
      if (body.length > maxBodyLength) {
        throw ArgumentError('Content is too long (max $maxBodyLength).');
      }
    }
    await _ref(kind).set({
      'titleEn': content.titleEn.trim(),
      'titleSw': content.titleSw.trim(),
      'bodyEn': content.bodyEn,
      'bodySw': content.bodySw,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
    });
  }
}

class LegalDefaults {
  LegalDefaults._();

  static LegalContent of(LegalKind kind) =>
      kind == LegalKind.privacy ? _privacy : _terms;

  static const _privacy = LegalContent(
    isDefault: true,
    titleEn: 'Privacy Policy',
    titleSw: 'Sera ya Faragha',
    bodyEn: '''
# Who we are
MJASI POS is a business management and social-commerce app for small businesses and individuals. This policy explains what information we handle and why.

# What we collect
- **Account details:** name, business name, phone number, email address and password.
- **Business records you enter:** income, expenses, categories, debts, jobs, invoices, quotations, receipts, document designs and terms.
- **Staff details you add:** name, contact details and permissions.
- **MJASI MARKET content:** posts, reels, statuses, comments, messages, images, videos and sounds you choose to publish.
- **Subscription status** and trial information.

# How we use it
- To sign you in and keep your account secure.
- To store and show your records, reports and documents.
- To let your staff access only what you allow.
- To run MJASI MARKET features such as feeds, reels and following.

We do not sell your data and the app shows no third-party ads.

# Where it is stored
Your data is stored on Google Firebase (Authentication, Firestore, Cloud Storage and Cloud Functions) and is encrypted in transit. Some preferences stay on your device.

# Sharing
We share data only with our service provider Google Firebase, and where the law requires it. Content you publish on MJASI MARKET is visible to other users. Documents you share as PDF or image go where you send them.

# Staff access
Business owners control what their staff can see. Staff can only access data allowed by their permissions.

# Retention and deletion
Data is kept while your account is active. You can delete your account inside the app. Deleting an owner account permanently removes business records, staff logins and uploaded files.

# Children
The app is not directed at children.

# Your rights
You can access, correct or delete your data inside the app, or contact us through the in-app Help & Support.

# Changes
We will update this page and its date when the policy changes.
''',
    bodySw: '''
# Sisi ni nani
MJASI POS ni app ya kusimamia biashara na kuuza mtandaoni kwa biashara ndogo na watu binafsi. Sera hii inaeleza taarifa tunazoshughulikia na kwa nini.

# Tunachokusanya
- **Taarifa za akaunti:** jina, jina la biashara, namba ya simu, barua pepe na nenosiri.
- **Kumbukumbu za biashara unazoweka:** mapato, matumizi, madeni, kazi, ankara, nukuu, risiti, miundo ya nyaraka na masharti.
- **Taarifa za wafanyakazi unaowaongeza:** jina, mawasiliano na ruhusa.
- **Maudhui ya MJASI MARKET:** machapisho, reels, status, maoni, ujumbe, picha, video na sauti unazochagua kuchapisha.
- **Hali ya usajili** na taarifa za trial.

# Tunavyotumia
- Kukuingiza na kulinda akaunti yako.
- Kuhifadhi na kuonyesha kumbukumbu, ripoti na nyaraka zako.
- Kuwaruhusu wafanyakazi wako kuona tu unachoruhusu.
- Kuendesha huduma za MJASI MARKET kama feed, reels na kufuata.

Hatuuzi data yako na app haionyeshi matangazo ya watu wengine.

# Mahali inapohifadhiwa
Data yako huhifadhiwa kwenye Google Firebase (Authentication, Firestore, Cloud Storage na Cloud Functions) na husimbwa inaposafirishwa. Baadhi ya mipangilio hubaki kwenye kifaa chako.

# Kushirikisha
Tunashirikisha data na mtoa huduma wetu Google Firebase tu, na pale sheria inapohitaji. Maudhui unayochapisha MJASI MARKET yanaonekana na watumiaji wengine. Nyaraka unazotuma kama PDF au picha huenda unakozituma.

# Ufikiaji wa wafanyakazi
Wamiliki wa biashara hudhibiti wanachoona wafanyakazi wao. Wafanyakazi hufikia data iliyoruhusiwa na ruhusa zao pekee.

# Kuhifadhi na kufuta
Data huhifadhiwa wakati akaunti yako inatumika. Unaweza kufuta akaunti ndani ya app. Kufuta akaunti ya mmiliki huondoa kabisa kumbukumbu za biashara, akaunti za wafanyakazi na mafaili yaliyopakiwa.

# Watoto
App hii haikulenga watoto.

# Haki zako
Unaweza kuona, kurekebisha au kufuta data yako ndani ya app, au kutuandikia kupitia Msaada ndani ya app.

# Mabadiliko
Tutasasisha ukurasa huu na tarehe yake sera inapobadilika.
''',
  );

  static const _terms = LegalContent(
    isDefault: true,
    titleEn: 'Terms & Conditions',
    titleSw: 'Masharti na Vigezo',
    bodyEn: '''
# Acceptance
By creating an account or using MJASI POS you agree to these terms. If you do not agree, please do not use the app.

# Your account
- You must give accurate information and keep your password safe.
- You are responsible for all activity on your account and for the staff you add.
- Business accounts are used by the owner and the staff the owner authorises.

# Subscriptions and free trial
- Some features need a paid subscription. Price and duration are shown in the app before you pay.
- A free trial may be offered once per business. Its length can change and it may be switched off at any time.
- When a trial or subscription ends, access to paid features may stop. Your data is kept.

# Your data
You own the records you enter. You give us permission to store and process them only to provide the service, as described in the Privacy Policy.

# MJASI MARKET content
- You are responsible for what you publish and must have the right to share it.
- Do not post illegal, misleading, abusive, hateful or infringing content, and do not impersonate others.
- We may remove content or suspend accounts that break these rules.

# Acceptable use
Do not misuse the service, attempt to break its security, scrape it, or use it for fraud.

# Documents you create
Invoices, quotations and receipts are generated from the details you provide. You are responsible for their accuracy and for meeting your own tax and legal duties.

# Availability
We work to keep the service running but cannot promise it will be uninterrupted or error-free.

# Limitation of liability
To the extent allowed by law, we are not liable for indirect losses, lost profits or data loss caused by events outside our reasonable control. Please keep your own backups of important records.

# Termination
You may stop using the app and delete your account at any time. We may suspend or end access for breach of these terms.

# Changes
We may update these terms. Continuing to use the app after changes means you accept them.

# Contact
Use Help & Support inside the app for questions about these terms.
''',
    bodySw: '''
# Kukubali
Kwa kufungua akaunti au kutumia MJASI POS unakubali masharti haya. Kama hukubali, tafadhali usitumie app.

# Akaunti yako
- Lazima utoe taarifa sahihi na uhifadhi nenosiri lako salama.
- Unawajibika kwa shughuli zote kwenye akaunti yako na wafanyakazi unaowaongeza.
- Akaunti ya biashara hutumiwa na mmiliki na wafanyakazi anaowaruhusu.

# Usajili na trial ya bure
- Baadhi ya huduma zinahitaji usajili wa kulipia. Bei na muda huonyeshwa ndani ya app kabla ya kulipa.
- Trial ya bure inaweza kutolewa mara moja kwa kila biashara. Muda wake unaweza kubadilika na inaweza kuzimwa wakati wowote.
- Trial au usajili ukiisha, huduma za kulipia zinaweza kusimama. Data yako inabaki.

# Data yako
Kumbukumbu unazoweka ni zako. Unatupa ruhusa ya kuzihifadhi na kuzishughulikia ili kutoa huduma tu, kama ilivyoelezwa kwenye Sera ya Faragha.

# Maudhui ya MJASI MARKET
- Unawajibika kwa unachochapisha na lazima uwe na haki ya kukishirikisha.
- Usichapishe maudhui haramu, ya kupotosha, ya matusi, ya chuki au yanayokiuka haki za wengine, wala usijifanye mtu mwingine.
- Tunaweza kuondoa maudhui au kusimamisha akaunti zinazovunja sheria hizi.

# Matumizi yanayokubalika
Usitumie huduma vibaya, usijaribu kuvunja usalama wake, kuikusanya kwa wingi, au kuitumia kwa ulaghai.

# Nyaraka unazotengeneza
Ankara, nukuu na risiti hutengenezwa kutokana na taarifa unazotoa. Unawajibika kwa usahihi wake na kwa wajibu wako wa kodi na kisheria.

# Upatikanaji
Tunajitahidi huduma ifanye kazi kila wakati lakini hatuwezi kuahidi haitakatika au haitakuwa na makosa.

# Ukomo wa dhima
Kwa kadri sheria inavyoruhusu, hatuhusiki na hasara zisizo za moja kwa moja, faida iliyopotea au upotevu wa data unaosababishwa na matukio nje ya uwezo wetu. Tafadhali weka nakala zako za kumbukumbu muhimu.

# Kusitisha
Unaweza kuacha kutumia app na kufuta akaunti wakati wowote. Tunaweza kusimamisha au kumaliza ufikiaji ukivunja masharti haya.

# Mabadiliko
Tunaweza kusasisha masharti haya. Kuendelea kutumia app baada ya mabadiliko kunamaanisha unayakubali.

# Mawasiliano
Tumia Msaada ndani ya app kwa maswali kuhusu masharti haya.
''',
  );
}
