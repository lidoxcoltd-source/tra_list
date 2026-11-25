import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:tra_list/business_intelligence/ai_history.dart';
import 'package:tra_list/business_intelligence/ai_models.dart';
import 'package:tra_list/business_intelligence/ai_document_draft.dart';
import 'package:tra_list/business_intelligence/ai_invoice_guide.dart';
import 'package:tra_list/business_intelligence/voice_transaction_draft.dart';
import 'package:tra_list/business_intelligence/ai_invoice_save.dart';
import 'package:tra_list/business_intelligence/ai_saved_invoice_pdf.dart';
import 'package:tra_list/business_intelligence/ai_transaction_suggestions.dart';
import 'package:tra_list/business_intelligence/ai_provider.dart';
import 'package:tra_list/business_intelligence/business_context.dart';
import 'package:tra_list/business_intelligence/chat_period.dart';
import 'package:tra_list/business_intelligence/isher_avatar.dart';
import 'package:tra_list/business_intelligence/isher_package_quota_notice.dart';
import 'package:tra_list/business_intelligence/isher_navigation.dart';
import 'package:tra_list/business_intelligence/isher_thinking_indicator.dart';
import 'package:tra_list/invoice/InvoicePage.dart';
import 'package:tra_list/invoice/quotation_page.dart';
import 'package:tra_list/invoice/advance_invoice_page.dart';
import 'package:tra_list/AddReceiptPage.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/pages/creative_studio_page.dart';
import 'package:tra_list/services/pdf/invoice_pdf.dart';
import 'package:tra_list/stock/stock_models.dart';
import 'package:tra_list/stock/stock_service.dart';
import 'package:tra_list/stock/stock_ui.dart';
import 'package:tra_list/jobs/models/debt.dart';
import 'package:tra_list/jobs/services/debt_service.dart';
import 'package:url_launcher/url_launcher.dart';

@visibleForTesting
String aiResourceLimitMessageKey(String? message) => switch (message) {
  'package-quota-exhausted' => 'isher_package_exhausted_notice',
  'quota-exhausted' => 'bi_chat_quota_exhausted',
  'rate-limited' => 'bi_chat_rate_limited',
  'Report preparation limit reached. Try again later.' =>
    'bi_chat_preparation_limited',
  'Too many records to prepare a complete report. Select a shorter period.' ||
  'Too many staff records to prepare a complete report.' ||
  'The business report is too large to share safely.' ||
  'Document details exceed the report size limit. Choose a shorter period.' =>
    'bi_chat_report_too_large',
  _ => 'bi_chat_limit_error',
};

Object? localizedAiSnapshot(
  Object? value,
  String language, {
  bool limitation = false,
}) {
  if (language != 'sw') return value ?? 'Unavailable';
  const keys = <String, String>{
    'businessName': 'Jina la biashara',
    'businessProfile': 'Taarifa za biashara',
    'businessType': 'Aina ya biashara',
    'businessDescription': 'Shughuli za biashara',
    'categories': 'Makundi ya miamala',
    'productCatalog': 'Orodha ya bidhaa na huduma',
    'products': 'Bidhaa na huduma',
    'productCatalogCount': 'Idadi ya bidhaa na huduma',
    'productCatalogTruncated': 'Orodha ya bidhaa imefupishwa',
    'sellPrice': 'Bei ya kuuza',
    'description': 'Maelezo',
    'tracked': 'Inafuatiliwa kwenye stock',
    'available': 'Stock inayopatikana',
    'unitCost': 'Gharama ya kununua kwa unit',
    'unitGrossMargin': 'Faida ghafi kwa unit',
    'address': 'Anwani',
    'phone': 'Simu',
    'website': 'Tovuti',
    'socialHandle': 'Jina la mtandao wa kijamii',
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
    'Business type and activity description are not provided in the business profile.':
        'Aina na maelezo ya shughuli za biashara hazijawekwa kwenye wasifu wa biashara.',
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

class OpenAiCloudProvider implements AIProvider, AiDocumentReviewProvider {
  OpenAiCloudProvider({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;
  final FirebaseFunctions _functions;

  @override
  Future<AiDocumentReview?> prepareDocumentReview({
    required BusinessContext context,
    required AiSnapshot snapshot,
    required String question,
  }) async {
    final result = await _functions
        .httpsCallable('prepareBusinessAiDocuments')
        .call({
          'businessUid': context.businessId,
          'token': snapshot.token,
          'question': question,
        });
    final data = Map<String, dynamic>.from(result.data as Map);
    if (data['required'] == false) return null;
    return AiDocumentReview(
      Map<String, dynamic>.from(data['details'] as Map),
      data['token'] as String,
    );
  }

  @override
  Future<AiSnapshot> prepare(BusinessContext context) async {
    final result = await _functions
        .httpsCallable('prepareBusinessAiContextV2')
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
    String? messageId,
  }) async {
    await AiModelSelection.load();
    final selectedModel =
        AiModelSelection.selectedId.value ??
        defaultAiModelId(
          (await AiModelRepository(functions: _functions).available()).models,
        );
    final result = await _functions.httpsCallable('askBusinessAiV2').call({
      'businessUid': context.businessId,
      'token': snapshot.token,
      'messages': messages,
      'language': language,
      'model': selectedModel,
      if (messageId != null) 'messageId': messageId,
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
    this.historyCache,
    this.transactionCategoryLoader,
    this.invoiceSaveFactory,
    this.invoiceStockPicker,
  });
  final BusinessContext businessContext;
  final bool Function() isCurrent;
  final AIProvider? provider;
  final AiHistoryRepository? historyRepository;
  final AiHistoryCache? historyCache;
  final Future<List<String>> Function(String type)? transactionCategoryLoader;
  final Future<String> Function(AiDocumentDraft draft) Function()?
  invoiceSaveFactory;
  final Future<Product?> Function()? invoiceStockPicker;

  @override
  State<BusinessAiChat> createState() => BusinessAiChatState();
}

class BusinessAiChatState extends State<BusinessAiChat> {
  late final AIProvider _provider;
  late final AiHistoryRepository _history;
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _messages = <AiChatMessage>[];
  final _expandedMessageIds = <String>{};
  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasMore = false;
  String? _historyError;
  AiChatMessage? _unsavedAnswer;
  AiChatMessage? _pendingUser;
  ReportingPeriod? _conversationPeriod;
  bool _busy = false;
  bool _awaitingResponse = false;
  bool _guidingInvoice = false;
  bool _openingDraft = false;
  bool _invoiceSaveFailed = false;
  AiInvoiceSave? _invoiceSave;
  Future<String> Function(AiDocumentDraft)? _saveInvoice;
  AiChatMessage? _pendingDocumentRequest;
  AiChatMessage? _replyTo;

  @override
  void initState() {
    super.initState();
    _provider = widget.provider ?? OpenAiCloudProvider();
    _history = widget.historyRepository ?? CloudAiHistoryRepository();
    final cached = widget.historyCache?.read(widget.businessContext);
    if (cached != null) {
      _messages.addAll(cached.messages);
      _hasMore = cached.hasMore;
      _restorePeriod();
    }
    _loadHistory();
  }

  void _restorePeriod() {
    _conversationPeriod = _messages.reversed
        .where((message) => message.role == 'user' && message.period != null)
        .map((message) => message.period)
        .firstOrNull;
  }

  void _cacheHistory() {
    widget.historyCache?.store(widget.businessContext, _messages, _hasMore);
  }

  String _messageText(AiChatMessage message, bool showTransactionSuggestions) {
    if (showTransactionSuggestions && identical(message, _messages.last)) {
      return 'bi_transaction_suggestion_prompt'.tr;
    }
    return decodeDocumentHistoryEvent(message)?.text ?? message.content;
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
        _restorePeriod();
        _cacheHistory();
      });
    } catch (error, stack) {
      debugPrint('Business AI history load failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted && widget.isCurrent()) {
        setState(() {
          if (error is FirebaseFunctionsException &&
              (error.code == 'permission-denied' ||
                  error.code == 'unauthenticated')) {
            _messages.clear();
            widget.historyCache?.clear();
          }
          _historyError = 'bi_history_error'.tr;
        });
      }
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
        _cacheHistory();
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

  Future<void> _openCreativeStudio({ImageSource? source}) async {
    if (!widget.isCurrent() || _busy || _guidingInvoice || _openingDraft)
      return;
    Uint8List? imageBytes;
    var imageName = '';
    if (source != null) {
      try {
        final picker = ImagePicker();
        XFile? photo;
        try {
          photo = await picker.pickImage(
            source: source,
            imageQuality: 90,
            maxWidth: 2400,
            maxHeight: 2400,
          );
        } on PlatformException catch (error) {
          if (source != ImageSource.camera ||
              error.code != 'no_available_camera') {
            rethrow;
          }
          photo = await picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 90,
            maxWidth: 2400,
            maxHeight: 2400,
          );
        }
        if (photo == null) return;
        imageBytes = await photo.readAsBytes();
        imageName = photo.name;
        final extension = imageName.split('.').last.toLowerCase();
        if (!{'jpg', 'jpeg', 'png', 'webp'}.contains(extension) ||
            imageBytes.length > 8 * 1024 * 1024) {
          throw ArgumentError('Choose a JPG, PNG or WebP image under 8 MB.');
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not add this photo: $error')),
          );
        }
        return;
      }
    }
    if (!mounted || !widget.isCurrent()) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CreativeStudioPage(
          initialBrief: _input.text.trim(),
          initialReferenceBytes: imageBytes,
          initialReferenceName: imageName,
        ),
      ),
    );
  }

  Future<void> _showCreativeActions() async {
    var startDesign = false;
    final source = await showModalBottomSheet<ImageSource?>(
      context: context,
      backgroundColor: const Color(0xFF10182A),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: Color(0xFF34445F)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'bi_chat_design_poster'.tr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'bi_chat_design_poster_hint'.tr,
                      style: const TextStyle(
                        color: Color(0xFFAAB8D0),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              _creativeActionTile(
                icon: Icons.auto_awesome_rounded,
                title: 'bi_chat_design_poster'.tr,
                subtitle: 'bi_chat_design_poster_hint'.tr,
                onTap: () {
                  startDesign = true;
                  Navigator.pop(sheetContext);
                },
              ),
              const SizedBox(height: 8),
              _creativeActionTile(
                icon: Icons.photo_library_outlined,
                title: 'bi_chat_choose_design_photo'.tr,
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
              _creativeActionTile(
                icon: Icons.camera_alt_outlined,
                title: 'bi_chat_take_design_photo'.tr,
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (source != null) await _openCreativeStudio(source: source);
    if (startDesign) await _openCreativeStudio();
  }

  Widget _creativeActionTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) => Material(
    color: const Color(0xFF202C43),
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF3A4C69)),
        ),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF384A70),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFFB9D8FF), size: 21),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFB3C0D5),
                    fontSize: 12,
                  ),
                ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: Color(0xFF9CB0D1),
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  bool get _canEditMessage =>
      widget.isCurrent() &&
      !_busy &&
      !_guidingInvoice &&
      !_openingDraft &&
      !_loading &&
      !_loadingOlder &&
      _historyError == null &&
      _unsavedAnswer == null;

  Future<void> _editMessage(AiChatMessage message) async {
    final Object repository = _history;
    if (!_canEditMessage ||
        message.role != 'user' ||
        decodeDocumentHistoryEvent(message) != null ||
        repository is! AiHistoryEditing) {
      return;
    }
    final editor = TextEditingController(text: message.content);
    final updated = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('bi_chat_edit_title'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('bi_chat_edit_notice'.tr),
            TextField(controller: editor, maxLength: 2000, maxLines: 5),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, editor.text.trim()),
            child: Text('bi_chat_edit_save'.tr),
          ),
        ],
      ),
    );
    editor.dispose();
    if (!mounted || updated == null || !_canEditMessage) return;
    if (updated.isEmpty || updated.length > 2000) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('bi_chat_edit_invalid'.tr)));
      return;
    }
    if (updated == message.content) return;
    setState(() => _busy = true);
    try {
      await repository.edit(
        widget.businessContext.businessId,
        message.id,
        updated,
      );
      if (!mounted || !widget.isCurrent()) return;
      final index = _messages.indexWhere((item) => item.id == message.id);
      if (index < 0) return;
      setState(() {
        _messages[index] = AiChatMessage(
          id: message.id,
          role: message.role,
          content: updated,
          createdAt: message.createdAt,
        );
        if (_replyTo?.id == message.id) _replyTo = _messages[index];
        _restorePeriod();
        _cacheHistory();
      });
    } catch (error, stack) {
      debugPrint('Business AI edit failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('bi_chat_change_error'.tr)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteMessage(AiChatMessage message) async {
    final Object repository = _history;
    if (!_canEditMessage || repository is! AiHistoryEditing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('bi_chat_delete_title'.tr),
        content: Text('bi_chat_delete_notice'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('bi_chat_delete'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_canEditMessage) return;
    setState(() => _busy = true);
    try {
      await repository.delete(widget.businessContext.businessId, message.id);
      if (!mounted || !widget.isCurrent()) return;
      setState(() {
        _messages.removeWhere((item) => item.id == message.id);
        if (_replyTo?.id == message.id) _replyTo = null;
        _restorePeriod();
        _cacheHistory();
      });
      if (_messages.isEmpty && _hasMore) await _loadHistory();
    } catch (error, stack) {
      debugPrint('Business AI delete failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('bi_chat_change_error'.tr)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startReply(AiChatMessage message) {
    if (!_canEditMessage) return;
    setState(() => _replyTo = message);
    _inputFocus.requestFocus();
  }

  Future<void> submitVoiceTransaction(VoiceTransactionDraft draft) async {
    bool allowed() =>
        _canEditMessage &&
        BusinessAccessService.hasBusinessAccess &&
        BusinessAccessService.isOwner.value &&
        BusinessAccessService.businessId == widget.businessContext.businessId;
    if (!allowed()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('bi_voice_draft_unavailable'.tr)),
        );
      }
      return;
    }
    await _send(draft.chatCommand);
  }

  bool _isDebtQuestion(String prompt) => RegExp(
    r'\b(debt|debts|owe|owes|owed|owing|deadline|due|overdue|madeni|deni|ananidai|unaowadadai|ninaodai|ninayodai|wanaonidai|tarehe ya mwisho|muda wa kulipa|waliochelewa)\b',
    caseSensitive: false,
  ).hasMatch(prompt);

  bool _isDebtReminderRequest(String prompt) => RegExp(
    r'\b(remind|reminder|send.*whatsapp|whatsapp.*send|kumbush|wakumbushe|mkumbushe|tuma.*whatsapp|whatsapp.*tuma)\b',
    caseSensitive: false,
  ).hasMatch(prompt);

  Debt? _matchReminderTarget(String prompt, List<Debt> debts) {
    final text = prompt.toLowerCase();
    final matches = debts
        .where(
          (debt) =>
              !debt.isSettled &&
              debt.phone.trim().isNotEmpty &&
              debt.direction == DebtDirection.customerOwesShop &&
              debt.debtorName.trim().length >= 2 &&
              text.contains(debt.debtorName.trim().toLowerCase()),
        )
        .toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) => b.debtorName.length.compareTo(a.debtorName.length));
    if (matches.length > 1 &&
        matches[0].debtorName.length == matches[1].debtorName.length) {
      return null;
    }
    return matches.first;
  }

  String _debtFactsForAi(List<Debt> debts, String prompt) {
    final open = debts.where((debt) => !debt.isSettled).toList()
      ..sort((a, b) {
        if (a.dueDate == null) return b.dueDate == null ? 0 : 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });
    final language = supportedAiLanguage(Get.locale?.languageCode);
    final lines = open
        .take(50)
        .map(
          (debt) => [
            debt.debtorName,
            debt.direction == DebtDirection.customerOwesShop
                ? 'customer owes business'
                : 'business owes supplier',
            'balance ${NumberFormat('#,##0', 'en_US').format(debt.balance)} TZS',
            'due ${debt.dueDate == null ? 'not set' : DateFormat('yyyy-MM-dd').format(debt.dueDate!)}',
            if (debt.isOverdue) 'overdue',
          ].join(' | '),
        )
        .toList();
    final isReminder = _isDebtReminderRequest(prompt);
    final facts = lines.isEmpty ? 'No open debts.' : lines.join('\n');
    return '${language == 'sw' ? 'Taarifa mpya za madeni zilizopatikana kwa ruhusa ya kazi zilizopo. Tumia majina, salio na tarehe hizi pekee.' : 'Fresh debt records retrieved under the existing jobs view permission. Use only these names, balances and dates.'}\n$facts${isReminder ? '\n${language == 'sw' ? 'Andaa ujumbe mfupi wa WhatsApp kwa mtu aliyetajwa tu. Tumia salio na tarehe zilizothibitishwa. Rudisha ujumbe pekee bila maelezo.' : 'Draft a brief WhatsApp reminder only for the named person. Use the verified balance and due date. Return only the message, no explanation.'}' : ''}';
  }

  Future<bool> _reviewChatDebtReminder(Debt debt, String draft) async {
    if (!BusinessAccessService.can('jobs', 'view') || !widget.isCurrent())
      return false;
    final editor = TextEditingController(text: draft.trim());
    String? approvedMessage;
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('bi_debt_reminder_review_title'.tr),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${debt.debtorName}  -  ${NumberFormat('#,##0', 'en_US').format(debt.balance)} TZS',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: editor,
                  maxLines: 5,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    labelText: 'bi_debt_reminder_message'.tr,
                    border: const OutlineInputBorder(),
                  ),
                ),
                Text(
                  'bi_debt_reminder_whatsapp_notice'.tr,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('cancel'.tr),
            ),
            FilledButton.icon(
              onPressed: () {
                if (editor.text.trim().isEmpty) return;
                approvedMessage = editor.text.trim();
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text('bi_debt_reminder_open_whatsapp'.tr),
            ),
          ],
        ),
      );
      if (approved != true || approvedMessage == null || !widget.isCurrent())
        return false;
    } finally {
      editor.dispose();
    }
    final current = await DebtService.loadAssistantDebt(debt.id);
    if (!widget.isCurrent() ||
        current == null ||
        current.isSettled ||
        current.phone.isEmpty)
      return false;
    var phone = current.phone.replaceAll(RegExp(r'\D'), '');
    if (phone.startsWith('00')) phone = phone.substring(2);
    if (phone.startsWith('0')) phone = '255${phone.substring(1)}';
    if (phone.length == 9) phone = '255$phone';
    if (phone.length < 8 || phone.length > 15) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('debt_whatsapp_invalid'.tr)));
      return false;
    }
    final uri = Uri.https('wa.me', '/$phone', {'text': approvedMessage!});
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('bi_debt_reminder_opened_notice'.tr)),
      );
    }
    return opened;
  }

  Future<bool> _confirmDebtDataForAi(List<Debt> debts) async {
    final openDebts = debts.where((debt) => !debt.isSettled).take(50).toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('bi_debt_ai_review_title'.tr),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('bi_debt_ai_review_notice'.tr),
                const SizedBox(height: 10),
                for (final debt in openDebts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      '${debt.debtorName}  -  ${NumberFormat('#,##0', 'en_US').format(debt.balance)} TZS  -  ${debt.dueDate == null ? 'debt_due_date_unspecified'.tr : DateFormat.yMMMd().format(debt.dueDate!)}',
                    ),
                  ),
                if (debts.length >= 100) Text('bi_debt_ai_review_limited'.tr),
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
    );
    return confirmed == true;
  }

  Future<void> _send([String? suggestion]) async {
    final typed = (suggestion ?? _input.text).trim();
    final reply = suggestion == null ? _replyTo : null;
    final quoted = reply == null
        ? ''
        : (decodeDocumentHistoryEvent(reply)?.text ?? reply.content);
    final excerpt = String.fromCharCodes(quoted.runes.take(300));
    final prompt = reply == null || typed.isEmpty
        ? typed
        : '${'bi_chat_reply_context'.tr}: $excerpt\n\n$typed';
    final isTransactionFollowUp =
        _messages.isNotEmpty &&
        _messages.last.role == 'assistant' &&
        (_messages.last.content ==
                'Tafadhali tuma kundi na maelezo kwa muundo: kundi: Kodi; maelezo: Kodi ya duka. Tumia kundi lililopo; tarehe itakuwa leo.' ||
            _messages.last.content ==
                'Please send the category and description in this format: category: Rent; description: Shop rent. Use an existing category; the date will be today.') &&
        RegExp(
          r'^\s*(kundi|category)\s*:',
          caseSensitive: false,
        ).hasMatch(prompt);
    if (prompt.isEmpty ||
        _busy ||
        _openingDraft ||
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
    if (reply == null && isIsherNavigationCommand(prompt)) {
      final destination = parseIsherNavigationCommand(prompt);
      if (destination == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('bi_navigation_unknown'.tr)));
        return;
      }
      setState(() => _busy = true);
      try {
        final opened = await openIsherDestination(
          context: context,
          destination: destination,
          businessId: widget.businessContext.businessId,
          isCurrent: widget.isCurrent,
        );
        if (opened && mounted && suggestion == null) _input.clear();
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    AiDocumentDraft? draft;
    try {
      draft = reply == null ? parseAiDocumentDraft(prompt) : null;
    } on FormatException {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('bi_draft_invalid'.tr)));
      return;
    }
    if (draft != null) {
      if (draft.kind == AiDocumentKind.invoice &&
          draft.customer == null &&
          draft.description == null) {
        if (!_canCreateDraft(draft)) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('bi_access_error'.tr)));
          return;
        }
        setState(() => _busy = true);
        final recorded = await _recordDocumentRequest(prompt);
        if (mounted) setState(() => _busy = false);
        if (!recorded || !mounted || !widget.isCurrent()) return;
        if (suggestion == null) _input.clear();
        setState(() {
          _guidingInvoice = true;
          _invoiceSaveFailed = false;
          _invoiceSave = AiInvoiceSave(
            widget.businessContext.businessId,
            widget.isCurrent,
          );
          _saveInvoice =
              widget.invoiceSaveFactory?.call() ?? _invoiceSave!.save;
        });
        return;
      }
      await _openDraft(draft, prompt: prompt, clearInput: suggestion == null);
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('bi_chat_period_error'.tr)));
        }
        return;
      }
      final requestContext = widget.businessContext.withPeriod(selectedPeriod);
      var snapshot = await _provider.prepare(requestContext);
      if (!mounted || !widget.isCurrent()) return;
      final asksAboutDebts = _isDebtQuestion(prompt);
      final currentDebts = asksAboutDebts
          ? await DebtService.loadForAssistant()
          : const <Debt>[];
      if (!mounted || !widget.isCurrent()) return;
      if (asksAboutDebts && !await _confirmDebtDataForAi(currentDebts)) return;
      if (!mounted || !widget.isCurrent()) return;
      final reminderTarget = _isDebtReminderRequest(prompt)
          ? _matchReminderTarget(prompt, currentDebts)
          : null;
      final debtFacts = asksAboutDebts
          ? _debtFactsForAi(currentDebts, prompt)
          : '';
      final Object provider = _provider;
      if (provider is AiDocumentReviewProvider) {
        final review = await provider.prepareDocumentReview(
          context: requestContext,
          snapshot: snapshot,
          question: prompt,
        );
        if (!mounted || !widget.isCurrent()) return;
        if (review != null) {
          snapshot = AiSnapshot(snapshot.context, review.token);
        }
      }
      final history = <Map<String, String>>[
        ..._messages
            .where((m) => decodeDocumentHistoryEvent(m) == null)
            .toList()
            .reversed
            .take(11)
            .toList()
            .reversed
            .map(
              (m) => {
                'role': m.role,
                'content': m.content.length > 2000
                    ? m.content.substring(0, 2000)
                    : m.content,
              },
            ),
        {
          'role': 'user',
          'content': debtFacts.isEmpty ? prompt : '$prompt\n\n$debtFacts',
        },
      ];
      final userMessage =
          _pendingUser?.content == prompt &&
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
        _cacheHistory();
        if (suggestion == null) {
          _input.clear();
          _replyTo = null;
        }
      });
      setState(() => _awaitingResponse = true);
      final answer = await _provider.respond(
        context: requestContext,
        snapshot: snapshot,
        messages: history,
        language: supportedAiLanguage(Get.locale?.languageCode),
        messageId: userMessage.id,
      );
      if (!mounted || !widget.isCurrent()) return;
      setState(() => _awaitingResponse = false);
      if (reminderTarget != null) {
        await _reviewChatDebtReminder(reminderTarget, answer);
        if (!mounted || !widget.isCurrent()) return;
      }
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
      setState(() {
        _messages.add(aiMessage);
        _cacheHistory();
      });
    } catch (e, stack) {
      debugPrint('Business AI request failed: $e');
      debugPrintStack(stackTrace: stack);
      if (mounted && widget.isCurrent()) {
        if (e is FirebaseFunctionsException &&
            e.code == 'resource-exhausted' &&
            aiResourceLimitMessageKey(e.message) ==
                'isher_package_exhausted_notice') {
          showIsherPackageQuotaNotice(context);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'bi_action_error'.trParams({
                'error': e is FirebaseFunctionsException
                    ? switch (e.code) {
                        'permission-denied' ||
                        'unauthenticated' => 'bi_chat_access_error'.tr,
                        'invalid-argument' => 'bi_chat_period_error'.tr,
                        'failed-precondition' =>
                          e.details is Map &&
                                  (e.details as Map)['reason'] ==
                                      'ai-transaction-category'
                              ? 'bi_transaction_category_error'.tr
                              : e.details is Map &&
                                    (e.details as Map)['reason'] ==
                                        'ai-model-unavailable'
                              ? 'bi_chat_model_unavailable'.tr
                              : e.details is Map &&
                                    (e.details as Map)['reason'] ==
                                        'ai-web-search-provider-required'
                              ? 'bi_chat_web_search_gemini_required'.tr
                              : 'bi_chat_snapshot_error'.tr,
                        'unavailable' || 'deadline-exceeded' =>
                          (isTransactionCommand(prompt) ||
                                  isTransactionFollowUp)
                              ? 'bi_transaction_uncertain'.tr
                              : 'bi_chat_server_error'.tr,
                        'resource-exhausted' => aiResourceLimitMessageKey(
                          e.message,
                        ).tr,
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
      if (mounted) {
        setState(() {
          _busy = false;
          _awaitingResponse = false;
        });
      }
    }
  }

  bool _canCreateDraft(AiDocumentDraft draft) {
    final module = switch (draft.kind) {
      AiDocumentKind.quotation => 'quotations',
      AiDocumentKind.receipt => 'receipts',
      _ => 'invoices',
    };
    return widget.isCurrent() &&
        BusinessAccessService.hasBusinessAccess &&
        BusinessAccessService.businessId == widget.businessContext.businessId &&
        BusinessAccessService.can(module, 'create');
  }

  Future<bool> _recordDocumentRequest(String prompt) async {
    final content = encodeDocumentHistoryEvent(prompt);
    final message = _pendingDocumentRequest?.content == content
        ? _pendingDocumentRequest!
        : newAiChatMessage('user', content);
    _pendingDocumentRequest = message;
    try {
      await _history.save(widget.businessContext.businessId, message);
      if (!mounted || !widget.isCurrent()) return false;
      _pendingDocumentRequest = null;
      setState(() {
        _messages.add(message);
        _cacheHistory();
      });
      return true;
    } catch (error, stack) {
      debugPrint('Document request history save failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted && widget.isCurrent()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('bi_question_unsaved'.tr)));
      }
      return false;
    }
  }

  Future<void> _recordDocumentResult(String text, {String? invoiceId}) async {
    final message = newAiChatMessage(
      'assistant',
      encodeBoundedDocumentHistoryEvent(
        text,
        truncatedNotice: 'bi_document_history_truncated'.tr,
        invoiceId: invoiceId,
      ),
    );
    try {
      await _history.save(widget.businessContext.businessId, message);
      if (!mounted || !widget.isCurrent()) return;
      setState(() {
        _messages.add(message);
        _cacheHistory();
      });
    } catch (error, stack) {
      debugPrint('Document result history save failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted && widget.isCurrent()) {
        setState(() {
          _messages.add(message);
          _unsavedAnswer = message;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('bi_answer_unsaved'.tr)));
      }
    }
  }

  Future<Product?> _pickInvoiceStock() async {
    try {
      if (!_canCreateDraft(
        const AiDocumentDraft(kind: AiDocumentKind.invoice),
      )) {
        throw StateError('Invoice access changed');
      }
      final customPicker = widget.invoiceStockPicker;
      if (customPicker != null) return await customPicker();
      final result = await StockService.current().products
          .orderBy('name')
          .get(const GetOptions(source: Source.server));
      final products = result.docs.map(Product.fromDoc).toList();
      if (!mounted ||
          !_canCreateDraft(
            const AiDocumentDraft(kind: AiDocumentKind.invoice),
          )) {
        throw StateError('Invoice access changed');
      }
      final selected = await pickProduct(context, products, trackedOnly: true);
      if (!mounted ||
          !_canCreateDraft(
            const AiDocumentDraft(kind: AiDocumentKind.invoice),
          )) {
        throw StateError('Invoice access changed');
      }
      return selected;
    } catch (error, stack) {
      debugPrint('Invoice stock selection failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('bi_invoice_stock_error'.tr)));
      }
      return null;
    }
  }

  Future<void> _saveGuidedInvoice(AiDocumentDraft draft) async {
    if (_openingDraft || _saveInvoice == null) return;
    setState(() => _openingDraft = true);
    try {
      final id = await _saveInvoice!(draft);
      if (!mounted || !widget.isCurrent()) return;
      setState(() {
        _guidingInvoice = false;
        _invoiceSaveFailed = false;
      });
      await _recordDocumentResult(
        '${'bi_invoice_saved'.tr}\n${formatAiInvoiceSummary(draft)}',
        invoiceId: id,
      );
    } catch (error, stack) {
      debugPrint('Guided invoice save failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted && widget.isCurrent()) {
        setState(() => _invoiceSaveFailed = true);
        final message = error is StockException
            ? stockErrorText(error)
            : 'bi_invoice_save_error'.tr;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _openingDraft = false);
    }
  }

  Future<void> _savedInvoicePdf(String id, {required bool save}) async {
    if (_openingDraft) return;
    setState(() => _openingDraft = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      bool hasAccess() =>
          uid != null &&
          FirebaseAuth.instance.currentUser?.uid == uid &&
          widget.isCurrent() &&
          BusinessAccessService.hasBusinessAccess &&
          BusinessAccessService.businessId ==
              widget.businessContext.businessId &&
          BusinessAccessService.can('invoices', 'view');
      if (!hasAccess()) throw StateError('Invoice access changed');
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.businessContext.businessId)
          .collection('invoices')
          .doc(id)
          .get(const GetOptions(source: Source.server));
      if (!mounted || !hasAccess()) throw StateError('Invoice access changed');
      final data = doc.data();
      if (data == null || data['kind'] != 'invoice') {
        throw StateError('Invoice is unavailable');
      }
      final bytes = await InvoicePdf.generateBytes(savedInvoicePdfData(data));
      if (!mounted || !hasAccess()) throw StateError('Invoice access changed');
      if (save) {
        final path = await saveInvoicePdfToDevice(bytes, id);
        if (mounted && hasAccess()) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${'bi_invoice_pdf_saved'.tr}: $path')),
          );
        }
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: Text('bi_invoice_pdf_preview'.tr)),
              body: PdfPreview(
                build: (_) async => bytes,
                canChangePageFormat: false,
                canChangeOrientation: false,
                canDebug: false,
              ),
            ),
          ),
        );
      }
    } catch (error, stack) {
      debugPrint('Saved invoice PDF failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted && widget.isCurrent()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('bi_invoice_pdf_error'.tr)));
      }
    } finally {
      if (mounted) setState(() => _openingDraft = false);
    }
  }

  Future<void> _editSavedInvoice(String id) async {
    if (_openingDraft) return;
    setState(() => _openingDraft = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      bool hasAccess() =>
          uid != null &&
          FirebaseAuth.instance.currentUser?.uid == uid &&
          widget.isCurrent() &&
          BusinessAccessService.hasBusinessAccess &&
          BusinessAccessService.businessId ==
              widget.businessContext.businessId &&
          BusinessAccessService.can('invoices', 'view') &&
          BusinessAccessService.can('invoices', 'edit');
      if (!hasAccess()) throw StateError('Invoice access changed');
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.businessContext.businessId)
          .collection('invoices')
          .doc(id)
          .get(const GetOptions(source: Source.server));
      if (!mounted || !hasAccess()) throw StateError('Invoice access changed');
      final data = doc.data();
      if (data == null || data['kind'] != 'invoice') {
        throw StateError('Invoice is unavailable');
      }
      if (invoiceHasStockLinks(data)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('bi_invoice_stock_edit_unavailable'.tr)),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => InvoicePage(
            invoice: doc,
            aiEditBusinessId: widget.businessContext.businessId,
            aiEditUserId: uid,
          ),
        ),
      );
    } catch (error, stack) {
      debugPrint('Edit saved invoice failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted && widget.isCurrent()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('bi_invoice_open_error'.tr)));
      }
    } finally {
      if (mounted) setState(() => _openingDraft = false);
    }
  }

  Future<void> _openDraft(
    AiDocumentDraft draft, {
    required String prompt,
    bool clearInput = false,
  }) async {
    if (_busy || _openingDraft) return;
    if (!_canCreateDraft(draft)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('bi_access_error'.tr)));
      return;
    }

    setState(() => _openingDraft = true);
    try {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('bi_draft_title'.tr),
          content: Text(
            draft.kind == AiDocumentKind.receipt
                ? 'bi_draft_receipt_notice'.tr
                : 'bi_draft_notice'.tr,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('cancel'.tr),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('bi_draft_open'.tr),
            ),
          ],
        ),
      );
      if (!mounted || proceed != true) return;
      if (!_canCreateDraft(draft)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('bi_access_error'.tr)));
        return;
      }
      if (!await _recordDocumentRequest(prompt) ||
          !mounted ||
          !_canCreateDraft(draft)) {
        return;
      }
      await _recordDocumentResult('bi_document_form_opened'.tr);
      if (!mounted || !_canCreateDraft(draft)) return;
      if (clearInput) _input.clear();
      if (_guidingInvoice) setState(() => _guidingInvoice = false);
      final page = switch (draft.kind) {
        AiDocumentKind.invoice ||
        AiDocumentKind.proforma => InvoicePage(aiDraft: draft),
        AiDocumentKind.quotation => QuotationPage(aiDraft: draft),
        AiDocumentKind.advance => AdvanceInvoicePage(aiDraft: draft),
        AiDocumentKind.receipt => AddReceiptPage(aiDraft: draft),
      };
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => page));
    } finally {
      if (mounted) setState(() => _openingDraft = false);
    }
  }

  Future<void> openVoiceDraft(AiDocumentDraft draft) async {
    if (_loading ||
        _historyError != null ||
        _unsavedAnswer != null ||
        _busy ||
        _openingDraft ||
        !widget.isCurrent()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('bi_voice_draft_unavailable'.tr)),
        );
      }
      return;
    }
    await _openDraft(
      draft,
      prompt: 'Voice document request: ${draft.kind.name}',
    );
  }

  Future<void> _retryAnswer() async {
    final message = _unsavedAnswer;
    if (message == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _history.save(widget.businessContext.businessId, message);
      if (mounted && widget.isCurrent()) {
        setState(() {
          _unsavedAnswer = null;
          _cacheHistory();
        });
      }
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

  Future<List<String>> _loadTransactionCategories(String type) async {
    if (!widget.isCurrent() ||
        !BusinessAccessService.hasBusinessAccess ||
        !BusinessAccessService.isOwner.value ||
        BusinessAccessService.businessId != widget.businessContext.businessId) {
      throw StateError('Business owner access is unavailable.');
    }
    final loader = widget.transactionCategoryLoader;
    final names = <String>{};
    if (loader != null) {
      names.addAll(await loader(type));
    } else {
      final result = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.businessContext.businessId)
          .collection('categories')
          .where('type', isEqualTo: type)
          .get(const GetOptions(source: Source.server));
      for (final doc in result.docs) {
        final name = doc.data()['name'];
        if (name is String) names.add(name);
      }
    }
    if (!widget.isCurrent() ||
        !BusinessAccessService.hasBusinessAccess ||
        !BusinessAccessService.isOwner.value ||
        BusinessAccessService.businessId != widget.businessContext.businessId) {
      throw StateError('Business owner access changed.');
    }
    return names
        .where(
          (name) =>
              name.isNotEmpty &&
              name == name.trim() &&
              name.length <= 100 &&
              !RegExp(r'[;\r\n]').hasMatch(name),
        )
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  void _submitTransactionSuggestion(String command) {
    if (!widget.isCurrent() ||
        !BusinessAccessService.hasBusinessAccess ||
        !BusinessAccessService.isOwner.value ||
        BusinessAccessService.businessId != widget.businessContext.businessId) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('bi_chat_access_error'.tr)));
      return;
    }
    _send(command);
  }

  Future<void> _pickEmoji() async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1C1732),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final emoji in [
                '😊',
                '👍',
                '💡',
                '📈',
                '📊',
                '💰',
                '🎯',
                '✅',
                '🙏',
                '✨',
              ])
                IconButton(
                  tooltip: emoji,
                  onPressed: () => Navigator.pop(context, emoji),
                  icon: Text(emoji, style: const TextStyle(fontSize: 25)),
                ),
            ],
          ),
        ),
      ),
    );
    if (emoji == null || !mounted) return;
    final value = _input.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final text = value.text.replaceRange(start, end, emoji);
    if (text.length > 2000) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('bi_chat_too_long'.tr)));
      return;
    }
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingTransaction = pendingAiTransaction(
      _messages
          .map((message) => {'role': message.role, 'content': message.content})
          .toList(),
    );
    final showTransactionSuggestions =
        !_guidingInvoice &&
        pendingTransaction != null &&
        widget.isCurrent() &&
        BusinessAccessService.hasBusinessAccess &&
        BusinessAccessService.isOwner.value &&
        BusinessAccessService.businessId == widget.businessContext.businessId;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF080817), Color(0xFF17102D)],
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: _loading && _messages.isEmpty
                ? const SizedBox.shrink()
                : _historyError != null && _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _historyError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        if (_historyError != null && _messages.isNotEmpty)
                          TextButton.icon(
                            onPressed: _loading ? null : _loadHistory,
                            icon: const Icon(Icons.refresh),
                            label: Text('bi_history_error'.tr),
                          ),
                        TextButton(
                          onPressed: _loadHistory,
                          child: Text('refresh'.tr),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) => ListView(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      children: [
                        if (_awaitingResponse) const IsherThinkingIndicator(),
                        if (_guidingInvoice)
                          AiInvoiceGuide(
                            enabled:
                                !_busy && !_openingDraft && widget.isCurrent(),
                            onCancel: () =>
                                setState(() => _guidingInvoice = false),
                            pickStock: _pickInvoiceStock,
                            onComplete: _saveGuidedInvoice,
                          ),
                        if (_guidingInvoice && _invoiceSaveFailed)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              'bi_invoice_save_error'.tr,
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        if (showTransactionSuggestions)
                          AiTransactionSuggestions(
                            key: ValueKey(_messages.last.id),
                            request: pendingTransaction,
                            loadCategories: _loadTransactionCategories,
                            enabled:
                                !_busy &&
                                !_loading &&
                                _historyError == null &&
                                _unsavedAnswer == null,
                            onSubmit: _submitTransactionSuggestion,
                          ),
                        for (final message in _messages.reversed)
                          GestureDetector(
                            key: ValueKey('ai_message_${message.id}'),
                            onHorizontalDragEnd: (details) {
                              if ((details.primaryVelocity ?? 0) > 150) {
                                _startReply(message);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: message.role == 'user'
                                    ? MainAxisAlignment.end
                                    : MainAxisAlignment.start,
                                children: [
                                  if (message.role != 'user') ...[
                                    const IsherAvatar(size: 32),
                                    const SizedBox(width: 8),
                                  ],
                                  Flexible(
                                    child: Container(
                                      constraints: BoxConstraints(
                                        maxWidth: (constraints.maxWidth * 0.72)
                                            .clamp(0.0, 420.0)
                                            .toDouble(),
                                      ),
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        9,
                                        12,
                                        6,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: message.role == 'user'
                                              ? const [
                                                  Color(0xFF6543BD),
                                                  Color(0xFF374FA1),
                                                ]
                                              : const [
                                                  Color(0xFF25213D),
                                                  Color(0xFF1B1A30),
                                                ],
                                        ),
                                        border: Border.all(
                                          color: message.role == 'user'
                                              ? const Color(0xFF8E79DD)
                                              : const Color(0xFF3A3353),
                                        ),
                                        borderRadius: BorderRadius.circular(17),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SelectableText(
                                            _messageText(
                                              message,
                                              showTransactionSuggestions,
                                            ),
                                            maxLines:
                                                _messageText(
                                                          message,
                                                          showTransactionSuggestions,
                                                        ).length >
                                                        500 &&
                                                    !_expandedMessageIds
                                                        .contains(message.id)
                                                ? 8
                                                : null,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              height: 1.4,
                                            ),
                                          ),
                                          if (_messageText(
                                                message,
                                                showTransactionSuggestions,
                                              ).length >
                                              500)
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: TextButton(
                                                onPressed: () {
                                                  setState(() {
                                                    if (!_expandedMessageIds
                                                        .add(message.id)) {
                                                      _expandedMessageIds
                                                          .remove(message.id);
                                                    }
                                                  });
                                                },
                                                style: TextButton.styleFrom(
                                                  foregroundColor: const Color(
                                                    0xFFC7A9FF,
                                                  ),
                                                  padding: EdgeInsets.zero,
                                                  minimumSize: const Size(
                                                    0,
                                                    32,
                                                  ),
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                                child: Text(
                                                  _expandedMessageIds.contains(
                                                        message.id,
                                                      )
                                                      ? 'market_read_less'.tr
                                                      : 'market_read_more'.tr,
                                                ),
                                              ),
                                            ),
                                          if (decodeDocumentHistoryEvent(
                                                message,
                                              )?.invoiceId
                                              case final String invoiceId)
                                            Wrap(
                                              spacing: 4,
                                              children: [
                                                TextButton(
                                                  onPressed: _openingDraft
                                                      ? null
                                                      : () => _editSavedInvoice(
                                                          invoiceId,
                                                        ),
                                                  child: Text(
                                                    'bi_invoice_edit_saved'.tr,
                                                  ),
                                                ),
                                                TextButton(
                                                  onPressed: _openingDraft
                                                      ? null
                                                      : () => _savedInvoicePdf(
                                                          invoiceId,
                                                          save: false,
                                                        ),
                                                  child: Text(
                                                    'bi_invoice_pdf_preview'.tr,
                                                  ),
                                                ),
                                                TextButton(
                                                  onPressed: _openingDraft
                                                      ? null
                                                      : () => _savedInvoicePdf(
                                                          invoiceId,
                                                          save: true,
                                                        ),
                                                  child: Text(
                                                    'bi_invoice_pdf_save'.tr,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          Wrap(
                                            alignment: WrapAlignment.end,
                                            children: [
                                              IconButton(
                                                tooltip: 'bi_chat_reply'.tr,
                                                onPressed: _canEditMessage
                                                    ? () => _startReply(message)
                                                    : null,
                                                visualDensity:
                                                    VisualDensity.compact,
                                                icon: const Icon(
                                                  Icons.reply,
                                                  size: 18,
                                                ),
                                                color: Colors.white70,
                                              ),
                                              if (message.role == 'user' &&
                                                  decodeDocumentHistoryEvent(
                                                        message,
                                                      ) ==
                                                      null &&
                                                  _history is AiHistoryEditing)
                                                IconButton(
                                                  tooltip:
                                                      'bi_chat_edit_title'.tr,
                                                  onPressed: _canEditMessage
                                                      ? () => _editMessage(
                                                          message,
                                                        )
                                                      : null,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  icon: const Icon(
                                                    Icons.edit_outlined,
                                                    size: 18,
                                                  ),
                                                  color: Colors.white70,
                                                ),
                                              if (_history is AiHistoryEditing)
                                                IconButton(
                                                  tooltip: 'bi_chat_delete'.tr,
                                                  onPressed: _canEditMessage
                                                      ? () => _deleteMessage(
                                                          message,
                                                        )
                                                      : null,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  icon: const Icon(
                                                    Icons.delete_outline,
                                                    size: 18,
                                                  ),
                                                  color: Colors.white70,
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: Text(
                                              DateFormat.Hm().format(
                                                message.createdAt,
                                              ),
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_hasMore)
                          Center(
                            child: TextButton(
                              onPressed:
                                  _loadingOlder ||
                                      _guidingInvoice ||
                                      _openingDraft ||
                                      _loading ||
                                      _historyError != null
                                  ? null
                                  : _loadOlder,
                              child: Text('bi_load_older'.tr),
                            ),
                          ),
                        if (_messages.isEmpty && !_guidingInvoice)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const IsherAvatar(size: 76),
                              const SizedBox(height: 18),
                              const Text(
                                'Isher AI',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'bi_chat_empty'.tr,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 12),
                              for (final key in [
                                'bi_question_performance',
                                if (BusinessAccessService.can('jobs', 'view'))
                                  'bi_question_debts',
                                if (widget
                                    .businessContext
                                    .expenseCategories
                                    .isNotEmpty)
                                  'bi_question_expenses',
                                if (widget
                                        .businessContext
                                        .lowStock
                                        ?.isNotEmpty ==
                                    true)
                                  'bi_question_stock',
                                if (widget
                                        .businessContext
                                        .pos
                                        ?.products
                                        .isNotEmpty ==
                                    true)
                                  'bi_question_products',
                                if (widget.businessContext.tasks != null &&
                                    (widget.businessContext.tasks!.open > 0 ||
                                        widget
                                                .businessContext
                                                .tasks!
                                                .awaitingReview >
                                            0))
                                  'bi_question_tasks',
                              ])
                                ActionChip(
                                  label: Text(key.tr),
                                  labelStyle: const TextStyle(
                                    color: Color(0xFFE6DEFF),
                                  ),
                                  backgroundColor: const Color(0xFF29213F),
                                  side: const BorderSide(
                                    color: Color(0xFF51446F),
                                  ),
                                  onPressed: _busy ? null : () => _send(key.tr),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
          if (_unsavedAnswer != null)
            TextButton.icon(
              onPressed: _busy ? null : _retryAnswer,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: Text('bi_retry_save'.tr),
            ),
          if (_replyTo case final AiChatMessage reply)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.reply, color: Color(0xFFC7A9FF), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${'bi_chat_reply'.tr}: ${decodeDocumentHistoryEvent(reply)?.text ?? reply.content}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'cancel'.tr,
                    onPressed: () => setState(() => _replyTo = null),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'bi_chat_design_poster'.tr,
                    onPressed:
                        _busy || _guidingInvoice || _openingDraft || _loading
                        ? null
                        : _showCreativeActions,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    color: const Color(0xFFB9A4FF),
                  ),
                  IconButton(
                    tooltip: 'bi_chat_emoji'.tr,
                    onPressed:
                        _guidingInvoice ||
                            _openingDraft ||
                            _loading ||
                            _historyError != null ||
                            _unsavedAnswer != null
                        ? null
                        : _pickEmoji,
                    icon: const Icon(Icons.emoji_emotions_outlined),
                    color: const Color(0xFFB9A4FF),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _inputFocus,
                      enabled:
                          !_guidingInvoice &&
                          !_openingDraft &&
                          !_loading &&
                          _historyError == null &&
                          _unsavedAnswer == null,
                      maxLength: 2000,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.35,
                      ),
                      cursorColor: const Color(0xFFC7A9FF),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'bi_chat_hint'.tr,
                        hintStyle: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                        counterText: '',
                        filled: true,
                        fillColor: const Color(0xFF1D1A2B),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(
                            color: Color(0xFF342D4F),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(
                            color: Color(0xFF8E79DD),
                            width: 1.2,
                          ),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'bi_chat_send_confirm'.tr,
                    child: FilledButton.icon(
                      onPressed:
                          _busy ||
                              _guidingInvoice ||
                              _openingDraft ||
                              _loading ||
                              _historyError != null ||
                              _unsavedAnswer != null
                          ? null
                          : () => _send(),
                      icon: const Icon(Icons.send, size: 18),
                      label: Text('bi_chat_send_button'.tr),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF7656D6),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF493A75),
                        disabledForegroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
