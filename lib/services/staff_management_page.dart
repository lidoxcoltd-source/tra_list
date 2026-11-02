import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:tra_list/invoice/transaction_model.dart';
import 'package:tra_list/invoice/transaction_service.dart';
import 'business_access_service.dart';
import 'profile_service.dart';
import 'staff_service.dart';
import 'package:tra_list/theme/app_theme.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/tasks/task_editor_page.dart';
import 'chat_service.dart';

class _BarModeSettingsCard extends StatefulWidget {
  const _BarModeSettingsCard();

  @override
  State<_BarModeSettingsCard> createState() => _BarModeSettingsCardState();
}

class _BarModeSettingsCardState extends State<_BarModeSettingsCard> {
  bool _saving = false;

  DocumentReference<Map<String, dynamic>> get _settingsRef => FirebaseFirestore
      .instance
      .collection('users')
      .doc(BusinessAccessService.businessId)
      .collection('barSettings')
      .doc('config');

  Future<void> _setEnabled(bool enabled) async {
    setState(() => _saving = true);
    try {
      await StaffService.setBarModeEnabled(enabled);
      if (mounted) {
        Get.snackbar(
          'success'.tr,
          enabled ? 'bar_mode_enabled'.tr : 'bar_mode_disabled'.tr,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Could not update Bar Mode: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        Get.snackbar('error'.tr, '${'bar_mode_save_error'.tr}: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!BusinessAccessService.isOwner.value) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _settingsRef.snapshots(),
      builder: (context, snapshot) {
        final enabled = snapshot.data?.data()?['enabled'] == true;
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MjasiRadius.md),
            side: BorderSide(
              color: StaffManagementPage._brand.withValues(alpha: 0.18),
            ),
          ),
          child: Column(
            children: [
              SwitchListTile.adaptive(
                value: enabled,
                onChanged: _saving || snapshot.hasError || !snapshot.hasData
                    ? null
                    : _setEnabled,
                secondary: const Icon(
                  Icons.local_bar_outlined,
                  color: StaffManagementPage._brand,
                ),
                title: Text(
                  'bar_mode_title'.tr,
                  style: const TextStyle(
                    color: StaffManagementPage._ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  snapshot.hasError
                      ? '${'bar_mode_load_error'.tr}: ${snapshot.error}'
                      : !snapshot.hasData
                      ? 'bar_mode_loading'.tr
                      : enabled
                      ? 'bar_mode_active_help'.tr
                      : 'bar_mode_off_help'.tr,
                  style: const TextStyle(
                    color: StaffManagementPage._muted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class StaffManagementPage extends StatelessWidget {
  const StaffManagementPage({super.key});

  static const _ink = MjasiColors.textPrimary;
  static const _muted = MjasiColors.textSecondary;
  static const _brand = MjasiColors.primaryBlue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MjasiColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          onPressed: Get.back,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text('staff_title'.tr),
        actions: [
          if (BusinessAccessService.isOwner.value ||
              BusinessAccessService.can('tasks', 'view') ||
              BusinessAccessService.can('tasks', 'create'))
            IconButton(
              onPressed: () => Get.toNamed(AppRoutes.tasks),
              tooltip: 'tk_all'.tr,
              icon: const Icon(Icons.task_alt_rounded),
            ),
          IconButton(
            onPressed: () => _showInvitationDialog(context),
            tooltip: 'staff_invite'.tr,
            icon: const Icon(Icons.mail_outline_rounded),
          ),
        ],
        backgroundColor: MjasiColors.background,
        foregroundColor: _ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: StreamBuilder<List<StaffMember>>(
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

              final staff = snapshot.data ?? const <StaffMember>[];
              final activeCount = staff
                  .where((member) => member.data['active'] == true)
                  .length;
              final removedCount = staff
                  .where((member) => member.data['removed'] == true)
                  .length;
              final disabledCount = staff
                  .where(
                    (member) =>
                        member.data['active'] != true &&
                        member.data['removed'] != true,
                  )
                  .length;
              if (staff.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.all(MjasiSpacing.md),
                  children: [
                    const _BarModeSettingsCard(),
                    const SizedBox(height: MjasiSpacing.md),
                    _messageState(
                      icon: Icons.groups_2_outlined,
                      message: 'staff_empty'.tr,
                      action: FilledButton.icon(
                        onPressed: () => _showStaffDialog(context),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: Text('staff_add'.tr),
                      ),
                    ),
                  ],
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  MjasiSpacing.md,
                  MjasiSpacing.sm,
                  MjasiSpacing.md,
                  88,
                ),
                children: [
                  const _BarModeSettingsCard(),
                  const SizedBox(height: MjasiSpacing.sm),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _staffStat(
                        label: 'staff_total'.tr,
                        count: staff.length,
                        color: MjasiColors.primaryBlue,
                        icon: Icons.people_alt_outlined,
                      ),
                      _staffStat(
                        label: 'staff_active'.tr,
                        count: activeCount,
                        color: MjasiColors.success,
                        icon: Icons.check_circle_outline_rounded,
                      ),
                      if (disabledCount > 0)
                        _staffStat(
                          label: 'staff_disabled'.tr,
                          count: disabledCount,
                          color: MjasiColors.warning,
                          icon: Icons.pause_circle_outline_rounded,
                        ),
                      if (removedCount > 0)
                        _staffStat(
                          label: 'staff_removed'.tr,
                          count: removedCount,
                          color: MjasiColors.error,
                          icon: Icons.person_off_outlined,
                        ),
                    ],
                  ),
                  const SizedBox(height: MjasiSpacing.sm),
                  const _TransactionThresholdSettings(),
                  const SizedBox(height: MjasiSpacing.md),
                  _StaffInsights(
                    staff: staff,
                    cardBuilder: (member, perf) =>
                        _staffCard(context, member.data, member.id, perf: perf),
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(MjasiRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: _muted, fontSize: 10)),
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
  }) {
    final active = data['active'] == true;
    final removed = data['removed'] == true;
    final name = data['name']?.toString() ?? '';
    final email = data['email']?.toString() ?? '';
    final phone = data['phone']?.toString() ?? '';
    final shopNickname = data['shopNickname']?.toString() ?? '';
    final dailyExpenseLimit =
        (data['dailyExpenseLimit'] as num?)?.toDouble() ?? 0;
    Future<void> openChat() async {
      try {
        final conversationId = await ChatService.getOrCreateDirectChat(
          otherUid: employeeUid,
          otherName: name,
        );
        if (context.mounted) {
          Get.toNamed(AppRoutes.getChatRoomRoute(conversationId));
        }
      } catch (error, stackTrace) {
        debugPrint('Could not open staff chat: $error');
        debugPrintStack(stackTrace: stackTrace);
        Get.snackbar('error'.tr, '${'chat_open_failed'.tr}: $error');
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: active
              ? MjasiColors.primaryBlue.withValues(alpha: 0.16)
              : MjasiColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: active
                      ? MjasiColors.lightBlue
                      : MjasiColors.border,
                  child: Text(
                    name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                    style: const TextStyle(
                      color: _brand,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          _statusBadge(active: active, removed: removed),
                        ],
                      ),
                      Text(
                        email.isEmpty ? 'staff_email_not_added'.tr : email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36),
                  iconSize: 18,
                  tooltip: 'staff_edit'.tr,
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
                    } else if (value == 'limit') {
                      _editDailyExpenseLimit(
                        context,
                        employeeUid,
                        dailyExpenseLimit,
                      );
                    } else if (value == 'chat') {
                      openChat();
                    } else if (value == 'task') {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              TaskEditorPage(initialAssigneeUid: employeeUid),
                        ),
                      );
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
                      value: 'limit',
                      child: Text(
                        dailyExpenseLimit > 0
                            ? 'staff_change_limit'.tr
                            : 'staff_set_limit'.tr,
                      ),
                    ),
                    if (active)
                      PopupMenuItem(
                        value: 'chat',
                        child: Text('chat_start_private'.tr),
                      ),
                    if (active && BusinessAccessService.isOwner.value)
                      PopupMenuItem(value: 'task', child: Text('tk_new'.tr)),
                    PopupMenuItem(
                      value: 'active',
                      child: Text(
                        active ? 'staff_disable'.tr : 'staff_enable'.tr,
                      ),
                    ),
                    if (!removed && data['invitationId'] == null)
                      PopupMenuItem(
                        value: 'password',
                        child: Text('staff_change_password'.tr),
                      ),
                    if (!removed)
                      PopupMenuItem(
                        value: 'remove',
                        child: Text(
                          'staff_remove'.tr,
                          style: const TextStyle(color: MjasiColors.error),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (shopNickname.isNotEmpty || phone.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                [
                  if (shopNickname.isNotEmpty) shopNickname,
                  if (phone.isNotEmpty) phone,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 10),
              ),
            ],
            Row(
              children: [
                Obx(() {
                  if (!BusinessAccessService.barModeEnabled.value) {
                    return const SizedBox.shrink();
                  }
                  final currentRole = data['barRole'] == 'bartender'
                      ? 'bartender'
                      : 'waiter';
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.local_bar_outlined,
                        size: 14,
                        color: MjasiColors.primaryBlue,
                      ),
                      const SizedBox(width: 2),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: currentRole,
                          isDense: true,
                          iconSize: 14,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'waiter',
                              child: Text('bar_role_waiter'.tr),
                            ),
                            DropdownMenuItem(
                              value: 'bartender',
                              child: Text('bar_role_bartender'.tr),
                            ),
                          ],
                          onChanged: (role) {
                            if (role != null && role != currentRole) {
                              _changeBarRole(employeeUid, role);
                            }
                          },
                        ),
                      ),
                    ],
                  );
                }),
                const Spacer(),
                if (perf != null)
                  Flexible(
                    child: Text(
                      '${'income'.tr}: ${_money(perf.income)} · '
                      '${'expenses'.tr}: ${_money(perf.expense)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(color: _muted, fontSize: 10),
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
          fontSize: 9,
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

  Future<void> _changeBarRole(String employeeUid, String role) async {
    try {
      await StaffService.setBarRole(employeeUid: employeeUid, role: role);
      Get.snackbar(
        'success'.tr,
        role == 'bartender'
            ? 'bar_role_bartender_assigned'.tr
            : 'bar_role_waiter_assigned'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (error, stackTrace) {
      debugPrint('Could not update staff Bar Mode role: $error');
      debugPrintStack(stackTrace: stackTrace);
      Get.snackbar('error'.tr, '${'staff_update_error'.tr}: $error');
    }
  }

  Future<void> _editDailyExpenseLimit(
    BuildContext context,
    String employeeUid,
    double currentLimit,
  ) async {
    final dailyExpenseLimit = await Get.dialog<double>(
      _StaffDailyExpenseLimitDialog(currentLimit: currentLimit),
      barrierDismissible: false,
    );
    if (dailyExpenseLimit == null || !context.mounted) return;

    try {
      await StaffService.updateDailyExpenseLimit(
        employeeUid: employeeUid,
        dailyExpenseLimit: dailyExpenseLimit,
      );
      Get.snackbar(
        'success'.tr,
        'staff_daily_expense_limit_saved'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (error, stackTrace) {
      debugPrint('Could not update staff daily expense limit: $error');
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

  Future<void> _showInvitationDialog(BuildContext context) async {
    final invitation = await Get.dialog<_StaffInvitation>(
      const _StaffInvitationDialog(),
      barrierDismissible: false,
    );
    if (invitation == null || !context.mounted) return;

    try {
      final code = await StaffService.createInvitation(
        email: invitation.email,
        name: invitation.name,
        phone: invitation.phone,
        shopNickname: invitation.shopNickname,
        permissions: invitation.permissions,
      );
      if (!context.mounted) return;
      await Get.dialog<void>(
        AlertDialog(
          icon: const Icon(Icons.mark_email_read_outlined, color: _brand),
          title: Text('staff_invitation_created'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('staff_invitation_code_help'.tr),
              const SizedBox(height: 12),
              SelectableText(
                code,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('copied'.tr)));
                  }
                },
                icon: const Icon(Icons.copy_rounded),
                label: Text('copy'.tr),
              ),
            ],
          ),
          actions: [TextButton(onPressed: Get.back, child: Text('close'.tr))],
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Could not create business invitation: $error');
      debugPrintStack(stackTrace: stackTrace);
      Get.snackbar('error'.tr, '${'staff_invitation_create_error'.tr}: $error');
    }
  }
}

class _Perf {
  double income = 0;
  double expense = 0;
  int count = 0;
}

class _TransactionThresholdSettings extends StatefulWidget {
  const _TransactionThresholdSettings();

  @override
  State<_TransactionThresholdSettings> createState() =>
      _TransactionThresholdSettingsState();
}

class _TransactionThresholdSettingsState
    extends State<_TransactionThresholdSettings> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _expenseAbove;
  late final TextEditingController _expenseBelow;
  late final TextEditingController _incomeAbove;
  late final TextEditingController _incomeBelow;
  bool _loading = true;
  bool _saving = false;

  DocumentReference<Map<String, dynamic>> get _settingsRef => FirebaseFirestore
      .instance
      .collection('users')
      .doc(BusinessAccessService.businessId)
      .collection('settings')
      .doc('transactionAlerts');

  @override
  void initState() {
    super.initState();
    _expenseAbove = TextEditingController();
    _expenseBelow = TextEditingController();
    _incomeAbove = TextEditingController();
    _incomeBelow = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _expenseAbove.dispose();
    _expenseBelow.dispose();
    _incomeAbove.dispose();
    _incomeBelow.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final snapshot = await _settingsRef.get();
      final data = snapshot.data() ?? const <String, dynamic>{};
      _expenseAbove.text = _initialThreshold(data['expenseAbove']);
      _expenseBelow.text = _initialThreshold(data['expenseBelow']);
      _incomeAbove.text = _initialThreshold(data['incomeAbove']);
      _incomeBelow.text = _initialThreshold(data['incomeBelow']);
    } catch (error, stackTrace) {
      debugPrint('Could not load transaction alert thresholds: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        Get.snackbar(
          'error'.tr,
          '${'transaction_alert_load_error'.tr}: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _initialThreshold(dynamic value) {
    if (value is! num || value <= 0) return '';
    return _formatDailyExpenseLimit(value.toDouble());
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _settingsRef.set({
        'expenseAbove': _parseDailyExpenseLimit(_expenseAbove.text),
        'expenseBelow': _parseDailyExpenseLimit(_expenseBelow.text),
        'incomeAbove': _parseDailyExpenseLimit(_incomeAbove.text),
        'incomeBelow': _parseDailyExpenseLimit(_incomeBelow.text),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      Get.snackbar('success'.tr, 'transaction_alert_saved'.tr);
    } catch (error, stackTrace) {
      debugPrint('Could not save transaction alert thresholds: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        Get.snackbar(
          'error'.tr,
          '${'transaction_alert_save_error'.tr}: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _thresholdField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: const [_ThousandsSeparatorInputFormatter()],
      decoration: InputDecoration(
        labelText: label,
        prefixText: 'TZS ',
        helperText: 'transaction_alert_blank_disables'.tr,
        isDense: true,
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return null;
        final amount = _parseDailyExpenseLimit(value);
        return amount == null || amount <= 0 || amount > 1000000000
            ? 'staff_daily_expense_limit_invalid'.tr
            : null;
      },
    );
  }

  Widget _typeFields({
    required String title,
    required TextEditingController above,
    required TextEditingController below,
    required IconData icon,
  }) {
    final color = icon == Icons.north_east_rounded
        ? MjasiColors.error
        : MjasiColors.success;
    final backgroundColor = icon == Icons.north_east_rounded
        ? MjasiColors.errorBackground
        : MjasiColors.successBackground;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(MjasiSpacing.md),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(MjasiRadius.sm),
            border: Border.all(color: color.withValues(alpha: 0.16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(MjasiRadius.sm),
                    ),
                    child: Icon(icon, size: 17, color: color),
                  ),
                  const SizedBox(width: MjasiSpacing.sm),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: color,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: MjasiSpacing.sm),
              _thresholdField(
                controller: above,
                label: 'transaction_alert_above'.tr,
              ),
              const SizedBox(height: MjasiSpacing.sm),
              _thresholdField(
                controller: below,
                label: 'transaction_alert_below'.tr,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MjasiRadius.md),
        side: const BorderSide(color: MjasiColors.border),
      ),
      child: ExpansionTile(
        shape: const RoundedRectangleBorder(),
        collapsedShape: const RoundedRectangleBorder(),
        backgroundColor: MjasiColors.surface,
        collapsedBackgroundColor: MjasiColors.surface,
        tilePadding: const EdgeInsets.symmetric(horizontal: MjasiSpacing.md),
        childrenPadding: const EdgeInsets.fromLTRB(
          MjasiSpacing.md,
          0,
          MjasiSpacing.md,
          MjasiSpacing.md,
        ),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: MjasiColors.lightBlue,
            borderRadius: BorderRadius.circular(MjasiRadius.sm),
          ),
          child: const Icon(
            Icons.notifications_active_outlined,
            color: StaffManagementPage._brand,
            size: 20,
          ),
        ),
        title: Text(
          'transaction_alert_title'.tr,
          style: const TextStyle(
            color: StaffManagementPage._ink,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          'transaction_alert_description'.tr,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: StaffManagementPage._muted,
            fontSize: 11,
          ),
        ),
        children: [
          const Divider(height: MjasiSpacing.md),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(MjasiSpacing.md),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _typeFields(
                    title: 'transaction_expenses'.tr,
                    above: _expenseAbove,
                    below: _expenseBelow,
                    icon: Icons.north_east_rounded,
                  ),
                  const SizedBox(height: MjasiSpacing.md),
                  _typeFields(
                    title: 'transaction_income'.tr,
                    above: _incomeAbove,
                    below: _incomeBelow,
                    icon: Icons.south_west_rounded,
                  ),
                  const SizedBox(height: MjasiSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined, size: 18),
                      label: Text('save'.tr),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

enum _Range { today, yesterday, week, month }

class _StaffInsights extends StatefulWidget {
  const _StaffInsights({required this.staff, required this.cardBuilder});

  final List<StaffMember> staff;
  final Widget Function(StaffMember member, _Perf perf) cardBuilder;

  @override
  State<_StaffInsights> createState() => _StaffInsightsState();
}

class _StaffInsightsState extends State<_StaffInsights> {
  static const _ink = MjasiColors.textPrimary;
  static const _muted = MjasiColors.textSecondary;
  static const _brand = MjasiColors.primaryBlue;

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
        final ra = a.data['removed'] == true ? 1 : 0;
        final rb = b.data['removed'] == true ? 1 : 0;
        if (ra != rb) return ra.compareTo(rb);
        final ia = _perf[a.id]?.income ?? 0;
        final ib = _perf[b.id]?.income ?? 0;
        return ib.compareTo(ia);
      });
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
        const SizedBox(height: MjasiSpacing.xs),
        Row(
          children: [
            _teamStat('income'.tr, teamIncome, MjasiColors.success),
            _teamStat('expenses'.tr, teamExpense, MjasiColors.error),
            _teamStat('net'.tr, teamIncome - teamExpense, _brand),
          ],
        ),
        const SizedBox(height: MjasiSpacing.sm),
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
          for (final m in members)
            widget.cardBuilder(m, _perf[m.id] ?? _Perf()),
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
              color: MjasiColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              StaffManagementPage._money(value),
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
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

class _StaffDailyExpenseLimitDialog extends StatefulWidget {
  const _StaffDailyExpenseLimitDialog({required this.currentLimit});

  final double currentLimit;

  @override
  State<_StaffDailyExpenseLimitDialog> createState() =>
      _StaffDailyExpenseLimitDialogState();
}

class _StaffDailyExpenseLimitDialogState
    extends State<_StaffDailyExpenseLimitDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _limitController;

  @override
  void initState() {
    super.initState();
    _limitController = TextEditingController(
      text: widget.currentLimit > 0
          ? _formatDailyExpenseLimit(widget.currentLimit)
          : '',
    );
  }

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('staff_daily_expense_limit'.tr),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _limitController,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: const [_ThousandsSeparatorInputFormatter()],
          decoration: InputDecoration(
            labelText: 'staff_daily_expense_limit'.tr,
            prefixText: 'TZS ',
            helperText: 'staff_daily_expense_limit_hint'.tr,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) return null;
            final amount = _parseDailyExpenseLimit(value);
            return amount == null || amount > 1000000000
                ? 'staff_daily_expense_limit_invalid'.tr
                : null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back<double>(),
          child: Text('cancel'.tr),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final amount = _parseDailyExpenseLimit(_limitController.text) ?? 0;
            Get.back<double>(result: amount);
          },
          child: Text('save'.tr),
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
  late final TextEditingController _dailyExpenseLimitController;
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
    _dailyExpenseLimitController = TextEditingController(
      text: widget.memberData?['dailyExpenseLimit'] is num
          ? _formatDailyExpenseLimit(
              (widget.memberData!['dailyExpenseLimit'] as num).toDouble(),
            )
          : '',
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
    _dailyExpenseLimitController.dispose();
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
                const SizedBox(height: 10),
                TextFormField(
                  controller: _dailyExpenseLimitController,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [_ThousandsSeparatorInputFormatter()],
                  decoration: InputDecoration(
                    labelText: 'staff_daily_expense_limit'.tr,
                    prefixIcon: const Icon(Icons.warning_amber_rounded),
                    helperText: 'staff_daily_expense_limit_hint'.tr,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final amount = _parseDailyExpenseLimit(value);
                    return amount == null || amount < 0 || amount > 1000000000
                        ? 'staff_daily_expense_limit_invalid'.tr
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
    final hasSelectedPermission = _permissions.values.any(
      (actions) => actions.values.any((allowed) => allowed),
    );
    final dailyExpenseLimit =
        _parseDailyExpenseLimit(_dailyExpenseLimitController.text) ?? 0;
    if (!hasSelectedPermission && dailyExpenseLimit <= 0) {
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
          dailyExpenseLimit: dailyExpenseLimit,
        );
      } else {
        await StaffService.createStaff(
          name: _nameController.text,
          email: _emailController.text,
          phone: _phoneController.text,
          shopNickname: _shopNicknameController.text,
          password: _passwordController.text,
          permissions: _permissions,
          dailyExpenseLimit: dailyExpenseLimit,
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

class _StaffInvitation {
  const _StaffInvitation({
    required this.name,
    required this.email,
    required this.phone,
    required this.shopNickname,
    required this.permissions,
  });

  final String name;
  final String email;
  final String phone;
  final String shopNickname;
  final Map<String, Map<String, bool>> permissions;
}

class _StaffInvitationDialog extends StatefulWidget {
  const _StaffInvitationDialog();

  @override
  State<_StaffInvitationDialog> createState() => _StaffInvitationDialogState();
}

class _StaffInvitationDialogState extends State<_StaffInvitationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _shopNickname = TextEditingController();
  final _permissions = BusinessAccessService.emptyPermissions();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _shopNickname.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.65;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      title: Text('staff_invite'.tr),
      content: SizedBox(
        width: 520,
        height: maxHeight,
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text(
                'staff_invitation_account_hint'.tr,
                style: const TextStyle(color: StaffManagementPage._muted),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'account_full_name'.tr,
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'account_full_name_required'.tr
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'email'.tr,
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
                      ? null
                      : 'Invalid email format'.tr;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'account_phone_optional'.tr,
                  prefixIcon: const Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _shopNickname,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'staff_shop_nickname'.tr,
                  prefixIcon: const Icon(Icons.store_outlined),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'required'.tr
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                'staff_permissions'.tr,
                style: const TextStyle(
                  color: StaffManagementPage._ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'staff_select_permission'.tr,
                style: const TextStyle(
                  color: StaffManagementPage._muted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              for (final entry in BusinessAccessService.modules.entries)
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  color: const Color(0xFFF8FAFA),
                  child: ExpansionTile(
                    dense: true,
                    title: Text(entry.value.tr),
                    children: [
                      for (final action
                          in BusinessAccessService.actions.entries)
                        SwitchListTile.adaptive(
                          dense: true,
                          title: Text(action.value.tr),
                          value: _permissions[entry.key]![action.key]!,
                          onChanged: (value) => setState(
                            () => _permissions[entry.key]![action.key] = value,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Get.back(), child: Text('cancel'.tr)),
        FilledButton(onPressed: _save, child: Text('staff_invite'.tr)),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (!_permissions.values.any(
      (actions) => actions.values.any((allowed) => allowed),
    )) {
      Get.snackbar('staff_permissions'.tr, 'staff_select_permission'.tr);
      return;
    }
    Get.back<_StaffInvitation>(
      result: _StaffInvitation(
        name: _name.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        shopNickname: _shopNickname.text.trim(),
        permissions: _permissions,
      ),
    );
  }
}

double? _parseDailyExpenseLimit(String? value) {
  final digits = value?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
  return digits.isEmpty ? null : double.tryParse(digits);
}

String _formatDailyExpenseLimit(double value) =>
    NumberFormat('#,##0').format(value);

class _ThousandsSeparatorInputFormatter extends TextInputFormatter {
  const _ThousandsSeparatorInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final rawDigits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (rawDigits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final digitsBeforeCursor = newValue.text
        .substring(
          0,
          newValue.selection.extentOffset.clamp(0, newValue.text.length),
        )
        .replaceAll(RegExp(r'[^0-9]'), '')
        .length;
    final formatted = rawDigits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    var cursorOffset = 0;
    var digitsPassed = 0;
    while (cursorOffset < formatted.length &&
        digitsPassed < digitsBeforeCursor) {
      if (RegExp(r'[0-9]').hasMatch(formatted[cursorOffset])) {
        digitsPassed++;
      }
      cursorOffset++;
    }
    while (cursorOffset < formatted.length &&
        !RegExp(r'[0-9]').hasMatch(formatted[cursorOffset])) {
      cursorOffset++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
  }
}
