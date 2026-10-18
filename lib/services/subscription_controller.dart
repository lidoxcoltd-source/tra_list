import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:tra_list/payment/payment_controller.dart'; // You must implement or adapt this controller for your payment logic
import 'business_access_service.dart';

class BusinessSubscriptionStatus {
  const BusinessSubscriptionStatus({
    required this.isSubscribed,
    required this.isTrial,
  });

  final bool isSubscribed;
  final bool isTrial;

  String get badge => isSubscribed
      ? 'SUBSCRIBED'
      : isTrial
      ? 'TRIAL'
      : '';
}

class SubscriptionController extends GetxController {
  DocumentReference<Map<String, dynamic>> get _businessSubscription =>
      FirebaseFirestore.instance
          .collection('subscriptions')
          .doc(BusinessAccessService.businessId);

  Future<BusinessSubscriptionStatus> getBusinessSubscriptionStatus() async {
    if (FirebaseAuth.instance.currentUser == null ||
        !BusinessAccessService.isReady.value ||
        !BusinessAccessService.isActive.value) {
      return const BusinessSubscriptionStatus(
        isSubscribed: false,
        isTrial: false,
      );
    }

    final doc = await _businessSubscription.get();
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
    final trialStart = _asDate(data['trialStart']);
    final subscribed = expiry != null && expiry.isAfter(now);
    final trialEnabled = data.containsKey('trialActive')
        ? data['trialActive'] == true
        : data['trial'] == true;
    final trial =
        trialEnabled &&
        trialStart != null &&
        !trialStart.isAfter(now) &&
        now.difference(trialStart) < const Duration(days: 7);
    debugPrint(
      'Business subscription check: business=${BusinessAccessService.businessId}, '
      'owner=${BusinessAccessService.isOwner.value}, '
      'active=${BusinessAccessService.isActive.value}, '
      'expiry=${data['expiry'] ?? data['expiryDate']}, '
      'subscribed=$subscribed, trial=$trial',
    );
    return BusinessSubscriptionStatus(isSubscribed: subscribed, isTrial: trial);
  }

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
