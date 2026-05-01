import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:tra_list/payment/payment_controller.dart'; // You must implement or adapt this controller for your payment logic

class SubscriptionController extends GetxController {
  /// Returns a badge string for the current user's subscription status
  Future<String> getUserSubscriptionBadge() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';
    final doc = await FirebaseFirestore.instance
        .collection('subscriptions')
        .doc(user.uid)
        .get();
    if (!doc.exists) return '';
    final data = doc.data();
    if (data == null) return '';
    final expiry = (data['expiryDate'] as Timestamp).toDate();
    if (expiry.isAfter(DateTime.now())) {
      return 'SUBSCRIBED';
    }
    if (data['trial'] == true) {
      final trialStart = (data['trialStart'] as Timestamp?)?.toDate();
      if (trialStart != null &&
          DateTime.now().difference(trialStart).inDays < 7) {
        return 'TRIAL';
      }
    }
    return '';
  }

  /// Returns true if the user is in a valid trial period
  Future<bool> isUserInTrial() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final doc = await FirebaseFirestore.instance
        .collection('subscriptions')
        .doc(user.uid)
        .get();
    if (!doc.exists) return false;
    final data = doc.data();
    if (data == null) return false;
    if (data['trial'] == true) {
      final trialStart = (data['trialStart'] as Timestamp?)?.toDate();
      if (trialStart != null &&
          DateTime.now().difference(trialStart).inDays < 7) {
        return true;
      }
    }
    return false;
  }

  /// Starts a trial for the user if not already started
  Future<void> startTrialIfNeeded(String userId) async {
    final doc = await FirebaseFirestore.instance
        .collection('subscriptions')
        .doc(userId)
        .get();
    final now = DateTime.now();
    if (!doc.exists || doc.data()?['trial'] != true) {
      await FirebaseFirestore.instance
          .collection('subscriptions')
          .doc(userId)
          .set({'trial': true, 'trialStart': now}, SetOptions(merge: true));
    }
  }

  final loading = false.obs;

  /// Call this to start a subscription payment
  Future<void> subscribeUser({required String phone}) async {
    loading.value = true;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not logged in');

      // Call payment and check result
      await PaymentController().payForSubscription(
        userId: user.uid,
        phone: phone,
      );

      // On success, record subscription
      final now = DateTime.now();
      final expiry = DateTime(now.year + 1, now.month, now.day);
      await FirebaseFirestore.instance
          .collection('subscriptions')
          .doc(user.uid)
          .set({
            'userId': user.uid,
            'startDate': now,
            'expiryDate': expiry,
            'status': 'active',
            'phone': phone,
          }, SetOptions(merge: true));
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

  /// Check if current user is subscribed
  Future<bool> isSubscribed() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final doc = await FirebaseFirestore.instance
        .collection('subscriptions')
        .doc(user.uid)
        .get();
    if (!doc.exists) return false;
    final data = doc.data();
    if (data == null) return false;
    final expiry = (data['expiryDate'] as Timestamp).toDate();
    return expiry.isAfter(DateTime.now());
  }
}
