import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tra_list/payment/payment_controller.dart'; // You must implement or adapt this controller for your payment logic
import 'business_access_service.dart';
import 'super_admin_subscription_service.dart';

class BusinessSubscriptionStatus {
  const BusinessSubscriptionStatus({
    required this.isSubscribed,
    required this.isTrial,
    this.validUntil,
  });

  final bool isSubscribed;
  final bool isTrial;
  final DateTime? validUntil;

  String get badge => isSubscribed
      ? 'SUBSCRIBED'
      : isTrial
      ? 'TRIAL'
      : '';
}

class SubscriptionController extends GetxController {
  static const offlineGracePeriod = Duration(hours: 24);

  DocumentReference<Map<String, dynamic>> get _businessSubscription =>
      FirebaseFirestore.instance
          .collection('subscriptions')
          .doc(BusinessAccessService.businessId);

  static bool isWithinOfflineGrace(DateTime verifiedAt, DateTime now) {
    final elapsed = now.toUtc().difference(verifiedAt.toUtc());
    return !elapsed.isNegative && elapsed < offlineGracePeriod;
  }

  static bool isCachedSubscriptionValid({
    required DateTime verifiedAt,
    required DateTime validUntil,
    required DateTime now,
  }) =>
      isWithinOfflineGrace(verifiedAt, now) &&
      now.toUtc().isBefore(validUntil.toUtc());

  Future<BusinessSubscriptionStatus> getBusinessSubscriptionStatus() async {
    if (FirebaseAuth.instance.currentUser == null ||
        !BusinessAccessService.isReady.value ||
        !BusinessAccessService.isActive.value) {
      return const BusinessSubscriptionStatus(
        isSubscribed: false,
        isTrial: false,
      );
    }

    try {
      final doc = await _businessSubscription.get(
        const GetOptions(source: Source.server),
      );
      final status = await _statusFromDocument(doc);
      await _cacheStatus(status);
      return status;
    } on FirebaseException catch (error) {
      if (!_isNetworkError(error)) rethrow;
      return _readCachedStatus();
    }
  }

  Future<BusinessSubscriptionStatus> _statusFromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (!doc.exists) {
      return const BusinessSubscriptionStatus(
        isSubscribed: false,
        isTrial: false,
      );
    }
    final data = doc.data();
    if (data == null) {
      return const BusinessSubscriptionStatus(
        isSubscribed: false,
        isTrial: false,
      );
    }

    final now = DateTime.now();
    // The payment flow writes `expiry`; older in-app flows wrote
    // `expiryDate`. Accept both so a valid business plan remains shared.
    final expiry = _asDate(data['expiry']) ?? _asDate(data['expiryDate']);
    final global = await SuperAdminSubscriptionService.loadTrialSettings();
    final trialEnd = TrialSettings.runningEnd(data, global, now);
    final subscribed = expiry != null && expiry.isAfter(now);
    final trial = trialEnd != null;
    final validUntilCandidates = <DateTime>[
      if (subscribed) expiry,
      if (trialEnd != null) trialEnd,
    ];
    final validUntil = validUntilCandidates.isEmpty
        ? null
        : validUntilCandidates.reduce(
            (latest, candidate) =>
                candidate.isAfter(latest) ? candidate : latest,
          );
    debugPrint(
      'Business subscription check: business=${BusinessAccessService.businessId}, '
      'owner=${BusinessAccessService.isOwner.value}, '
      'active=${BusinessAccessService.isActive.value}, '
      'expiry=${data['expiry'] ?? data['expiryDate']}, '
      'subscribed=$subscribed, trial=$trial',
    );
    return BusinessSubscriptionStatus(
      isSubscribed: subscribed,
      isTrial: trial,
      validUntil: validUntil,
    );
  }

  Future<void> _cacheStatus(BusinessSubscriptionStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey,
      jsonEncode({
        'verifiedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
        'isSubscribed': status.isSubscribed,
        'isTrial': status.isTrial,
        'validUntil': status.validUntil?.toUtc().millisecondsSinceEpoch,
      }),
    );
  }

  Future<BusinessSubscriptionStatus> _readCachedStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached == null) return _inactiveStatus;

    try {
      final data = jsonDecode(cached);
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid subscription cache.');
      }
      final verifiedAtMillis = data['verifiedAt'];
      final isSubscribed = data['isSubscribed'] == true;
      final isTrial = data['isTrial'] == true;
      final validUntilMillis = data['validUntil'];
      if (verifiedAtMillis is! int ||
          validUntilMillis is! int ||
          (!isSubscribed && !isTrial) ||
          !isCachedSubscriptionValid(
            verifiedAt: DateTime.fromMillisecondsSinceEpoch(
              verifiedAtMillis,
              isUtc: true,
            ),
            validUntil: DateTime.fromMillisecondsSinceEpoch(
              validUntilMillis,
              isUtc: true,
            ),
            now: DateTime.now().toUtc(),
          )) {
        return _inactiveStatus;
      }
      final status = BusinessSubscriptionStatus(
        isSubscribed: isSubscribed,
        isTrial: isTrial,
        validUntil: DateTime.fromMillisecondsSinceEpoch(
          validUntilMillis,
          isUtc: true,
        ),
      );
      debugPrint(
        'Using cached subscription status for '
        '${BusinessAccessService.businessId}; verifiedAt=$verifiedAtMillis',
      );
      return status;
    } on FormatException catch (error, stackTrace) {
      debugPrint('Could not read cached subscription status: $error');
      debugPrintStack(stackTrace: stackTrace);
      await prefs.remove(_cacheKey);
      return _inactiveStatus;
    }
  }

  String get _cacheKey =>
      'subscription_status.${BusinessAccessService.businessId}';

  static const _inactiveStatus = BusinessSubscriptionStatus(
    isSubscribed: false,
    isTrial: false,
  );

  bool _isNetworkError(FirebaseException error) => const {
    'unavailable',
    'deadline-exceeded',
    'network-request-failed',
  }.contains(error.code);

  Future<String> getUserSubscriptionBadge() async {
    return (await getBusinessSubscriptionStatus()).badge;
  }

  Future<bool> isUserInTrial() async =>
      (await getBusinessSubscriptionStatus()).isTrial;

  Future<bool> isSubscribed() async =>
      (await getBusinessSubscriptionStatus()).isSubscribed;

  final loading = false.obs;

  /// Call this to start a subscription payment
  Future<void> subscribeUser({required String phone}) async {
    loading.value = true;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not logged in');
      if (!BusinessAccessService.isOwner.value) {
        throw StateError(
          'Only the business owner can manage its subscription.',
        );
      }

      // Call payment and check result
      await PaymentController().payForSubscription(
        userId: BusinessAccessService.businessId,
        phone: phone,
      );

      final subscription = await _businessSubscription.get();
      final expiry =
          _asDate(subscription.data()?['expiry']) ??
          _asDate(subscription.data()?['expiryDate']);
      if (expiry == null) {
        throw StateError(
          'Payment succeeded but subscription expiry is missing.',
        );
      }
      Get.snackbar(
        'Success',
        'Subscription activated until ${DateFormat.yMMMd().format(expiry)}',
      );
    } catch (e) {
      rethrow;
    } finally {
      loading.value = false;
    }
  }

  DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
