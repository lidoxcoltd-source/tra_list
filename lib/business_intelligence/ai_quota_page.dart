import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:tra_list/business_intelligence/ai_models_admin_page.dart';
import 'package:tra_list/business_intelligence/isher_voice_language_page.dart';
import 'package:tra_list/business_intelligence/isher_packages_page.dart';
import 'package:tra_list/services/business_access_service.dart';

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
      if (!widget.admin) {
        final businessUid = BusinessAccessService.businessUid.value;
        if (businessUid.isNotEmpty) {
          final response = await _functions
              .httpsCallable('getIsherTestSubscriptions')
              .call({'businessUid': businessUid});
          if (BusinessAccessService.businessUid.value != businessUid) {
            throw StateError('Selected business changed.');
          }
          final subscriptions =
              ((response.data as Map)['subscriptions'] as List)
                  .map((item) => Map<String, dynamic>.from(item as Map))
                  .toList();
          final active = subscriptions.where(
            (item) => item['status'] == 'active',
          );
          status['subscription'] = active.isNotEmpty
              ? active.first
              : subscriptions.isNotEmpty
              ? subscriptions.first
              : null;
          status['businessName'] = BusinessAccessService.businessName.value;
        }
      }
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

  Widget _subscriptionCard(Map<String, dynamic>? subscription) {
    final theme = Theme.of(context);
    final package = subscription?['package'] is Map
        ? Map<String, dynamic>.from(subscription!['package'] as Map)
        : null;
    final businessName = (_status?['businessName'] as String?)?.trim() ?? '';
    final status = subscription?['status']?.toString() ?? '';
    final hasActivePackage = status == 'active' && package != null;
    final remainingChats = subscription?['remainingChats'] as int? ?? 0;
    final remainingVoiceSessions =
        subscription?['remainingVoiceSessions'] as int? ?? 0;
    final maxMinutesPerCall = package?['voiceMinutes'] as int? ?? 0;
    final remainingVoiceMinutes = remainingVoiceSessions * maxMinutesPerCall;
    final packageName = package?['name']?.toString() ?? '';
    final statusLabel = status.isEmpty
        ? 'bi_quota_no_package'.tr
        : 'isher_package_$status'.tr;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.primary,
                  child: const Icon(Icons.auto_awesome_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        businessName.isEmpty
                            ? 'bi_quota_business'.tr
                            : 'bi_quota_business_greeting'.trParams({
                                'name': businessName,
                              }),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasActivePackage
                            ? packageName
                            : packageName.isNotEmpty
                            ? '$packageName · $statusLabel'
                            : statusLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasActivePackage)
                  Chip(
                    label: Text(statusLabel),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (hasActivePackage) ...[
              Row(
                children: [
                  Expanded(
                    child: _quotaMetric(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: 'bi_quota_package_chats'.tr,
                      value: '$remainingChats',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _quotaMetric(
                      icon: Icons.graphic_eq_rounded,
                      label: 'bi_quota_package_voice'.tr,
                      value: '$remainingVoiceMinutes',
                      detail: 'bi_quota_voice_calls_left'.trParams({
                        'count': '$remainingVoiceSessions',
                      }),
                    ),
                  ),
                ],
              ),
              if (maxMinutesPerCall > 0) ...[
                const SizedBox(height: 12),
                Text(
                  'bi_quota_voice_duration_note'.trParams({
                    'minutes': '$maxMinutesPerCall',
                  }),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ] else
              Text(
                status == 'queued'
                    ? 'bi_quota_waiting_package'.tr
                    : subscription == null
                    ? 'bi_quota_no_active_package'.tr
                    : 'bi_quota_inactive_package'.tr,
                style: theme.textTheme.bodyMedium,
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Get.to(() => const IsherPackagesPage());
                  if (mounted) await _load();
                },
                icon: const Icon(Icons.workspace_premium_outlined),
                label: Text('isher_packages_title'.tr),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quotaMetric({
    required IconData icon,
    required String label,
    required String value,
    String? detail,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(label, style: theme.textTheme.bodySmall),
          if (detail != null) ...[
            const SizedBox(height: 3),
            Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

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
                Text(
                  widget.admin
                      ? 'bi_quota_explanation'.tr
                      : 'bi_quota_package_explanation'.tr,
                ),
                const SizedBox(height: 16),
                if (widget.admin) ...[
                  OutlinedButton.icon(
                    onPressed: () =>
                        Get.to(() => const IsherPackagesPage(admin: true)),
                    icon: const Icon(Icons.workspace_premium_outlined),
                    label: Text('isher_packages_title'.tr),
                  ),
                  const SizedBox(height: 16),
                ],
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
                  _subscriptionCard(
                    _status!['subscription'] as Map<String, dynamic>?,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'bi_quota_daily_limits'.trParams({
                      'messages': '${settings['dailyMessages']}',
                      'voice': '${settings['dailyVoice']}',
                    }),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
