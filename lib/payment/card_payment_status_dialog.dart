import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'card_payment_service.dart';

enum StatusDialogAction { paid, retry, mobileMoney, close }

enum _Phase { checking, success, failed, pending }

/// Checks a card payment with the server and shows each stage clearly.
/// Returns what the user chose to do next.
class CardPaymentStatusDialog extends StatefulWidget {
  const CardPaymentStatusDialog({
    super.key,
    required this.reference,
    required this.businessId,
    required this.amount,
    this.singleCheck = false,
  });

  final String reference;
  final String businessId;
  final num amount;
  final bool singleCheck;

  static Future<StatusDialogAction> show(
    BuildContext context, {
    required String reference,
    required String businessId,
    required num amount,
    bool singleCheck = false,
  }) async {
    final result = await showDialog<StatusDialogAction>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CardPaymentStatusDialog(
        reference: reference,
        businessId: businessId,
        amount: amount,
        singleCheck: singleCheck,
      ),
    );
    return result ?? StatusDialogAction.close;
  }

  @override
  State<CardPaymentStatusDialog> createState() =>
      _CardPaymentStatusDialogState();
}

class _CardPaymentStatusDialogState extends State<CardPaymentStatusDialog> {
  static const _teal = Color(0xFF12647C);

  _Phase _phase = _Phase.checking;
  CardPaymentState _state = CardPaymentState.pending;
  bool _activationFailed = false;
  bool _stopped = false;
  bool _single = false;
  int _elapsed = 0;
  Timer? _ticker;

  int get _total => CardPaymentService.pollTimeout.inSeconds;

  @override
  void initState() {
    super.initState();
    _single = widget.singleCheck;
    _run();
  }

  @override
  void dispose() {
    _stopped = true;
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _phase = _Phase.checking;
      _elapsed = 0;
      _activationFailed = false;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _phase == _Phase.checking) {
        setState(() => _elapsed = (_elapsed + 1).clamp(0, _total));
      }
    });

    CardPaymentState state;
    try {
      state = _single
          ? await CardPaymentService.checkStatus(widget.reference)
          : await CardPaymentService.pollStatus(
              widget.reference,
              isCancelled: () => _stopped,
            );
    } on CardPaymentException {
      state = CardPaymentState.pending;
    }
    _ticker?.cancel();
    if (!mounted) return;

    if (state == CardPaymentState.success) {
      var failed = false;
      try {
        await CardPaymentService.activateSubscription(widget.businessId);
      } catch (_) {
        failed = true;
      }
      if (!mounted) return;
      setState(() {
        _state = state;
        _activationFailed = failed;
        _phase = _Phase.success;
      });
      return;
    }
    if (state == CardPaymentState.pending) {
      setState(() {
        _state = state;
        _phase = _Phase.pending;
      });
      return;
    }
    await CardPaymentService.clearPending();
    if (!mounted) return;
    setState(() {
      _state = state;
      _phase = _Phase.failed;
    });
  }

  void _checkAgain() {
    _single = false;
    _run();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [_header(), _body(), _actions()],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color get _accent {
    switch (_phase) {
      case _Phase.checking:
        return _teal;
      case _Phase.success:
        return const Color(0xFF16A34A);
      case _Phase.failed:
        return const Color(0xFFDC2626);
      case _Phase.pending:
        return const Color(0xFFD97706);
    }
  }

  Widget _header() {
    final progress = _total == 0 ? 0.0 : _elapsed / _total;
    Widget icon;
    switch (_phase) {
      case _Phase.checking:
        icon = SizedBox(
          width: 84,
          height: 84,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 84,
                height: 84,
                child: CircularProgressIndicator(
                  value: _single ? null : progress.clamp(0.02, 1.0),
                  strokeWidth: 5,
                  color: Colors.white,
                  backgroundColor: Colors.white24,
                ),
              ),
              const Icon(
                Icons.credit_card_rounded,
                color: Colors.white,
                size: 34,
              ),
            ],
          ),
        );
      case _Phase.success:
        icon = const Icon(
          Icons.check_circle_rounded,
          color: Colors.white,
          size: 84,
        );
      case _Phase.failed:
        icon = const Icon(Icons.cancel_rounded, color: Colors.white, size: 84);
      case _Phase.pending:
        icon = const Icon(
          Icons.hourglass_top_rounded,
          color: Colors.white,
          size: 76,
        );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_accent, Color.lerp(_accent, Colors.black, 0.25)!],
        ),
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: KeyedSubtree(key: ValueKey(_phase), child: icon),
        ),
      ),
    );
  }

  String get _title {
    switch (_phase) {
      case _Phase.checking:
        return 'Tunakagua malipo yako...';
      case _Phase.success:
        return _activationFailed
            ? 'Malipo yamepokelewa'
            : 'Malipo yamefanikiwa!';
      case _Phase.failed:
        return _state == CardPaymentState.cancelled
            ? 'Umesitisha malipo'
            : _state == CardPaymentState.expired
            ? 'Muda wa malipo umeisha'
            : 'Malipo hayakufanikiwa';
      case _Phase.pending:
        return 'Bado tunasubiri uthibitisho';
    }
  }

  String get _message {
    switch (_phase) {
      case _Phase.checking:
        return 'Tafadhali subiri, usifunge ukurasa huu. Tunathibitisha malipo yako na benki.';
      case _Phase.success:
        return _activationFailed
            ? 'Malipo yako yamefanikiwa, lakini tumeshindwa kuwasha huduma sasa hivi. Fungua programu tena baada ya muda mfupi.'
            : 'Asante! Usajili wako umewashwa na unaweza kuendelea kutumia huduma zote.';
      case _Phase.failed:
        return _state == CardPaymentState.cancelled
            ? 'Hakuna pesa iliyokatwa. Unaweza kujaribu tena wakati wowote.'
            : _state == CardPaymentState.expired
            ? 'Tafadhali anza malipo upya.'
            : 'Hakuna pesa iliyokatwa kwenye kadi yako. Jaribu tena au tumia pesa ya simu.';
      case _Phase.pending:
        return 'Ukishalipa, bonyeza "Kagua tena". Kama pesa imekatwa, usilipe mara ya pili.';
    }
  }

  Widget _body() {
    final amount = NumberFormat.currency(
      symbol: 'Tsh ',
      decimalDigits: 0,
    ).format(widget.amount);
    final remaining = (_total - _elapsed).clamp(0, _total);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
      child: Column(
        children: [
          Text(
            _title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0E3A4C),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: Color(0xFF55717B),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F8F9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE3ECEE)),
            ),
            child: Column(
              children: [
                _row('Kiasi', amount, bold: true),
                const SizedBox(height: 8),
                _row('Namba ya malipo', widget.reference, small: true),
                if (_phase == _Phase.checking && !_single) ...[
                  const SizedBox(height: 8),
                  _row('Muda uliobaki', '${remaining}s'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    String label,
    String value, {
    bool bold = false,
    bool small = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF64808A)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: small ? 11 : (bold ? 16 : 13),
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: const Color(0xFF0E3A4C),
            ),
          ),
        ),
      ],
    );
  }

  Widget _actions() {
    Widget filled(String text, VoidCallback onTap) => SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onTap,
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
    Widget plain(String text, VoidCallback onTap) =>
        TextButton(onPressed: onTap, child: Text(text));

    final children = <Widget>[];
    switch (_phase) {
      case _Phase.checking:
        break;
      case _Phase.success:
        children.add(
          filled(
            _activationFailed ? 'Sawa' : 'Endelea',
            () => Navigator.pop(
              context,
              _activationFailed
                  ? StatusDialogAction.close
                  : StatusDialogAction.paid,
            ),
          ),
        );
      case _Phase.failed:
        children
          ..add(
            filled(
              'Jaribu tena',
              () => Navigator.pop(context, StatusDialogAction.retry),
            ),
          )
          ..add(
            plain(
              'Tumia pesa ya simu',
              () => Navigator.pop(context, StatusDialogAction.mobileMoney),
            ),
          )
          ..add(
            plain(
              'Funga',
              () => Navigator.pop(context, StatusDialogAction.close),
            ),
          );
      case _Phase.pending:
        children
          ..add(filled('Kagua tena', _checkAgain))
          ..add(
            plain(
              'Funga',
              () => Navigator.pop(context, StatusDialogAction.close),
            ),
          );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
      child: Column(children: children),
    );
  }
}
