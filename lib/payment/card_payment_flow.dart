import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
    @visibleForTesting Future<CardPaymentSession> Function()? createSession,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final loadingRoute = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text('sub_processing'.tr)),
            ],
          ),
        ),
      ),
    );
    navigator.push(loadingRoute);
    CardPaymentSession? session;
    try {
      session =
          await (createSession?.call() ??
              CardPaymentService.createCardPayment(
                orderId: businessId,
                amount: amount,
                buyerName: buyerName,
                buyerEmail: buyerEmail,
                buyerPhone: buyerPhone,
              ));
    } catch (_) {
      session = null;
    } finally {
      if (navigator.mounted && loadingRoute.isActive) {
        navigator.removeRoute(loadingRoute);
      }
    }
    if (!context.mounted) return CardFlowOutcome.dismissed;
    final confirmedSession = session;
    if (confirmedSession == null) return _failureDialog(context);

    var singleCheck = false;
    if (_hasWebView) {
      final result = await Navigator.of(context).push<CardWebViewResult>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) =>
              CardPaymentWebViewPage(url: confirmedSession.gatewayUrl),
        ),
      );
      singleCheck = result != CardWebViewResult.success;
    } else {
      final opened = await launchUrl(
        Uri.parse(confirmedSession.gatewayUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        if (!context.mounted) return CardFlowOutcome.dismissed;
        return _failureDialog(context);
      }
    }
    if (!context.mounted) return CardFlowOutcome.dismissed;

    // The redirect alone is never trusted: the status endpoint decides.
    final action = await CardPaymentStatusDialog.show(
      context,
      reference: confirmedSession.reference,
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

  static Future<CardFlowOutcome> _failureDialog(BuildContext context) async {
    final choice = await showDialog<CardFlowOutcome>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        icon: const Icon(
          Icons.error_outline_rounded,
          color: Color(0xFFDC2626),
          size: 44,
        ),
        title: Text('sub_payment_unconfirmed_title'.tr),
        content: Text(
          'sub_payment_unconfirmed'.tr,
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, CardFlowOutcome.dismissed),
            child: Text('close'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, CardFlowOutcome.mobileMoney),
            child: Text('subx_mobile'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, CardFlowOutcome.retry),
            child: Text('subx_retry'.tr),
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
