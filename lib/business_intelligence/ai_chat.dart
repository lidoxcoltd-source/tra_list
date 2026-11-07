import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:tra_list/business_intelligence/ai_history.dart';
import 'package:tra_list/business_intelligence/ai_provider.dart';
import 'package:tra_list/business_intelligence/business_context.dart';
import 'package:tra_list/business_intelligence/chat_period.dart';

Object? localizedAiSnapshot(
  Object? value,
  String language, {
  bool limitation = false,
}) {
  if (language != 'sw') return value ?? 'Unavailable';
  const keys = <String, String>{
    'businessName': 'Jina la biashara',
    'periodStart': 'Mwanzo wa kipindi (UTC)',
    'periodEndExclusive': 'Mwisho wa kipindi usiojumuishwa (UTC)',
    'updatedAt': 'Muhtasari umesasishwa (UTC)',
    'currency': 'Sarafu',
    'transactions': 'Miamala iliyorekodiwa',
    'income': 'Mapato',
    'incomeByDayUtc': 'Mapato kwa siku (UTC)',
    'expenses': 'Matumizi',
    'count': 'Idadi',
    'invalid': 'Taarifa zisizo sahihi',
    'expenseCategories': 'Makundi ya matumizi',
    'category': 'Kundi',
    'amount': 'Kiasi',
    'categoriesTruncated': 'Makundi mengine yameachwa',
    'pos': 'Mauzo ya POS',
    'total': 'Jumla',
    'topProducts': 'Bidhaa zinazoongoza',
    'name': 'Jina',
    'lowStock': 'Bidhaa zenye akiba ndogo',
    'lowStockCount': 'Idadi ya bidhaa zenye akiba ndogo',
    'quantity': 'Kiasi cha akiba',
    'unit': 'Kipimo',
    'invalidStock': 'Bidhaa zenye taarifa pungufu',
    'debts': 'Madeni',
    'receivable': 'Madeni ya wateja',
    'payable': 'Madeni ya biashara',
    'invalidDebts': 'Madeni yenye taarifa pungufu',
    'purchases': 'Manunuzi',
    'tasks': 'Kazi',
    'open': 'Zilizo wazi sasa',
    'awaitingReview': 'Zinazosubiri ukaguzi sasa',
    'approvedInPeriod': 'Zilizoidhinishwa katika kipindi',
    'limitations': 'Mipaka ya taarifa',
  };
  const phrases = <String, String>{
    'Recorded transaction income may overlap POS sales; do not add them together.':
        'Mapato ya miamala yanaweza kuingiliana na mauzo ya POS; usiyajumlishe pamoja.',
    'Income minus expenses is cash flow, not gross or net profit.':
        'Mapato toa matumizi ni salio la fedha, si faida ghafi au halisi.',
    'Transactions without valid dates are excluded. Stock and debt balances are current.':
        'Miamala isiyo na tarehe sahihi haijajumuishwa. Akiba na madeni vinaonyesha hali ya sasa.',
    'POS sales exclude bar orders, refunds and deleted invoices; product amounts exclude invoice-level adjustments.':
        'Mauzo ya POS hayajumuishi oda za baa, marejesho au ankara zilizofutwa; thamani za bidhaa hazijumuishi marekebisho ya ankara.',
    'Daily income is grouped by UTC date. Business type, customer history, staff and job records are unavailable.':
        'Mapato ya kila siku yamepangwa kwa tarehe ya UTC. Aina ya biashara, historia ya wateja, wafanyakazi na rekodi za kazi za wateja havipatikani.',
    'Purchases are business-wide received stock purchases by purchase date, not necessarily paid expenses. Purchases may overlap recorded expenses; do not add them. Records without valid dates are excluded.':
        'Manunuzi ni ya bidhaa zilizopokelewa katika biashara nzima kwa tarehe ya manunuzi, si lazima yawe matumizi yaliyolipwa. Yanaweza kuingiliana na matumizi yaliyorekodiwa; usiyajumlishe pamoja. Rekodi zisizo na tarehe sahihi hazijajumuishwa.',
    'Purchase data is unavailable to this account.':
        'Taarifa za manunuzi hazipatikani kwa akaunti hii.',
    'Task counts cover all tasks currently visible with tasks view permission. Open and review counts are current; approved count uses approval date within the selected period.':
        'Idadi inahusu kazi zote zinazoonekana kwa ruhusa ya kuona kazi. Kazi zilizo wazi na zinazosubiri ukaguzi ni za sasa; zilizoidhinishwa zinahesabiwa kwa tarehe ya idhini katika kipindi kilichochaguliwa.',
    'Task data is unavailable to this account.':
        'Taarifa za kazi hazipatikani kwa akaunti hii.',
    'Transactions and debts are limited to the assigned shop; stock is business-wide.':
        'Miamala na madeni ni ya duka ulilopangiwa; akiba ni ya biashara nzima.',
    'Only the first 50 low-stock products are shown.':
        'Bidhaa 50 za kwanza zenye akiba ndogo ndizo zimeonyeshwa.',
  };
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry(
        keys[key.toString()] ?? key.toString(),
        localizedAiSnapshot(item, language, limitation: key == 'limitations'),
      ),
    );
  }
  if (value is List) {
    return value
        .map(
          (item) => localizedAiSnapshot(item, language, limitation: limitation),
        )
        .toList();
  }
  if (value == null) return 'Haipatikani';
  if (value is String && limitation) return phrases[value] ?? value;
  return value;
}

class OpenAiCloudProvider implements AIProvider {
  OpenAiCloudProvider({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;
  final FirebaseFunctions _functions;

  @override
  Future<AiSnapshot> prepare(BusinessContext context) async {
    final result = await _functions
        .httpsCallable('prepareBusinessAiContext')
        .call({
          'businessUid': context.businessId,
          'startMillis': context.period.start.millisecondsSinceEpoch,
          'endMillis': context.period.end.millisecondsSinceEpoch,
        });
    final data = Map<String, dynamic>.from(result.data as Map);
    return AiSnapshot(
      Map<String, dynamic>.from(data['context'] as Map),
      data['token'] as String,
    );
  }

  @override
  Future<String> respond({
    required BusinessContext context,
    required AiSnapshot snapshot,
    required List<Map<String, String>> messages,
    required String language,
  }) async {
    final result = await _functions.httpsCallable('askBusinessAi').call({
      'businessUid': context.businessId,
      'token': snapshot.token,
      'messages': messages,
      'language': language,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['answer'] as String;
  }
}

class BusinessAiChat extends StatefulWidget {
  const BusinessAiChat({
    super.key,
    required this.businessContext,
    required this.isCurrent,
    this.provider,
    this.historyRepository,
  });
  final BusinessContext businessContext;
  final bool Function() isCurrent;
  final AIProvider? provider;
  final AiHistoryRepository? historyRepository;

  @override
  State<BusinessAiChat> createState() => _BusinessAiChatState();
}

class _BusinessAiChatState extends State<BusinessAiChat> {
  late final AIProvider _provider;
  late final AiHistoryRepository _history;
  final _input = TextEditingController();
  final _messages = <AiChatMessage>[];
  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasMore = false;
  String? _historyError;
  AiChatMessage? _unsavedAnswer;
  AiChatMessage? _pendingUser;
  ReportingPeriod? _conversationPeriod;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _provider = widget.provider ?? OpenAiCloudProvider();
    _history = widget.historyRepository ?? CloudAiHistoryRepository();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _historyError = null;
    });
    try {
      final page = await _history.load(widget.businessContext.businessId);
      if (!mounted || !widget.isCurrent()) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(page.messages);
        _hasMore = page.hasMore;
        _conversationPeriod = page.messages.reversed
            .where((message) => message.role == 'user' && message.period != null)
            .map((message) => message.period)
            .firstOrNull;
      });
    } catch (error, stack) {
      debugPrint('Business AI history load failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) setState(() => _historyError = 'bi_history_error'.tr);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || _messages.isEmpty) return;
    setState(() => _loadingOlder = true);
    try {
      final page = await _history.load(
        widget.businessContext.businessId,
        before: _messages.first.id,
      );
      if (!mounted || !widget.isCurrent()) return;
      setState(() {
        _messages.insertAll(0, page.messages);
        _hasMore = page.hasMore;
      });
    } catch (error, stack) {
      debugPrint('Business AI older history load failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('bi_history_error'.tr)));
      }
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send([String? suggestion]) async {
    final prompt = (suggestion ?? _input.text).trim();
    if (prompt.isEmpty ||
        _busy ||
        _loading ||
        _historyError != null ||
        _unsavedAnswer != null) {
      return;
    }
    if (prompt.length > 2000) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('bi_chat_too_long'.tr)));
      return;
    }
    setState(() => _busy = true);
    try {
      final interpretation = resolveChatPeriod(prompt, DateTime.now());
      if (interpretation.kind == ChatPeriodKind.comparison) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('bi_date_comparison_unsupported'.tr)),
        );
        return;
      }
      ReportingPeriod? period = interpretation.period;
      if (interpretation.kind == ChatPeriodKind.needsSelection) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final suggested = interpretation.suggested ?? today;
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(1970),
          lastDate: today,
          initialDateRange: DateTimeRange(start: suggested, end: suggested),
          helpText: 'bi_chat_choose_period'.tr,
        );
        if (range == null || !mounted || !widget.isCurrent()) return;
        period = ReportingPeriod(
          range.start,
          DateTime(range.end.year, range.end.month, range.end.day + 1),
        );
      }
      final selectedPeriod =
          period ?? _conversationPeriod ?? widget.businessContext.period;
      if (selectedPeriod.end.difference(selectedPeriod.start) >
          const Duration(days: 366)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('bi_chat_period_error'.tr)),
          );
        }
        return;
      }
      final requestContext = widget.businessContext.withPeriod(selectedPeriod);
      final snapshot = await _provider.prepare(requestContext);
      if (!mounted || !widget.isCurrent()) return;
      final history = <Map<String, String>>[
        ..._messages
            .skip(_messages.length > 11 ? _messages.length - 11 : 0)
            .map(
              (m) => {
                'role': m.role,
                'content': m.content.length > 2000
                    ? m.content.substring(0, 2000)
                    : m.content,
              },
            ),
        {'role': 'user', 'content': prompt},
      ];
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => Obx(
          () => !widget.isCurrent()
              ? AlertDialog(
                  content: Text('bi_access_error'.tr),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text('close'.tr),
                    ),
                  ],
                )
              : AlertDialog(
                  title: Text('bi_chat_review'.tr),
                  content: SizedBox(
                    width: 600,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('bi_chat_disclosure'.tr),
                          const SizedBox(height: 8),
                          Text(
                            'bi_chat_selected_period'.trParams({
                              'start': DateFormat.yMMMd().format(selectedPeriod.start),
                              'end': DateFormat.yMMMd().format(selectedPeriod.end.subtract(const Duration(microseconds: 1))),
                            }),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          SelectableText(
                            const JsonEncoder.withIndent('  ').convert(
                              localizedAiSnapshot(
                                snapshot.context,
                                Get.locale?.languageCode ?? 'en',
                              ),
                            ),
                          ),
                          const Divider(),
                          Text(
                            'bi_chat_history'.tr,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          for (final message in history)
                            SelectableText(
                              '${(message['role'] == 'user' ? 'bi_chat_user' : 'bi_chat_assistant').tr}: ${message['content']}\n',
                            ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text('cancel'.tr),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text('bi_chat_send_confirm'.tr),
                    ),
                  ],
                ),
        ),
      );
      if (confirmed != true || !mounted || !widget.isCurrent()) return;
      final userMessage = _pendingUser?.content == prompt &&
              _pendingUser?.period?.start == selectedPeriod.start &&
              _pendingUser?.period?.end == selectedPeriod.end
          ? _pendingUser!
          : newAiChatMessage('user', prompt, period: selectedPeriod);
      _pendingUser = userMessage;
      try {
        await _history.save(widget.businessContext.businessId, userMessage);
      } catch (error, stack) {
        debugPrint('Business AI question save failed: $error');
        debugPrintStack(stackTrace: stack);
        if (mounted && widget.isCurrent()) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('bi_question_unsaved'.tr)));
        }
        return;
      }
      _pendingUser = null;
      if (!mounted || !widget.isCurrent()) return;
      setState(() {
        _messages.add(userMessage);
        _conversationPeriod = selectedPeriod;
        if (suggestion == null) _input.clear();
      });
      final answer = await _provider.respond(
        context: requestContext,
        snapshot: snapshot,
        messages: history,
        language: Get.locale?.languageCode ?? 'en',
      );
      if (!mounted || !widget.isCurrent()) return;
      final aiMessage = newAiChatMessage('assistant', answer);
      try {
        await _history.save(widget.businessContext.businessId, aiMessage);
      } catch (error, stack) {
        debugPrint('Business AI answer save failed: $error');
        debugPrintStack(stackTrace: stack);
        if (mounted && widget.isCurrent()) {
          setState(() {
            _messages.add(aiMessage);
            _unsavedAnswer = aiMessage;
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('bi_answer_unsaved'.tr)));
        }
        return;
      }
      if (!mounted || !widget.isCurrent()) return;
      setState(() => _messages.add(aiMessage));
    } catch (e, stack) {
      debugPrint('Business AI request failed: $e');
      debugPrintStack(stackTrace: stack);
      if (mounted && widget.isCurrent()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'bi_action_error'.trParams({
                'error': e is FirebaseFunctionsException
                    ? switch (e.code) {
                        'permission-denied' ||
                        'unauthenticated' => 'bi_chat_access_error'.tr,
                        'invalid-argument' => 'bi_chat_period_error'.tr,
                        'failed-precondition' => 'bi_chat_snapshot_error'.tr,
                        'resource-exhausted' => 'bi_chat_limit_error'.tr,
                        'not-found' ||
                        'unimplemented' => 'bi_chat_not_configured'.tr,
                        _ => 'bi_chat_server_error'.tr,
                      }
                    : e.toString(),
              }),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryAnswer() async {
    final message = _unsavedAnswer;
    if (message == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _history.save(widget.businessContext.businessId, message);
      if (mounted && widget.isCurrent()) setState(() => _unsavedAnswer = null);
    } catch (error, stack) {
      debugPrint('Business AI answer retry failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('bi_answer_unsaved'.tr)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _historyError != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _historyError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    TextButton(
                      onPressed: _loadHistory,
                      child: Text('refresh'.tr),
                    ),
                  ],
                ),
              )
            : ListView(
                reverse: true,
                padding: const EdgeInsets.all(16),
                children: [
                  for (final message in _messages.reversed)
                    Align(
                      alignment: message.role == 'user'
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 520),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.fromLTRB(14, 11, 14, 7),
                        decoration: BoxDecoration(
                          color: message.role == 'user'
                              ? const Color(0xFF1757A5)
                              : const Color(0xFF263246),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SelectableText(
                              message.content,
                              style: const TextStyle(color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat.Hm().format(message.createdAt),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_hasMore)
                    Center(
                      child: TextButton(
                        onPressed: _loadingOlder ? null : _loadOlder,
                        child: Text('bi_load_older'.tr),
                      ),
                    ),
                  if (_messages.isEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'bi_chat_empty'.tr,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 12),
                        for (final key in [
                          'bi_question_performance',
                          if (widget
                              .businessContext
                              .expenseCategories
                              .isNotEmpty)
                            'bi_question_expenses',
                          if (widget.businessContext.lowStock?.isNotEmpty ==
                              true)
                            'bi_question_stock',
                          if (widget.businessContext.pos?.products.isNotEmpty ==
                              true)
                            'bi_question_products',
                          if (widget.businessContext.tasks != null &&
                              (widget.businessContext.tasks!.open > 0 ||
                                  widget.businessContext.tasks!.awaitingReview >
                                      0))
                            'bi_question_tasks',
                        ])
                          ActionChip(
                            label: Text(key.tr),
                            onPressed: _busy ? null : () => _send(key.tr),
                          ),
                      ],
                    ),
                ],
              ),
      ),
      if (_unsavedAnswer != null)
        TextButton.icon(
          onPressed: _busy ? null : _retryAnswer,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: Text('bi_retry_save'.tr),
        ),
      if (_busy) const LinearProgressIndicator(),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled:
                      !_loading &&
                      _historyError == null &&
                      _unsavedAnswer == null,
                  maxLength: 2000,
                  minLines: 1,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'bi_chat_hint'.tr,
                    hintStyle: const TextStyle(color: Colors.white54),
                    counterText: '',
                    filled: true,
                    fillColor: const Color(0xFF263246),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed:
                    _busy ||
                        _loading ||
                        _historyError != null ||
                        _unsavedAnswer != null
                    ? null
                    : () => _send(),
                icon: const Icon(Icons.send),
                tooltip: 'bi_chat_send_confirm'.tr,
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
