import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'support_center_service.dart';

class SupportFaqPage extends StatefulWidget {
  const SupportFaqPage({super.key});

  @override
  State<SupportFaqPage> createState() => _SupportFaqPageState();
}

class _SupportFaqPageState extends State<SupportFaqPage> {
  late Future<SupportCenterConfig> _configFuture;

  @override
  void initState() {
    super.initState();
    _configFuture = SupportCenterService.load();
  }

  Future<void> _openWhatsApp(String number, {String question = ''}) async {
    final message = question.isEmpty
        ? 'support_general_message'.tr
        : 'support_question_message'.trParams({'question': question});
    final uri = Uri.https('wa.me', '/$number', {'text': message});
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('WhatsApp link could not be opened.');
      }
    } catch (error, stackTrace) {
      debugPrint('Could not open WhatsApp support: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      Get.snackbar('error'.tr, 'support_whatsapp_open_error'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MjasiColors.background,
      appBar: AppBar(title: Text('support_title'.tr)),
      body: FutureBuilder<SupportCenterConfig>(
        future: _configFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _buildError(snapshot.error);
          }
          final config = snapshot.data ?? const SupportCenterConfig();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.all(MjasiSpacing.lg),
                children: [
                  _buildHero(config.whatsappNumber),
                  const SizedBox(height: MjasiSpacing.xl),
                  Row(
                    children: [
                      const Icon(
                        Icons.help_outline_rounded,
                        color: MjasiColors.primaryBlue,
                      ),
                      const SizedBox(width: MjasiSpacing.sm),
                      Text(
                        'support_faq_heading'.tr,
                        style: const TextStyle(
                          color: MjasiColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MjasiSpacing.md),
                  if (config.faqs.isEmpty)
                    _buildEmptyFaq(config.whatsappNumber)
                  else
                    for (final faq in config.faqs)
                      _buildFaqTile(faq, config.whatsappNumber),
                  const SizedBox(height: MjasiSpacing.xl),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHero(String phone) {
    return Container(
      padding: const EdgeInsets.all(MjasiSpacing.xl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [MjasiColors.primaryNavy, MjasiColors.primaryBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(MjasiRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.support_agent_rounded,
            color: Colors.white,
            size: 34,
          ),
          const SizedBox(height: MjasiSpacing.md),
          Text(
            'support_welcome_title'.tr,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: MjasiSpacing.xs),
          Text(
            'support_welcome_message'.tr,
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: MjasiSpacing.lg),
            FilledButton.icon(
              onPressed: () => _openWhatsApp(phone),
              icon: const Icon(Icons.chat_rounded),
              label: Text('support_chat_button'.tr),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: MjasiColors.primaryNavy,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFaqTile(SupportFaq faq, String phone) {
    return Card(
      margin: const EdgeInsets.only(bottom: MjasiSpacing.sm),
      child: ExpansionTile(
        leading: const Icon(
          Icons.quiz_outlined,
          color: MjasiColors.primaryBlue,
        ),
        title: Text(
          faq.question,
          style: const TextStyle(
            color: MjasiColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          MjasiSpacing.lg,
          0,
          MjasiSpacing.lg,
          MjasiSpacing.md,
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              faq.answer,
              style: const TextStyle(
                color: MjasiColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: MjasiSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _openWhatsApp(phone, question: faq.question),
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: Text('support_ask_question'.tr),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyFaq(String phone) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(MjasiSpacing.xl),
        child: Column(
          children: [
            const Icon(
              Icons.menu_book_outlined,
              size: 40,
              color: MjasiColors.textSecondary,
            ),
            const SizedBox(height: MjasiSpacing.md),
            Text(
              'support_no_faq'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(color: MjasiColors.textSecondary),
            ),
            if (phone.isNotEmpty) ...[
              const SizedBox(height: MjasiSpacing.md),
              OutlinedButton.icon(
                onPressed: () => _openWhatsApp(phone),
                icon: const Icon(Icons.chat_outlined),
                label: Text('support_chat_button'.tr),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildError(Object? error) {
    final message =
        error is FirebaseException && error.code == 'permission-denied'
        ? 'support_load_permission_error'.tr
        : error is FirebaseException &&
              const {
                'unavailable',
                'deadline-exceeded',
                'network-request-failed',
              }.contains(error.code)
        ? 'support_load_error'.tr
        : 'support_load_generic_error'.tr;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MjasiSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              color: MjasiColors.warning,
              size: 40,
            ),
            const SizedBox(height: MjasiSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: MjasiColors.textSecondary),
            ),
            const SizedBox(height: MjasiSpacing.md),
            FilledButton.icon(
              onPressed: () =>
                  setState(() => _configFuture = SupportCenterService.load()),
              icon: const Icon(Icons.refresh_rounded),
              label: Text('refresh'.tr),
            ),
          ],
        ),
      ),
    );
  }
}
