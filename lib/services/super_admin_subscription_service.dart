import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ManagedBusinessSubscription {
  const ManagedBusinessSubscription({
    required this.businessId,
    required this.name,
    required this.ownerName,
    required this.email,
    required this.phone,
    required this.address,
    required this.website,
    required this.taxId,
    required this.handle,
    required this.isSubscribed,
    required this.isTrial,
    required this.expiry,
    required this.isDisabled,
    required this.amount,
    required this.durationDays,
  });

  final String businessId;
  final String name;
  final String ownerName;
  final String email;
  final String phone;
  final String address;
  final String website;
  final String taxId;
  final String handle;
  final bool isSubscribed;
  final bool isTrial;
  final DateTime? expiry;
  final bool isDisabled;
  final double? amount;
  final int? durationDays;
}

class PaymentLogo {
  const PaymentLogo({required this.name, required this.url});
  final String name;
  final String url;

  static List<PaymentLogo> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (m) => PaymentLogo(
            name: (m['name'] ?? '').toString(),
            url: (m['url'] ?? '').toString(),
          ),
        )
        .where((l) => l.url.startsWith('http'))
        .toList();
  }

  // One logo per line: "Name | https://image-url".
  static String toText(List<PaymentLogo> logos) =>
      logos.map((l) => '${l.name} | ${l.url}').join('\n');

  static List<PaymentLogo> fromText(String text) {
    final result = <PaymentLogo>[];
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final sep = trimmed.lastIndexOf('|');
      final name = sep > 0 ? trimmed.substring(0, sep).trim() : '';
      final url = (sep >= 0 ? trimmed.substring(sep + 1) : trimmed).trim();
      if (Uri.tryParse(url)?.hasAuthority == true && url.startsWith('http')) {
        result.add(PaymentLogo(name: name, url: url));
      }
    }
    return result;
  }
}

class SubscriptionPlanSettings {
  const SubscriptionPlanSettings({
    required this.amount,
    required this.durationDays,
    this.version = 1,
    this.mobileLogos = const [],
    this.cardLogos = const [],
  });

  static const defaults = SubscriptionPlanSettings(
    amount: 20000,
    durationDays: 365,
  );

  final int amount;
  final int durationDays;
  final int version;
  final List<PaymentLogo> mobileLogos;
  final List<PaymentLogo> cardLogos;

  factory SubscriptionPlanSettings.fromMap(Map<String, dynamic>? data) {
    if (data == null) return defaults;
    return SubscriptionPlanSettings(
      amount: (data['amount'] as num?)?.toInt() ?? defaults.amount,
      durationDays:
          (data['durationDays'] as num?)?.toInt() ?? defaults.durationDays,
      version: (data['version'] as num?)?.toInt() ?? defaults.version,
      mobileLogos: PaymentLogo.listFrom(data['mobileLogos']),
      cardLogos: PaymentLogo.listFrom(data['cardLogos']),
    );
  }
}

class TrialSettings {
  const TrialSettings({
    required this.enabled,
    required this.durationDays,
    this.version = 1,
  });

  static const defaults = TrialSettings(enabled: true, durationDays: 7);

  final bool enabled;
  final int durationDays;
  final int version;

  factory TrialSettings.fromMap(Map<String, dynamic>? data) {
    if (data == null) return defaults;
    return TrialSettings(
      enabled: data['enabled'] != false,
      durationDays:
          (data['durationDays'] as num?)?.toInt() ?? defaults.durationDays,
      version: (data['version'] as num?)?.toInt() ?? 1,
    );
  }

  // End of the trial for a subscription doc, or null when it is not running.
  // Global "off" stops every trial, running ones included.
  static DateTime? runningEnd(
    Map<String, dynamic> subscription,
    TrialSettings global,
    DateTime now,
  ) {
    if (!global.enabled) return null;
    final on = subscription.containsKey('trialActive')
        ? subscription['trialActive'] == true
        : subscription['trial'] == true;
    final raw = subscription['trialStart'];
    final start = raw is Timestamp ? raw.toDate() : null;
    if (!on || start == null || start.isAfter(now)) return null;
    final end = start.add(Duration(days: daysFor(subscription, global)));
    return end.isAfter(now) ? end : null;
  }

  // Admin-granted per-business override wins; otherwise the global setting
  // applies, so admin changes affect every running trial.
  static int daysFor(Map<String, dynamic> subscription, TrialSettings global) =>
      (subscription['trialOverrideDays'] as num?)?.toInt() ??
      global.durationDays;
}

class SuperAdminSubscriptionService {
  static final _firestore = FirebaseFirestore.instance;
  static DocumentReference<Map<String, dynamic>> get _trialRef =>
      _firestore.collection('app_config').doc('trial_settings');

  static Future<TrialSettings> loadTrialSettings() async {
    try {
      return TrialSettings.fromMap((await _trialRef.get()).data());
    } on FirebaseException {
      return TrialSettings.defaults;
    }
  }

  static Future<void> saveTrialSettings({
    required bool enabled,
    required int durationDays,
  }) async {
    await _requireSuperAdmin();
    if (durationDays < 1 || durationDays > 365) {
      throw ArgumentError.value(
        durationDays,
        'durationDays',
        'Must be between 1 and 365 days.',
      );
    }
    await _trialRef.set({
      'enabled': enabled,
      'durationDays': durationDays,
      'version': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': FirebaseAuth.instance.currentUser!.uid,
    }, SetOptions(merge: true));
  }

  // Owner-initiated: allowed once per business while trials are enabled.
  static Future<void> startOwnTrial(String businessId) async {
    final settings = await loadTrialSettings();
    if (!settings.enabled) throw StateError('trial_disabled');
    final reference = _firestore.collection('subscriptions').doc(businessId);
    await _firestore.runTransaction((transaction) async {
      final data = (await transaction.get(reference)).data() ?? {};
      if (data['trialUsed'] == true || data['trialStart'] != null) {
        throw StateError('trial_used');
      }
      transaction.set(reference, {
        'userId': businessId,
        'trial': true,
        'trialActive': true,
        'trialUsed': true,
        'trialStart': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  static Future<void> grantTrial(String businessId, {required int days}) async {
    await _requireSuperAdmin();
    if (days < 1 || days > 365) {
      throw ArgumentError.value(days, 'days', 'Must be between 1 and 365.');
    }
    await _firestore.collection('subscriptions').doc(businessId).set({
      'userId': businessId,
      'trial': true,
      'trialActive': true,
      'trialUsed': true,
      'trialStart': Timestamp.fromDate(DateTime.now()),
      'trialOverrideDays': days,
      'managedBy': FirebaseAuth.instance.currentUser!.uid,
      'managedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> endTrial(String businessId) async {
    await _requireSuperAdmin();
    await _firestore.collection('subscriptions').doc(businessId).set({
      'trial': false,
      'trialActive': false,
      'managedBy': FirebaseAuth.instance.currentUser!.uid,
      'managedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static DocumentReference<Map<String, dynamic>> get _planRef =>
      _firestore.collection('app_config').doc('subscription_plan');

  static String _normalizeRole(String? role) =>
      (role ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static Future<void> _requireSuperAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to manage subscriptions.');

    final profile = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('profile')
        .doc('company')
        .get();
    if (_normalizeRole(profile.data()?['role']?.toString()) != 'superadmin') {
      throw StateError('Only a super admin can manage user subscriptions.');
    }
  }

  static Future<List<ManagedBusinessSubscription>> loadBusinesses() async {
    await _requireSuperAdmin();
    final profiles = await _firestore.collectionGroup('profile').get();
    final companyProfiles = profiles.docs.where(
      (profile) =>
          profile.id == 'company' &&
          profile.reference.path.split('/').length == 4 &&
          profile.reference.path.startsWith('users/') &&
          _normalizeRole(profile.data()['role']?.toString()) != 'superadmin',
    );

    final trialGlobal = await loadTrialSettings();
    final businesses = await Future.wait(
      companyProfiles.map((profile) async {
        final businessId = profile.reference.parent.parent!.id;
        final subscription = await _firestore
            .collection('subscriptions')
            .doc(businessId)
            .get();
        final data = subscription.data() ?? const <String, dynamic>{};
        final expiry = _asDate(data['expiry']) ?? _asDate(data['expiryDate']);
        final now = DateTime.now();
        final isSubscribed = expiry != null && expiry.isAfter(now);
        final isTrial =
            TrialSettings.runningEnd(data, trialGlobal, now) != null;
        final profileData = profile.data();
        final accountAccess = await _firestore
            .collection('accountAccess')
            .doc(businessId)
            .get();

        return ManagedBusinessSubscription(
          businessId: businessId,
          name: profileData['name']?.toString().trim() ?? '',
          ownerName: profileData['ownerName']?.toString().trim() ?? '',
          email: profileData['email']?.toString().trim() ?? '',
          phone: profileData['phone']?.toString().trim() ?? '',
          address: profileData['address']?.toString().trim() ?? '',
          website: profileData['website']?.toString().trim() ?? '',
          taxId: profileData['taxId']?.toString().trim() ?? '',
          handle: profileData['handle']?.toString().trim() ?? '',
          isSubscribed: isSubscribed,
          isTrial: isTrial,
          expiry: expiry,
          isDisabled: accountAccess.data()?['disabled'] == true,
          amount: (data['planAmount'] as num?)?.toDouble(),
          durationDays: (data['planDurationDays'] as num?)?.toInt(),
        );
      }),
    );

    businesses.sort((a, b) {
      final nameOrder = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return nameOrder == 0 ? a.businessId.compareTo(b.businessId) : nameOrder;
    });
    return businesses;
  }

  static Future<SubscriptionPlanSettings> loadPlanSettings() async {
    final snapshot = await _planRef.get();
    return SubscriptionPlanSettings.fromMap(snapshot.data());
  }

  static Future<SubscriptionPlanSettings> savePlanSettings({
    required int amount,
    required int durationDays,
  }) async {
    await _requireSuperAdmin();
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be greater than zero.');
    }
    if (durationDays <= 0 || durationDays > 3650) {
      throw ArgumentError.value(
        durationDays,
        'durationDays',
        'Must be between 1 and 3650 days.',
      );
    }

    final adminUid = FirebaseAuth.instance.currentUser!.uid;
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(_planRef);
      final current = SubscriptionPlanSettings.fromMap(snapshot.data());
      final updated = SubscriptionPlanSettings(
        amount: amount,
        durationDays: durationDays,
        version: current.version + 1,
        mobileLogos: current.mobileLogos,
        cardLogos: current.cardLogos,
      );
      transaction.set(_planRef, {
        'amount': amount,
        'durationDays': durationDays,
        'version': updated.version,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': adminUid,
      }, SetOptions(merge: true));
      return updated;
    });
  }

  static Future<void> savePaymentLogos({
    required List<PaymentLogo> mobile,
    required List<PaymentLogo> card,
  }) async {
    await _requireSuperAdmin();
    if (!(await _planRef.get()).exists) {
      await savePlanSettings(
        amount: SubscriptionPlanSettings.defaults.amount,
        durationDays: SubscriptionPlanSettings.defaults.durationDays,
      );
    }
    Map<String, String> map(PaymentLogo l) => {'name': l.name, 'url': l.url};
    await _planRef.set({
      'mobileLogos': mobile.map(map).toList(),
      'cardLogos': card.map(map).toList(),
    }, SetOptions(merge: true));
  }

  static Future<DateTime> setSubscribed(
    String businessId, {
    required bool subscribed,
  }) async {
    await _requireSuperAdmin();
    if (businessId.trim().isEmpty) {
      throw ArgumentError.value(businessId, 'businessId', 'Cannot be empty.');
    }

    final now = DateTime.now();
    final plan = subscribed ? await loadPlanSettings() : null;
    final expiry = subscribed
        ? now.add(Duration(days: plan!.durationDays))
        : now;
    await _firestore.collection('subscriptions').doc(businessId).set({
      'userId': businessId,
      'startDate': subscribed ? Timestamp.fromDate(now) : FieldValue.delete(),
      'expiry': Timestamp.fromDate(expiry),
      'expiryDate': Timestamp.fromDate(expiry),
      'status': subscribed ? 'active' : 'cancelled',
      'subscribed': subscribed,
      'trial': false,
      'trialActive': false,
      if (plan != null) ...{
        'planAmount': plan.amount,
        'planDurationDays': plan.durationDays,
        'planVersion': plan.version,
      },
      'managedBy': FirebaseAuth.instance.currentUser!.uid,
      'managedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return expiry;
  }

  static Future<DateTime> extendSubscription(
    String businessId, {
    required int additionalDays,
  }) async {
    await _requireSuperAdmin();
    if (businessId.trim().isEmpty) {
      throw ArgumentError.value(businessId, 'businessId', 'Cannot be empty.');
    }
    if (additionalDays <= 0 || additionalDays > 3650) {
      throw ArgumentError.value(
        additionalDays,
        'additionalDays',
        'Must be between 1 and 3650 days.',
      );
    }
    final adminUid = FirebaseAuth.instance.currentUser!.uid;
    final reference = _firestore.collection('subscriptions').doc(businessId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final data = snapshot.data() ?? const <String, dynamic>{};
      final currentExpiry =
          _asDate(data['expiry']) ?? _asDate(data['expiryDate']);
      final now = DateTime.now();
      final base = currentExpiry != null && currentExpiry.isAfter(now)
          ? currentExpiry
          : now;
      final expiry = base.add(Duration(days: additionalDays));
      transaction.set(reference, {
        'userId': businessId,
        'startDate': data['startDate'] ?? Timestamp.fromDate(now),
        'expiry': Timestamp.fromDate(expiry),
        'expiryDate': Timestamp.fromDate(expiry),
        'status': 'active',
        'subscribed': true,
        'trial': false,
        'trialActive': false,
        'adminExtensionDays': additionalDays,
        'managedBy': adminUid,
        'managedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return expiry;
    });
  }

  static DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static Future<void> setAccountEnabled(
    String businessId, {
    required bool enabled,
  }) async {
    await _requireSuperAdmin();
    final adminUid = FirebaseAuth.instance.currentUser!.uid;
    if (businessId.trim().isEmpty) {
      throw ArgumentError.value(businessId, 'businessId', 'Cannot be empty.');
    }
    if (businessId == adminUid) {
      throw StateError('You cannot disable your own super admin account.');
    }

    final accessRef = _firestore.collection('accountAccess').doc(businessId);
    if (enabled) {
      await accessRef.set({
        'disabled': false,
        'enabledAt': FieldValue.serverTimestamp(),
        'enabledBy': adminUid,
        'disabledAt': FieldValue.delete(),
        'disabledBy': FieldValue.delete(),
      }, SetOptions(merge: true));
    } else {
      await accessRef.set({
        'disabled': true,
        'disabledAt': FieldValue.serverTimestamp(),
        'disabledBy': adminUid,
      }, SetOptions(merge: true));
    }
  }
}
