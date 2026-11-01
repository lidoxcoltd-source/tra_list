import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'invoice/language_controller.dart';
import 'payment/card_payment_flow.dart';
import 'payment/card_payment_service.dart';
import 'services/business_access_service.dart';
import 'services/subscription_controller.dart';
import 'services/super_admin_subscription_service.dart';

const _ink = Color(0xFF0E3A4C);
const _muted = Color(0xFF64808A);
const _line = Color(0xFFE3ECEE);
const _gold = Color(0xFFF5B83D);
const _cardIndigo = Color(0xFF4F46E5);
const _mobileGreen = Color(0xFF059669);
const _tealCard = Color(0xFF0E5E6D);

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key, this.checkoutOnly = false});

  final bool checkoutOnly;

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  final SubscriptionController _controller = Get.put(SubscriptionController());
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  SubscriptionPlanSettings _plan = SubscriptionPlanSettings.defaults;
  bool _planLoading = true;
  String? _planError;
  bool _payByCard = false;
  bool _cardBusy = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _nameController.text = user?.displayName ?? '';
    _emailController.text = user?.email ?? '';
    if ((user?.phoneNumber ?? '').isNotEmpty) {
      _phoneController.text = user!.phoneNumber!;
    }
    _loadPlan();
    _loadTrial();
    if (!widget.checkoutOnly) _resumePendingCard();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _resumePendingCard() async {
    final activated = await CardPaymentFlow.resumePending(
      BusinessAccessService.businessId,
    );
    if (activated && mounted) {
      Get.snackbar(
        'success'.tr,
        'subx_card_ok'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    }
  }

  void _warn(String message) {
    Get.snackbar(
      'subx_complete'.tr,
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.orange,
      colorText: Colors.white,
    );
  }

  Future<void> _subscribeWithCard() async {
    if (_cardBusy) return;
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    if (name.isEmpty) return _warn('subx_need_name'.tr);
    if (!CardPaymentService.isValidEmail(email)) {
      return _warn('subx_need_email'.tr);
    }
    if (phone.replaceAll(RegExp(r'\D'), '').length < 9) {
      return _warn('subx_need_phone'.tr);
    }
    if (!BusinessAccessService.isOwner.value) {
      return _warn('subx_owner_only'.tr);
    }

    setState(() => _cardBusy = true);
    try {
      var outcome = CardFlowOutcome.retry;
      while (outcome == CardFlowOutcome.retry && mounted) {
        outcome = await CardPaymentFlow.start(
          context,
          businessId: BusinessAccessService.businessId,
          amount: _plan.amount,
          buyerName: name,
          buyerEmail: email,
          buyerPhone: phone,
        );
      }
      if (outcome == CardFlowOutcome.mobileMoney && mounted) {
        setState(() => _payByCard = false);
      }
    } finally {
      if (mounted) setState(() => _cardBusy = false);
    }
  }

  Future<void> _loadPlan() async {
    try {
      final plan = await SuperAdminSubscriptionService.loadPlanSettings();
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _planLoading = false;
        _planError = null;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load subscription plan: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _planLoading = false;
        _planError = error.toString();
      });
    }
  }

  Future<void> _subscribe() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      Get.snackbar(
        'sub_missing_phone_title'.tr,
        'sub_missing_phone_msg'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    try {
      await _controller.subscribeUser(phone: phone);
      Get.snackbar(
        'success'.tr,
        'sub_activated_msg'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (error) {
      Get.snackbar(
        'sub_failed_title'.tr,
        error.toString(),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  String get _priceText => _planLoading
      ? '...'
      : _planError != null
      ? '-'
      : NumberFormat.currency(
          locale: Get.locale?.toString() ?? 'en_TZ',
          symbol: 'Tsh ',
          decimalDigits: 0,
        ).format(_plan.amount);

  String get _usdPriceText => _planLoading || _planError != null
      ? '-'
      : '\$${NumberFormat.decimalPattern().format((_plan.amount / _tzsPerUsd).round())}';

  String get _shownPrice => _usd ? _usdPriceText : _priceText;

  String get _durationText => 'duration_months_days'.trParams({
    'months': '${_plan.durationDays ~/ 30}',
    'days': '${_plan.durationDays % 30}',
  });

  void _openCheckout() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SubscriptionPage(checkoutOnly: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final checkout = widget.checkoutOnly;
    const dark = Color(0xFF0A333D);
    return Scaffold(
      backgroundColor: dark,
      appBar: checkout
          ? AppBar(
              title: Text(
                'subx_finish'.tr,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              centerTitle: false,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: dark,
              foregroundColor: Colors.white,
              toolbarHeight: 66,
              actions: [
                Center(child: _currencyToggle()),
                const SizedBox(width: 8),
                Center(child: _languageToggle()),
                const SizedBox(width: 12),
              ],
            )
          : null,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, checkout ? 20 : 12, 16, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: checkout ? 620 : 1100),
                  child: checkout
                      ? Column(children: [_trialCard(), _checkoutCard()])
                      : Column(
                          children: [
                            _heading(),
                            const SizedBox(height: 16),
                            _trialCard(),
                            _plansView(),
                          ],
                        ),
                ),
              ),
            ),
            if (!checkout && Navigator.of(context).canPop())
              Positioned(
                left: 8,
                top: 4,
                child: IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white70,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Live subscription state so the owner sees what they already have.
  TrialSettings _trialSettings = TrialSettings.defaults;
  Map<String, dynamic> _subData = const {};
  bool _trialBusy = false;

  Future<void> _loadTrial() async {
    try {
      final settings = await SuperAdminSubscriptionService.loadTrialSettings();
      final doc = await FirebaseFirestore.instance
          .collection('subscriptions')
          .doc(BusinessAccessService.businessId)
          .get();
      if (!mounted) return;
      setState(() {
        _trialSettings = settings;
        _subData = doc.data() ?? const {};
      });
    } catch (error) {
      debugPrint('Failed to load trial state: $error');
    }
  }

  Future<void> _startTrial() async {
    if (_trialBusy) return;
    setState(() => _trialBusy = true);
    try {
      await SuperAdminSubscriptionService.startOwnTrial(
        BusinessAccessService.businessId,
      );
      await _loadTrial();
      if (!mounted) return;
      Get.snackbar(
        'success'.tr,
        'subx_trial_started'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
      if (widget.checkoutOnly && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) return;
      _warn(
        error.toString().contains('trial_used')
            ? 'subx_trial_used'.tr
            : error.toString().contains('trial_disabled')
            ? 'subx_trial_off'.tr
            : error.toString(),
      );
    } finally {
      if (mounted) setState(() => _trialBusy = false);
    }
  }

  Widget _trialCard() {
    final now = DateTime.now();
    final start = _subData['trialStart'] is Timestamp
        ? (_subData['trialStart'] as Timestamp).toDate()
        : null;
    final end = TrialSettings.runningEnd(_subData, _trialSettings, now);
    final expiry = _subData['expiry'] is Timestamp
        ? (_subData['expiry'] as Timestamp).toDate()
        : null;
    if (expiry != null && expiry.isAfter(now)) return const SizedBox.shrink();

    final running = end != null;
    final used = _subData['trialUsed'] == true || start != null;
    final canStart =
        !used && _trialSettings.enabled && BusinessAccessService.isOwner.value;
    if (!running && !canStart) return const SizedBox.shrink();

    final daysLeft = end != null ? end.difference(now).inDays + 1 : 0;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.card_giftcard_rounded, color: _gold, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  running
                      ? 'subx_trial_running'.trParams({'days': '$daysLeft'})
                      : 'subx_trial_title'.trParams({
                          'days': '${_trialSettings.durationDays}',
                        }),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  running
                      ? (daysLeft <= 3
                            ? 'subx_trial_ending'.tr
                            : 'subx_trial_running_sub'.tr)
                      : 'subx_trial_sub'.tr,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          if (canStart) ...[
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _trialBusy ? null : _startTrial,
              style: FilledButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: _ink,
              ),
              child: _trialBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('subx_trial_start'.tr),
            ),
          ],
        ],
      ),
    );
  }

  bool _usd = false;
  static const double _tzsPerUsd = 2600;

  Widget _currencyToggle() {
    Widget item(String label, bool active, bool usd) {
      return GestureDetector(
        onTap: () => setState(() => _usd = usd),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: active ? const Color(0xFF0F3D3E) : Colors.white70,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [item('TZS', !_usd, false), item('USD', _usd, true)],
      ),
    );
  }

  Widget _languageToggle() {
    final lc = Get.isRegistered<LanguageController>()
        ? Get.find<LanguageController>()
        : Get.put(LanguageController());
    final isSw = (Get.locale?.languageCode ?? 'en') == 'sw';
    Widget item(String label, bool active, String code, String country) {
      return GestureDetector(
        onTap: () {
          lc.changeLanguage(code, country);
          setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: active ? const Color(0xFF0F3D3E) : Colors.white70,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [item('SW', isSw, 'sw', 'TZ'), item('EN', !isSw, 'en', 'US')],
      ),
    );
  }

  Widget _statusChip() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('subscriptions')
          .doc(BusinessAccessService.businessId)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        DateTime? date(dynamic v) => v is Timestamp ? v.toDate() : null;
        final expiry = date(data?['expiry']) ?? date(data?['expiryDate']);
        final now = DateTime.now();
        late final String text;
        late final IconData icon;
        late final Color color;
        if (expiry != null && expiry.isAfter(now)) {
          final days = expiry.difference(now).inDays;
          text = 'subx_active_until'.trParams({
            'date': DateFormat.yMMMd().format(expiry),
            'days': '$days',
          });
          icon = Icons.verified_rounded;
          color = const Color(0xFF34D399);
        } else if (expiry != null) {
          text = 'subx_expired_on'.trParams({
            'date': DateFormat.yMMMd().format(expiry),
          });
          icon = Icons.error_outline_rounded;
          color = const Color(0xFFFCA5A5);
        } else {
          text = 'subx_none'.tr;
          icon = Icons.workspace_premium_rounded;
          color = _gold;
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sideCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF123F4B),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF24616F)),
      ),
      child: child,
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 14),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white60,
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      ),
    ),
  );

  Widget _infoCard() {
    return _sideCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              'subx_info_title'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFC4B5FD),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'subx_info_body'.tr,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          _label('subx_toggle_status'.tr),
          _statusChip(),
          _label('subx_toggle_lang'.tr),
          _languageToggle(),
          _label('subx_toggle_cur'.tr),
          _currencyToggle(),
        ],
      ),
    );
  }

  Widget _payInfoCard() {
    Widget bullet(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF34D399),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );

    return _sideCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              'subx_pay_title'.tr,
              style: const TextStyle(
                color: Color(0xFF6EE7B7),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _label('subx_mobile'.tr),
          if (_plan.mobileLogos.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: _LogoStrip(logos: _plan.mobileLogos, height: 22),
            )
          else
            Text(
              'subx_mobile_sub'.tr,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          _label('subx_card'.tr),
          if (_plan.cardLogos.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: _LogoStrip(logos: _plan.cardLogos, height: 22),
            )
          else
            Text(
              'subx_card_sub'.tr,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          const SizedBox(height: 22),
          bullet('subx_secure_1'.tr),
          bullet('subx_secure_2'.tr),
          bullet('subx_secure_3'.tr),
        ],
      ),
    );
  }

  Widget _heading() {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Column(
      children: [
        Text.rich(
          TextSpan(
            style: TextStyle(
              color: Colors.white,
              fontSize: wide ? 34 : 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              height: 1.1,
            ),
            children: [
              TextSpan(text: '${'subx_head1'.tr} '),
              TextSpan(
                text: 'subx_head2'.tr,
                style: const TextStyle(color: Color(0xFFF9A8D4)),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'subx_head_sub'.tr,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: wide ? 15 : 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _plansView() {
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 4, child: _infoCard()),
              const SizedBox(width: 18),
              Expanded(flex: 5, child: _planCard()),
              const SizedBox(width: 18),
              Expanded(flex: 4, child: _payInfoCard()),
            ],
          );
        }
        return Column(
          children: [
            _planCard(),
            const SizedBox(height: 16),
            _infoCard(),
            const SizedBox(height: 16),
            _payInfoCard(),
          ],
        );
      },
    );
  }

  Widget _planCard() {
    final perDay =
        (!_planLoading && _planError == null && _plan.durationDays > 0)
        ? (_usd
              ? '\$${(_plan.amount / _plan.durationDays / _tzsPerUsd).toStringAsFixed(2)}'
              : 'Tsh ${NumberFormat.decimalPattern().format((_plan.amount / _plan.durationDays).round())}')
        : null;
    final features = <(IconData, String, Color)>[
      (
        Icons.receipt_long_rounded,
        'sub_feature_receipts'.tr,
        const Color(0xFF60A5FA),
      ),
      (
        Icons.description_rounded,
        'sub_feature_invoicing'.tr,
        const Color(0xFFFBBF24),
      ),
      (
        Icons.insights_rounded,
        'sub_feature_analytics'.tr,
        const Color(0xFF34D399),
      ),
      (
        Icons.cloud_done_rounded,
        'sub_feature_backup'.tr,
        const Color(0xFFC4B5FD),
      ),
      (Icons.group_add_rounded, 'subx_f_staff'.tr, const Color(0xFFF472B6)),
      (Icons.inventory_2_rounded, 'subx_f_manage'.tr, const Color(0xFF38BDF8)),
      (Icons.palette_rounded, 'subx_f_designs'.tr, const Color(0xFFFB923C)),
      (
        Icons.notifications_active_rounded,
        'subx_f_alerts'.tr,
        const Color(0xFFFACC15),
      ),
      (Icons.translate_rounded, 'subx_f_lang'.tr, const Color(0xFF2DD4BF)),
      (Icons.devices_rounded, 'subx_f_devices'.tr, const Color(0xFFA3E635)),
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B4A57),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _gold, width: 1.6),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _gold,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.workspace_premium_rounded,
                        size: 17,
                        color: _ink,
                      ),
                      SizedBox(width: 7),
                      Text(
                        'MJASI POS PRO',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: _ink,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: FittedBox(
                    key: ValueKey(_shownPrice),
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _shownPrice,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 43,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'sub_for_days'.trParams({'duration': _durationText}),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (perDay != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E5E6D),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _gold, width: 1.4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.trending_down_rounded,
                              color: _gold,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'subx_per_day_label'.tr,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                            _currencyToggle(),
                          ],
                        ),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            perDay,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 40,
                              height: 1.1,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1,
                            ),
                          ),
                        ),
                        if (_usd)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'subx_usd_note'.tr,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (_planError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'sub_plan_load_error'.tr,
                    style: const TextStyle(
                      color: Color(0xFFFCA5A5),
                      fontSize: 12,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _planLoading = true);
                      _loadPlan();
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text('subx_retry'.tr),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: ElevatedButton.icon(
                    onPressed: _planLoading || _planError != null
                        ? null
                        : _openCheckout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: const Color(0xFF3B2A00),
                      disabledBackgroundColor: Colors.white24,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    icon: const Icon(Icons.lock_rounded, size: 22),
                    label: Text(
                      'subx_pay_now'.tr,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'subx_includes'.tr,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF34D399).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'subx_included'.tr,
                        style: const TextStyle(
                          color: Color(0xFF6EE7B7),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, c) {
                    const gap = 8.0;
                    final w = (c.maxWidth - gap) / 2;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final f in features)
                          SizedBox(
                            width: w,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0E5E6D),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFF157384),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: f.$3.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Icon(f.$1, color: f.$3, size: 17),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      f.$2,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11.5,
                                        height: 1.25,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'sub_plan_existing_unchanged'.tr,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.58),
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon, {String? hint}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: Color(0xFF24616F)),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Colors.white70),
      hintStyle: const TextStyle(color: Colors.white38),
      prefixIcon: Icon(icon, size: 21, color: Colors.white70),
      filled: true,
      fillColor: const Color(0xFF0E5E6D),
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 17),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: _gold, width: 1.7),
      ),
    );
  }

  Widget _methodTile({
    required bool selected,
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<PaymentLogo> logos,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _cardBusy ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? Color.alphaBlend(color.withValues(alpha: 0.25), _tealCard)
                : _tealCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _gold : const Color(0xFF24616F),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, color: color, size: 21),
                  ),
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: selected ? _gold : Colors.white38,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                ),
              ),
              if (logos.isNotEmpty) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _LogoStrip(logos: logos, height: 18),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _checkoutCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0B4A57),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _gold, width: 1.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _gold,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: _ink,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'subx_finish'.tr,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'subx_finish_hint'.tr,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'subx_step1'.tr,
            style: const TextStyle(
              fontSize: 10.5,
              letterSpacing: 1,
              fontWeight: FontWeight.w900,
              color: Colors.white60,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _methodTile(
                selected: !_payByCard,
                color: _mobileGreen,
                icon: Icons.phone_android_rounded,
                title: 'subx_mobile'.tr,
                subtitle: 'subx_mobile_sub'.tr,
                logos: _plan.mobileLogos,
                onTap: () => setState(() => _payByCard = false),
              ),
              const SizedBox(width: 12),
              _methodTile(
                selected: _payByCard,
                color: _cardIndigo,
                icon: Icons.credit_card_rounded,
                title: 'subx_card'.tr,
                subtitle: 'subx_card_sub'.tr,
                logos: _plan.cardLogos,
                onTap: () => setState(() => _payByCard = true),
              ),
            ],
          ),
          const SizedBox(height: 23),
          Row(
            children: [
              Container(
                width: 27,
                height: 27,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _gold,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Text(
                  '2',
                  style: TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Text(
                'subx_step2'.tr,
                style: const TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w900,
                  color: Colors.white60,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_payByCard) ...[
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white),
                    textCapitalization: TextCapitalization.words,
                    decoration: _decoration(
                      'subx_full_name'.tr,
                      Icons.person_outline_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.emailAddress,
                    decoration: _decoration(
                      'subx_email'.tr,
                      Icons.alternate_email_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _phoneController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.phone,
                  decoration: _decoration(
                    'sub_phone_label'.tr,
                    Icons.phone_iphone_rounded,
                    hint: 'sub_phone_hint'.tr,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _tealCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF24616F)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.receipt_long_outlined,
                      color: Colors.white70,
                      size: 19,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'subx_plan_line'.tr,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      _priceText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: Color(0xFF24616F)),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'subx_total'.tr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _priceText,
                          style: const TextStyle(
                            color: _gold,
                            fontWeight: FontWeight.w900,
                            fontSize: 24,
                            letterSpacing: -0.4,
                          ),
                        ),
                        if (_usd)
                          Text(
                            '≈ $_usdPriceText',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Obx(() {
            final busy = _controller.loading.value || _cardBusy;
            return SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: busy || _planLoading || _planError != null
                    ? null
                    : (_payByCard ? _subscribeWithCard : _subscribe),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: const Color(0xFF3B2A00),
                  disabledBackgroundColor: Colors.white24,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: busy
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.3,
                          color: Color(0xFF3B2A00),
                        ),
                      )
                    : Icon(
                        _payByCard
                            ? Icons.lock_rounded
                            : Icons.arrow_forward_rounded,
                      ),
                label: Text(
                  busy
                      ? 'sub_processing'.tr
                      : _payByCard
                      ? 'subx_pay_card'.tr
                      : 'sub_subscribe_now'.tr,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.verified_user_rounded,
                size: 17,
                color: _mobileGreen,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  'sub_secure_checkout'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          if (_payByCard) ...[
            const SizedBox(height: 12),
            if (_plan.cardLogos.isNotEmpty) ...[
              Text(
                'subx_accepted'.tr,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const SizedBox(height: 6),
              _LogoStrip(logos: _plan.cardLogos, height: 26),
              const SizedBox(height: 8),
            ],
            const _Badge('3D Secure', Color(0xFF34D399)),
            const SizedBox(height: 10),
            Text(
              'subx_card_note'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Small logos set by the admin; falls back to the name if an image fails.
class _LogoStrip extends StatelessWidget {
  const _LogoStrip({required this.logos, this.height = 22});
  final List<PaymentLogo> logos;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final logo in logos)
          Container(
            height: height + 8,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _line),
            ),
            child: Image.network(
              logo.url,
              height: height,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Center(
                child: Text(
                  logo.name,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _muted,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
