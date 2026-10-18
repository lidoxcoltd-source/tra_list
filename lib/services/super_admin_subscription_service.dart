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

class SubscriptionPlanSettings {
  const SubscriptionPlanSettings({
    required this.amount,
    required this.durationDays,
    this.version = 1,
  });

  static const defaults = SubscriptionPlanSettings(
    amount: 20000,
    durationDays: 365,
  );

  final int amount;
  final int durationDays;
  final int version;

  factory SubscriptionPlanSettings.fromMap(Map<String, dynamic>? data) {
    if (data == null) return defaults;
    return SubscriptionPlanSettings(
      amount: (data['amount'] as num?)?.toInt() ?? defaults.amount,
      durationDays:
          (data['durationDays'] as num?)?.toInt() ?? defaults.durationDays,
      version: (data['version'] as num?)?.toInt() ?? defaults.version,
    );
  }
}

class SuperAdminSubscriptionService {
  static final _firestore = FirebaseFirestore.instance;
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
        final trialStart = _asDate(data['trialStart']);
        final trialEnabled = data.containsKey('trialActive')
            ? data['trialActive'] == true
            : data['trial'] == true;
        final isTrial =
            trialEnabled &&
            trialStart != null &&
            !trialStart.isAfter(now) &&
            now.difference(trialStart) < const Duration(days: 7);
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
      );
      transaction.set(_planRef, {
        'amount': amount,
        'durationDays': durationDays,
        'version': updated.version,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': adminUid,
      });
      return updated;
    });
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
