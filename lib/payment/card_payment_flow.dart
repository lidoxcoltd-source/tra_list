import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'card_payment_service.dart';
import 'card_payment_status_dialog.dart';
import 'card_payment_webview_page.dart';

enum CardFlowOutcome { paid, retry, mobileMoney, dismissed }

class CardPaymentFlow {
  // webview_flutter only runs on Android and iOS; other platforms use the browser.
  static bool get _hasWebView =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<CardFlowOutcome> start(
    BuildContext context, {
    required String businessId,
    required num amount,
    required String buyerName,
    required String buyerEmail,
    required String buyerPhone,
  }) async {
    final CardPaymentSession session;
    try {
      session = await CardPaymentService.createCardPayment(
        orderId: businessId,
        amount: amount,
        buyerName: buyerName,
        buyerEmail: buyerEmail,
        buyerPhone: buyerPhone,
      );
    } on CardPaymentException catch (e) {
      if (!context.mounted) return CardFlowOutcome.dismissed;
      return _failureDialog(context, e.message);
    }
    if (!context.mounted) return CardFlowOutcome.dismissed;

    var singleCheck = false;
    if (_hasWebView) {
      final result = await Navigator.of(context).push<CardWebViewResult>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CardPaymentWebViewPage(url: session.gatewayUrl),
        ),
      );
      singleCheck = result != CardWebViewResult.success;
    } else {
      final opened = await launchUrl(
        Uri.parse(session.gatewayUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        if (!context.mounted) return CardFlowOutcome.dismissed;
        return _failureDialog(
          context,
          'Tumeshindwa kufungua ukurasa wa malipo. Tafadhali jaribu tena.',
        );
      }
    }
    if (!context.mounted) return CardFlowOutcome.dismissed;

    // The redirect alone is never trusted: the status endpoint decides.
    final action = await CardPaymentStatusDialog.show(
      context,
      reference: session.reference,
      businessId: businessId,
      amount: amount,
      singleCheck: singleCheck,
    );
    switch (action) {
      case StatusDialogAction.paid:
        return CardFlowOutcome.paid;
      case StatusDialogAction.retry:
        return CardFlowOutcome.retry;
      case StatusDialogAction.mobileMoney:
        return CardFlowOutcome.mobileMoney;
      case StatusDialogAction.close:
        return CardFlowOutcome.dismissed;
    }
  }

  static Future<CardFlowOutcome> _failureDialog(
    BuildContext context,
    String message,
  ) async {
    final choice = await showDialog<CardFlowOutcome>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        icon: const Icon(
          Icons.error_outline_rounded,
          color: Color(0xFFDC2626),
          size: 44,
        ),
        title: const Text('Malipo hayajakamilika'),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, CardFlowOutcome.dismissed),
            child: const Text('Funga'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, CardFlowOutcome.mobileMoney),
            child: const Text('Tumia pesa ya simu'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, CardFlowOutcome.retry),
            child: const Text('Jaribu tena'),
          ),
        ],
      ),
    );
    return choice ?? CardFlowOutcome.dismissed;
  }

  /// Confirms a card payment that was started before the app closed.
  /// Returns true if a subscription was activated.
  static Future<bool> resumePending(String businessId) async {
    if (FirebaseAuth.instance.currentUser == null) return false;
    final pending = await CardPaymentService.pending();
    final reference = pending?['reference']?.toString();
    if (reference == null || reference.isEmpty) return false;
    if (pending?['orderId']?.toString() != businessId) return false;
    try {
      final state = await CardPaymentService.checkStatus(reference);
      if (state == CardPaymentState.success) {
        await CardPaymentService.activateSubscription(businessId);
        return true;
      }
      if (state != CardPaymentState.pending) {
        await CardPaymentService.clearPending();
      }
    } catch (_) {}
    return false;
  }
}
