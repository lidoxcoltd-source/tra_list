import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:tra_list/business_intelligence/ai_models_admin_page.dart';
import 'package:tra_list/business_intelligence/isher_voice_language_page.dart';

class AiQuotaPage extends StatefulWidget {
  const AiQuotaPage({super.key, this.admin = false});

  final bool admin;

  @override
  State<AiQuotaPage> createState() => _AiQuotaPageState();
}

class _AiQuotaPageState extends State<AiQuotaPage> {
  final _functions = FirebaseFunctions.instance;
  final _fields = <String, TextEditingController>{};
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _status;
  String? _pendingGrantId;

  static const _settings = [
    'dailyVoice',
    'dailyMessages',
    'voiceMinutes',
    'voicePrice',
    'messagePrice',
  ];

  @override
  void initState() {
    super.initState();
    for (final key in [..._settings, 'uid', 'voice', 'messages']) {
      _fields[key] = TextEditingController();
    }
    _load();
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _functions
          .httpsCallable(
            widget.admin ? 'getBusinessAiAdminSettings' : 'getBusinessAiQuota',
          )
          .call();
      final status = Map<String, dynamic>.from(result.data as Map);
      if (!mounted) return;
      final settings = Map<String, dynamic>.from(status['settings'] as Map);
      for (final key in _settings) {
        _fields[key]!.text = settings[key].toString();
      }
      setState(() => _status = status);
    } catch (error, stack) {
      debugPrint('AI quota load failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) setState(() => _error = 'bi_quota_load_error'.tr);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final values = <String, int>{};
    for (final key in _settings) {
      final value = int.tryParse(_fields[key]!.text.trim());
      if (value == null) {
        _notice('bi_quota_invalid'.tr);
        return;
      }
      values[key] = value;
    }
    setState(() => _loading = true);
    try {
      await _functions.httpsCallable('saveBusinessAiAdminSettings').call({
        'settings': values,
      });
      if (mounted) _notice('bi_quota_saved'.tr);
    } catch (error, stack) {
      debugPrint('AI settings save failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) _notice('bi_quota_save_error'.tr);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _grant() async {
    final uid = _fields['uid']!.text.trim();
    final voice = int.tryParse(_fields['voice']!.text.trim());
    final messages = int.tryParse(_fields['messages']!.text.trim());
    if (uid.isEmpty ||
        voice == null ||
        messages == null ||
        voice < 0 ||
        messages < 0 ||
        voice + messages == 0) {
      _notice('bi_quota_invalid'.tr);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('bi_quota_grant'.tr),
        content: Text(
          'bi_quota_grant_confirm'.trParams({
            'uid': uid,
            'voice': '$voice',
            'messages': '$messages',
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('bi_quota_grant'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    _pendingGrantId ??= const Uuid().v4();
    try {
      await _functions.httpsCallable('grantBusinessAiQuota').call({
        'uid': uid,
        'voice': voice,
        'messages': messages,
        'grantId': _pendingGrantId,
      });
      _pendingGrantId = null;
      if (mounted) _notice('bi_quota_granted'.tr);
    } catch (error, stack) {
      debugPrint('AI quota grant failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) _notice('bi_quota_grant_error'.tr);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _notice(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _field(String key, String label, {bool numeric = true}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: _fields[key],
      onChanged: key == 'uid' || key == 'voice' || key == 'messages'
          ? (_) => _pendingGrantId = null
          : null,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final settings = _status?['settings'] as Map?;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          (widget.admin ? 'bi_quota_admin_title' : 'bi_quota_title').tr,
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('bi_quota_explanation'.tr),
                const SizedBox(height: 16),
                if (widget.admin) ...[
                  OutlinedButton.icon(
                    onPressed: () =>
                        Get.to(() => const IsherVoiceLanguagePage()),
                    icon: const Icon(Icons.record_voice_over_outlined),
                    label: Text('isher_language_title'.tr),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => Get.to(() => const AiModelsAdminPage()),
                    icon: const Icon(Icons.tune),
                    label: Text('bi_models_admin_title'.tr),
                  ),
                  const SizedBox(height: 16),
                  for (final key in _settings) _field(key, 'bi_quota_$key'.tr),
                  FilledButton(
                    onPressed: _save,
                    child: Text('bi_quota_save'.tr),
                  ),
                  const Divider(height: 40),
                  Text(
                    'bi_quota_test_grant'.tr,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _field('uid', 'bi_quota_uid'.tr, numeric: false),
                  _field('voice', 'bi_quota_extra_voice'.tr),
                  _field('messages', 'bi_quota_extra_messages'.tr),
                  FilledButton.tonal(
                    onPressed: _grant,
                    child: Text('bi_quota_grant'.tr),
                  ),
                ] else if (settings != null) ...[
                  Text(
                    'bi_quota_voice_remaining'.trParams({
                      'count': '${_status!['voiceRemaining']}',
                    }),
                  ),
                  Text(
                    'bi_quota_messages_remaining'.trParams({
                      'count': '${_status!['messagesRemaining']}',
                    }),
                  ),
                  Text(
                    'bi_quota_minutes_value'.trParams({
                      'count': '${settings['voiceMinutes']}',
                    }),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'bi_quota_prices'.trParams({
                      'voice': '${settings['voicePrice']}',
                      'message': '${settings['messagePrice']}',
                    }),
                  ),
                  const SizedBox(height: 12),
                  Text('bi_quota_payment_later'.tr),
                ],
              ],
            ),
    );
  }
}
