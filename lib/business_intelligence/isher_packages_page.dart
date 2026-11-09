import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:intl/intl.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:uuid/uuid.dart';

class IsherPackagesPage extends StatefulWidget {
  const IsherPackagesPage({super.key, this.admin = false});

  final bool admin;

  @override
  State<IsherPackagesPage> createState() => _IsherPackagesPageState();
}

class _IsherPackagesPageState extends State<IsherPackagesPage> {
  final _functions = FirebaseFunctions.instance;
  List<Map<String, dynamic>> _packages = [];
  bool _loading = true;
  String? _error;
  int _version = 0;
  final _storage = GetStorage();
  bool _testEnabled = false;
  bool _paying = false;
  List<Map<String, dynamic>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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
            widget.admin ? 'getIsherAdminPackages' : 'getIsherPackages',
          )
          .call();
      final data = Map<String, dynamic>.from(result.data as Map);
      final packages = (data['packages'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      Map<String, dynamic>? paymentSettings;
      List<Map<String, dynamic>> subscriptions = [];
      if (widget.admin) {
        final response = await _functions
            .httpsCallable('getIsherTestPaymentSettings')
            .call();
        paymentSettings = Map<String, dynamic>.from(
          (response.data as Map)['settings'] as Map,
        );
      } else {
        final businessUid = BusinessAccessService.businessUid.value;
        if (businessUid.isNotEmpty) {
          final response = await _functions
              .httpsCallable('getIsherTestSubscriptions')
              .call({'businessUid': businessUid});
          if (BusinessAccessService.businessUid.value != businessUid) {
            throw StateError('Selected business changed.');
          }
          subscriptions = ((response.data as Map)['subscriptions'] as List)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        }
      }
      if (mounted) {
        setState(() {
          _packages = packages;
          if (widget.admin) _version = data['version'] as int;
          if (paymentSettings != null) {
            _testEnabled = paymentSettings['enabled'] == true;
          }
          _subscriptions = subscriptions;
        });
      }
    } catch (error, stack) {
      debugPrint('Isher packages load failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) setState(() => _error = 'isher_packages_error'.tr);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveTestSettings() async {
    setState(() => _loading = true);
    try {
      await _functions.httpsCallable('saveIsherTestPaymentSettings').call({
        'settings': {'enabled': _testEnabled},
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('bi_quota_saved'.tr)));
      }
    } catch (error, stack) {
      debugPrint('Test payment settings failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('bi_quota_save_error'.tr)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _purchase(Map<String, dynamic> package) async {
    if (_paying) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final businessUid = BusinessAccessService.businessUid.value;
    if (uid == null ||
        !BusinessAccessService.hasBusinessAccess ||
        businessUid.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('staff_no_permission'.tr)));
      return;
    }
    final pendingKey = 'isher_test_payment_$uid';
    final rawPending = _storage.read<dynamic>(pendingKey);
    final pending = rawPending is Map
        ? Map<String, dynamic>.from(rawPending)
        : null;
    if (pending != null && pending['businessUid'] != businessUid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('isher_test_pending'.tr)));
      return;
    }
    if (pending != null && pending['packageId'] != package['id']) {
      final pendingRequestId = pending['requestId'];
      if (pendingRequestId is! String ||
          !RegExp(r'^[a-f0-9-]{36}$').hasMatch(pendingRequestId)) {
        await _storage.remove(pendingKey);
      } else {
        try {
          final response = await _functions
              .httpsCallable('getIsherTestPurchaseStatus')
              .call({
                'businessUid': businessUid,
                'requestId': pendingRequestId,
              });
          if (!mounted) return;
          if (FirebaseAuth.instance.currentUser?.uid != uid ||
              BusinessAccessService.businessUid.value != businessUid) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('staff_no_permission'.tr)));
            return;
          }
          final found = (response.data as Map)['found'] == true;
          if (found) {
            await _storage.remove(pendingKey);
            await _load();
            if (!mounted) return;
          } else {
            await _storage.remove(pendingKey);
          }
        } catch (error, stack) {
          debugPrint('Previous Isher package purchase lookup failed: $error');
          debugPrintStack(stackTrace: stack);
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('isher_test_error'.tr)));
          }
          return;
        }
      }
    }
    final reviewed = pending == null
        ? Map<String, dynamic>.from(package)
        : Map<String, dynamic>.from(pending['package'] as Map);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('isher_test_confirm_title'.tr),
        content: Text(
          'isher_test_confirm_body'.trParams({
            'name': '${reviewed['name']}',
            'price': NumberFormat.decimalPattern().format(reviewed['price']),
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'isher_test_pay'.trParams({
                'price': NumberFormat.decimalPattern().format(
                  reviewed['price'],
                ),
              }),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _paying) return;
    if (FirebaseAuth.instance.currentUser?.uid != uid ||
        BusinessAccessService.businessUid.value != businessUid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('staff_no_permission'.tr)));
      return;
    }
    setState(() => _paying = true);
    final requestId = pending?['requestId'] as String? ?? const Uuid().v4();
    try {
      await _storage.write(pendingKey, {
        'requestId': requestId,
        'businessUid': businessUid,
        'packageId': reviewed['id'],
        'package': reviewed,
      });
      final result = await _functions
          .httpsCallable('purchaseIsherTestPackage')
          .call({
            'businessUid': businessUid,
            'packageId': reviewed['id'],
            'expectedPackage': reviewed,
            'requestId': requestId,
          });
      await _storage.remove(pendingKey);
      final record = Map<String, dynamic>.from(result.data as Map);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('isher_test_success'.tr),
          content: Text(
            'isher_test_success_body'.trParams({
              'name': '${reviewed['name']}',
              'status': 'isher_package_status_${record['status']}'.tr,
              'start': DateFormat.yMMMd().format(
                DateTime.fromMillisecondsSinceEpoch(record['startsAt'] as int),
              ),
              'end': DateFormat.yMMMd().format(
                DateTime.fromMillisecondsSinceEpoch(record['endsAt'] as int),
              ),
            }),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) await _load();
    } on FirebaseFunctionsException catch (error, stack) {
      debugPrint('Test payment failed: ${error.code}');
      debugPrintStack(stackTrace: stack);
      if ([
        'invalid-argument',
        'failed-precondition',
        'resource-exhausted',
      ].contains(error.code)) {
        await _storage.remove(pendingKey);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.code == 'permission-denied'
                  ? 'isher_test_denied'.tr
                  : error.code == 'failed-precondition'
                  ? 'isher_test_changed'.tr
                  : 'isher_test_error'.tr,
            ),
          ),
        );
      }
    } catch (error, stack) {
      debugPrint('Test payment failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('isher_test_error'.tr)));
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? existing]) async {
    final keys = [
      'id',
      'name',
      'price',
      'chats',
      'voiceSessions',
      'voiceMinutes',
      'analyses',
      'research',
      'credits',
    ];
    final fields = {
      for (final key in keys)
        key: TextEditingController(text: existing?[key]?.toString() ?? ''),
    };
    var enabled = existing?['enabled'] as bool? ?? true;
    final edited = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          backgroundColor: const Color(0xFF171627),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFF514477)),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B2D67),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFFD8CCFF),
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  'isher_package_edit'.tr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final key in keys)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 11),
                      child: TextField(
                        controller: fields[key],
                        enabled: key != 'id' || existing == null,
                        style: const TextStyle(color: Colors.white),
                        cursorColor: const Color(0xFFC1AFFF),
                        keyboardType: key == 'id' || key == 'name'
                            ? TextInputType.text
                            : TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'isher_package_$key'.tr,
                          labelStyle: const TextStyle(color: Color(0xFFB8B3D0)),
                          filled: true,
                          fillColor: const Color(0xFF11111E),
                          prefixIcon: Icon(
                            key == 'name'
                                ? Icons.sell_outlined
                                : key == 'id'
                                ? Icons.tag_rounded
                                : Icons.tune_rounded,
                            color: const Color(0xFFB9A4FF),
                            size: 19,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFF383254),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFF383254),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFF9B7BFF),
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF211F34),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF393550)),
                    ),
                    child: SwitchListTile(
                      title: Text(
                        'isher_package_enabled'.tr,
                        style: const TextStyle(color: Colors.white),
                      ),
                      value: enabled,
                      activeThumbColor: const Color(0xFFB9A4FF),
                      onChanged: (value) => update(() => enabled = value),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFCAC5D9),
              ),
              child: Text('cancel'.tr),
            ),
            FilledButton(
              onPressed: () {
                final value = <String, dynamic>{
                  'id': fields['id']!.text.trim(),
                  'name': fields['name']!.text.trim(),
                  'enabled': enabled,
                };
                for (final key in keys.skip(2)) {
                  final number = int.tryParse(fields[key]!.text.trim());
                  if (number == null || number < 0 || number > 100000000) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('bi_quota_invalid'.tr)),
                    );
                    return;
                  }
                  value[key] = number;
                }
                if (!RegExp(
                      r'^[a-z0-9_-]{1,48}$',
                    ).hasMatch(value['id'] as String) ||
                    (value['name'] as String).isEmpty ||
                    (value['name'] as String).length > 80 ||
                    (existing == null &&
                        _packages.any((p) => p['id'] == value['id']))) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('bi_quota_invalid'.tr)),
                  );
                  return;
                }
                Navigator.pop(context, value);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7656D6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: Text('bi_quota_save'.tr),
            ),
          ],
        ),
      ),
    );
    for (final field in fields.values) {
      field.dispose();
    }
    if (edited == null || !mounted) return;
    final updated = _packages
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final index = updated.indexWhere((item) => item['id'] == edited['id']);
    if (index < 0) {
      updated.add(edited);
    } else {
      updated[index] = edited;
    }
    setState(() => _loading = true);
    try {
      await _functions.httpsCallable('saveIsherAdminPackages').call({
        'packages': updated,
        'version': _version,
      });
      if (mounted) await _load();
    } catch (error, stack) {
      debugPrint('Isher packages save failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('bi_quota_save_error'.tr)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final rawPending = uid == null
        ? null
        : _storage.read<dynamic>('isher_test_payment_$uid');
    final pending = rawPending is Map
        ? Map<String, dynamic>.from(rawPending)
        : null;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B16),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text('isher_packages_title'.tr),
        actions: [
          if (widget.admin)
            IconButton(
              tooltip: 'isher_package_edit'.tr,
              onPressed: _loading ? null : () => _edit(),
              icon: const Icon(Icons.add_rounded),
            ),
          IconButton(
            tooltip: 'refresh'.tr,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
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
                  top: -90,
                  right: -100,
                  child: Container(
                    width: 280,
                    height: 280,
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
                    _heroHeader(),
                    const SizedBox(height: 18),
                    if (widget.admin) ...[
                      _sectionPanel(
                        icon: Icons.science_outlined,
                        title: 'isher_test_mode'.tr,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'isher_test_mode'.tr,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              'isher_test_admin_desc'.tr,
                              style: const TextStyle(color: Color(0xFFB8B3D0)),
                            ),
                            value: _testEnabled,
                            activeThumbColor: const Color(0xFFB9A4FF),
                            onChanged: (value) =>
                                setState(() => _testEnabled = value),
                          ),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _saveTestSettings,
                              icon: const Icon(Icons.save_rounded),
                              label: Text('bi_quota_save'.tr),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      if (pending != null &&
                          pending['businessUid'] ==
                              BusinessAccessService.businessUid.value)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: OutlinedButton.icon(
                            onPressed: _paying
                                ? null
                                : () => _purchase(
                                    Map<String, dynamic>.from(
                                      pending['package'] as Map,
                                    ),
                                  ),
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text('isher_test_retry'.tr),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFE2D9FF),
                              side: const BorderSide(color: Color(0xFF62518B)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                          ),
                        ),
                      if (_subscriptions.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _sectionHeading(
                          'isher_test_period'.tr,
                          Icons.receipt_long_rounded,
                        ),
                        const SizedBox(height: 10),
                        for (final item in _subscriptions)
                          _subscriptionTile(item),
                      ],
                    ],
                    const SizedBox(height: 22),
                    _sectionHeading(
                      'isher_packages_title'.tr,
                      Icons.auto_awesome_rounded,
                    ),
                    const SizedBox(height: 12),
                    if (_packages.isEmpty)
                      _noticeCard('isher_packages_error'.tr)
                    else
                      for (final package in _packages) _packageCard(package),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _heroHeader() => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF49337A), Color(0xFF27234E), Color(0xFF19172F)],
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
          top: -20,
          child: Icon(
            Icons.auto_awesome_rounded,
            size: 104,
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
                Icons.rocket_launch_rounded,
                color: Color(0xFFE0D4FF),
                size: 24,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'isher_packages_title'.tr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w800,
                letterSpacing: -.4,
              ),
            ),
            if (!widget.admin) ...[
              const SizedBox(height: 7),
              Text(
                'isher_test_notice'.tr,
                style: const TextStyle(
                  color: Color(0xFFD2CDE6),
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );

  Widget _sectionHeading(String title, IconData icon) => Row(
    children: [
      Icon(icon, color: const Color(0xFFC1AFFF), size: 20),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      if (!widget.admin)
        Text(
          '${_packages.length}',
          style: const TextStyle(
            color: Color(0xFF9A91B5),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
    ],
  );

  Widget _noticeCard(String message) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: const Color(0xFF171627),
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: const Color(0xFF34314A)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          color: Color(0xFFB9A4FF),
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: Color(0xFFD0CCDF),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _subscriptionTile(Map<String, dynamic> item) {
    final package = Map<String, dynamic>.from(item['package'] as Map);
    final status = item['status']?.toString() ?? '';
    final starts = DateFormat.yMMMd().format(
      DateTime.fromMillisecondsSinceEpoch(item['startsAt'] as int),
    );
    final ends = DateFormat.yMMMd().format(
      DateTime.fromMillisecondsSinceEpoch(item['endsAt'] as int),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF25223A), Color(0xFF191827)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF3B3655)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.workspace_premium_outlined,
                color: Color(0xFFC1AFFF),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'TEST · ${package['name']}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _statusPill('isher_package_$status'.tr, status),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'isher_test_period'.trParams({'start': starts, 'end': ends}),
            style: const TextStyle(color: Color(0xFFB8B3D0), fontSize: 12),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _inlineMetric(
                Icons.chat_bubble_outline_rounded,
                'isher_package_chats_remaining'.tr,
                item['remainingChats']?.toString() ?? '-',
              ),
              _inlineMetric(
                Icons.graphic_eq_rounded,
                'isher_package_voice_remaining'.tr,
                item['remainingVoiceSessions']?.toString() ?? '-',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _packageCard(Map<String, dynamic> package) {
    final enabled = package['enabled'] != false;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF25213A), Color(0xFF171625), Color(0xFF12121F)],
        ),
        border: Border.all(
          color: enabled ? const Color(0xFF474064) : const Color(0xFF393545),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x30272051),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: InkWell(
        onTap: widget.admin
            ? () => _edit(package)
            : !enabled || _paying
            ? null
            : () => _purchase(package),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8162E8), Color(0xFF4F55B7)],
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          package['name']?.toString() ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (!enabled)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: _statusPill(
                              'isher_package_disabled'.tr,
                              'disabled',
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.admin)
                    const Icon(
                      Icons.edit_outlined,
                      color: Color(0xFFB9A4FF),
                      size: 20,
                    )
                  else
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: Color(0xFFC1AFFF),
                      size: 20,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'TZS ${NumberFormat.decimalPattern().format(package['price'])}',
                style: const TextStyle(
                  color: Color(0xFFD8CCFF),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.4,
                ),
              ),
              const SizedBox(height: 15),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _packageFeature(
                    Icons.chat_bubble_outline_rounded,
                    'isher_package_chats'.tr,
                    package['chats'],
                  ),
                  _packageFeature(
                    Icons.graphic_eq_rounded,
                    'isher_package_voiceSessions'.tr,
                    package['voiceSessions'],
                  ),
                  _packageFeature(
                    Icons.timelapse_rounded,
                    'isher_package_voiceMinutes'.tr,
                    package['voiceMinutes'],
                  ),
                  _packageFeature(
                    Icons.analytics_outlined,
                    'isher_package_analyses'.tr,
                    package['analyses'],
                  ),
                  _packageFeature(
                    Icons.travel_explore_rounded,
                    'isher_package_research'.tr,
                    package['research'],
                  ),
                  _packageFeature(
                    Icons.stars_rounded,
                    'isher_package_credits'.tr,
                    package['credits'],
                  ),
                ],
              ),
              if (!widget.admin) ...[
                const SizedBox(height: 17),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: !enabled || _paying
                        ? null
                        : () => _purchase(package),
                    icon: Icon(
                      _paying
                          ? Icons.hourglass_top_rounded
                          : Icons.bolt_rounded,
                    ),
                    label: Text(
                      _paying
                          ? 'isher_test_pending'.tr
                          : 'isher_test_pay'.trParams({
                              'price': NumberFormat.decimalPattern().format(
                                package['price'],
                              ),
                            }),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7656D6),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF39324E),
                      disabledForegroundColor: const Color(0xFFAAA4BC),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _packageFeature(IconData icon, String label, dynamic value) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF211F34),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF393550)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFFB9A4FF), size: 15),
            const SizedBox(width: 6),
            Text(
              '$value $label',
              style: const TextStyle(
                color: Color(0xFFD0CCDF),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  Widget _inlineMetric(IconData icon, String label, String value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: const Color(0xFFB9A4FF)),
      const SizedBox(width: 5),
      Text(
        '$label: $value',
        style: const TextStyle(color: Color(0xFFCAC5D9), fontSize: 11),
      ),
    ],
  );

  Widget _statusPill(String label, String status) {
    final active = status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF173B36) : const Color(0xFF393044),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active ? const Color(0xFF286653) : const Color(0xFF544565),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? const Color(0xFF8BF0C2) : const Color(0xFFD3C0E5),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _sectionPanel({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: const Color(0xFF141321),
      borderRadius: BorderRadius.circular(21),
      border: Border.all(color: const Color(0xFF34314A)),
    ),
    child: Column(
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
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );
}
