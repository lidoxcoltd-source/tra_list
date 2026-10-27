import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/theme/app_theme.dart';

import 'support_center_service.dart';

class _FaqDraft {
  _FaqDraft({String question = '', String answer = ''})
    : question = TextEditingController(text: question),
      answer = TextEditingController(text: answer);

  final TextEditingController question;
  final TextEditingController answer;

  void dispose() {
    question.dispose();
    answer.dispose();
  }
}

class SupportCenterAdminPage extends StatefulWidget {
  const SupportCenterAdminPage({super.key});

  @override
  State<SupportCenterAdminPage> createState() => _SupportCenterAdminPageState();
}

class _SupportCenterAdminPageState extends State<SupportCenterAdminPage> {
  final _formKey = GlobalKey<FormState>();
  final _whatsappController = TextEditingController();
  final List<_FaqDraft> _faqs = [];
  bool _loading = true;
  bool _saving = false;
  bool _authorized = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _whatsappController.dispose();
    for (final faq in _faqs) {
      faq.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _authorized = false;
          _loading = false;
        });
        return;
      }
      final profile = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('profile')
          .doc('company')
          .get();
      if (!mounted) return;
      final role = (profile.data()?['role']?.toString() ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (role != 'superadmin') {
        setState(() {
          _authorized = false;
          _loading = false;
        });
        return;
      }

      final config = await SupportCenterService.load();
      if (!mounted) return;
      _whatsappController.text = config.whatsappNumber;
      _faqs
        ..forEach((faq) => faq.dispose())
        ..clear()
        ..addAll(
          config.faqs.map(
            (faq) => _FaqDraft(question: faq.question, answer: faq.answer),
          ),
        );
      setState(() {
        _authorized = true;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load support center settings: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  void _addFaq() {
    if (_faqs.length >= 50) {
      Get.snackbar('error'.tr, 'support_faq_limit'.tr);
      return;
    }
    setState(() => _faqs.add(_FaqDraft()));
  }

  void _removeFaq(int index) {
    setState(() {
      _faqs.removeAt(index).dispose();
    });
  }

  Future<void> _save() async {
    if (!_authorized || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final config = SupportCenterConfig(
        whatsappNumber: _whatsappController.text.replaceAll(RegExp(r'\D'), ''),
        faqs: [
          for (final faq in _faqs)
            SupportFaq(
              question: faq.question.text.trim(),
              answer: faq.answer.text.trim(),
            ),
        ],
      );
      await SupportCenterService.save(config);
      if (!mounted) return;
      Get.snackbar('success'.tr, 'support_settings_saved'.tr);
    } catch (error, stackTrace) {
      debugPrint('Failed to save support center settings: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      Get.snackbar(
        'error'.tr,
        'support_settings_save_error'.trParams({'error': error.toString()}),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validatePhone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return 'support_whatsapp_required'.tr;
    if (digits.length < 8 || digits.length > 15) {
      return 'support_whatsapp_invalid'.tr;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MjasiColors.background,
      appBar: AppBar(title: Text('support_admin_title'.tr)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_authorized
          ? _buildUnauthorized()
          : _loadError != null
          ? _buildLoadError()
          : Form(
              key: _formKey,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView(
                    padding: const EdgeInsets.all(MjasiSpacing.lg),
                    children: [
                      _buildIntro(),
                      const SizedBox(height: MjasiSpacing.lg),
                      _buildWhatsAppCard(),
                      const SizedBox(height: MjasiSpacing.lg),
                      _buildFaqsCard(),
                      const SizedBox(height: MjasiSpacing.xl),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(_saving ? 'support_saving'.tr : 'save'.tr),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: MjasiColors.primaryBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildIntro() {
    return Container(
      padding: const EdgeInsets.all(MjasiSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [MjasiColors.primaryNavy, MjasiColors.primaryBlue],
        ),
        borderRadius: BorderRadius.circular(MjasiRadius.md),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.support_agent_rounded,
            size: 34,
            color: Colors.white,
          ),
          const SizedBox(width: MjasiSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'support_admin_intro_title'.tr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'support_admin_intro_message'.tr,
                  style: const TextStyle(color: Colors.white70, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhatsAppCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(MjasiSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'support_whatsapp_heading'.tr,
              style: const TextStyle(
                color: MjasiColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: MjasiSpacing.xs),
            Text(
              'support_whatsapp_help'.tr,
              style: const TextStyle(
                color: MjasiColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: MjasiSpacing.md),
            TextFormField(
              controller: _whatsappController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'support_whatsapp_number'.tr,
                hintText: '255712345678',
                prefixIcon: const Icon(Icons.phone_android_rounded),
                helperText: 'support_whatsapp_format'.tr,
              ),
              validator: _validatePhone,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFaqsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(MjasiSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'support_faq_heading'.tr,
                        style: const TextStyle(
                          color: MjasiColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'support_faq_admin_help'.tr,
                        style: const TextStyle(
                          color: MjasiColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _addFaq,
                  icon: const Icon(Icons.add_rounded),
                  label: Text('support_add_faq'.tr),
                ),
              ],
            ),
            const SizedBox(height: MjasiSpacing.md),
            if (_faqs.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(MjasiSpacing.xl),
                  child: Text(
                    'support_no_admin_faq'.tr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: MjasiColors.textSecondary),
                  ),
                ),
              ),
            for (var index = 0; index < _faqs.length; index++)
              _buildFaqEditor(index, _faqs[index]),
          ],
        ),
      ),
    );
  }

  Widget _buildFaqEditor(int index, _FaqDraft faq) {
    return Container(
      margin: const EdgeInsets.only(bottom: MjasiSpacing.md),
      padding: const EdgeInsets.all(MjasiSpacing.md),
      decoration: BoxDecoration(
        color: MjasiColors.background,
        borderRadius: BorderRadius.circular(MjasiRadius.sm),
        border: Border.all(color: MjasiColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'support_question_index'.trParams({'number': '${index + 1}'}),
                  style: const TextStyle(
                    color: MjasiColors.primaryNavy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'delete'.tr,
                onPressed: () => _removeFaq(index),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: MjasiColors.error,
                ),
              ),
            ],
          ),
          TextFormField(
            controller: faq.question,
            maxLength: 120,
            decoration: InputDecoration(
              labelText: 'support_question_label'.tr,
              prefixIcon: const Icon(Icons.help_outline_rounded),
            ),
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'support_question_required'.tr
                : null,
          ),
          const SizedBox(height: MjasiSpacing.sm),
          TextFormField(
            controller: faq.answer,
            minLines: 2,
            maxLines: 5,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: 'support_answer_label'.tr,
              prefixIcon: const Icon(Icons.chat_bubble_outline_rounded),
              alignLabelWithHint: true,
            ),
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'support_answer_required'.tr
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildUnauthorized() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MjasiSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 44,
              color: MjasiColors.error,
            ),
            const SizedBox(height: MjasiSpacing.md),
            Text(
              'staff_no_permission'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(color: MjasiColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MjasiSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'support_admin_load_error'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(color: MjasiColors.textSecondary),
            ),
            const SizedBox(height: MjasiSpacing.md),
            FilledButton.icon(
              onPressed: _loadSettings,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('refresh'.tr),
            ),
          ],
        ),
      ),
    );
  }
}
