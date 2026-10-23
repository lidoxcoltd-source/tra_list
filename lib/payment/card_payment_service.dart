import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/super_admin_subscription_service.dart';

enum CardPaymentState { success, failed, cancelled, expired, pending }

class CardPaymentException implements Exception {
  CardPaymentException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CardPaymentSession {
  const CardPaymentSession({required this.reference, required this.gatewayUrl});
  final String reference;
  final String gatewayUrl;
}

class CardPaymentService {
  static const String _base =
      'https://us-central1-mbokashopping.cloudfunctions.net';
  static const String createEndpoint = '$_base/splashpayCardPayment';
  static const String statusEndpoint = '$_base/splashpayPaymentStatus';
  static const String returnPrefix = '$_base/cardPaymentReturn';

  static const String _pendingKey = 'pending_card_payment';
  static const Duration pollInterval = Duration(seconds: 3);
  static const Duration pollTimeout = Duration(minutes: 2);

  static const String _networkMsg =
      'Hakuna mtandao. Tafadhali angalia intaneti yako kisha ujaribu tena.';
  static const String _genericMsg =
      'Samahani, tatizo limetokea. Tafadhali jaribu tena.';

  static String newReference(String orderId) =>
      'CARD-$orderId-${DateTime.now().millisecondsSinceEpoch}';

  static bool isValidEmail(String value) => RegExp(
    r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$',
  ).hasMatch(value.trim());

  static String normalizePhone(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.startsWith('255')) return '0${cleaned.substring(3)}';
    if (cleaned.startsWith('0')) return cleaned;
    return '0$cleaned';
  }

  static Future<CardPaymentSession> createCardPayment({
    required String orderId,
    required num amount,
    required String buyerName,
    required String buyerEmail,
    required String buyerPhone,
    String currency = 'TZS',
  }) async {
    final reference = newReference(orderId);
    final parts = buyerName.trim().split(RegExp(r'\s+'));
    final phone = normalizePhone(buyerPhone);
    final body = <String, dynamic>{
      'reference': reference,
      'amount': amount,
      'currency': currency,
      'buyer_name': buyerName.trim(),
      'buyer_email': buyerEmail.trim(),
      'buyer_phone': phone,
      'billing_firstname': parts.first,
      if (parts.length > 1) 'billing_lastname': parts.sublist(1).join(' '),
      'billing_country': 'TZ',
      'billing_phone': phone,
    };

    final data = await _post(createEndpoint, body, const Duration(seconds: 45));
    final url = (data['payment_gateway_url'] ?? '').toString();
    final result = (data['result'] ?? '').toString().toUpperCase();
    if (result == 'FAILED' || url.isEmpty) {
      throw CardPaymentException(_messageOf(data));
    }
    final ref = (data['reference'] ?? reference).toString();
    await _savePending(ref, orderId);
    return CardPaymentSession(reference: ref, gatewayUrl: url);
  }

  static Future<CardPaymentState> checkStatus(String reference) async {
    final data = await _post(statusEndpoint, {
      'reference': reference,
    }, const Duration(seconds: 30));
    switch ((data['result'] ?? data['status'] ?? '').toString().toUpperCase()) {
      case 'SUCCESS':
        return CardPaymentState.success;
      case 'FAILED':
        return CardPaymentState.failed;
      case 'CANCELLED':
        return CardPaymentState.cancelled;
      case 'EXPIRED':
        return CardPaymentState.expired;
      default:
        return CardPaymentState.pending;
    }
  }

  /// Polls every 3 seconds for up to 2 minutes. Returns pending on timeout.
  static Future<CardPaymentState> pollStatus(
    String reference, {
    bool Function()? isCancelled,
  }) async {
    final deadline = DateTime.now().add(pollTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (isCancelled?.call() ?? false) return CardPaymentState.pending;
      try {
        final state = await checkStatus(reference);
        if (state != CardPaymentState.pending) return state;
      } on CardPaymentException {
        // Temporary network problem: keep trying until the timeout.
      }
      await Future<void>.delayed(pollInterval);
    }
    return CardPaymentState.pending;
  }

  static Future<Map<String, dynamic>> _post(
    String url,
    Map<String, dynamic> body,
    Duration timeout,
  ) async {
    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(url),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on SocketException {
      throw CardPaymentException(_networkMsg);
    } on http.ClientException {
      throw CardPaymentException(_networkMsg);
    } on TimeoutException {
      throw CardPaymentException(_networkMsg);
    } catch (_) {
      throw CardPaymentException(_genericMsg);
    }

    Map<String, dynamic> data = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}

    if (response.statusCode >= 400) {
      throw CardPaymentException(_messageOf(data));
    }
    return data;
  }

  static String _messageOf(Map<String, dynamic> data) {
    final message = (data['message'] ?? '').toString().trim();
    return message.isNotEmpty ? message : _genericMsg;
  }

  // Saved so a payment can be confirmed after the app was closed mid-payment.
  static Future<void> _savePending(String reference, String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pendingKey,
      jsonEncode({'reference': reference, 'orderId': orderId}),
    );
  }

  static Future<void> clearPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingKey);
  }

  static Future<Map<String, dynamic>?> pending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingKey);
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  /// Marks the subscription active. Only call after a confirmed SUCCESS status.
  static Future<void> activateSubscription(String businessId) async {
    final plan = await SuperAdminSubscriptionService.loadPlanSettings();
    final now = DateTime.now();
    final expiry = now.add(Duration(days: plan.durationDays));
    await FirebaseFirestore.instance
        .collection('subscriptions')
        .doc(businessId)
        .set({
          'subscribed': true,
          'subscribedAt': FieldValue.serverTimestamp(),
          'startDate': Timestamp.fromDate(now),
          'expiry': Timestamp.fromDate(expiry),
          'expiryDate': Timestamp.fromDate(expiry),
          'status': 'active',
          'trialActive': false,
          'trial': false,
          'paymentMethod': 'card',
          'planAmount': plan.amount,
          'planDurationDays': plan.durationDays,
          'planVersion': plan.version,
        }, SetOptions(merge: true));
    await clearPending();
  }
}
