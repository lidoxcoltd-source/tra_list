import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tra_list/business_intelligence/business_context.dart';
import 'package:tra_list/business_intelligence/business_context_service.dart';
import 'package:tra_list/business_intelligence/ai_assistant_page.dart';
import 'package:tra_list/business_intelligence/ai_history.dart';
import 'package:tra_list/business_intelligence/ai_quota_page.dart';
import 'package:tra_list/business_intelligence/isher_welcome_screen.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class BusinessIntelligenceController extends GetxController {
  final _service = BusinessContextService();
  final historyCache = AiHistoryCache();
  final context = Rxn<BusinessContext>();
  final loading = false.obs;
  final error = ''.obs;
  final periodKey = 'month'.obs;
  ReportingPeriod? _custom;
  int _request = 0;
  Worker? _accessWorker;
  StreamSubscription<User?>? _authSubscription;

  @override
  void onInit() {
    super.onInit();
    _accessWorker = everAll([
      BusinessAccessService.businessUid,
      BusinessAccessService.isActive,
      BusinessAccessService.isReady,
      BusinessAccessService.isOwner,
      BusinessAccessService.shopNickname,
      BusinessAccessService.permissions,
    ], (_) => refreshContext());
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      (_) => refreshContext(),
      onError: (Object e) {
        _request++;
        context.value = null;
        loading.value = false;
        error.value = e.toString();
      },
    );
    refreshContext();
  }

  Future<void> refreshContext() async {
    final request = ++_request;
    historyCache.clear();
    context.value = null;
    error.value = '';
    if (!BusinessAccessService.hasBusinessAccess ||
        !BusinessAccessService.can('analytics', 'view') ||
        FirebaseAuth.instance.currentUser == null) {
      loading.value = false;
      error.value = 'bi_access_error'.tr;
      return;
    }
    loading.value = true;
    try {
      final period = periodKey.value == 'custom'
          ? _custom!
          : ReportingPeriod.fromKey(periodKey.value, DateTime.now());
      final result = await _service.load(period);
      if (request == _request) context.value = result;
    } catch (e, stack) {
      debugPrint('Business intelligence load failed: $e');
      debugPrintStack(stackTrace: stack);
      if (request == _request) {
        error.value = 'bi_load_error'.trParams({'error': e.toString()});
      }
    } finally {
      if (request == _request) loading.value = false;
    }
  }

  void selectPeriod(String value, {ReportingPeriod? custom}) {
    if (value == 'custom' && custom == null) return;
    _custom = custom;
    periodKey.value = value;
    refreshContext();
  }

  @override
  void onClose() {
    _request++;
    historyCache.clear();
    _accessWorker?.dispose();
    _authSubscription?.cancel();
    super.onClose();
  }
}

class BusinessIntelligencePage extends StatefulWidget {
  const BusinessIntelligencePage({super.key, this.initialTab});

  final AiAssistantTab? initialTab;

  @override
  State<BusinessIntelligencePage> createState() =>
      _BusinessIntelligencePageState();
}

class _BusinessIntelligencePageState extends State<BusinessIntelligencePage> {
  late final BusinessIntelligenceController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(BusinessIntelligenceController());
  }

  @override
  void dispose() {
    Get.delete<BusinessIntelligenceController>();
    super.dispose();
  }

  Future<void> _selectPeriod(String? value) async {
    if (value == null) return;
    if (value != 'custom') {
      controller.selectPeriod(value);
      return;
    }
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (range == null) return;
    controller.selectPeriod(
      'custom',
      custom: ReportingPeriod(
        range.start,
        DateTime(range.end.year, range.end.month, range.end.day + 1),
      ),
    );
  }

  Future<void> _review(BusinessContext data) async {
    final report = data.report(language: Get.locale?.languageCode ?? 'en');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Obx(
        () => controller.context.value != data
            ? AlertDialog(
                content: Text('bi_access_error'.tr),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text('close'.tr),
                  ),
                ],
              )
            : AlertDialog(
                title: Text('bi_review'.tr),
                content: SizedBox(
                  width: 600,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('bi_privacy'.tr),
                        const SizedBox(height: 12),
                        SelectableText(report),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text('close'.tr),
                  ),
                  TextButton(
                    onPressed: () async {
                      try {
                        await Clipboard.setData(ClipboardData(text: report));
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text('bi_copied'.tr)),
                          );
                        }
                      } catch (e) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                'bi_action_error'.trParams({
                                  'error': e.toString(),
                                }),
                              ),
                            ),
                          );
                        }
                      }
                    },
                    child: Text('bi_copy'.tr),
                  ),
                  TextButton(
                    onPressed: () =>
                        _openProvider(dialogContext, Uri.https('chatgpt.com')),
                    child: const Text('ChatGPT'),
                  ),
                  TextButton(
                    onPressed: () => _openProvider(
                      dialogContext,
                      Uri.https('gemini.google.com'),
                    ),
                    child: const Text('Google Gemini'),
                  ),
                  TextButton(
                    onPressed: () async {
                      try {
                        await SharePlus.instance.share(
                          ShareParams(
                            text: report,
                            title: 'MJASI Business Intelligence',
                          ),
                        );
                      } catch (e) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                'bi_action_error'.trParams({
                                  'error': e.toString(),
                                }),
                              ),
                            ),
                          );
                        }
                      }
                    },
                    child: Text('bi_share_sheet'.tr),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _openProvider(BuildContext context, Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Could not open ${uri.host}');
      }
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('bi_paste'.tr)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('bi_action_error'.trParams({'error': e.toString()})),
          ),
        );
      }
    }
  }

  void _openAssistant(AiAssistantTab tab) {
    Get.to(
      () => AiAssistantPage(
        business: controller.context,
        loading: controller.loading,
        error: controller.error,
        historyCache: controller.historyCache,
        initialTab: tab,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.initialTab != null
      ? AiAssistantPage(
          business: controller.context,
          loading: controller.loading,
          error: controller.error,
          historyCache: controller.historyCache,
          initialTab: widget.initialTab!,
        )
      : Obx(
    () => IsherWelcomeScreen(
      loading: controller.loading.value,
      error: controller.error.value,
      ready: controller.context.value != null,
      businessName: BusinessAccessService.businessName.value,
      businessId:
          BusinessAccessService.hasBusinessAccess &&
              BusinessAccessService.can('analytics', 'view') &&
              FirebaseAuth.instance.currentUser != null
          ? BusinessAccessService.businessUid.value
          : null,
      greetingReady:
          BusinessAccessService.hasBusinessAccess &&
          BusinessAccessService.can('analytics', 'view') &&
          FirebaseAuth.instance.currentUser != null,
      onRetry: controller.refreshContext,
      onChat: () => _openAssistant(AiAssistantTab.chat),
      onVoice: () => _openAssistant(AiAssistantTab.voice),
      onUsage: () => Get.to(() => const AiQuotaPage()),
      onReport: () => Get.to(() => _businessOverview()),
    ),
  );

  Widget _businessOverview() => Scaffold(
    backgroundColor: const Color(0xFF080817),
    appBar: AppBar(
      backgroundColor: const Color(0xFF080817),
      foregroundColor: Colors.white,
      elevation: 0,
      title: const Text(
        'Isher AI',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      actions: [
        IconButton(
          tooltip: 'bi_quota_title'.tr,
          onPressed: () => Get.to(() => const AiQuotaPage()),
          icon: const Icon(Icons.data_usage_rounded),
        ),
      ],
    ),
    body: Obx(() {
      final data = controller.context.value;
      final loading = controller.loading.value;
      final error = controller.error.value;
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF080817), Color(0xFF101127), Color(0xFF17102D)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                children: [
                  const SizedBox(height: 20),
                  Center(
                    child: Container(
                      width: 164,
                      height: 164,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          center: Alignment(-0.45, -0.5),
                          radius: 0.9,
                          colors: [
                            Color(0xFFB9A4FF),
                            Color(0xFF6B3EC0),
                            Color(0xFF15122D),
                            Color(0xFF2878FF),
                            Color(0xFF080817),
                          ],
                          stops: [0, 0.24, 0.58, 0.85, 1],
                        ),
                        border: Border.all(
                          color: const Color(0xFFAB92FF).withValues(alpha: 0.4),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF7048ED,
                            ).withValues(alpha: 0.28),
                            blurRadius: 55,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 98,
                          height: 98,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(
                              center: Alignment(-0.3, -0.5),
                              colors: [Color(0xFF443B75), Color(0xFF090817)],
                            ),
                            border: Border.all(
                              color: const Color(
                                0xFFB9A4FF,
                              ).withValues(alpha: 0.35),
                            ),
                          ),
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 36,
                            color: Color(0xFFE6DEFF),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'bi_welcome_title'.tr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'bi_welcome_subtitle'.tr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFB3B2C7),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (loading)
                    const Center(child: CircularProgressIndicator())
                  else if (error.isNotEmpty || data == null)
                    Column(
                      children: [
                        Text(
                          error.isEmpty ? 'bi_access_error'.tr : error,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        TextButton.icon(
                          onPressed: controller.refreshContext,
                          icon: const Icon(Icons.refresh),
                          label: Text('refresh'.tr),
                        ),
                      ],
                    )
                  else ...[
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF26213E),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: const Color(0xFF40345D)),
                        ),
                        child: Text(
                          data.businessName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFD8CCFF),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final chat = _modeCard(
                          icon: Icons.chat_bubble_rounded,
                          title: 'bi_mode_chat'.tr,
                          subtitle: 'bi_mode_chat_desc'.tr,
                          accent: const Color(0xFFB9A4FF),
                          onTap: () => _openAssistant(AiAssistantTab.chat),
                        );
                        final voice = _modeCard(
                          icon: Icons.call_rounded,
                          title: 'bi_mode_voice'.tr,
                          subtitle: 'bi_mode_voice_desc'.tr,
                          accent: const Color(0xFF00D9FF),
                          onTap: () => _openAssistant(AiAssistantTab.voice),
                        );
                        if (constraints.maxWidth < 360 ||
                            MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [chat, const SizedBox(height: 12), voice],
                          );
                        }
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: chat),
                              const SizedBox(width: 12),
                              Expanded(child: voice),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    TextButton.icon(
                      onPressed: () => Get.to(() => _reportPage()),
                      icon: const Icon(Icons.bar_chart_rounded, size: 19),
                      label: Text('bi_view_report'.tr),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFC6BBE8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }),
  );

  Widget _modeCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accent,
    required VoidCallback onTap,
  }) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(24),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent.withValues(alpha: 0.16), const Color(0xFF17162C)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: accent.withValues(alpha: 0.28)),
                  ),
                  child: Icon(icon, color: accent, size: 27),
                ),
                const Spacer(),
                Icon(Icons.arrow_outward_rounded, color: accent, size: 20),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFFB3B2C7),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _reportPage() => Scaffold(
    appBar: AppBar(title: Text('bi_title'.tr)),
    body: Obx(() {
      final data = controller.context.value;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          InputDecorator(
            decoration: InputDecoration(labelText: 'bi_period'.tr),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: controller.periodKey.value,
                isExpanded: true,
                items: [
                  for (final key in [
                    'today',
                    'yesterday',
                    'seven',
                    'thirty',
                    'month',
                    'previous',
                    'custom',
                  ])
                    DropdownMenuItem(
                      value: key,
                      child: Text('bi_period_$key'.tr),
                    ),
                ],
                onChanged: _selectPeriod,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (controller.loading.value)
            const Center(child: CircularProgressIndicator())
          else if (controller.error.value.isNotEmpty) ...[
            Text(controller.error.value),
            TextButton(
              onPressed: controller.refreshContext,
              child: Text('refresh'.tr),
            ),
          ] else if (data != null) ...[
            Card(
              color: MjasiColors.primaryNavy,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.businessName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'bi_updated'.trParams({
                        'time': DateFormat.yMd().add_Hm().format(
                          data.updatedAt,
                        ),
                      }),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _metric('bi_income'.tr, data.income),
            _metric('bi_expenses'.tr, data.expenses),
            _metric('bi_cashflow'.tr, data.income! - data.expenses!),
            if (data.incomeByDayUtc.isNotEmpty)
              Card(
                child: ListTile(
                  title: Text('bi_income_trend'.tr),
                  subtitle: Text(
                    (data.incomeByDayUtc.entries.toList()
                          ..sort((a, b) => a.key.compareTo(b.key)))
                        .map(
                          (e) =>
                              '${e.key}: TZS ${NumberFormat('#,##0.##', 'en_US').format(e.value)}',
                        )
                        .join('\n'),
                  ),
                ),
              ),
            if (data.pos != null) ...[
              _metric('bi_pos_sales'.tr, data.pos!.total),
              if (data.pos!.products.isNotEmpty)
                Card(
                  child: ListTile(
                    title: Text('bi_top_products'.tr),
                    subtitle: Text(
                      (data.pos!.products.entries.toList()
                            ..sort((a, b) => b.value.compareTo(a.value)))
                          .take(10)
                          .map(
                            (e) =>
                                '${e.key}: TZS ${NumberFormat('#,##0.##', 'en_US').format(e.value)}',
                          )
                          .join('\n'),
                    ),
                  ),
                ),
            ],
            Card(
              child: ListTile(
                title: Text('bi_transactions'.tr),
                trailing: Text('${data.transactionCount}'),
              ),
            ),
            if (data.lowStock != null)
              Card(
                child: ListTile(
                  title: Text('bi_stock'.tr),
                  subtitle: Text(
                    data.lowStock!.isEmpty
                        ? 'bi_none'.tr
                        : data.lowStock!.join('\n'),
                  ),
                ),
              ),
            if (data.receivable != null)
              _metric('bi_receivable'.tr, data.receivable),
            if (data.payable != null) _metric('bi_payable'.tr, data.payable),
            if (data.purchases != null) ...[
              _metric('bi_purchases'.tr, data.purchases!.total),
              Card(
                child: ListTile(
                  title: Text('bi_purchase_count'.tr),
                  trailing: Text('${data.purchases!.count}'),
                ),
              ),
            ],
            if (data.tasks != null)
              Card(
                child: ListTile(
                  title: Text('bi_tasks'.tr),
                  subtitle: Text(
                    'bi_tasks_summary'.trParams({
                      'open': '${data.tasks!.open}',
                      'review': '${data.tasks!.awaitingReview}',
                      'approved': '${data.tasks!.approvedInPeriod}',
                    }),
                  ),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'bi_coverage'.tr,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (final limitation in data.limitations)
                      Text('• $limitation'),
                  ],
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _review(data),
              icon: const Icon(Icons.ios_share),
              label: Text('bi_share'.tr),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _openAssistant(AiAssistantTab.chat),
              icon: const Icon(Icons.chat_bubble_outline),
              label: Text('bi_open_assistant'.tr),
            ),
          ],
        ],
      );
    }),
  );

  Widget _metric(String title, double? value) => Card(
    child: ListTile(
      title: Text(title),
      trailing: Text('TZS ${NumberFormat('#,##0.##', 'en_US').format(value)}'),
    ),
  );
}
