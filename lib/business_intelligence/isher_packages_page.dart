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
      final result = await _functions.httpsCallable(
        widget.admin ? 'getIsherAdminPackages' : 'getIsherPackages',
      ).call();
      final data = Map<String, dynamic>.from(result.data as Map);
      final packages = (data['packages'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      Map<String, dynamic>? paymentSettings;
      List<Map<String, dynamic>> subscriptions = [];
      if (widget.admin) {
        final response = await _functions.httpsCallable('getIsherTestPaymentSettings').call();
        paymentSettings = Map<String, dynamic>.from(
          (response.data as Map)['settings'] as Map,
        );
      } else {
        final businessUid = BusinessAccessService.businessUid.value;
        if (businessUid.isNotEmpty) {
          final response = await _functions.httpsCallable('getIsherTestSubscriptions').call({
            'businessUid': businessUid,
          });
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('bi_quota_saved'.tr)));
      }
    } catch (error, stack) {
      debugPrint('Test payment settings failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('bi_quota_save_error'.tr)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _purchase(Map<String, dynamic> package) async {
    if (_paying) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final businessUid = BusinessAccessService.businessUid.value;
    if (uid == null || !BusinessAccessService.hasBusinessAccess || businessUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('staff_no_permission'.tr)));
      return;
    }
    final pendingKey = 'isher_test_payment_$uid';
    final rawPending = _storage.read<dynamic>(pendingKey);
    final pending = rawPending is Map ? Map<String, dynamic>.from(rawPending) : null;
    if (pending != null &&
        (pending['businessUid'] != businessUid || pending['packageId'] != package['id'])) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('isher_test_pending'.tr)));
      return;
    }
    final reviewed = pending == null
        ? Map<String, dynamic>.from(package)
        : Map<String, dynamic>.from(pending['package'] as Map);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('isher_test_confirm_title'.tr),
        content: Text('isher_test_confirm_body'.trParams({
          'name': '${reviewed['name']}',
          'price': NumberFormat.decimalPattern().format(reviewed['price']),
        })),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('cancel'.tr)),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('isher_test_pay'.trParams({
              'price': NumberFormat.decimalPattern().format(reviewed['price']),
            })),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _paying) return;
    if (FirebaseAuth.instance.currentUser?.uid != uid ||
        BusinessAccessService.businessUid.value != businessUid) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('staff_no_permission'.tr)));
      return;
    }
    setState(() => _paying = true);
    final requestId = pending?['requestId'] as String? ?? const Uuid().v4();
    try {
      await _storage.write(pendingKey, {
        'requestId': requestId, 'businessUid': businessUid,
        'packageId': reviewed['id'], 'package': reviewed,
      });
      final result = await _functions.httpsCallable('purchaseIsherTestPackage').call({
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
          content: Text('isher_test_success_body'.trParams({
            'name': '${reviewed['name']}',
            'status': 'isher_package_status_${record['status']}'.tr,
            'start': DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch(record['startsAt'] as int)),
            'end': DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch(record['endsAt'] as int)),
          })),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
      if (mounted) await _load();
    } on FirebaseFunctionsException catch (error, stack) {
      debugPrint('Test payment failed: ${error.code}');
      debugPrintStack(stackTrace: stack);
      if (['invalid-argument', 'failed-precondition', 'resource-exhausted'].contains(error.code)) {
        await _storage.remove(pendingKey);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.code == 'permission-denied'
              ? 'isher_test_denied'.tr
              : error.code == 'failed-precondition'
              ? 'isher_test_changed'.tr
              : 'isher_test_error'.tr),
        ));
      }
    } catch (error, stack) {
      debugPrint('Test payment failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('isher_test_error'.tr)));
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? existing]) async {
    final keys = ['id', 'name', 'price', 'chats', 'voiceSessions', 'voiceMinutes', 'analyses', 'research', 'credits'];
    final fields = {
      for (final key in keys)
        key: TextEditingController(text: existing?[key]?.toString() ?? ''),
    };
    var enabled = existing?['enabled'] as bool? ?? true;
    final edited = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('isher_package_edit'.tr),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final key in keys)
                  TextField(
                    controller: fields[key],
                    enabled: key != 'id' || existing == null,
                    keyboardType: key == 'id' || key == 'name'
                        ? TextInputType.text
                        : TextInputType.number,
                    decoration: InputDecoration(labelText: 'isher_package_$key'.tr),
                  ),
                SwitchListTile(
                  title: Text('isher_package_enabled'.tr),
                  value: enabled,
                  onChanged: (value) => update(() => enabled = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
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
                if (!RegExp(r'^[a-z0-9_-]{1,48}$').hasMatch(value['id'] as String) ||
                    (value['name'] as String).isEmpty ||
                    (value['name'] as String).length > 80 ||
                    (existing == null && _packages.any((p) => p['id'] == value['id']))) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('bi_quota_invalid'.tr)),
                  );
                  return;
                }
                Navigator.pop(context, value);
              },
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
    final updated = _packages.map((item) => Map<String, dynamic>.from(item)).toList();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('bi_quota_save_error'.tr)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final rawPending = uid == null ? null : _storage.read<dynamic>('isher_test_payment_$uid');
    final pending = rawPending is Map ? Map<String, dynamic>.from(rawPending) : null;
    return Scaffold(
    appBar: AppBar(
      title: Text('isher_packages_title'.tr),
      actions: [
        if (widget.admin)
          IconButton(onPressed: _loading ? null : () => _edit(), icon: const Icon(Icons.add)),
        IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(child: Text(_error!))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.admin) ...[
                SwitchListTile(
                  title: Text('isher_test_mode'.tr),
                  subtitle: Text('isher_test_admin_desc'.tr),
                  value: _testEnabled,
                  onChanged: (value) => setState(() => _testEnabled = value),
                ),
                FilledButton(onPressed: _saveTestSettings, child: Text('bi_quota_save'.tr)),
                const Divider(height: 32),
              ] else ...[
                Text('isher_test_notice'.tr),
                if (pending != null &&
                    pending['businessUid'] == BusinessAccessService.businessUid.value)
                  OutlinedButton(
                    onPressed: _paying
                        ? null
                        : () => _purchase(Map<String, dynamic>.from(pending['package'] as Map)),
                    child: Text('isher_test_retry'.tr),
                  ),
                for (final item in _subscriptions)
                  Card(
                    child: ListTile(
                      title: Text('TEST · ${(item['package'] as Map)['name']} · ${'isher_package_${item['status']}'.tr}'),
                      subtitle: Text(
                        '${'isher_test_period'.trParams({
                          'start': DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch(item['startsAt'] as int)),
                          'end': DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch(item['endsAt'] as int)),
                        })}\n'
                        '${'isher_package_chats_remaining'.tr}: ${item['remainingChats'] ?? '-'}  ·  '
                        '${'isher_package_voice_remaining'.tr}: ${item['remainingVoiceSessions'] ?? '-'}',
                      ),
                      isThreeLine: true,
                    ),
                  ),
              ],
              for (final package in _packages)
                Card(
                  child: ListTile(
                    title: Text('${package['name']}  ·  TZS ${NumberFormat.decimalPattern().format(package['price'])}'),
                    subtitle: Text(
                      '${'isher_package_chats'.tr}: ${package['chats']}  ·  '
                      '${'isher_package_voiceSessions'.tr}: ${package['voiceSessions']}  ·  '
                      '${'isher_package_voiceMinutes'.tr}: ${package['voiceMinutes']}\n'
                      '${'isher_package_analyses'.tr}: ${package['analyses']}  ·  '
                      '${'isher_package_research'.tr}: ${package['research']}'
                      '\n${'isher_package_credits'.tr}: ${package['credits']}'
                      '${widget.admin && package['enabled'] != true ? '\n${'isher_package_disabled'.tr}' : ''}',
                    ),
                    isThreeLine: true,
                    trailing: widget.admin ? const Icon(Icons.edit_outlined) : const Icon(Icons.chevron_right),
                    onTap: widget.admin ? () => _edit(package) : _paying ? null : () => _purchase(package),
                  ),
                ),
            ],
          ),
  );
  }
}
