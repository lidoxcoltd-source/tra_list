import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:tra_list/invoice/transaction_model.dart';
import 'package:tra_list/invoice/transaction_service.dart';
import 'business_access_service.dart';
import 'profile_service.dart';
import 'staff_service.dart';

class StaffManagementPage extends StatelessWidget {
  const StaffManagementPage({super.key});

  static const _ink = Color(0xFF19313A);
  static const _muted = Color(0xFF75838A);
  static const _brand = Color(0xFF0E5962);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F8),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          onPressed: Get.back,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text('staff_title'.tr),
        backgroundColor: const Color(0xFFF5F7F8),
        foregroundColor: _ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: StaffService.watchStaff(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _messageState(
                  icon: Icons.error_outline_rounded,
                  message: '${'staff_load_error'.tr}\n${snapshot.error}',
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: _brand),
                );
              }

              final staff = snapshot.data?.docs ?? [];
              final activeCount = staff
                  .where((member) => member.data()['active'] == true)
                  .length;
              final removedCount = staff
                  .where((member) => member.data()['removed'] == true)
                  .length;
              final disabledCount = staff
                  .where(
                    (member) =>
                        member.data()['active'] != true &&
                        member.data()['removed'] != true,
                  )
                  .length;
              if (staff.isEmpty) {
                return _messageState(
                  icon: Icons.groups_2_outlined,
                  message: 'staff_empty'.tr,
                  action: FilledButton.icon(
                    onPressed: () => _showStaffDialog(context),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: Text('staff_add'.tr),
                  ),
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEAF4F3), Colors.white],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFDCE9E8)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5F0F0),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.groups_2_rounded,
                            color: _brand,
                            size: 27,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'staff_subtitle'.tr,
                                style: const TextStyle(
                                  color: _ink,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'staff_management_hint'.tr,
                                style: const TextStyle(color: _muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _staffStat(
                        label: 'staff_total'.tr,
                        count: staff.length,
                        color: _brand,
                        icon: Icons.people_alt_outlined,
                      ),
                      _staffStat(
                        label: 'staff_active'.tr,
                        count: activeCount,
                        color: const Color(0xFF237A52),
                        icon: Icons.check_circle_outline_rounded,
                      ),
                      _staffStat(
                        label: 'staff_disabled'.tr,
                        count: disabledCount,
                        color: const Color(0xFFB64D4D),
                        icon: Icons.pause_circle_outline_rounded,
                      ),
                      if (removedCount > 0)
                        _staffStat(
                          label: 'staff_removed'.tr,
                          count: removedCount,
                          color: const Color(0xFF7C657F),
                          icon: Icons.person_off_outlined,
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _StaffInsights(
                    staff: staff,
                    cardBuilder: (member, perf, rank) => _staffCard(
                      context,
                      member.data(),
                      member.id,
                      perf: perf,
                      rank: rank,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showStaffDialog(context),
        backgroundColor: _brand,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text('staff_add'.tr),
      ),
    );
  }

  Widget _staffStat({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5EAEC)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _messageState({
    required IconData icon,
    required String message,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: _brand),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, height: 1.4),
            ),
            if (action != null) ...[const SizedBox(height: 18), action],
          ],
        ),
      ),
    );
  }

  Widget _staffCard(
    BuildContext context,
    Map<String, dynamic> data,
    String employeeUid, {
    _Perf? perf,
    int? rank,
  }) {
    final active = data['active'] == true;
    final removed = data['removed'] == true;
    final name = data['name']?.toString() ?? '';
    final email = data['email']?.toString() ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5EAEC)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: active
                      ? const Color(0xFFE5F0F0)
                      : const Color(0xFFF0F2F3),
                  child: Text(
                    name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                    style: const TextStyle(
                      color: _brand,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (rank != null) ...[
                  const SizedBox(height: 6),
                  _rankBadge(rank),
                ],
              ],
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _statusBadge(active: active, removed: removed),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    email.isEmpty ? 'staff_email_not_added'.tr : email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  if ((data['shopNickname']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${'staff_shop_nickname'.tr}: ${data['shopNickname']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                  if ((data['phone']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      data['phone'].toString(),
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                  if (perf != null) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _perfChip(
                          Icons.south_west_rounded,
                          _money(perf.income),
                          const Color(0xFF237A52),
                          const Color(0xFFEAF5EF),
                        ),
                        _perfChip(
                          Icons.north_east_rounded,
                          _money(perf.expense),
                          const Color(0xFFB64D4D),
                          const Color(0xFFFAEEEE),
                        ),
                        _perfChip(
                          Icons.receipt_long_outlined,
                          '${perf.count}',
                          _brand,
                          const Color(0xFFE5F0F0),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 7),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'permissions') {
                  _showStaffDialog(
                    context,
                    employeeUid: employeeUid,
                    memberData: data,
                  );
                } else if (value == 'password') {
                  _changeStaffPassword(context, employeeUid);
                } else if (value == 'remove') {
                  _confirmRemoveStaff(context, employeeUid, name);
                } else {
                  _changeActive(employeeUid, !active);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'permissions',
                  child: Text('staff_edit'.tr),
                ),
                PopupMenuItem(
                  value: 'active',
                  child: Text(active ? 'staff_disable'.tr : 'staff_enable'.tr),
                ),
                if (!removed)
                  PopupMenuItem(
                    value: 'password',
                    child: Text('staff_change_password'.tr),
                  ),
                if (!removed)
                  PopupMenuItem(
                    value: 'remove',
                    child: Text(
                      'staff_remove'.tr,
                      style: const TextStyle(color: Color(0xFFB64D4D)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _money(double v) => NumberFormat('#,##0').format(v);

  static Widget _perfChip(IconData icon, String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  static Color _rankColor(int rank) => switch (rank) {
    1 => const Color(0xFFD4A017),
    2 => const Color(0xFF8A99A3),
    3 => const Color(0xFFB87333),
    _ => const Color(0xFF9AA8AF),
  };

  static Widget _rankBadge(int rank) {
    final color = _rankColor(rank);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '#$rank',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _statusBadge({required bool active, required bool removed}) {
    final color = removed
        ? const Color(0xFF7C657F)
        : active
        ? const Color(0xFF237A52)
        : const Color(0xFFB64D4D);
    final backgroundColor = removed
        ? const Color(0xFFF1ECF2)
        : active
        ? const Color(0xFFEAF5EF)
        : const Color(0xFFFAEEEE);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        removed
            ? 'staff_removed'.tr
            : active
            ? 'staff_active'.tr
            : 'staff_disabled'.tr,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _changeActive(String employeeUid, bool active) async {
    try {
      await StaffService.setActive(employeeUid, active);
      Get.snackbar(
        'success'.tr,
        active ? 'staff_enabled_success'.tr : 'staff_disabled_success'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (error, stackTrace) {
      debugPrint('Could not update staff status: $error');
      debugPrintStack(stackTrace: stackTrace);
      Get.snackbar('error'.tr, '${'staff_update_error'.tr}: $error');
    }
  }

  Future<void> _changeStaffPassword(
    BuildContext context,
    String employeeUid,
  ) async {
    final password = await Get.dialog<String>(
      const _StaffPasswordDialog(),
      barrierDismissible: false,
    );
    if (password == null || !context.mounted) return;

    try {
      await StaffService.updateStaffPassword(
        employeeUid: employeeUid,
        password: password,
      );
      Get.snackbar(
        'success'.tr,
        'staff_password_change_success'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (error, stackTrace) {
      debugPrint('Could not change staff password: $error');
      debugPrintStack(stackTrace: stackTrace);
      Get.snackbar('error'.tr, '${'staff_password_change_error'.tr}: $error');
    }
  }

  Future<void> _confirmRemoveStaff(
    BuildContext context,
    String employeeUid,
    String name,
  ) async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        icon: const Icon(
          Icons.person_off_outlined,
          color: Color(0xFFB64D4D),
          size: 30,
        ),
        title: Text('staff_remove_title'.tr),
        content: Text(
          'staff_remove_message'.trParams({'name': name}),
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back<bool>(result: false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB64D4D),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Get.back<bool>(result: true),
            child: Text('staff_remove'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await StaffService.removeStaff(employeeUid);
      Get.snackbar(
        'success'.tr,
        'staff_removed_success'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (error, stackTrace) {
      debugPrint('Could not remove staff access: $error');
      debugPrintStack(stackTrace: stackTrace);
      Get.snackbar('error'.tr, '${'staff_update_error'.tr}: $error');
    }
  }

  Future<void> _showStaffDialog(
    BuildContext context, {
    String? employeeUid,
    Map<String, dynamic>? memberData,
  }) async {
    final isEditing = employeeUid != null;
    final saved = await Get.dialog<bool>(
      _StaffEditorDialog(employeeUid: employeeUid, memberData: memberData),
      barrierDismissible: false,
    );
    if (saved == true) {
      Get.snackbar(
        'success'.tr,
        isEditing ? 'staff_permissions_saved'.tr : 'staff_created_success'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }
}

class _Perf {
  double income = 0;
  double expense = 0;
  int count = 0;
}

enum _Range { today, yesterday, week, month }

class _StaffInsights extends StatefulWidget {
  const _StaffInsights({required this.staff, required this.cardBuilder});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> staff;
  final Widget Function(
    QueryDocumentSnapshot<Map<String, dynamic>> member,
    _Perf perf,
    int? rank,
  )
  cardBuilder;

  @override
  State<_StaffInsights> createState() => _StaffInsightsState();
}

class _StaffInsightsState extends State<_StaffInsights> {
  static const _ink = Color(0xFF19313A);
  static const _muted = Color(0xFF75838A);
  static const _brand = Color(0xFF0E5962);

  _Range _range = _Range.month;
  Map<String, _Perf> _perf = {};
  bool _loading = true;
  bool _failed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _label(_Range r) => switch (r) {
    _Range.today => 'transactions_today'.tr,
    _Range.yesterday => 'yesterday'.tr,
    _Range.week => 'transactions_this_week'.tr,
    _Range.month => 'transactions_this_month'.tr,
  };

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final (start, end) = switch (_range) {
      _Range.today => (today, today.add(const Duration(days: 1))),
      _Range.yesterday => (today.subtract(const Duration(days: 1)), today),
      _Range.week => (
        today.subtract(Duration(days: now.weekday - 1)),
        today
            .subtract(Duration(days: now.weekday - 1))
            .add(const Duration(days: 7)),
      ),
      _Range.month => (
        DateTime(now.year, now.month, 1),
        DateTime(now.year, now.month + 1, 1),
      ),
    };
    try {
      final snap = await TransactionService.getTransactions(
        limit: 2000,
        startDate: start,
        endDate: end,
      );
      final result = <String, _Perf>{};
      for (final doc in snap.docs) {
        final t = doc.data();
        final p = result.putIfAbsent(t.uid, _Perf.new);
        p.count++;
        if (t.type == TransactionType.income) {
          p.income += t.amount;
        } else {
          p.expense += t.amount;
        }
      }
      if (!mounted || request != _request) return;
      setState(() {
        _perf = result;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Could not load staff performance: $error');
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = [...widget.staff]
      ..sort((a, b) {
        final ra = a.data()['removed'] == true ? 1 : 0;
        final rb = b.data()['removed'] == true ? 1 : 0;
        if (ra != rb) return ra.compareTo(rb);
        final ia = _perf[a.id]?.income ?? 0;
        final ib = _perf[b.id]?.income ?? 0;
        return ib.compareTo(ia);
      });
    final ranked = members.where((m) => m.data()['removed'] != true).toList();
    final ownerPerf = _perf[BusinessAccessService.businessId];
    final teamIncome = _perf.values.fold<double>(0, (s, p) => s + p.income);
    final teamExpense = _perf.values.fold<double>(0, (s, p) => s + p.expense);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final r in _Range.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_label(r)),
                    selected: _range == r,
                    selectedColor: _brand,
                    labelStyle: TextStyle(
                      color: _range == r ? Colors.white : _ink,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    showCheckmark: false,
                    onSelected: (_) {
                      if (_range == r) return;
                      _range = r;
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _brand,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              _teamStat('income'.tr, teamIncome, const Color(0xFF6EE7B7)),
              _teamStat('expenses'.tr, teamExpense, const Color(0xFFFCA5A5)),
              _teamStat('net'.tr, teamIncome - teamExpense, Colors.white),
            ],
          ),
        ),
        if (ownerPerf != null) ...[
          const SizedBox(height: 8),
          Text(
            '${'hs_owner'.tr}: ${StaffManagementPage._money(ownerPerf.income)} · ${ownerPerf.count}',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ],
        const SizedBox(height: 14),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: _brand)),
          )
        else if (_failed)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'staff_load_error'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted),
            ),
          )
        else ...[
          if (ranked.where((m) => (_perf[m.id]?.income ?? 0) > 0).isNotEmpty)
            _podium(ranked),
          for (final m in members)
            widget.cardBuilder(
              m,
              _perf[m.id] ?? _Perf(),
              m.data()['removed'] == true ? null : ranked.indexOf(m) + 1,
            ),
        ],
      ],
    );
  }

  Widget _teamStat(String label, double value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              StaffManagementPage._money(value),
              style: TextStyle(
                color: color,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _podium(List<QueryDocumentSnapshot<Map<String, dynamic>>> ranked) {
    final top = ranked
        .where((m) => (_perf[m.id]?.income ?? 0) > 0)
        .take(3)
        .toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5EAEC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: Color(0xFFD4A017),
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                'staff_top'.tr,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < top.length; i++)
                Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: i == top.length - 1 ? 0 : 8),
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 6,
                    ),
                    decoration: BoxDecoration(
                      color: StaffManagementPage._rankColor(
                        i + 1,
                      ).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        StaffManagementPage._rankBadge(i + 1),
                        const SizedBox(height: 6),
                        Text(
                          top[i].data()['name']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            StaffManagementPage._money(
                              _perf[top[i].id]!.income,
                            ),
                            style: const TextStyle(
                              color: Color(0xFF237A52),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StaffPasswordDialog extends StatefulWidget {
  const _StaffPasswordDialog();

  @override
  State<_StaffPasswordDialog> createState() => _StaffPasswordDialogState();
}

class _StaffPasswordDialogState extends State<_StaffPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _showPassword = false;
  bool _showConfirmation = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  int get _strength {
    final password = _passwordController.text;
    if (password.isEmpty) return 0;

    var score = password.length >= 6 ? 1 : 0;
    if (password.length >= 10) score++;
    if (RegExp(r'[a-z]').hasMatch(password) &&
        RegExp(r'[A-Z]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'\d').hasMatch(password)) score++;
    if (RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) score++;
    return score;
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_passwordController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF4F3),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.lock_reset_rounded,
          color: StaffManagementPage._brand,
          size: 28,
        ),
      ),
      title: Text(
        'staff_change_password_title'.tr,
        textAlign: TextAlign.center,
      ),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F7F7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 19,
                        color: StaffManagementPage._brand,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'staff_change_password_message'.tr,
                          style: const TextStyle(height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _passwordController,
                  autofocus: true,
                  obscureText: !_showPassword,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'staff_new_password'.tr,
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: _showPassword
                          ? 'staff_hide_password'.tr
                          : 'staff_show_password'.tr,
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'staff_password_required'.tr;
                    }
                    if (value.length < 6) return 'staff_password_minimum'.tr;
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                _passwordStrengthIndicator(),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: !_showConfirmation,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'staff_confirm_new_password'.tr,
                    prefixIcon: const Icon(Icons.verified_user_outlined),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_confirmPasswordController.text.isNotEmpty)
                          Icon(
                            _confirmPasswordController.text ==
                                    _passwordController.text
                                ? Icons.check_circle_rounded
                                : Icons.cancel_rounded,
                            color:
                                _confirmPasswordController.text ==
                                    _passwordController.text
                                ? const Color(0xFF237A52)
                                : const Color(0xFFB64D4D),
                            size: 20,
                          ),
                        IconButton(
                          tooltip: _showConfirmation
                              ? 'staff_hide_password'.tr
                              : 'staff_show_password'.tr,
                          onPressed: () => setState(
                            () => _showConfirmation = !_showConfirmation,
                          ),
                          icon: Icon(
                            _showConfirmation
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ],
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'staff_password_required'.tr;
                    }
                    if (value != _passwordController.text) {
                      return 'staff_password_confirmation_mismatch'.tr;
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('cancel'.tr),
        ),
        FilledButton(
          onPressed: _submit,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_rounded, size: 18),
              const SizedBox(width: 7),
              Text('staff_change_password'.tr),
            ],
          ),
        ),
      ],
    );
  }

  Widget _passwordStrengthIndicator() {
    final strength = _strength;
    final color = strength <= 1
        ? const Color(0xFFB64D4D)
        : strength <= 3
        ? const Color(0xFFE39B32)
        : const Color(0xFF237A52);
    final label = strength == 0
        ? 'staff_password_strength_empty'.tr
        : strength <= 1
        ? 'staff_password_strength_weak'.tr
        : strength <= 3
        ? 'staff_password_strength_medium'.tr
        : 'staff_password_strength_strong'.tr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: strength / 5,
                  minHeight: 6,
                  backgroundColor: const Color(0xFFE7ECEE),
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: strength == 0 ? StaffManagementPage._muted : color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Icon(
              _passwordController.text.length >= 6
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              size: 15,
              color: _passwordController.text.length >= 6
                  ? const Color(0xFF237A52)
                  : StaffManagementPage._muted,
            ),
            const SizedBox(width: 6),
            Text(
              'staff_password_minimum'.tr,
              style: const TextStyle(
                color: StaffManagementPage._muted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StaffEditorDialog extends StatefulWidget {
  const _StaffEditorDialog({this.employeeUid, this.memberData});

  final String? employeeUid;
  final Map<String, dynamic>? memberData;

  @override
  State<_StaffEditorDialog> createState() => _StaffEditorDialogState();
}

class _StaffEditorDialogState extends State<_StaffEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _shopNicknameController;
  final _passwordController = TextEditingController();
  late final Future<Map<String, dynamic>> _businessProfile;
  late final Map<String, Map<String, bool>> _permissions;
  bool _saving = false;

  bool get _isEditing => widget.employeeUid != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.memberData?['name']?.toString() ?? '',
    );
    _emailController = TextEditingController(
      text: widget.memberData?['email']?.toString() ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.memberData?['phone']?.toString() ?? '',
    );
    _shopNicknameController = TextEditingController(
      text:
          widget.memberData?['shopNickname']?.toString() ??
          widget.memberData?['username']?.toString() ??
          '',
    );
    _businessProfile = ProfileService.loadOrCreate();
    _permissions = _readPermissions(widget.memberData?['permissions']);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _shopNicknameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final availableHeight =
        media.size.height -
        media.viewInsets.bottom -
        media.viewPadding.vertical -
        180;
    final dialogHeight = availableHeight.clamp(80.0, 560.0);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      title: Text(
        _isEditing ? 'staff_edit'.tr : 'staff_add'.tr,
        style: const TextStyle(
          color: StaffManagementPage._ink,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SizedBox(
        width: 560,
        height: dialogHeight,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_isEditing) ...[
                  FutureBuilder<Map<String, dynamic>>(
                    future: _businessProfile,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _assignedBusinessCard(
                          'staff_store_load_error'.tr,
                        );
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _assignedBusinessCard('staff_store_loading'.tr);
                      }
                      final profile = snapshot.data ?? const {};
                      final shopNickname =
                          profile['shopNickname']?.toString().trim() ?? '';
                      if (_shopNicknameController.text.isEmpty &&
                          shopNickname.isNotEmpty) {
                        _shopNicknameController.text = shopNickname;
                      }
                      return _assignedBusinessCard(
                        profile['name']?.toString().trim().isNotEmpty == true
                            ? profile['name'].toString().trim()
                            : 'staff_store_not_named'.tr,
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 17,
                          color: StaffManagementPage._brand,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'staff_login_credentials_note'.tr,
                            style: const TextStyle(
                              color: StaffManagementPage._muted,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'staff_name'.tr,
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'required_field'.tr
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  readOnly:
                      _isEditing && widget.memberData?['businessEmail'] == null,
                  decoration: InputDecoration(
                    labelText: 'staff_email_optional'.tr,
                    prefixIcon: const Icon(Icons.email_outlined),
                    helperText:
                        _isEditing &&
                            widget.memberData?['businessEmail'] == null
                        ? 'staff_email_legacy_note'.tr
                        : 'staff_email_contact_note'.tr,
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    return email.isEmpty || GetUtils.isEmail(email)
                        ? null
                        : 'invalid_email'.tr;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'staff_phone'.tr,
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _shopNicknameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'staff_shop_nickname'.tr,
                    prefixIcon: const Icon(Icons.storefront_outlined),
                    helperText: 'staff_shop_nickname_hint'.tr,
                  ),
                  validator: (value) {
                    return (value?.trim().isEmpty ?? true)
                        ? 'staff_shop_nickname_required'.tr
                        : null;
                  },
                ),
                if (!_isEditing) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'staff_password'.tr,
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                    validator: (value) => (value?.length ?? 0) >= 6
                        ? null
                        : 'staff_password_minimum'.tr,
                  ),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'staff_permissions'.tr,
                    style: const TextStyle(
                      color: StaffManagementPage._ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (final module in BusinessAccessService.modules.entries)
                  _permissionCard(module.key, module.value.tr),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Get.back<bool>(),
          child: Text('cancel'.tr),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(_isEditing ? 'save'.tr : 'staff_create'.tr),
        ),
      ],
    );
  }

  Widget _assignedBusinessCard(String businessName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4F3),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFC9E1DF)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.storefront_outlined,
            color: StaffManagementPage._brand,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'staff_assigned_store'.tr,
                  style: const TextStyle(
                    color: StaffManagementPage._muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  businessName,
                  style: const TextStyle(
                    color: StaffManagementPage._ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _permissionCard(String module, String label) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFFF8FAFA),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: const BorderSide(color: Color(0xFFE5EAEC)),
      ),
      child: ExpansionTile(
        dense: true,
        title: Text(
          label,
          style: const TextStyle(
            color: StaffManagementPage._ink,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          for (final action in BusinessAccessService.actions.entries)
            SwitchListTile.adaptive(
              dense: true,
              title: Text(action.value.tr),
              value: _permissions[module]![action.key] ?? false,
              activeTrackColor: StaffManagementPage._brand,
              onChanged: (value) {
                setState(() => _permissions[module]![action.key] = value);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_permissions.values.any(
      (actions) => actions.values.any((allowed) => allowed),
    )) {
      Get.snackbar('staff_permissions'.tr, 'staff_select_permission'.tr);
      return;
    }

    setState(() => _saving = true);
    try {
      if (_isEditing) {
        await StaffService.updateStaff(
          employeeUid: widget.employeeUid!,
          name: _nameController.text,
          email: _emailController.text,
          phone: _phoneController.text,
          shopNickname: _shopNicknameController.text,
          permissions: _permissions,
        );
      } else {
        await StaffService.createStaff(
          name: _nameController.text,
          email: _emailController.text,
          phone: _phoneController.text,
          shopNickname: _shopNicknameController.text,
          password: _passwordController.text,
          permissions: _permissions,
        );
      }
      if (mounted) Get.back<bool>(result: true);
    } catch (error, stackTrace) {
      debugPrint('Could not save staff account: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _saving = false);
        Get.snackbar('error'.tr, '${'staff_save_error'.tr}: $error');
      }
    }
  }

  Map<String, Map<String, bool>> _readPermissions(dynamic raw) {
    final result = BusinessAccessService.emptyPermissions();
    if (raw is! Map) return result;
    for (final module in result.keys) {
      final moduleRaw = raw[module];
      if (moduleRaw is! Map) continue;
      for (final action in result[module]!.keys) {
        result[module]![action] = moduleRaw[action] == true;
      }
    }
    return result;
  }
}
