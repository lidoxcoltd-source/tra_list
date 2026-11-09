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
      style: const TextStyle(color: Colors.white),
      cursorColor: const Color(0xFFC1AFFF),
      onChanged: key == 'uid' || key == 'voice' || key == 'messages'
          ? (_) => _pendingGrantId = null
          : null,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFFB8B3D0)),
        filled: true,
        fillColor: const Color(0xFF17152A),
        prefixIcon: Icon(
          numeric ? Icons.tune_rounded : Icons.badge_outlined,
          color: const Color(0xFFB9A4FF),
          size: 19,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFF383254)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFF383254)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFF9B7BFF), width: 1.4),
        ),
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

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF282044), Color(0xFF17172D), Color(0xFF121222)],
        ),
        border: Border.all(color: const Color(0xFF514477)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x443E2B80),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: const Color(0xFF3B2D67),
                  foregroundColor: const Color(0xFFD8CCFF),
                  child: const Icon(Icons.auto_awesome_rounded, size: 24),
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
                          color: Colors.white,
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
                          color: const Color(0xFFB8B3D0),
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasActivePackage)
                  Chip(
                    label: Text(statusLabel),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: const Color(0xFF173B36),
                    labelStyle: const TextStyle(
                      color: Color(0xFF8BF0C2),
                      fontWeight: FontWeight.w700,
                    ),
                    side: const BorderSide(color: Color(0xFF286653)),
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
                    color: const Color(0xFFB8B3D0),
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
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFD8D5E5),
                ),
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await Get.to(() => const IsherPackagesPage());
                  if (mounted) await _load();
                },
                icon: const Icon(Icons.rocket_launch_rounded),
                label: Text('isher_packages_title'.tr),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7656D6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF282441), Color(0xFF1E1C34)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF393354)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFC1AFFF), size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFFB8B3D0),
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 3),
            Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF8E89A7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _heroHeader(String description) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF49337A), Color(0xFF27234E), Color(0xFF1B1A34)],
      ),
      border: Border.all(color: const Color(0xFF69569B)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x443D2B7E),
          blurRadius: 26,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Stack(
      children: [
        Positioned(
          right: -8,
          top: -18,
          child: Icon(
            Icons.auto_awesome_rounded,
            size: 100,
            color: Colors.white.withValues(alpha: .07),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white.withValues(alpha: .14)),
              ),
              child: const Icon(
                Icons.bolt_rounded,
                color: Color(0xFFE0D4FF),
                size: 24,
              ),
            ),
            const SizedBox(height: 17),
            Text(
              (widget.admin ? 'bi_quota_admin_title' : 'bi_quota_title').tr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w800,
                letterSpacing: -.4,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              description,
              style: const TextStyle(
                color: Color(0xFFD2CDE6),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final settings = _status?['settings'] as Map?;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B16),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
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
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFB9A4FF),
                strokeWidth: 2.5,
              ),
            )
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFFFB4AB)),
                ),
              ),
            )
          : Stack(
              children: [
                Positioned(
                  top: 0,
                  right: -100,
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0x332D63D8), Color(0x000B0B16)],
                      ),
                    ),
                  ),
                ),
                ListView(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
                  children: [
                    _heroHeader(
                      widget.admin
                          ? 'bi_quota_explanation'.tr
                          : 'bi_quota_package_explanation'.tr,
                    ),
                    const SizedBox(height: 20),
                    if (widget.admin) ...[
                      _adminAction(
                        icon: Icons.workspace_premium_outlined,
                        title: 'isher_packages_title'.tr,
                        onPressed: () =>
                            Get.to(() => const IsherPackagesPage(admin: true)),
                      ),
                      _adminAction(
                        icon: Icons.record_voice_over_outlined,
                        title: 'isher_language_title'.tr,
                        onPressed: () =>
                            Get.to(() => const IsherVoiceLanguagePage()),
                      ),
                      _adminAction(
                        icon: Icons.tune_rounded,
                        title: 'bi_models_admin_title'.tr,
                        onPressed: () => Get.to(
                          () => const AiModelsAdminPage(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _sectionPanel(
                        title: 'bi_quota_admin_title'.tr,
                        icon: Icons.settings_suggest_rounded,
                        children: [
                          for (final key in _settings)
                            _field(key, 'bi_quota_$key'.tr),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _save,
                              icon: const Icon(Icons.save_rounded),
                              label: Text('bi_quota_save'.tr),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _sectionPanel(
                        title: 'bi_quota_test_grant'.tr,
                        icon: Icons.card_giftcard_rounded,
                        children: [
                          _field('uid', 'bi_quota_uid'.tr, numeric: false),
                          _field('voice', 'bi_quota_extra_voice'.tr),
                          _field('messages', 'bi_quota_extra_messages'.tr),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonalIcon(
                              onPressed: _grant,
                              icon: const Icon(Icons.add_circle_outline),
                              label: Text('bi_quota_grant'.tr),
                            ),
                          ),
                        ],
                      ),
                    ] else if (settings != null) ...[
                      _subscriptionCard(
                        _status!['subscription'] as Map<String, dynamic>?,
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF171627),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFF34314A)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.speed_rounded,
                              color: Color(0xFFB9A4FF),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'bi_quota_daily_limits'.trParams({
                                  'messages': '${settings['dailyMessages']}',
                                  'voice': '${settings['dailyVoice']}',
                                }),
                                style: const TextStyle(
                                  color: Color(0xFFD0CCDF),
                                  fontSize: 12,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
    );
  }

  Widget _adminAction({
    required IconData icon,
    required String title,
    required VoidCallback onPressed,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(title),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          foregroundColor: const Color(0xFFE4DEFF),
          side: const BorderSide(color: Color(0xFF40395E)),
          backgroundColor: const Color(0xFF171627),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    ),
  );

  Widget _sectionPanel({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFF141321),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFF34314A)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFFC1AFFF), size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
}
