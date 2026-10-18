import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'services/subscription_controller.dart';
import 'services/super_admin_subscription_service.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({Key? key}) : super(key: key);

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  final SubscriptionController _controller = Get.put(SubscriptionController());
  final TextEditingController _phoneController = TextEditingController();
  SubscriptionPlanSettings _plan = SubscriptionPlanSettings.defaults;
  bool _planLoading = true;
  String? _planError;

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        title: Text('sub_title'.tr),
        centerTitle: false,
        elevation: 0,
        backgroundColor: const Color(0xFF0E3A4C),
        foregroundColor: Colors.white,
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildHero(context)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: _buildSubscriptionCard(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ClipRect(
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B3445), Color(0xFF12647C), Color(0xFF2E9C9B)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -86,
              right: -42,
              child: _buildGlowCircle(const Color(0x20FFFFFF), 220),
            ),
            Positioned(
              bottom: -120,
              left: -80,
              child: _buildGlowCircle(const Color(0x16FFFFFF), 250),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    children: [
                      Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.14),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.24),
                          ),
                        ),
                        child: const Icon(
                          Icons.workspace_premium_rounded,
                          color: Colors.white,
                          size: 31,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'sub_upgrade_heading'.tr,
                        textAlign: TextAlign.center,
                        style: textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'sub_upgrade_desc'.tr,
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withOpacity(0.82),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionCard(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE5EDF0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF173D4A).withOpacity(0.08),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPricePanel(context),
            const SizedBox(height: 20),
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                _FeatureTag(label: 'sub_feature_receipts'.tr),
                _FeatureTag(label: 'sub_feature_invoicing'.tr),
                _FeatureTag(label: 'sub_feature_analytics'.tr),
                _FeatureTag(label: 'sub_feature_backup'.tr),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'sub_phone_label'.tr,
                hintText: 'sub_phone_hint'.tr,
                prefixIcon: const Icon(Icons.phone_iphone_rounded),
                filled: true,
                fillColor: const Color(0xFFF5F8F9),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 17,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE1E9EC)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE1E9EC)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: Color(0xFF176B87),
                    width: 1.6,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Obx(
              () => Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          _controller.loading.value ||
                              _planLoading ||
                              _planError != null
                          ? null
                          : _subscribe,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF12647C),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFB8C9CE),
                        elevation: 2,
                        shadowColor: const Color(0xFF12647C).withOpacity(0.25),
                        padding: const EdgeInsets.symmetric(vertical: 17),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: _controller.loading.value
                          ? const SizedBox(
                              width: 19,
                              height: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.3,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.lock_open_rounded),
                      label: Text(
                        _controller.loading.value
                            ? 'sub_processing'.tr
                            : 'sub_subscribe_now'.tr,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  size: 17,
                  color: Color(0xFF64808A),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    'sub_secure_checkout'.tr,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64808A),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPricePanel(BuildContext context) {
    final theme = Theme.of(context);
    final price = _planLoading
        ? '...'
        : _planError != null
        ? '-'
        : NumberFormat.currency(
            locale: Get.locale?.toString() ?? 'en_TZ',
            symbol: 'Tsh ',
            decimalDigits: 0,
          ).format(_plan.amount);
    final priceDetails = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOut,
          child: Text(
            price,
            key: ValueKey(price),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0E3A4C),
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'sub_for_days'.trParams({
            'duration': 'duration_months_days'.trParams({
              'months': '${_plan.durationDays ~/ 30}',
              'days': '${_plan.durationDays % 30}',
            }),
          }),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: const Color(0xFF55717B),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _planError != null
              ? 'sub_plan_load_error'.tr
              : 'sub_plan_existing_unchanged'.tr,
          style: theme.textTheme.bodySmall?.copyWith(
            color: _planError != null
                ? const Color(0xFFB34343)
                : const Color(0xFF64808A),
            height: 1.4,
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF0FAFB), Color(0xFFF7FBFC)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD7ECEE)),
      ),
      child: priceDetails,
    );
  }

  Widget _buildGlowCircle(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _FeatureTag extends StatelessWidget {
  const _FeatureTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3ECEE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 16,
            color: Color(0xFF218A87),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF315A65),
            ),
          ),
        ],
      ),
    );
  }
}
