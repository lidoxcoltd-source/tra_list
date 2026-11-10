import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/ai_chat.dart';
import 'package:tra_list/business_intelligence/ai_history.dart';
import 'package:tra_list/business_intelligence/ai_document_draft.dart';
import 'package:tra_list/business_intelligence/ai_models.dart';
import 'package:tra_list/business_intelligence/ai_models_ui.dart';
import 'package:tra_list/business_intelligence/ai_provider.dart';
import 'package:tra_list/business_intelligence/ai_quota_page.dart';
import 'package:tra_list/business_intelligence/business_context.dart';
import 'package:tra_list/business_intelligence/isher_avatar.dart';
import 'package:tra_list/business_intelligence/realtime_voice.dart';
import 'package:tra_list/business_intelligence/voice_transaction_draft.dart';

class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({
    super.key,
    required this.business,
    required this.loading,
    required this.error,
    this.provider,
    this.historyRepository,
    this.historyCache,
    this.initialTab = AiAssistantTab.chat,
  });
  final Rxn<BusinessContext> business;
  final RxBool loading;
  final RxString error;
  final AIProvider? provider;
  final AiHistoryRepository? historyRepository;
  final AiHistoryCache? historyCache;
  final AiAssistantTab initialTab;

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

enum AiAssistantTab { chat, voice }

class _AiAssistantPageState extends State<AiAssistantPage> {
  late final AIProvider _provider;
  late int _tab;
  BusinessContext? _chatBusiness;
  GlobalKey<BusinessAiChatState> _chatKey = GlobalKey<BusinessAiChatState>();

  void _openVoiceDocument(BusinessContext business, AiDocumentDraft draft) {
    if (!mounted || widget.business.value != business) return;
    final key = _chatKey;
    setState(() => _tab = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.business.value != business) return;
      final chat = key.currentState;
      if (chat == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('bi_voice_draft_unavailable'.tr)),
        );
        return;
      }

      chat.openVoiceDraft(draft);
    });
  }

  void _openVoiceTransaction(
    BusinessContext business,
    VoiceTransactionDraft draft,
  ) {
    if (!mounted || widget.business.value != business) return;
    final key = _chatKey;
    setState(() => _tab = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.business.value != business) return;
      final chat = key.currentState;
      if (chat == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('bi_voice_draft_unavailable'.tr)),
        );
        return;
      }
      chat.submitVoiceTransaction(draft);
    });
  }

  @override
  void initState() {
    super.initState();
    _provider = widget.provider ?? OpenAiCloudProvider();
    AiModelSelection.load();
    _tab = widget.initialTab == AiAssistantTab.voice ? 1 : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080817),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080817),
        foregroundColor: Colors.white,
        actions: [
          if (_tab == 0)
            IconButton(
              tooltip: 'bi_tab_call'.tr,
              onPressed: () => setState(() => _tab = 1),
              icon: const Icon(Icons.call_outlined),
            ),
          const AiModelPickerButton(),
          IconButton(
            tooltip: 'bi_quota_title'.tr,
            onPressed: () => Get.to(() => const AiQuotaPage()),
            icon: const Icon(Icons.data_usage),
          ),
        ],
        title: Row(
          children: [
            const IsherAvatar(size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Isher AI', style: TextStyle(fontSize: 18)),
                  Obx(
                    () => Text(
                      widget.business.value?.businessName ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Obx(() {
        final business = widget.business.value;
        if (business == null) {
          return Center(
            child: widget.loading.value
                ? const CircularProgressIndicator()
                : Text(
                    widget.error.value.isEmpty
                        ? 'bi_access_error'.tr
                        : widget.error.value,
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
          );
        }
        if (_chatBusiness != business) {
          _chatBusiness = business;
          _chatKey = GlobalKey<BusinessAiChatState>();
        }
        bool isCurrent() => widget.business.value == business;
        return Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Offstage(
                    offstage: _tab != 0,
                    child: TickerMode(
                      enabled: _tab == 0,
                      child: BusinessAiChat(
                        key: _chatKey,
                        businessContext: business,
                        isCurrent: isCurrent,
                        provider: _provider,
                        historyRepository: widget.historyRepository,
                        historyCache: widget.historyCache,
                      ),
                    ),
                  ),
                  Offstage(
                    offstage: _tab != 1,
                    child: TickerMode(
                      enabled: _tab == 1,
                      child: BusinessRealtimeVoice(
                        key: ObjectKey(business),
                        businessContext: business,
                        isCurrent: isCurrent,
                        provider: _provider,
                        visible: _tab == 1,
                        onOpenChat: () => setState(() => _tab = 0),
                        onOpenDocument: (draft) =>
                            _openVoiceDocument(business, draft),
                        onOpenTransaction: (draft) =>
                            _openVoiceTransaction(business, draft),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}
