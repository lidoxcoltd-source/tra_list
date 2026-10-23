import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:tra_list/invoice/add_transaction_page.dart';
import 'package:tra_list/invoice/language_controller.dart';
import 'package:tra_list/invoice/transaction_model.dart';
import 'package:tra_list/invoice/transaction_service.dart';
import 'package:tra_list/jobs/controllers/debt_controller.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/services/pages/ProfilePage.dart';
import 'package:tra_list/services/pages/document_design_page.dart';
import 'package:tra_list/services/profile_service.dart';
import 'package:tra_list/services/account_deletion_service.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/notifications_page.dart';
import 'package:tra_list/tasks/task_banner.dart';
import 'package:tra_list/tasks/task_service.dart';
import 'package:tra_list/services/push_service.dart';
import 'services/subscription_controller.dart';

enum _FinancePeriod { today, yesterday, thisWeek, thisMonth }

class _StaffStat {
  _StaffStat(this.name);
  final String name;
  double income = 0;
  double expense = 0;
  int count = 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────
class _AppColors {
  static const ink = Color(0xFF0F172A);
  static const inkSoft = Color(0xFF334155);
  static const muted = Color(0xFF64748B);
  static const canvas = Color(0xFFF1F5F9);
  static const surface = Colors.white;
  static const border = Color(0xFFE2E8F0);
  static const borderSoft = Color(0xFFF1F5F9);
  static const brand = Color(0xFF1E40AF);
  static const brandDark = Color(0xFF1E3A8A);
  static const brandDeep = Color(0xFF0F172A);
  static const positive = Color(0xFF059669);
  static const positiveBg = Color(0xFFECFDF5);
  static const negative = Color(0xFFDC2626);
  static const negativeBg = Color(0xFFFEF2F2);
  static const warning = Color(0xFFD97706);
  static const warningBg = Color(0xFFFFFBEB);
}

class _Spacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class _Radius {
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const pill = 999.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// HomePage
// ─────────────────────────────────────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final SubscriptionController subscriptionController = Get.put(
    SubscriptionController(),
  );
  final LanguageController languageController =
      Get.isRegistered<LanguageController>()
      ? Get.find<LanguageController>()
      : Get.put(LanguageController());
  DebtController? debtController;

  String subscriptionBadge = '';
  String storeName = '';
  String shopNickname = '';
  bool isSubscribed = false;
  bool isTrial = false;
  String userRole = 'user';
  bool loading = true;
  bool financeLoading = true;
  String? financeError;
  double financeIncome = 0;
  double financeExpense = 0;
  int docCount = 0;
  double docTotal = 0;
  int jobCount = 0;
  int? staffCount;
  int taskCount = 0;
  bool _staffOpen = false;
  List<_StaffStat> staffStats = [];
  _FinancePeriod _financePeriod = _FinancePeriod.today;
  int _financeRequest = 0;
  bool _desktop = false;

  String get _normalizedUserRole =>
      userRole.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  bool get _isSuperAdmin => _normalizedUserRole == 'superadmin';

  bool get _hasSubscriptionExemption =>
      _isSuperAdmin || _normalizedUserRole == 'admin';

  @override
  void initState() {
    super.initState();
    if (BusinessAccessService.can('jobs', 'view')) {
      debtController = Get.put(DebtController());
    }
    _loadUserRole();
    _loadSubscriptionStatus();
    _loadFinanceSummary();
  }

  // ── Data loading (unchanged logic) ─────────────────────────────────────────
  Future<void> _loadFinanceSummary() async {
    if (!BusinessAccessService.can('transactions', 'view') &&
        !BusinessAccessService.can('analytics', 'view')) {
      if (!mounted) return;
      setState(() {
        financeLoading = false;
        financeError = null;
        financeIncome = 0;
        financeExpense = 0;
      });
      return;
    }

    final request = ++_financeRequest;
    if (mounted) {
      setState(() {
        financeLoading = true;
        financeError = null;
      });
    }

    final now = DateTime.now();
    final start = switch (_financePeriod) {
      _FinancePeriod.today => DateTime(now.year, now.month, now.day),
      _FinancePeriod.yesterday => DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 1)),
      _FinancePeriod.thisWeek => DateTime(
        now.year,
        now.month,
        now.day - (now.weekday - 1),
      ),
      _FinancePeriod.thisMonth => DateTime(now.year, now.month, 1),
    };
    final end = switch (_financePeriod) {
      _FinancePeriod.today ||
      _FinancePeriod.yesterday => start.add(const Duration(days: 1)),
      _FinancePeriod.thisWeek => start.add(const Duration(days: 7)),
      _FinancePeriod.thisMonth => DateTime(now.year, now.month + 1, 1),
    };
    try {
      final totals = await TransactionService.getTotals(
        startDate: start,
        endDate: end,
      );
      if (!mounted || request != _financeRequest) return;
      setState(() {
        financeIncome = totals['income'] ?? 0;
        financeExpense = totals['expense'] ?? 0;
        financeLoading = false;
      });
      _loadBusinessStats(start, end, request);
      _loadStaffStats(start, end, request);
    } catch (error, stackTrace) {
      debugPrint('Failed to load dashboard financial totals: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted || request != _financeRequest) return;
      setState(() {
        financeLoading = false;
        financeError = 'home_finance_load_error'.tr;
      });
    }
  }

  Future<void> _loadStaffStats(
    DateTime start,
    DateTime end,
    int request,
  ) async {
    if (!BusinessAccessService.isOwner.value) return;
    try {
      final members = await FirebaseFirestore.instance
          .collection('employeeMemberships')
          .where('businessUid', isEqualTo: BusinessAccessService.businessId)
          .get();
      final names = {
        for (final m in members.docs)
          m.id: (m.data()['name'] ?? '').toString().trim(),
      };
      final snap = await TransactionService.getTransactions(
        limit: 1000,
        startDate: start,
        endDate: end,
      );
      final byUid = <String, _StaffStat>{
        for (final e in names.entries)
          e.key: _StaffStat(e.value.isEmpty ? '—' : e.value),
      };
      for (final doc in snap.docs) {
        final t = doc.data();
        final stat = byUid.putIfAbsent(
          t.uid,
          () => _StaffStat(
            t.uid == BusinessAccessService.businessId ? 'hs_owner'.tr : '—',
          ),
        );
        stat.count++;
        if (t.type == TransactionType.income) {
          stat.income += t.amount;
        } else {
          stat.expense += t.amount;
        }
      }
      final list = byUid.values.toList()
        ..sort((a, b) => b.income.compareTo(a.income));
      if (!mounted || request != _financeRequest) return;
      setState(() {
        staffStats = list;
        staffCount = members.docs.length;
      });
    } catch (error) {
      debugPrint('Failed to load staff stats: $error');
    }
  }

  Future<void> _loadBusinessStats(
    DateTime start,
    DateTime end,
    int request,
  ) async {
    try {
      final base = FirebaseFirestore.instance
          .collection('users')
          .doc(BusinessAccessService.businessId);
      var count = 0;
      var total = 0.0;
      if (BusinessAccessService.can('invoices', 'view')) {
        final snap = await base
            .collection('invoices')
            .where(
              'createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(start),
            )
            .where('createdAt', isLessThan: Timestamp.fromDate(end))
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          if (data['kind'] == 'quotation') continue;
          count++;
          total += (data['total'] as num?)?.toDouble() ?? 0;
        }
      }
      var jobs = 0;
      if (BusinessAccessService.can('jobs', 'view')) {
        final jobsRef = base.collection('jobs');
        try {
          jobs = (await jobsRef.count().get()).count ?? 0;
        } catch (_) {
          jobs = (await jobsRef.get()).docs.length;
        }
      }
      var tasks = 0;
      try {
        tasks = await TaskService.activeCount();
      } catch (_) {}
      if (!mounted || request != _financeRequest) return;
      setState(() {
        taskCount = tasks;
        docCount = count;
        docTotal = total;
        jobCount = jobs;
      });
    } catch (error) {
      debugPrint('Failed to load business stats: $error');
    }
  }

  String _financePeriodLabel(_FinancePeriod period) {
    return switch (period) {
      _FinancePeriod.today => 'transactions_today'.tr,
      _FinancePeriod.yesterday => 'yesterday'.tr,
      _FinancePeriod.thisWeek => 'transactions_this_week'.tr,
      _FinancePeriod.thisMonth => 'transactions_this_month'.tr,
    };
  }

  void _selectFinancePeriod(_FinancePeriod period) {
    if (_financePeriod == period) return;
    setState(() => _financePeriod = period);
    _loadFinanceSummary();
  }

  Future<void> _loadSubscriptionStatus() async {
    try {
      if (!BusinessAccessService.isReady.value) {
        await BusinessAccessService.initializeForCurrentUser();
      }
      final status = await subscriptionController
          .getBusinessSubscriptionStatus();
      if (!mounted) return;
      setState(() {
        subscriptionBadge = status.badge;
        isSubscribed = status.isSubscribed;
        isTrial = status.isTrial;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load business subscription: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        subscriptionBadge = '';
        isSubscribed = false;
        isTrial = false;
      });
      Get.snackbar(
        'error'.tr,
        'Could not load the business subscription. Please refresh and try again.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> _loadUserRole() async {
    if (!BusinessAccessService.isOwner.value) {
      var loadedStoreName = BusinessAccessService.businessName.value.trim();
      var loadedShopNickname = BusinessAccessService.shopNickname.value.trim();
      if ((loadedStoreName.isEmpty || loadedShopNickname.isEmpty) &&
          BusinessAccessService.canReadBusinessProfile()) {
        try {
          final profile = await ProfileService.loadOrCreate();
          loadedStoreName = profile['name']?.toString().trim() ?? '';
          loadedShopNickname = profile['shopNickname']?.toString().trim() ?? '';
        } catch (error, stackTrace) {
          debugPrint('Could not load staff dashboard store name: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
      if (!mounted) return;
      setState(() {
        userRole = 'staff';
        storeName = loadedStoreName;
        shopNickname = loadedShopNickname;
        loading = false;
      });
      return;
    }
    try {
      final profile = await ProfileService.loadOrCreate();
      if (!mounted) return;
      setState(() {
        userRole = profile['role']?.toString() ?? 'user';
        storeName = profile['name']?.toString().trim() ?? '';
        shopNickname = profile['shopNickname']?.toString().trim() ?? '';
        loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load dashboard user profile: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        userRole = 'user';
        storeName = '';
        shopNickname = '';
        loading = false;
      });
    }
  }

  Future<bool> _checkCurrentSubscriptionAccess() async {
    if (_hasSubscriptionExemption) return true;
    try {
      if (!BusinessAccessService.isReady.value) {
        await BusinessAccessService.initializeForCurrentUser();
      }
      final status = await subscriptionController
          .getBusinessSubscriptionStatus();
      if (!mounted) return false;
      setState(() {
        subscriptionBadge = status.badge;
        isSubscribed = status.isSubscribed;
        isTrial = status.isTrial;
      });
      return status.isSubscribed || status.isTrial;
    } catch (error, stackTrace) {
      debugPrint('Could not verify shared subscription access: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        Get.snackbar(
          'error'.tr,
          'Could not verify the business subscription. Check your connection and try again.',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: _AppColors.canvas,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: _AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 960;
                  _desktop = wide;
                  final showFinance =
                      BusinessAccessService.can('transactions', 'view') ||
                      BusinessAccessService.can('analytics', 'view');
                  final showJobs = BusinessAccessService.can('jobs', 'view');

                  final financeColumn = <Widget>[
                    if (showFinance) ...[
                      _sectionHeading(
                        'home_finance_summary'.tr,
                        '${'home_month_to_date'.tr} · $_currentMonthLabel',
                        action: _periodPicker(),
                      ),
                      const SizedBox(height: _Spacing.md),
                      _buildFinanceCard(wide),
                      const SizedBox(height: _Spacing.xl),
                    ],
                    if (showJobs) ...[
                      _sectionHeading(
                        'home_jobs_overview'.tr,
                        'home_jobs_overview_sub'.tr,
                      ),
                      const SizedBox(height: _Spacing.md),
                      _buildDebtMetrics(wide),
                    ],
                  ];

                  final actionsColumn = <Widget>[
                    _sectionHeading(
                      'home_quick_access'.tr,
                      'home_quick_access_sub'.tr,
                    ),
                    const SizedBox(height: _Spacing.md),
                    _buildQuickActions(),
                    const SizedBox(height: _Spacing.xl),
                    if (BusinessAccessService.can('transactions', 'view')) ...[
                      _sectionHeading(
                        'home_transactions'.tr,
                        'home_transactions'.tr,
                      ),
                      const SizedBox(height: _Spacing.md),
                      _buildTransactionsButton(),
                      const SizedBox(height: _Spacing.lg),
                    ],
                    if (BusinessAccessService.isOwner.value)
                      _buildSubscriptionLink(),
                  ];

                  return RefreshIndicator(
                    onRefresh: _loadFinanceSummary,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        wide ? _Spacing.xxl : _Spacing.lg,
                        wide ? _Spacing.xl : _Spacing.md,
                        wide ? _Spacing.xxl : _Spacing.lg,
                        _Spacing.xxl,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 2000),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildWelcomePanel(wide),
                              const SizedBox(height: _Spacing.xl),
                              if (wide)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 7,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: financeColumn,
                                      ),
                                    ),
                                    const SizedBox(width: _Spacing.xl),
                                    Expanded(
                                      flex: 5,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: actionsColumn,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    ...financeColumn,
                                    const SizedBox(height: _Spacing.xl),
                                    ...actionsColumn,
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HEADER
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 600;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20),
      decoration: const BoxDecoration(
        color: _AppColors.brandDeep,
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: SizedBox(
        height: 68,
        child: Row(
          children: [
            // Brand mark
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _AppColors.brand,
                borderRadius: BorderRadius.circular(_Radius.sm),
              ),
              child: const Icon(
                Icons.storefront_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: _Spacing.md),
            // Store identity
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shopNickname.isNotEmpty
                        ? shopNickname
                        : storeName.isEmpty
                        ? 'Mjasi POS'
                        : storeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (shopNickname.isNotEmpty && storeName.isNotEmpty)
                    Text(
                      storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
            if (subscriptionBadge.isNotEmpty && !compact)
              Padding(
                padding: const EdgeInsets.only(right: _Spacing.sm),
                child: _buildPlanBadge(),
              ),
            if (_isSuperAdmin && !compact)
              _headerIconButton(
                icon: Icons.admin_panel_settings_outlined,
                tooltip: 'hub_title'.tr,
                onPressed: () => Get.toNamed(AppRoutes.adminHub),
              ),
            if (!compact) _buildLanguageButton(),
            const NotificationBell(),
            if (!compact &&
                (BusinessAccessService.can('profile', 'view') ||
                    BusinessAccessService.isOwner.value))
              _headerIconButton(
                icon: Icons.person_outline_rounded,
                tooltip: 'home_profile'.tr,
                onPressed: _openProfile,
              ),
            if (!compact)
              Container(
                width: 1,
                height: 24,
                margin: const EdgeInsets.symmetric(horizontal: _Spacing.sm),
                color: Colors.white.withValues(alpha: 0.15),
              ),
            _buildOverflowMenu(compact),
          ],
        ),
      ),
    );
  }

  Widget _headerIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 22),
    );
  }

  Widget _buildOverflowMenu(bool compact) {
    return PopupMenuButton<String>(
      tooltip: 'home_more'.tr,
      icon: Icon(
        Icons.more_vert_rounded,
        color: Colors.white.withValues(alpha: 0.9),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_Radius.md),
      ),
      offset: const Offset(0, 48),
      color: _AppColors.surface,
      elevation: 8,
      onSelected: _handleMenuSelection,
      itemBuilder: (context) => [
        if (compact &&
            (BusinessAccessService.can('profile', 'view') ||
                BusinessAccessService.isOwner.value))
          _menuItem('profile', 'home_profile'.tr, Icons.person_outline),
        if (compact && _isSuperAdmin)
          _menuItem(
            'admin_hub',
            'hub_title'.tr,
            Icons.admin_panel_settings_rounded,
          ),
        if (compact)
          _menuItem(
            'language_toggle',
            languageController.locale.languageCode == 'sw'
                ? 'language_english'.tr
                : 'language_swahili'.tr,
            Icons.language_rounded,
          ),
        if (compact) const PopupMenuDivider(),
        if (BusinessAccessService.can('transactions', 'view'))
          _menuItem('transactions', 'home_transactions'.tr, Icons.swap_vert),
        if (BusinessAccessService.can('invoices', 'create'))
          _menuItem(
            'generate_invoice',
            'home_generate_invoice'.tr,
            Icons.note_add_outlined,
          ),
        if (BusinessAccessService.can('invoices', 'view'))
          _menuItem('invoices', 'home_view_invoices'.tr, Icons.receipt_long),
        if (_isSuperAdmin && BusinessAccessService.can('receipts', 'view'))
          _menuItem('receipts', 'home_view_receipts'.tr, Icons.receipt),
        if (BusinessAccessService.can('jobs', 'view'))
          _menuItem(
            'jobs',
            'home_manage_jobs'.tr,
            Icons.account_balance_wallet_outlined,
          ),
        if (BusinessAccessService.can('analytics', 'view'))
          _menuItem('analytics', 'home_analytics'.tr, Icons.analytics_outlined),
        if (BusinessAccessService.can('invoices', 'create'))
          _menuItem('pos', 'pos_title'.tr, Icons.qr_code_scanner),
        if (BusinessAccessService.can('stock', 'view'))
          _menuItem('stock', 'stk_title'.tr, Icons.inventory_2_outlined),
        if (BusinessAccessService.can('categories', 'view'))
          _menuItem(
            'categories',
            'home_manage_categories'.tr,
            Icons.category_outlined,
          ),
        if (BusinessAccessService.isOwner.value)
          _menuItem('staff', 'home_manage_staff'.tr, Icons.groups_2_outlined),
        if (_isSuperAdmin)
          _menuItem(
            'admin_subscriptions',
            'admin_manage_subscriptions'.tr,
            Icons.manage_accounts_outlined,
          ),
        if (_isSuperAdmin)
          _menuItem(
            'admin_app_versions',
            'admin_manage_app_versions'.tr,
            Icons.system_update_alt_rounded,
          ),
        if (_isSuperAdmin)
          _menuItem(
            'admin_downloads',
            'admin_manage_downloads'.tr,
            Icons.cloud_download_rounded,
          ),
        if (_isSuperAdmin)
          _menuItem(
            'admin_analytics',
            'admin_manage_analytics'.tr,
            Icons.insights_rounded,
          ),
        if (_isSuperAdmin)
          _menuItem(
            'admin_announcements',
            'admin_manage_announcements'.tr,
            Icons.campaign_rounded,
          ),
        if (_isSuperAdmin)
          _menuItem(
            'create_receipt',
            'home_create_receipt'.tr,
            Icons.add_business_outlined,
          ),
        if (BusinessAccessService.isOwner.value)
          _menuItem(
            'subscription',
            'home_subscription'.tr,
            Icons.workspace_premium_outlined,
          ),
        if (BusinessAccessService.can('profile', 'view'))
          _menuItem(
            'document_design',
            'Document design',
            Icons.palette_outlined,
          ),
        _menuItem('about', 'home_about'.tr, Icons.info_outline),
        const PopupMenuDivider(),
        _menuItem(
          'logout',
          'home_sign_out'.tr,
          Icons.logout_rounded,
          destructive: true,
        ),
        if (!_isSuperAdmin)
          _menuItem(
            'delete_account',
            'Delete account',
            Icons.delete_forever_outlined,
            destructive: true,
          ),
      ],
    );
  }

  Widget _buildPlanBadge() {
    final color = isSubscribed
        ? _AppColors.positive
        : isTrial
        ? _AppColors.warning
        : _AppColors.muted;
    final bg = isSubscribed
        ? _AppColors.positiveBg
        : isTrial
        ? _AppColors.warningBg
        : _AppColors.borderSoft;
    return Container(
      constraints: const BoxConstraints(maxWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(_Radius.pill),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              subscriptionBadge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageButton() {
    final languageCode = languageController.locale.languageCode;
    return PopupMenuButton<String>(
      tooltip: 'language'.tr,
      onSelected: _changeLanguage,
      itemBuilder: (context) => [
        _languageMenuItem('en', 'language_english'.tr, languageCode),
        _languageMenuItem('sw', 'language_swahili'.tr, languageCode),
      ],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_Radius.md),
      ),
      offset: const Offset(0, 48),
      color: _AppColors.surface,
      elevation: 8,
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.language_rounded,
            color: Colors.white.withValues(alpha: 0.9),
            size: 20,
          ),
          if (MediaQuery.sizeOf(context).width >= 360) ...[
            const SizedBox(width: _Spacing.xs),
            Text(
              languageCode == 'sw' ? 'SW' : 'EN',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  PopupMenuItem<String> _languageMenuItem(
    String code,
    String label,
    String selectedCode,
  ) {
    return PopupMenuItem(
      value: code,
      child: Row(
        children: [
          Text(label),
          const Spacer(),
          if (code == selectedCode)
            const Icon(Icons.check_rounded, size: 18, color: _AppColors.brand),
        ],
      ),
    );
  }

  Future<void> _changeLanguage(String languageCode) async {
    final countryCode = languageCode == 'sw' ? 'TZ' : 'US';
    languageController.changeLanguage(languageCode, countryCode);
    if (!BusinessAccessService.can('profile', 'edit')) return;
    try {
      await ProfileService.save({'language': languageCode});
    } catch (error, stackTrace) {
      debugPrint('Could not save language preference: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      Get.snackbar(
        'error'.tr,
        'language_save_error'.trParams({'error': error.toString()}),
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  PopupMenuItem<String> _menuItem(
    String value,
    String title,
    IconData icon, {
    bool destructive = false,
  }) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: destructive ? _AppColors.negative : _AppColors.muted,
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              color: destructive ? _AppColors.negative : _AppColors.ink,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }

  void _openProfile() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const ProfilePage()));

  Future<void> _handleMenuSelection(String value) async {
    switch (value) {
      case 'profile':
        _openProfile();
      case 'language_toggle':
        await _changeLanguage(
          languageController.locale.languageCode == 'sw' ? 'en' : 'sw',
        );
      case 'transactions':
        await _openRestrictedRoute(
          AppRoutes.transactions,
          refreshFinance: true,
        );
      case 'generate_invoice':
        await _openRestrictedRoute(AppRoutes.invoice);
      case 'invoices':
        await _openRestrictedRoute(AppRoutes.invoicesList);
      case 'receipts':
        await _openRestrictedRoute(AppRoutes.receiptsList);
      case 'jobs':
        await _openRestrictedRoute(AppRoutes.jobs);
      case 'analytics':
        await _openRestrictedRoute(AppRoutes.analytics);
      case 'pos':
        await _openRestrictedRoute(AppRoutes.pos);
      case 'stock':
        await _openRestrictedRoute(AppRoutes.stock);
      case 'categories':
        await _openRestrictedRoute(AppRoutes.categories);
      case 'staff':
        await _openRestrictedRoute(AppRoutes.staff);
      case 'admin_hub':
        await Get.toNamed(AppRoutes.adminHub);
      case 'admin_subscriptions':
        await Get.toNamed(AppRoutes.adminSubscriptions);
      case 'admin_app_versions':
        await Get.toNamed(AppRoutes.adminAppVersions);
      case 'admin_downloads':
        await Get.toNamed(AppRoutes.adminDownloads);
      case 'admin_analytics':
        await Get.toNamed(AppRoutes.adminAnalytics);
        break;
      case 'admin_announcements':
        await Get.toNamed(AppRoutes.adminAnnouncements);
      case 'create_receipt':
        await _openRestrictedRoute(AppRoutes.addReceipt);
      case 'subscription':
        await Get.toNamed(AppRoutes.subscription);
        await _loadSubscriptionStatus();
      case 'document_design':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const DocumentDesignPage()));
      case 'about':
        _showAboutDialog();
      case 'delete_account':
        final deleted = await AccountDeletionService.confirmAndDelete(context);
        if (deleted && mounted) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
        }
      case 'logout':
        await PushService.unregister();
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
    }
  }

  Future<void> _openRestrictedRoute(
    String route, {
    bool refreshFinance = false,
  }) async {
    final isReceiptRoute =
        route == AppRoutes.receiptsList || route == AppRoutes.addReceipt;
    if (isReceiptRoute && !_isSuperAdmin) {
      Get.snackbar('error'.tr, 'staff_no_permission'.tr);
      return;
    }
    if (!BusinessAccessService.canAccessRoute(route)) {
      Get.snackbar('error'.tr, 'staff_no_permission'.tr);
      return;
    }
    if (!await _checkCurrentSubscriptionAccess()) {
      _showSubscriptionRequiredDialog();
      return;
    }
    await Get.toNamed(route);
    if (refreshFinance && mounted) await _loadFinanceSummary();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WELCOME HERO
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildWelcomePanel(bool wide) {
    final displayName = shopNickname.isNotEmpty
        ? shopNickname
        : storeName.isNotEmpty
        ? storeName
        : 'Mjasi POS';

    return ClipRRect(
      borderRadius: BorderRadius.circular(_Radius.lg),
      child: Stack(
        children: [
          // Solid base
          Positioned.fill(child: Container(color: _AppColors.brandDark)),
          // Content
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? _Spacing.lg : _Spacing.md,
              vertical: _Spacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Karibu, $displayName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: wide ? 18 : 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                          if (subscriptionBadge.isNotEmpty) ...[
                            const SizedBox(width: _Spacing.sm),
                            const Icon(
                              Icons.workspace_premium_outlined,
                              color: Color(0xFF60A5FA),
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                subscriptionBadge,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: _Spacing.sm),
                      Row(
                        children: [
                          _heroStat(
                            staffCount != null
                                ? 'hs_staff_count'.tr
                                : 'hs_invoices'.tr,
                            (staffCount ?? docCount).toDouble(),
                            Colors.white,
                            count: true,
                            onTap: () => _openRestrictedRoute(
                              staffCount != null
                                  ? AppRoutes.staff
                                  : AppRoutes.invoicesList,
                            ),
                          ),
                          const SizedBox(width: _Spacing.sm),
                          _heroStat(
                            'hs_tasks_assigned'.tr,
                            taskCount.toDouble(),
                            const Color(0xFF34D399),
                            count: true,
                            onTap: () => _openRestrictedRoute(AppRoutes.tasks),
                          ),
                          const SizedBox(width: _Spacing.sm),
                          _heroStat(
                            'hs_net'.tr,
                            financeIncome - financeExpense,
                            const Color(0xFFFBBF24),
                            onTap: () => _openRestrictedRoute(
                              AppRoutes.transactions,
                              refreshFinance: true,
                            ),
                          ),
                        ],
                      ),
                      TaskBanner(
                        onTap: () => _openRestrictedRoute(AppRoutes.tasks),
                      ),
                      if (staffStats.isNotEmpty) ...[
                        InkWell(
                          onTap: () => setState(() => _staffOpen = !_staffOpen),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'hs_staff_title'.tr,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.75,
                                      ),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Icon(
                                  _staffOpen
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_staffOpen) ...[
                          const SizedBox(height: _Spacing.sm),
                          _buildStaffSummary(),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffSummary() {
    Widget row(String name, String income, String expense, String count) {
      const style = TextStyle(
        color: Colors.white,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                income,
                textAlign: TextAlign.right,
                style: style.copyWith(color: const Color(0xFF34D399)),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                expense,
                textAlign: TextAlign.right,
                style: style.copyWith(color: const Color(0xFFF87171)),
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(count, textAlign: TextAlign.right, style: style),
            ),
          ],
        ),
      );
    }

    return Material(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(_Radius.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openRestrictedRoute(AppRoutes.tasks),
        child: Padding(
          padding: const EdgeInsets.all(_Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'hs_staff_title'.tr,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  Text(
                    'tk_all'.tr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              row('hs_staff'.tr, 'income'.tr, 'expenses'.tr, '#'),
              Divider(height: 8, color: Colors.white.withValues(alpha: 0.15)),
              for (final s in staffStats)
                row(
                  s.name,
                  _formatAmount(s.income),
                  _formatAmount(s.expense),
                  '${s.count}',
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroStat(
    String label,
    double amount,
    Color valueColor, {
    bool count = false,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(_Radius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(_Radius.sm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    count ? amount.toInt().toString() : _formatAmount(amount),
                    style: TextStyle(
                      color: valueColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SECTION HEADING
  // ─────────────────────────────────────────────────────────────────────────
  Widget _sectionHeading(String title, String subtitle, {Widget? action}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _AppColors.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (action != null) action,
      ],
    );
  }

  Widget _periodPicker() {
    return PopupMenuButton<_FinancePeriod>(
      tooltip: 'home_finance_period'.tr,
      onSelected: _selectFinancePeriod,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_Radius.sm),
      ),
      color: _AppColors.surface,
      elevation: 8,
      itemBuilder: (context) => _FinancePeriod.values
          .map(
            (period) => PopupMenuItem<_FinancePeriod>(
              value: period,
              child: Text(_financePeriodLabel(period)),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: _AppColors.surface,
          borderRadius: BorderRadius.circular(_Radius.sm),
          border: Border.all(color: _AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 13,
              color: _AppColors.muted,
            ),
            const SizedBox(width: 6),
            Text(
              _financePeriodLabel(_financePeriod),
              style: const TextStyle(
                color: _AppColors.inkSoft,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: _AppColors.muted,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FINANCE CARD
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildFinanceCard(bool wide) {
    final net = financeIncome - financeExpense;
    return Container(
      padding: EdgeInsets.all(wide ? _Spacing.xl : _Spacing.lg),
      decoration: BoxDecoration(
        color: _AppColors.surface,
        borderRadius: BorderRadius.circular(_Radius.md),
        border: Border.all(color: _AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _AppColors.borderSoft,
                  borderRadius: BorderRadius.circular(_Radius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.trending_up_rounded,
                      size: 13,
                      color: _AppColors.muted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'home_finance_summary'.tr,
                      style: const TextStyle(
                        color: _AppColors.inkSoft,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (financeLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                _softIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: 'refresh'.tr,
                  onPressed: _loadFinanceSummary,
                ),
            ],
          ),
          const SizedBox(height: _Spacing.lg),
          if (financeError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: _Spacing.md),
              child: Container(
                padding: const EdgeInsets.all(_Spacing.md),
                decoration: BoxDecoration(
                  color: _AppColors.negativeBg,
                  borderRadius: BorderRadius.circular(_Radius.sm),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: _AppColors.negative,
                      size: 18,
                    ),
                    const SizedBox(width: _Spacing.sm),
                    Expanded(
                      child: Text(
                        financeError!,
                        style: const TextStyle(
                          color: _AppColors.negative,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 460;
                final incomeCard = _amountTile(
                  title: 'income'.tr,
                  amount: financeIncome,
                  icon: Icons.south_west_rounded,
                  color: _AppColors.positive,
                  background: _AppColors.positiveBg,
                  actionLabel: 'home_view_income'.tr,
                  onTap: () => _openTransactionsByType(TransactionType.income),
                );
                final expenseCard = _amountTile(
                  title: 'expenses'.tr,
                  amount: financeExpense,
                  icon: Icons.north_east_rounded,
                  color: _AppColors.negative,
                  background: _AppColors.negativeBg,
                  actionLabel: 'home_view_expenses'.tr,
                  onTap: () => _openTransactionsByType(TransactionType.expense),
                );
                if (stacked) {
                  return Column(
                    children: [
                      incomeCard,
                      const SizedBox(height: _Spacing.md),
                      expenseCard,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: incomeCard),
                    const SizedBox(width: _Spacing.md),
                    Expanded(child: expenseCard),
                  ],
                );
              },
            ),
            const SizedBox(height: _Spacing.md),
            _buildNetAmount(net),
          ],
          const SizedBox(height: _Spacing.lg),
          if (BusinessAccessService.can('transactions', 'create'))
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 460;
                final buttons = [
                  _financeAction(
                    label: 'home_add_income'.tr,
                    icon: Icons.add_rounded,
                    color: _AppColors.positive,
                    onPressed: () =>
                        _openTransactionForm(TransactionType.income),
                  ),
                  _financeAction(
                    label: 'home_add_expense'.tr,
                    icon: Icons.remove_rounded,
                    color: _AppColors.negative,
                    onPressed: () =>
                        _openTransactionForm(TransactionType.expense),
                  ),
                ];
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      buttons[0],
                      const SizedBox(height: _Spacing.sm),
                      buttons[1],
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: buttons[0]),
                    const SizedBox(width: _Spacing.md),
                    Expanded(child: buttons[1]),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _amountTile({
    required String title,
    required double amount,
    required IconData icon,
    required Color color,
    required Color background,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(_Radius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_Radius.sm),
        child: Padding(
          padding: EdgeInsets.all(_desktop ? _Spacing.lg : _Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(_Radius.sm),
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const SizedBox(width: _Spacing.sm),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: _Spacing.md),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'TSh ${_formatAmount(amount)}',
                  style: TextStyle(
                    color: _AppColors.ink,
                    fontSize: _desktop ? 24 : 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: _Spacing.sm),
              Row(
                children: [
                  Text(
                    actionLabel,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 13, color: color),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNetAmount(double net) {
    final isPositive = net >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: _Spacing.md,
        vertical: _Spacing.md,
      ),
      decoration: BoxDecoration(
        color: _AppColors.borderSoft,
        borderRadius: BorderRadius.circular(_Radius.sm),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isPositive
                  ? _AppColors.positive.withValues(alpha: 0.1)
                  : _AppColors.negative.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isPositive
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              size: 16,
              color: isPositive ? _AppColors.positive : _AppColors.negative,
            ),
          ),
          const SizedBox(width: _Spacing.sm),
          Expanded(
            child: Text(
              'home_net_cash_flow'.tr,
              style: const TextStyle(
                color: _AppColors.inkSoft,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${isPositive ? '+' : '−'} TSh ${_formatAmount(net.abs())}',
            style: TextStyle(
              color: isPositive ? _AppColors.positive : _AppColors.negative,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _financeAction({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 44,
      child: FilledButton.icon(
        onPressed: () async {
          if (!await _checkCurrentSubscriptionAccess()) {
            _showSubscriptionRequiredDialog();
          } else {
            onPressed();
          }
        },
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_Radius.sm),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DEBT METRICS
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildDebtMetrics(bool wide) {
    final debts = debtController;
    if (debts == null) return const SizedBox.shrink();
    return Obx(() {
      final metrics = [
        _DebtMetric(
          'home_debt_receivable'.tr,
          'TZS ${debts.receivableBalance.toStringAsFixed(0)}',
          Icons.call_received_rounded,
          _AppColors.positive,
          _AppColors.positiveBg,
        ),
        _DebtMetric(
          'home_debt_payable'.tr,
          'TZS ${debts.payableBalance.toStringAsFixed(0)}',
          Icons.call_made_rounded,
          _AppColors.warning,
          _AppColors.warningBg,
        ),
        _DebtMetric(
          'debt_overdue'.tr,
          debts.overdueCount.toString(),
          Icons.event_busy_outlined,
          _AppColors.negative,
          _AppColors.negativeBg,
        ),
      ];
      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = wide && constraints.maxWidth >= 640 ? 3 : 2;
          const spacing = _Spacing.md;
          final width =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: metrics
                .map(
                  (metric) => SizedBox(
                    width: width,
                    child: _debtMetricCard(metric, wide: wide),
                  ),
                )
                .toList(),
          );
        },
      );
    });
  }

  Widget _debtMetricCard(_DebtMetric metric, {bool wide = false}) {
    return Container(
      padding: EdgeInsets.all(wide ? _Spacing.lg : _Spacing.md),
      decoration: BoxDecoration(
        color: _AppColors.surface,
        borderRadius: BorderRadius.circular(_Radius.md),
        border: Border.all(color: _AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: wide ? 36 : 30,
                height: wide ? 36 : 30,
                decoration: BoxDecoration(
                  color: metric.background,
                  borderRadius: BorderRadius.circular(_Radius.sm),
                ),
                child: Icon(
                  metric.icon,
                  size: wide ? 18 : 15,
                  color: metric.color,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.more_horiz_rounded,
                size: 16,
                color: _AppColors.muted.withValues(alpha: 0.5),
              ),
            ],
          ),
          SizedBox(height: wide ? _Spacing.md : _Spacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              metric.value,
              style: TextStyle(
                color: _AppColors.ink,
                fontSize: wide ? 20 : 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            metric.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _AppColors.muted,
              fontSize: wide ? 12 : 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // QUICK ACTIONS
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildQuickActions() {
    final actions = <Widget>[
      if (_isSuperAdmin)
        _quickAction(
          'hub_title'.tr,
          Icons.admin_panel_settings_rounded,
          () => Get.toNamed(AppRoutes.adminHub),
        ),
      if (_isSuperAdmin)
        _quickAction(
          'admin_manage_analytics'.tr,
          Icons.insights_rounded,
          () => Get.toNamed(AppRoutes.adminAnalytics),
        ),
      if (BusinessAccessService.can('transactions', 'create'))
        _quickAction(
          'home_add_income'.tr,
          Icons.add_circle_outline_rounded,
          () => _openTransactionForm(TransactionType.income),
          accent: _AppColors.positive,
        ),
      if (BusinessAccessService.can('transactions', 'create'))
        _quickAction(
          'home_add_expense'.tr,
          Icons.remove_circle_outline_rounded,
          () => _openTransactionForm(TransactionType.expense),
          accent: _AppColors.negative,
        ),
      if (BusinessAccessService.can('invoices', 'view'))
        _quickAction(
          'home_view_invoices'.tr,
          Icons.receipt_long_outlined,
          () => _openRestrictedRoute(AppRoutes.invoicesList),
          accent: _AppColors.brand,
        ),
      if (_isSuperAdmin && BusinessAccessService.can('receipts', 'view'))
        _quickAction(
          'home_view_receipts'.tr,
          Icons.receipt_outlined,
          () => _openRestrictedRoute(AppRoutes.receiptsList),
        ),
      if (BusinessAccessService.can('transactions', 'view'))
        _quickAction(
          'home_finance_tracker'.tr,
          Icons.account_balance_wallet_outlined,
          () => _openRestrictedRoute(
            AppRoutes.transactions,
            refreshFinance: true,
          ),
        ),
      if (BusinessAccessService.can('jobs', 'view'))
        _quickAction(
          'home_manage_jobs'.tr,
          Icons.work_outline_rounded,
          () => _openRestrictedRoute(AppRoutes.jobs),
        ),
      if (BusinessAccessService.can('analytics', 'view'))
        _quickAction(
          'home_analytics'.tr,
          Icons.analytics_outlined,
          () => _openRestrictedRoute(AppRoutes.analytics),
        ),
      if (BusinessAccessService.can('invoices', 'create'))
        _quickAction(
          'pos_title'.tr,
          Icons.qr_code_scanner,
          () => _openRestrictedRoute(AppRoutes.pos),
          accent: _AppColors.positive,
        ),
      if (BusinessAccessService.can('stock', 'view'))
        _quickAction(
          'stk_title'.tr,
          Icons.inventory_2_outlined,
          () => _openRestrictedRoute(AppRoutes.stock),
        ),
      if (BusinessAccessService.can('categories', 'view'))
        _quickAction(
          'home_manage_categories'.tr,
          Icons.category_outlined,
          () => _openRestrictedRoute(AppRoutes.categories),
        ),
      _quickAction(
        BusinessAccessService.isOwner.value ? 'tk_all'.tr : 'tk_my'.tr,
        Icons.task_alt_rounded,
        () => _openRestrictedRoute(AppRoutes.tasks),
        accent: _AppColors.positive,
      ),
      if (BusinessAccessService.isOwner.value)
        _quickAction(
          'home_manage_staff'.tr,
          Icons.groups_2_outlined,
          () => _openRestrictedRoute(AppRoutes.staff),
        ),
      if (_isSuperAdmin)
        _quickAction(
          'admin_manage_subscriptions'.tr,
          Icons.manage_accounts_outlined,
          () => Get.toNamed(AppRoutes.adminSubscriptions),
        ),
      if (_isSuperAdmin)
        _quickAction(
          'home_create_receipt'.tr,
          Icons.add_business_outlined,
          () => _openRestrictedRoute(AppRoutes.addReceipt),
        ),
      if (BusinessAccessService.can('profile', 'view'))
        _quickAction(
          'Document design',
          Icons.palette_outlined,
          () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const DocumentDesignPage())),
        ),
      _quickAction('home_about'.tr, Icons.info_outline, _showAboutDialog),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 3 : 2;
        const spacing = _Spacing.md;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        final canInvoice = BusinessAccessService.can('invoices', 'create');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canInvoice) ...[
              _primaryInvoiceButton(),
              const SizedBox(height: spacing),
            ],
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: actions
                  .map((action) => SizedBox(width: width, child: action))
                  .toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _primaryInvoiceButton() {
    return Material(
      color: _AppColors.brand,
      borderRadius: BorderRadius.circular(_Radius.md),
      child: InkWell(
        onTap: () => _openRestrictedRoute(AppRoutes.invoice),
        borderRadius: BorderRadius.circular(_Radius.md),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: _Spacing.lg,
            vertical: _desktop ? 20 : 16,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(_Radius.sm),
                ),
                child: const Icon(Icons.note_add_rounded, color: Colors.white),
              ),
              const SizedBox(width: _Spacing.md),
              Expanded(
                child: Text(
                  'home_generate_invoice'.tr,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickAction(
    String title,
    IconData icon,
    VoidCallback onTap, {
    Color? accent,
  }) {
    final color = accent ?? _AppColors.brand;
    return Material(
      color: _AppColors.surface,
      borderRadius: BorderRadius.circular(_Radius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_Radius.md),
        child: Container(
          constraints: BoxConstraints(minHeight: _desktop ? 76 : 66),
          padding: EdgeInsets.all(_desktop ? _Spacing.lg : _Spacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_Radius.md),
            border: Border.all(color: _AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: _desktop ? 40 : 34,
                height: _desktop ? 40 : 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(_Radius.sm),
                ),
                child: Icon(icon, size: _desktop ? 20 : 17, color: color),
              ),
              SizedBox(width: _desktop ? _Spacing.md : _Spacing.sm),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _AppColors.ink,
                    fontSize: _desktop ? 13 : 11.5,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: _AppColors.muted.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TRANSACTIONS BUTTON & SUBSCRIPTION LINK
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildTransactionsButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () =>
            _openRestrictedRoute(AppRoutes.transactions, refreshFinance: true),
        icon: const Icon(Icons.receipt_long_outlined, size: 17),
        label: Text('home_view_all_transactions'.tr),
        style: OutlinedButton.styleFrom(
          foregroundColor: _AppColors.brand,
          backgroundColor: _AppColors.surface,
          side: const BorderSide(color: _AppColors.border),
          padding: const EdgeInsets.symmetric(
            horizontal: _Spacing.md,
            vertical: 14,
          ),
          alignment: Alignment.centerLeft,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_Radius.sm),
          ),
        ),
      ),
    );
  }

  Widget _buildSubscriptionLink() {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: () async {
          await Get.toNamed(AppRoutes.subscription);
          await _loadSubscriptionStatus();
        },
        icon: const Icon(Icons.workspace_premium_outlined, size: 17),
        label: Text(
          isSubscribed || isTrial
              ? 'home_manage_subscription'.tr
              : 'home_subscription'.tr,
        ),
        style: TextButton.styleFrom(
          foregroundColor: _AppColors.brand,
          padding: const EdgeInsets.symmetric(vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_Radius.sm),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────
  Widget _softIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: _AppColors.borderSoft,
        borderRadius: BorderRadius.circular(_Radius.sm),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 16, color: _AppColors.inkSoft),
      ),
    );
  }

  Future<void> _openTransactionForm(TransactionType type) async {
    if (!BusinessAccessService.can('transactions', 'create')) {
      Get.snackbar('error'.tr, 'staff_no_permission'.tr);
      return;
    }
    if (!await _checkCurrentSubscriptionAccess()) {
      _showSubscriptionRequiredDialog();
      return;
    }
    final result = await Get.to<bool>(
      () => AddTransactionPage(initialType: type),
    );
    if (result == true && mounted) await _loadFinanceSummary();
  }

  Future<void> _openTransactionsByType(TransactionType type) async {
    if (!BusinessAccessService.can('transactions', 'view')) {
      Get.snackbar('error'.tr, 'staff_no_permission'.tr);
      return;
    }
    if (!await _checkCurrentSubscriptionAccess()) {
      _showSubscriptionRequiredDialog();
      return;
    }
    await Get.toNamed(
      AppRoutes.transactions,
      arguments: {
        'type': type == TransactionType.income ? 'income' : 'expense',
        'period': _financePeriod.name,
      },
    );
    if (mounted) await _loadFinanceSummary();
  }

  String _formatAmount(double amount) =>
      NumberFormat('#,##0.00').format(amount);

  String get _currentMonthLabel {
    final now = DateTime.now();
    return '${now.month.toString().padLeft(2, '0')}/${now.year}';
  }

  void _showSubscriptionRequiredDialog() {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_Radius.md),
        ),
        title: Row(
          children: [
            const Icon(Icons.lock_outline, color: _AppColors.brand),
            const SizedBox(width: 8),
            Flexible(child: Text('subscription_required_title'.tr)),
          ],
        ),
        content: Text('subscription_required_message'.tr),
        actions: [
          TextButton(onPressed: Get.back, child: Text('cancel'.tr)),
          if (BusinessAccessService.isOwner.value)
            FilledButton(
              onPressed: () {
                Get.back();
                _openSubscription();
              },
              style: FilledButton.styleFrom(backgroundColor: _AppColors.brand),
              child: Text('sub_subscribe_now'.tr),
            ),
        ],
      ),
      barrierDismissible: true,
    );
  }

  void _openSubscription() {
    Get.toNamed(AppRoutes.subscription)?.then((_) => _loadSubscriptionStatus());
  }

  void _showAboutDialog() {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_Radius.md),
        ),
        title: Text('home_about'.tr),
        content: const Text(
          'Mjasi POS helps you manage income, expenses, invoices, receipts and jobs.',
        ),
        actions: [TextButton(onPressed: Get.back, child: Text('close'.tr))],
      ),
    );
  }
}

class _DebtMetric {
  const _DebtMetric(
    this.label,
    this.value,
    this.icon,
    this.color,
    this.background,
  );

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;
}
