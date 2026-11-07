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
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class BusinessIntelligenceController extends GetxController {
  final _service = BusinessContextService();
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
    _accessWorker?.dispose();
    _authSubscription?.cancel();
    super.onClose();
  }
}

class BusinessIntelligencePage extends StatefulWidget {
  const BusinessIntelligencePage({super.key});

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

  @override
  Widget build(BuildContext context) => Scaffold(
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
              onPressed: () => Get.to(
                () => AiAssistantPage(
                  business: controller.context,
                  loading: controller.loading,
                  error: controller.error,
                ),
              ),
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
