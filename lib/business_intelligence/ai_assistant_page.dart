import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/ai_chat.dart';
import 'package:tra_list/business_intelligence/ai_history.dart';
import 'package:tra_list/business_intelligence/ai_provider.dart';
import 'package:tra_list/business_intelligence/business_context.dart';
import 'package:tra_list/business_intelligence/realtime_voice.dart';

class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({
    super.key,
    required this.business,
    required this.loading,
    required this.error,
    this.provider,
    this.historyRepository,
  });
  final Rxn<BusinessContext> business;
  final RxBool loading;
  final RxString error;
  final AIProvider? provider;
  final AiHistoryRepository? historyRepository;

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  late final AIProvider _provider;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _provider = widget.provider ?? OpenAiCloudProvider();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141C2E),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('MJASI AI', style: TextStyle(fontSize: 18)),
            Obx(
              () => Text(
                widget.business.value?.businessName ?? '',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
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
        bool isCurrent() => widget.business.value == business;
        return Column(
          children: [
            Container(
              color: const Color(0xFF141C2E),
              child: Row(
                children: [
                  _tabButton(0, Icons.chat_bubble_outline, 'bi_tab_chat'.tr),
                  _tabButton(1, Icons.call_outlined, 'bi_tab_call'.tr),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Offstage(
                    offstage: _tab != 0,
                    child: BusinessAiChat(
                      key: ObjectKey(business),
                      businessContext: business,
                      isCurrent: isCurrent,
                      provider: _provider,
                      historyRepository: widget.historyRepository,
                    ),
                  ),
                  if (_tab == 1)
                    Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: BusinessRealtimeVoice(
                          key: ObjectKey(business),
                          businessContext: business,
                          isCurrent: isCurrent,
                          provider: _provider,
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

  Widget _tabButton(int index, IconData icon, String label) => Expanded(
    child: InkWell(
      onTap: () => setState(() => _tab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: _tab == index
                  ? const Color(0xFF8F68FF)
                  : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 19,
              color: _tab == index ? Colors.white : Colors.white54,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: _tab == index ? Colors.white : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
