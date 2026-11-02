import 'dart:async';
import 'dart:math' show Random;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:tra_list/invoice/add_transaction_page.dart';
import 'package:tra_list/invoice/analytics_page.dart';
import 'package:tra_list/invoice/language_controller.dart';
import 'package:tra_list/invoice/transaction_model.dart';
import 'package:tra_list/invoice/transaction_service.dart';
import 'package:tra_list/jobs/controllers/debt_controller.dart';
import 'package:tra_list/market/explore_page.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/services/pages/ProfilePage.dart';
import 'package:tra_list/services/pages/document_design_page.dart';
import 'package:tra_list/services/profile_service.dart';
import 'package:tra_list/services/account_deletion_service.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/chat_page.dart';
import 'package:tra_list/services/notifications_page.dart';
import 'package:tra_list/services/account_mode_service.dart';
import 'package:tra_list/services/personal_device_lock_service.dart';
import 'package:tra_list/services/personal_finance_page.dart';
import 'package:tra_list/services/support_center_fab.dart';
import 'package:tra_list/services/staff_service.dart';
import 'package:tra_list/stock/products_pages.dart';
import 'package:tra_list/tasks/task_banner.dart';
import 'package:tra_list/tasks/task_service.dart';
import 'package:tra_list/services/push_service.dart';
import 'package:tra_list/theme/app_theme.dart';
import 'services/subscription_controller.dart';

enum _FinancePeriod { today, yesterday, thisWeek, thisMonth }

enum _HomeDestination { dashboard, explore, reports, chat }

class _StaffStat {
  _StaffStat(this.name);
  final String name;
  double income = 0;
  double expense = 0;
  int count = 0;
}

class _BusinessRecommendation {
  const _BusinessRecommendation({
    required this.titleKey,
    required this.descriptionKey,
    required this.icon,
    required this.color,
  });

  final String titleKey;
  final String descriptionKey;
  final IconData icon;
  final Color color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────
class _AppColors {
  static const ink = MjasiColors.textPrimary;
  static const inkSoft = MjasiColors.textPrimary;
  static const muted = MjasiColors.textSecondary;
  static const canvas = MjasiColors.background;
  static const surface = MjasiColors.surface;
  static const border = MjasiColors.border;
  static const borderSoft = MjasiColors.background;
  static const brand = MjasiColors.primaryBlue;
  static const brandDeep = MjasiColors.primaryNavy;
  static const positive = MjasiColors.success;
  static const positiveBg = MjasiColors.successBackground;
  static const negative = MjasiColors.error;
  static const negativeBg = MjasiColors.errorBackground;
  static const warning = MjasiColors.warning;
  static const warningBg = MjasiColors.warningBackground;
}

class _Spacing {
  static const xs = MjasiSpacing.xs;
  static const sm = MjasiSpacing.sm;
  static const md = MjasiSpacing.md;
  static const lg = MjasiSpacing.lg;
  static const xl = MjasiSpacing.xl;
  static const xxl = MjasiSpacing.xxl;
}

class _Radius {
  static const sm = MjasiRadius.sm;
  static const md = MjasiRadius.md;
  static const lg = MjasiRadius.lg;
  static const pill = MjasiRadius.pill;
}

// ─────────────────────────────────────────────────────────────────────────────
// HomePage
// ─────────────────────────────────────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.initialSection});

  final String? initialSection;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _personalFinanceKey = GlobalKey<PersonalFinancePageState>();
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
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
  String ownerName = '';
  String businessAddress = '';
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
  bool _quickActionsOpen = false;
  bool _desktopRailExtended = true;
  late _HomeDestination _activeDestination;
  List<_StaffStat> staffStats = [];
  List<String> _availableShopNicknames = [];
  Map<String, String> _shopByStaffUid = {};
  Map<String, String> _nameByStaffUid = {};
  String _selectedShopNickname = '';
  _FinancePeriod _financePeriod = _FinancePeriod.thisWeek;
  int _financeRequest = 0;
  bool _desktop = false;
  bool _isOnline = false;

  String get _normalizedUserRole =>
      userRole.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  bool get _isSuperAdmin => _normalizedUserRole == 'superadmin';

  bool get _isPersonalMode =>
      AccountModeService.current == AccountMode.personal;

  bool get _canSwitchBusiness =>
      BusinessAccessService.availableBusinesses
          .where((business) => business.isActive)
          .length >
      1;

  bool get _canSelectDashboardShop =>
      BusinessAccessService.isOwner.value &&
      _availableShopNicknames.isNotEmpty;

  bool get _hasSubscriptionExemption =>
      _isSuperAdmin || _normalizedUserRole == 'admin';

  @override
  void initState() {
    super.initState();
    _activeDestination = switch (widget.initialSection) {
      'explore' => _HomeDestination.explore,
      'reports' => _HomeDestination.reports,
      'chat' => _HomeDestination.chat,
      _ => _HomeDestination.dashboard,
    };
    _initConnectivityStatus();
    if (_isPersonalMode) unawaited(PersonalDeviceLockService.ensure());
    if (!_isPersonalMode && BusinessAccessService.can('jobs', 'view')) {
      debtController = Get.put(DebtController());
    }
    _loadUserRole();
    _loadSubscriptionStatus();
    _loadFinanceSummary();
  }

  @override
  void dispose() {
    unawaited(_connectivitySubscription?.cancel());
    super.dispose();
  }

  Future<void> _initConnectivityStatus() async {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _setConnectivityStatus,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Could not observe network connectivity: $error');
        debugPrintStack(stackTrace: stackTrace);
        _setConnectivityStatus(const [ConnectivityResult.none]);
      },
    );
    try {
      _setConnectivityStatus(await _connectivity.checkConnectivity());
    } catch (error, stackTrace) {
      debugPrint('Could not check network connectivity: $error');
      debugPrintStack(stackTrace: stackTrace);
      _setConnectivityStatus(const [ConnectivityResult.none]);
    }
  }

  void _setConnectivityStatus(List<ConnectivityResult> results) {
    if (!mounted) return;
    final isOnline = results.any((result) => result != ConnectivityResult.none);
    if (_isOnline != isOnline) setState(() => _isOnline = isOnline);
  }

  // ── Data loading (unchanged logic) ─────────────────────────────────────────
  Future<void> _loadFinanceSummary() async {
    if (_isPersonalMode) {
      if (!mounted) return;
      setState(() {
        financeLoading = false;
        financeError = null;
        financeIncome = 0;
        financeExpense = 0;
      });
      return;
    }
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
        shopNickname: _selectedShopNickname.isEmpty
            ? null
            : _selectedShopNickname,
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
        ..._nameByStaffUid,
        for (final m in members.docs)
          m.id: (m.data()['name'] ?? '').toString().trim(),
      };
      final snap = await TransactionService.getTransactions(
        limit: 1000,
        startDate: start,
        endDate: end,
        shopNickname: _selectedShopNickname.isEmpty
            ? null
            : _selectedShopNickname,
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
        Set<String>? invoiceStaffUids;
        if (_selectedShopNickname.isNotEmpty) {
          invoiceStaffUids = {
            for (final entry in _shopByStaffUid.entries)
              if (entry.value == _selectedShopNickname) entry.key,
          };
          final ownerUid = FirebaseAuth.instance.currentUser?.uid;
          if (_selectedShopNickname == shopNickname && ownerUid != null) {
            invoiceStaffUids.add(ownerUid);
          }
        }
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
          if (invoiceStaffUids != null &&
              !invoiceStaffUids.contains(data['uid']?.toString())) {
            continue;
          }
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
        final taskList = await TaskService.watchTasks().first;
        tasks = taskList
            .where(
              (task) =>
                  !task.isFinal &&
                  (_selectedShopNickname.isEmpty ||
                      task.assigneeShop.trim() == _selectedShopNickname),
            )
            .length;
      } catch (error, stackTrace) {
        debugPrint('Could not load dashboard task count: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
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

  List<_BusinessRecommendation> _buildBusinessRecommendations() {
    final recommendations = <_BusinessRecommendation>[
      const _BusinessRecommendation(
        titleKey: 'home_ai_next_step_review_goal',
        descriptionKey: 'home_ai_next_step_review_goal_desc',
        icon: Icons.flag_outlined,
        color: MjasiColors.primaryBlue,
      ),
      const _BusinessRecommendation(
        titleKey: 'home_ai_next_step_follow_up_customers',
        descriptionKey: 'home_ai_next_step_follow_up_customers_desc',
        icon: Icons.people_alt_outlined,
        color: Color(0xFF7C3AED),
      ),
    ];
    final net = financeIncome - financeExpense;

    if (financeIncome <= 0) {
      recommendations.add(
        const _BusinessRecommendation(
          titleKey: 'home_ai_next_step_record_sales',
          descriptionKey: 'home_ai_next_step_record_sales_desc',
          icon: Icons.point_of_sale_rounded,
          color: MjasiColors.warning,
        ),
      );
      recommendations.add(
        const _BusinessRecommendation(
          titleKey: 'home_ai_next_step_review_pricing',
          descriptionKey: 'home_ai_next_step_review_pricing_desc',
          icon: Icons.sell_outlined,
          color: MjasiColors.error,
        ),
      );
    } else {
      final expenseRatio = financeExpense / financeIncome;
      if (expenseRatio >= 0.65) {
        recommendations.add(
          const _BusinessRecommendation(
            titleKey: 'home_ai_next_step_review_costs',
            descriptionKey: 'home_ai_next_step_review_costs_desc',
            icon: Icons.trending_down_rounded,
            color: MjasiColors.error,
          ),
        );
        if (net <= 0) {
          recommendations.add(
            const _BusinessRecommendation(
              titleKey: 'home_ai_next_step_review_pricing',
              descriptionKey: 'home_ai_next_step_review_pricing_desc',
              icon: Icons.sell_outlined,
              color: MjasiColors.error,
            ),
          );
        }
      }
      if (net > 0) {
        recommendations.add(
          const _BusinessRecommendation(
            titleKey: 'home_ai_next_step_protect_surplus',
            descriptionKey: 'home_ai_next_step_protect_surplus_desc',
            icon: Icons.savings_outlined,
            color: MjasiColors.success,
          ),
        );
      }
    }

    if (_selectedShopNickname.isEmpty) {
      if (docCount == 0) {
        recommendations.add(
          const _BusinessRecommendation(
            titleKey: 'home_ai_next_step_invoice_sales',
            descriptionKey: 'home_ai_next_step_invoice_sales_desc',
            icon: Icons.receipt_long_outlined,
            color: Color(0xFF7C3AED),
          ),
        );
      } else if (docTotal > financeIncome) {
        recommendations.add(
          const _BusinessRecommendation(
            titleKey: 'home_ai_next_step_reconcile_payments',
            descriptionKey: 'home_ai_next_step_reconcile_payments_desc',
            icon: Icons.fact_check_outlined,
            color: Color(0xFF7C3AED),
          ),
        );
      }
    }

    if (taskCount > 0) {
      recommendations.add(
        const _BusinessRecommendation(
          titleKey: 'home_ai_next_step_prioritize_tasks',
          descriptionKey: 'home_ai_next_step_prioritize_tasks_desc',
          icon: Icons.task_alt_rounded,
          color: MjasiColors.warning,
        ),
      );
    }
    if ((staffCount ?? 0) > 0) {
      recommendations.add(
        const _BusinessRecommendation(
          titleKey: 'home_ai_next_step_align_team',
          descriptionKey: 'home_ai_next_step_align_team_desc',
          icon: Icons.groups_2_outlined,
          color: MjasiColors.primaryBlue,
        ),
      );
    }

    recommendations.shuffle(Random());
    return recommendations.take(3).toList();
  }

  Future<void> _showHomeBusinessSummary() async {
    if (financeLoading) await _loadFinanceSummary();
    if (!mounted) return;

    final net = financeIncome - financeExpense;
    final recommendations = _buildBusinessRecommendations();
    final insight = financeIncome <= 0
        ? 'home_ai_no_income_insight'.tr
        : (financeIncome - financeExpense).abs() < 0.01
        ? 'analytics_summary_balanced'.tr
        : net > 0
        ? 'analytics_summary_positive'.tr
        : 'analytics_summary_negative'.tr;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_Radius.lg),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [MjasiColors.primaryNavy, MjasiColors.primaryBlue],
                ),
                borderRadius: BorderRadius.circular(_Radius.sm),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 21,
              ),
            ),
            const SizedBox(width: _Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'analytics_ai_summary'.tr,
                    style: const TextStyle(
                      color: _AppColors.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    _financePeriodLabel(_financePeriod),
                    style: const TextStyle(
                      color: _AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'close'.tr,
              onPressed: () => Navigator.of(dialogContext).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * .68,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (financeLoading)
                  const Center(child: CircularProgressIndicator())
                else if (financeError != null)
                  Text(
                    financeError!,
                    style: const TextStyle(color: MjasiColors.error),
                  )
                else ...[
                  _homeSummaryMetric(
                    'analytics_total_income'.tr,
                    'TSH ${_formatAmount(financeIncome)}',
                    Icons.south_west_rounded,
                    MjasiColors.success,
                  ),
                  _homeSummaryMetric(
                    'analytics_total_expense'.tr,
                    'TSH ${_formatAmount(financeExpense)}',
                    Icons.north_east_rounded,
                    MjasiColors.error,
                  ),
                  _homeSummaryMetric(
                    'net'.tr,
                    '${net >= 0 ? '+' : '-'}TSH ${_formatAmount(net.abs())}',
                    Icons.account_balance_wallet_rounded,
                    net >= 0 ? MjasiColors.primaryBlue : MjasiColors.warning,
                  ),
                  const SizedBox(height: _Spacing.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(_Spacing.md),
                    decoration: BoxDecoration(
                      color: MjasiColors.primaryBlue.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(_Radius.sm),
                    ),
                    child: Text(
                      insight,
                      style: const TextStyle(
                        color: _AppColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: _Spacing.lg),
                  Text(
                    'home_ai_next_steps'.tr,
                    style: const TextStyle(
                      color: _AppColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: _Spacing.sm),
                  for (final recommendation in recommendations)
                    _homeRecommendationCard(recommendation),
                  const SizedBox(height: _Spacing.md),
                  Text(
                    'analytics_summary_disclaimer'.tr,
                    style: const TextStyle(
                      color: _AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _homeRecommendationCard(_BusinessRecommendation recommendation) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: _Spacing.sm),
      padding: const EdgeInsets.all(_Spacing.md),
      decoration: BoxDecoration(
        color: recommendation.color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(_Radius.sm),
        border: Border(
          left: BorderSide(color: recommendation.color, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(recommendation.icon, color: recommendation.color, size: 20),
          const SizedBox(width: _Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recommendation.titleKey.tr,
                  style: TextStyle(
                    color: recommendation.color,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  recommendation.descriptionKey.tr,
                  style: const TextStyle(
                    color: _AppColors.ink,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _homeSummaryMetric(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: _Spacing.sm),
      padding: const EdgeInsets.all(_Spacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(_Radius.sm),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: _Spacing.md),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: _Spacing.sm),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: _AppColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _selectFinancePeriod(_FinancePeriod period) {
    if (_financePeriod == period) return;
    setState(() => _financePeriod = period);
    _loadFinanceSummary();
  }

  Future<void> _loadSubscriptionStatus() async {
    if (_isPersonalMode) return;
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
    if (_isPersonalMode) {
      if (!mounted) return;
      setState(() {
        userRole = 'personal';
        storeName = '';
        shopNickname = '';
        ownerName = '';
        businessAddress = '';
        loading = false;
      });
      return;
    }
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
        ownerName =
            FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
        loading = false;
      });
      return;
    }
    try {
      final profile = await ProfileService.loadOrCreate();
      final availableShopNicknames = <String>{};
      final profileShopNickname =
          profile['shopNickname']?.toString().trim() ?? '';
      final shopByStaffUid = <String, String>{};
      final nameByStaffUid = <String, String>{};
      if (profileShopNickname.isNotEmpty) {
        availableShopNicknames.add(profileShopNickname);
      }
      try {
        final staff = await StaffService.fetchStaff();
        shopByStaffUid.addEntries(
          staff
              .where((member) => member.data['active'] == true)
              .map(
                (member) => MapEntry(
                  member.id,
                  member.data['shopNickname']?.toString().trim() ?? '',
                ),
              )
              .where((entry) => entry.value.isNotEmpty),
        );
        nameByStaffUid.addEntries(
          staff
              .where((member) => member.data['active'] == true)
              .map(
                (member) => MapEntry(
                  member.id,
                  member.data['name']?.toString().trim() ?? '',
                ),
              ),
        );
        availableShopNicknames.addAll(
          staff
              .where((member) => member.data['active'] == true)
              .map(
                (member) =>
                    member.data['shopNickname']?.toString().trim() ?? '',
              )
              .where((nickname) => nickname.isNotEmpty),
        );
      } catch (error, stackTrace) {
        debugPrint('Could not load dashboard shop branches: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      if (!mounted) return;
      setState(() {
        userRole = profile['role']?.toString() ?? 'user';
        storeName = profile['name']?.toString().trim() ?? '';
        shopNickname = profileShopNickname;
        _availableShopNicknames = availableShopNicknames.toList()..sort();
        _shopByStaffUid = shopByStaffUid;
        _nameByStaffUid = nameByStaffUid;
        ownerName =
            profile['ownerName']?.toString().trim() ??
            FirebaseAuth.instance.currentUser?.displayName?.trim() ??
            '';
        businessAddress = profile['address']?.toString().trim() ?? '';
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
        ownerName = '';
        businessAddress = '';
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

    final useNavigationRail = MediaQuery.sizeOf(context).width >= 900;
    final mobileBusinessDashboard =
        !useNavigationRail &&
        !_isPersonalMode &&
        _activeDestination == _HomeDestination.dashboard;
    return SupportCenterFabOverlay(
      onAiAnalysisPressed: _showHomeBusinessSummary,
      child: Scaffold(
        backgroundColor: _activeDestination == _HomeDestination.chat
            ? const Color(0xFF191D24)
            : mobileBusinessDashboard
            ? Colors.white
            : _AppColors.canvas,
        bottomNavigationBar: useNavigationRail
            ? null
            : _buildMobileNavigation(),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (_activeDestination != _HomeDestination.chat &&
                  !mobileBusinessDashboard)
                _buildHeader(context),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final showNavigationRail = constraints.maxWidth >= 900;
                    return Row(
                      children: [
                        if (showNavigationRail)
                          Container(
                            decoration: const BoxDecoration(
                              color: MjasiColors.primaryNavy,
                              border: Border(
                                right: BorderSide(color: Color(0xFF263952)),
                              ),
                            ),
                            child: _buildNavigationRail(
                              extended: _desktopRailExtended,
                            ),
                          ),
                        Expanded(child: _buildActiveContent(context)),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveContent(BuildContext context) {
    return switch (_activeDestination) {
      _HomeDestination.dashboard =>
        _isPersonalMode
            ? PersonalFinancePage(key: _personalFinanceKey, embedded: true)
            : _buildDashboardContent(context),
      _HomeDestination.explore => const MarketExplorePage(),
      _HomeDestination.reports =>
        _isPersonalMode
            ? PersonalFinancePage(
                key: _personalFinanceKey,
                embedded: true,
                analyticsOnly: true,
              )
            : const AnalyticsPage(),
      _HomeDestination.chat => const ChatPage(),
    };
  }

  void _selectDestination(_HomeDestination destination) {
    if (!mounted) return;
    if (kIsWeb) {
      final route = switch (destination) {
        _HomeDestination.dashboard => AppRoutes.home,
        _HomeDestination.explore => AppRoutes.getHomeSectionRoute('explore'),
        _HomeDestination.reports => AppRoutes.getHomeSectionRoute('reports'),
        _HomeDestination.chat => AppRoutes.getHomeSectionRoute('chat'),
      };
      if (Get.currentRoute != route) unawaited(Get.toNamed(route));
      return;
    }
    setState(() => _activeDestination = destination);
  }

  Future<void> _openMarket() async {
    if (!mounted) return;
    await Get.toNamed(AppRoutes.market);
  }

  Future<void> _openChat() async {
    _selectDestination(_HomeDestination.chat);
  }

  Widget _buildDashboardContent(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 960;
        _desktop = wide;
        if (constraints.maxWidth < 600 && !_isPersonalMode) {
          return _buildMobileBusinessDashboard();
        }
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
          _sectionHeading('home_quick_access'.tr, 'home_quick_access_sub'.tr),
          const SizedBox(height: _Spacing.md),
          _buildQuickActions(),
          const SizedBox(height: _Spacing.xl),
          if (BusinessAccessService.can('transactions', 'view')) ...[
            _sectionHeading('home_transactions'.tr, 'home_transactions'.tr),
            const SizedBox(height: _Spacing.md),
            _buildTransactionsButton(),
            const SizedBox(height: _Spacing.lg),
          ],
          if (BusinessAccessService.isOwner.value) _buildSubscriptionLink(),
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
                constraints: const BoxConstraints(maxWidth: 1440),
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
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: financeColumn,
                            ),
                          ),
                          const SizedBox(width: _Spacing.xl),
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: actionsColumn,
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
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
    );
  }

  Widget _buildMobileBusinessDashboard() {
    final user = FirebaseAuth.instance.currentUser;
    final greetingName = ownerName.isNotEmpty
        ? ownerName.split(RegExp(r'\s+')).first
        : user?.displayName?.trim().split(RegExp(r'\s+')).first ??
              user?.email?.split('@').first ??
              'MJASI';
    final activeShopNickname = BusinessAccessService.isOwner.value
        ? _selectedShopNickname
        : shopNickname;
    final shopSubtitle = BusinessAccessService.isOwner.value
        ? activeShopNickname.isNotEmpty
              ? activeShopNickname
              : 'home_all_shops'.tr
        : activeShopNickname.isNotEmpty
        ? activeShopNickname
        : storeName;
    final canViewFinance =
        BusinessAccessService.can('transactions', 'view') ||
        BusinessAccessService.can('analytics', 'view');

    return RefreshIndicator(
      onRefresh: _loadFinanceSummary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
        children: [
          _buildMobileHomeHeader(user),
          const SizedBox(height: 20),
          Text(
            'mobile_greeting'.trParams({'name': greetingName}),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF10233F),
              fontSize: 23,
              fontWeight: FontWeight.w800,
              letterSpacing: -.55,
            ),
          ),
          const SizedBox(height: 4),
          Tooltip(
            message: 'home_select_shop'.tr,
            child: InkWell(
              onTap: _canSelectDashboardShop ? _selectDashboardShop : null,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        BusinessAccessService.isOwner.value &&
                                activeShopNickname.isEmpty
                            ? shopSubtitle
                            : 'mobile_shop_label'.trParams({
                                'shop': activeShopNickname,
                              }),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF26364C),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (_canSelectDashboardShop)
                      const Padding(
                        padding: EdgeInsets.only(left: 5),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: Color(0xFF26364C),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildMobileBalanceCard(canViewFinance),
          const SizedBox(height: 10),
          _buildMobilePaymentActions(),
          if (canViewFinance) ...[
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'home_finance_summary'.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF10233F),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.35,
                    ),
                  ),
                ),
                _periodPicker(),
              ],
            ),
            const SizedBox(height: 12),
            _buildMobileFinanceSummary(),
          ],
          const SizedBox(height: 20),
          _buildMobileShortcuts(),
          const SizedBox(height: 22),
          _buildMobileMarketBanner(),
          if (BusinessAccessService.isOwner.value) ...[
            const SizedBox(height: 14),
            _buildSubscriptionLink(),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileHomeHeader(User? user) {
    final initials =
        (ownerName.isNotEmpty
                ? ownerName
                : user?.displayName ?? user?.email?.split('@').first ?? 'MJ')
            .trim()
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .take(2)
            .map((part) => part.characters.first.toUpperCase())
            .join();
    return Row(
      children: [
        IconButton(
          tooltip: 'home_more'.tr,
          onPressed: _showMoreActions,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.menu_rounded, size: 27),
          color: const Color(0xFF10233F),
        ),
        const SizedBox(width: 2),
        const Expanded(
          child: Text(
            'MJASI Social POS',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0xFF10233F),
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -.55,
            ),
          ),
        ),
        _buildLanguageButton(dark: true),
        if (!_isPersonalMode)
          const NotificationBell(iconColor: Color(0xFF10233F)),
        const SizedBox(width: 4),
        InkWell(
          onTap: _isPersonalMode
              ? () => Get.toNamed(AppRoutes.personalSettings)
              : _openProfile,
          customBorder: const CircleBorder(),
          child: CircleAvatar(
            radius: 21,
            backgroundColor: const Color(0xFF0D6FEB),
            foregroundImage: user?.photoURL == null
                ? null
                : NetworkImage(user!.photoURL!),
            child: Text(
              initials.isEmpty ? 'MJ' : initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileBalanceCard(bool canViewFinance) {
    final balance = financeIncome - financeExpense;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1266D8), Color(0xFF064CB5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x251256C4),
            blurRadius: 16,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'mobile_business_balance'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .88),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                if (financeLoading && canViewFinance)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'TZS ${_formatAmount(canViewFinance ? balance : 0)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.55,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (BusinessAccessService.can('transactions', 'create'))
            TextButton.icon(
              onPressed: () => _openTransactionForm(TransactionType.income),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF084AA9),
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 10,
                ),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 17),
              label: Text('mobile_add_sale'.tr),
            ),
        ],
      ),
    );
  }

  Widget _buildMobilePaymentActions() {
    final actions = <({String label, IconData icon, VoidCallback onTap})>[
      if (BusinessAccessService.can('transactions', 'create'))
        (
          label: 'income'.tr,
          icon: Icons.south_rounded,
          onTap: () => _openTransactionForm(TransactionType.income),
        ),
      if (BusinessAccessService.can('transactions', 'create'))
        (
          label: 'expense'.tr,
          icon: Icons.north_rounded,
          onTap: () => _openTransactionForm(TransactionType.expense),
        ),
      if (BusinessAccessService.can('staff', 'view') ||
          BusinessAccessService.isOwner.value)
        (
          label: 'home_manage_staff'.tr,
          icon: Icons.groups_2_outlined,
          onTap: () => _openRestrictedRoute(AppRoutes.staff),
        ),
      if (BusinessAccessService.can('invoices', 'view'))
        (
          label: 'home_view_invoices'.tr,
          icon: Icons.receipt_long_outlined,
          onTap: () => _openRestrictedRoute(AppRoutes.invoicesList),
        ),
      (
        label: 'home_more'.tr,
        icon: Icons.more_horiz_rounded,
        onTap: _showMoreActions,
      ),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FD),
        border: Border.all(color: const Color(0xFFE6ECF5)),
        borderRadius: BorderRadius.circular(19),
      ),
      child: Row(
        children: [
          for (final action in actions)
            Expanded(
              child: InkWell(
                onTap: action.onTap,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        action.icon,
                        color: const Color(0xFF0759BE),
                        size: 24,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        action.label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF17263D),
                          fontSize: 9.5,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMobileFinanceSummary() {
    final metrics = [
      (
        title: 'income'.tr,
        amount: financeIncome,
        color: const Color(0xFF059669),
        background: const Color(0xFFE6F7F1),
        icon: Icons.north_east_rounded,
        onTap: () => _openTransactionsByType(TransactionType.income),
      ),
      (
        title: 'expenses'.tr,
        amount: financeExpense,
        color: const Color(0xFFB4232D),
        background: const Color(0xFFFCEBED),
        icon: Icons.south_west_rounded,
        onTap: () => _openTransactionsByType(TransactionType.expense),
      ),
      (
        title: 'net'.tr,
        amount: financeIncome - financeExpense,
        color: const Color(0xFF1459B8),
        background: const Color(0xFFEAF2FF),
        icon: Icons.bar_chart_rounded,
        onTap: () =>
            _openRestrictedRoute(AppRoutes.transactions, refreshFinance: true),
      ),
    ];
    return Row(
      children: [
        for (var index = 0; index < metrics.length; index++) ...[
          if (index > 0) const SizedBox(width: 7),
          Expanded(
            child: Material(
              color: metrics[index].background,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: metrics[index].onTap,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 11, 8, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            metrics[index].icon,
                            color: metrics[index].color,
                            size: 19,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              metrics[index].title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF17263D),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'TZS ${_formatAmount(metrics[index].amount)}',
                          style: TextStyle(
                            color: metrics[index].color,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.3,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMobileShortcuts() {
    final shortcuts = <({String label, IconData icon, VoidCallback onTap})>[
      (
        label: 'efd_receipt'.tr,
        icon: Icons.receipt_rounded,
        onTap: () {
          if (_isSuperAdmin) {
            _openRestrictedRoute(AppRoutes.addReceipt);
          } else {
            Get.snackbar(
              'efd_receipt'.tr,
              'efd_receipt_coming_soon'.tr,
              snackPosition: SnackPosition.BOTTOM,
            );
          }
        },
      ),
      if (BusinessAccessService.canUseBarPos)
        (
          label: 'pos_title'.tr,
          icon: Icons.point_of_sale_rounded,
          onTap: () => _openRestrictedRoute(AppRoutes.pos),
        ),
      if (BusinessAccessService.can('stock', 'view'))
        (
          label: 'stk_title'.tr,
          icon: Icons.inventory_2_outlined,
          onTap: () => _openRestrictedRoute(AppRoutes.stock),
        ),
      if (BusinessAccessService.can('invoices', 'view'))
        (
          label: 'home_view_invoices'.tr,
          icon: Icons.receipt_long_outlined,
          onTap: () => _openRestrictedRoute(AppRoutes.invoicesList),
        ),
      if (BusinessAccessService.can('categories', 'view'))
        (
          label: 'home_manage_categories'.tr,
          icon: Icons.category_outlined,
          onTap: () => _openRestrictedRoute(AppRoutes.categories),
        ),
      if (BusinessAccessService.can('staff', 'view') ||
          BusinessAccessService.isOwner.value)
        (
          label: 'home_manage_staff'.tr,
          icon: Icons.groups_2_outlined,
          onTap: () => _openRestrictedRoute(AppRoutes.staff),
        ),
      if (BusinessAccessService.can('tasks', 'view') ||
          BusinessAccessService.isActive.value)
        (
          label: 'tk_my'.tr,
          icon: Icons.task_alt_rounded,
          onTap: () => _openRestrictedRoute(AppRoutes.tasks),
        ),
      if (BusinessAccessService.can('jobs', 'view'))
        (
          label: 'home_manage_jobs'.tr,
          icon: Icons.work_outline_rounded,
          onTap: () => _openRestrictedRoute(AppRoutes.jobs),
        ),
      if (BusinessAccessService.can('analytics', 'view'))
        (
          label: 'home_analytics'.tr,
          icon: Icons.bar_chart_rounded,
          onTap: () => _openRestrictedRoute(AppRoutes.analytics),
        ),
    ];
    if (shortcuts.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 7.0;
        const columns = 4;
        final tileWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final shortcut in shortcuts)
              SizedBox(
                width: tileWidth,
                height: 92,
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    onTap: shortcut.onTap,
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE5EAF2)),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            shortcut.icon,
                            color: const Color(0xFF0759BE),
                            size: 30,
                          ),
                          const SizedBox(height: 7),
                          Text(
                            shortcut.label,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF17263D),
                              fontSize: 10.5,
                              height: 1.15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMobileMarketBanner() {
    return Material(
      color: const Color(0xFFEAF2FF),
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        onTap: _openMarket,
        borderRadius: BorderRadius.circular(19),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF0D6FEB),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'mobile_market_title'.tr,
                      style: const TextStyle(
                        color: Color(0xFF10233F),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'mobile_market_subtitle'.tr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF26364C),
                        fontSize: 11.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF10233F),
                size: 27,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationRail({required bool extended}) {
    final railTextStyle = TextStyle(
      color: Colors.white.withValues(alpha: .82),
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    final destinations = <NavigationRailDestination>[
      NavigationRailDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home_rounded),
        label: Text(
          _isPersonalMode ? 'personal_title'.tr : 'home_dashboard_label'.tr,
        ),
      ),
    ];
    final actions = <VoidCallback?>[
      () => _selectDestination(_HomeDestination.dashboard),
    ];
    var selectedIndex = 0;

    if (_activeDestination == _HomeDestination.explore) {
      selectedIndex = destinations.length;
    }
    destinations.add(
      NavigationRailDestination(
        icon: const Icon(Icons.explore_outlined),
        selectedIcon: const Icon(Icons.explore_rounded),
        label: Text('explore_title'.tr),
      ),
    );
    actions.add(_openMarket);
    if (!_isPersonalMode && BusinessAccessService.hasBusinessAccess) {
      if (_activeDestination == _HomeDestination.chat) {
        selectedIndex = destinations.length;
      }
      destinations.add(
        NavigationRailDestination(
          icon: const Icon(Icons.chat_bubble_outline_rounded),
          selectedIcon: const Icon(Icons.chat_rounded),
          label: Text('chat_nav_label'.tr),
        ),
      );
      actions.add(_openChat);
    }
    if (BusinessAccessService.can('analytics', 'view') || _isPersonalMode) {
      if (_activeDestination == _HomeDestination.reports) {
        selectedIndex = destinations.length;
      }
      destinations.add(
        NavigationRailDestination(
          icon: const Icon(Icons.insert_chart_outlined),
          selectedIcon: const Icon(Icons.insert_chart_rounded),
          label: Text('home_analytics'.tr),
        ),
      );
      actions.add(
        () => _isPersonalMode
            ? _selectDestination(_HomeDestination.reports)
            : _openRestrictedRoute(
                AppRoutes.analytics,
                destination: _HomeDestination.reports,
              ),
      );
    }
    destinations.add(
      NavigationRailDestination(
        icon: const Icon(Icons.grid_view_outlined),
        selectedIcon: const Icon(Icons.grid_view_rounded),
        label: Text('home_more'.tr),
      ),
    );
    actions.add(() => _showMoreActions(desktop: true));

    return NavigationRail(
      extended: extended,
      minWidth: 76,
      minExtendedWidth: 208,
      labelType: extended ? null : NavigationRailLabelType.all,
      backgroundColor: Colors.transparent,
      indicatorColor: Colors.white.withValues(alpha: .16),
      selectedIconTheme: const IconThemeData(color: Colors.white),
      unselectedIconTheme: IconThemeData(
        color: Colors.white.withValues(alpha: .68),
      ),
      selectedLabelTextStyle: railTextStyle.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: railTextStyle,
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) {
        final action = actions[index];
        action?.call();
      },
      leading: Padding(
        padding: const EdgeInsets.only(top: _Spacing.md, bottom: _Spacing.lg),
        child: Column(
          children: [
            if (extended)
              Padding(
                padding: const EdgeInsets.only(bottom: _Spacing.md),
                child: SizedBox(
                  width: 176,
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          color: Colors.white,
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'MJASI POS',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .92),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .5,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'home_sidebar_collapse'.tr,
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            setState(() => _desktopRailExtended = false),
                        icon: const Icon(
                          Icons.keyboard_double_arrow_left_rounded,
                          color: Colors.white70,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: _Spacing.md),
                child: IconButton(
                  tooltip: 'home_sidebar_expand'.tr,
                  onPressed: () => setState(() => _desktopRailExtended = true),
                  icon: const Icon(
                    Icons.keyboard_double_arrow_right_rounded,
                    color: Colors.white70,
                  ),
                ),
              ),
            if (extended)
              SizedBox(
                width: 176,
                height: 44,
                child: FilledButton.icon(
                  onPressed: _showQuickActions,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _AppColors.brandDeep,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: AnimatedRotation(
                    turns: _quickActionsOpen ? .125 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    child: const Icon(Icons.add_rounded),
                  ),
                  label: Text(
                    'home_quick_access'.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
            else
              FloatingActionButton.small(
                heroTag: 'home_quick_actions_rail',
                onPressed: _showQuickActions,
                tooltip: 'home_quick_access'.tr,
                backgroundColor: Colors.white,
                foregroundColor: _AppColors.brandDeep,
                child: AnimatedRotation(
                  turns: _quickActionsOpen ? .125 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  child: const Icon(Icons.add_rounded),
                ),
              ),
          ],
        ),
      ),
      destinations: destinations,
    );
  }

  Widget _buildMobileNavigation() {
    final canOpenReports =
        _isPersonalMode || BusinessAccessService.can('analytics', 'view');
    final canOpenChat =
        !_isPersonalMode && BusinessAccessService.hasBusinessAccess;
    final lightStyle =
        !_isPersonalMode && _activeDestination == _HomeDestination.dashboard;
    final background = lightStyle ? Colors.white : MjasiColors.primaryNavy;

    return Container(
      margin: lightStyle
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: lightStyle
            ? BorderRadius.zero
            : BorderRadius.circular(MjasiRadius.md),
        border: lightStyle
            ? const Border(top: BorderSide(color: Color(0xFFE6ECF5)))
            : Border.all(color: Colors.white.withValues(alpha: .08)),
        boxShadow: lightStyle
            ? const []
            : const [
                BoxShadow(
                  color: Color(0x26071B3A),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: lightStyle
            ? BorderRadius.zero
            : BorderRadius.circular(MjasiRadius.md),
        child: BottomAppBar(
          color: background,
          elevation: 0,
          padding: EdgeInsets.symmetric(horizontal: lightStyle ? 4 : 10),
          child: SizedBox(
            height: lightStyle ? 76 : 72,
            child: Row(
              children: [
                Expanded(
                  child: _mobileNavigationItem(
                    icon: Icons.home_rounded,
                    label: 'nav_home'.tr,
                    onTap: () => _selectDestination(_HomeDestination.dashboard),
                    selected: _activeDestination == _HomeDestination.dashboard,
                    lightStyle: lightStyle,
                  ),
                ),
                Expanded(
                  child: _mobileNavigationItem(
                    icon: Icons.explore_outlined,
                    label: 'nav_explore'.tr,
                    onTap: _openMarket,
                    selected: _activeDestination == _HomeDestination.explore,
                    lightStyle: lightStyle,
                  ),
                ),
                SizedBox(
                  width: lightStyle ? 60 : 64,
                  child: _quickNavigationAction(lightStyle: lightStyle),
                ),
                if (canOpenChat)
                  Expanded(
                    child: _mobileNavigationItem(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: 'chat_nav_label'.tr,
                      onTap: _openChat,
                      selected: _activeDestination == _HomeDestination.chat,
                      lightStyle: lightStyle,
                    ),
                  ),
                if (canOpenReports)
                  Expanded(
                    child: _mobileNavigationItem(
                      icon: Icons.insert_chart_outlined,
                      label: 'nav_reports'.tr,
                      onTap: () => _isPersonalMode
                          ? _selectDestination(_HomeDestination.reports)
                          : _openRestrictedRoute(
                              AppRoutes.analytics,
                              destination: _HomeDestination.reports,
                            ),
                      selected: _activeDestination == _HomeDestination.reports,
                      lightStyle: lightStyle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickNavigationAction({bool lightStyle = false}) {
    return Semantics(
      button: true,
      label: 'home_quick_access'.tr,
      child: InkWell(
        onTap: _showQuickActions,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 70,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: lightStyle ? 46 : 38,
                height: lightStyle ? 46 : 34,
                decoration: BoxDecoration(
                  color: lightStyle
                      ? const Color(0xFF0D6FEB)
                      : MjasiColors.secondaryBlue,
                  borderRadius: BorderRadius.circular(lightStyle ? 23 : 12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x333B82F6),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: AnimatedRotation(
                  turns: _quickActionsOpen ? .125 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  child: const Icon(
                    Icons.add_rounded,
                    color: Colors.white,
                    size: 25,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'nav_add'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: lightStyle
                      ? const Color(0xFF17263D)
                      : Colors.white.withValues(alpha: .9),
                  fontSize: 9,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mobileNavigationItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
    bool lightStyle = false,
  }) {
    final color = lightStyle
        ? (selected ? const Color(0xFF0D6FEB) : const Color(0xFF52657D))
        : (selected
              ? const Color(0xFF8DBBFF)
              : Colors.white.withValues(alpha: .68));
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 62,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: selected && lightStyle
                    ? const Color(0xFFEAF2FF)
                    : selected
                    ? Colors.white.withValues(alpha: .09)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(lightStyle ? 24 : 14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: lightStyle
                          ? const Color(0xFF17263D)
                          : selected
                          ? Colors.white
                          : color,
                      fontSize: 9.5,
                      height: 1.1,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showQuickActions() async {
    if (_isPersonalMode) {
      await _personalFinanceKey.currentState?.showAddDialog();
      return;
    }
    final actions = <_QuickActionData>[
      if (BusinessAccessService.can('transactions', 'create'))
        (
          label: 'home_add_income'.tr,
          icon: Icons.add_circle_outline_rounded,
          onTap: () => _openTransactionForm(TransactionType.income),
        ),
      if (BusinessAccessService.can('transactions', 'create'))
        (
          label: 'home_add_expense'.tr,
          icon: Icons.remove_circle_outline_rounded,
          onTap: () => _openTransactionForm(TransactionType.expense),
        ),
      if (BusinessAccessService.canUseBarPos)
        (
          label: 'pos_title'.tr,
          icon: Icons.point_of_sale_rounded,
          onTap: () => _openRestrictedRoute(AppRoutes.pos),
        ),
      if (BusinessAccessService.can('stock', 'create'))
        (
          label: 'stk_add_product'.tr,
          icon: Icons.add_box_outlined,
          onTap: () => Get.to(() => const ProductFormPage()),
        ),
      if (BusinessAccessService.can('tasks', 'create'))
        (
          label: 'tk_my'.tr,
          icon: Icons.task_alt_rounded,
          onTap: () => _openRestrictedRoute(AppRoutes.tasks),
        ),
    ];

    if (actions.isEmpty) {
      await _showMoreActions();
      return;
    }

    if (!mounted) return;
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    setState(() => _quickActionsOpen = true);
    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'home_quick_access'.tr,
        barrierColor: desktop
            ? const Color(0x33071932)
            : const Color(0x99071932),
        transitionDuration: const Duration(milliseconds: 360),
        pageBuilder: (dialogContext, _, _) {
          final size = MediaQuery.sizeOf(dialogContext);
          final railWidth = _desktopRailExtended ? 216.0 : 84.0;
          return SafeArea(
            top: !desktop,
            child: desktop
                ? Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: railWidth,
                        top: 78,
                        bottom: 18,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 360,
                          maxHeight: size.height * .78,
                        ),
                        child: _QuickActionsPanel(
                          actions: actions,
                          desktop: true,
                          onSelected: (action) {
                            Navigator.pop(dialogContext);
                            action.onTap();
                          },
                          onClose: () => Navigator.pop(dialogContext),
                          title: 'home_quick_access'.tr,
                        ),
                      ),
                    ),
                  )
                : Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 64),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 520,
                          maxHeight: size.height * .72,
                        ),
                        child: _QuickActionsPanel(
                          actions: actions,
                          onSelected: (action) {
                            Navigator.pop(dialogContext);
                            action.onTap();
                          },
                          onClose: () => Navigator.pop(dialogContext),
                        ),
                      ),
                    ),
                  ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final eased = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: eased,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: desktop ? const Offset(-.12, 0) : const Offset(0, .24),
                end: Offset.zero,
              ).animate(eased),
              child: ScaleTransition(
                scale: Tween<double>(begin: .92, end: 1).animate(eased),
                child: child,
              ),
            ),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _quickActionsOpen = false);
    }
  }

  Future<void> _showMoreActions({bool desktop = false}) async {
    final options = <({String label, IconData icon, String value})>[
      if (_isPersonalMode)
        (
          label: 'personal_settings'.tr,
          icon: Icons.settings_outlined,
          value: 'personal_settings',
        ),
      if (!_isPersonalMode && BusinessAccessService.can('transactions', 'view'))
        (
          label: 'home_transactions'.tr,
          icon: Icons.swap_vert_rounded,
          value: 'transactions',
        ),
      if (!_isPersonalMode && BusinessAccessService.can('invoices', 'view'))
        (
          label: 'home_view_invoices'.tr,
          icon: Icons.receipt_long_outlined,
          value: 'invoices',
        ),
      if (!_isPersonalMode && BusinessAccessService.can('jobs', 'view'))
        (
          label: 'home_manage_jobs'.tr,
          icon: Icons.work_outline_rounded,
          value: 'jobs',
        ),
      if (!_isPersonalMode && BusinessAccessService.can('stock', 'view'))
        (
          label: 'stk_title'.tr,
          icon: Icons.inventory_2_outlined,
          value: 'stock',
        ),
      if (!_isPersonalMode &&
          (BusinessAccessService.can('tasks', 'view') ||
              BusinessAccessService.isActive.value))
        (label: 'tk_my'.tr, icon: Icons.task_alt_rounded, value: 'tasks'),
      if (!_isPersonalMode && BusinessAccessService.isOwner.value)
        (
          label: 'home_manage_staff'.tr,
          icon: Icons.groups_2_outlined,
          value: 'staff',
        ),
      if (!_isPersonalMode && BusinessAccessService.isOwner.value)
        (
          label: 'home_subscription'.tr,
          icon: Icons.workspace_premium_outlined,
          value: 'subscription',
        ),
      if (_isSuperAdmin) ...[
        (
          label: 'hub_title'.tr,
          icon: Icons.admin_panel_settings_rounded,
          value: 'admin_hub',
        ),
        (
          label: 'admin_manage_subscriptions'.tr,
          icon: Icons.manage_accounts_outlined,
          value: 'admin_subscriptions',
        ),
        (
          label: 'admin_manage_app_versions'.tr,
          icon: Icons.system_update_alt_rounded,
          value: 'admin_app_versions',
        ),
        (
          label: 'admin_manage_downloads'.tr,
          icon: Icons.cloud_download_rounded,
          value: 'admin_downloads',
        ),
        (
          label: 'admin_manage_analytics'.tr,
          icon: Icons.insights_rounded,
          value: 'admin_analytics',
        ),
        (
          label: 'admin_manage_announcements'.tr,
          icon: Icons.campaign_rounded,
          value: 'admin_announcements',
        ),
        (
          label: 'support_admin_title'.tr,
          icon: Icons.support_agent_rounded,
          value: 'admin_support',
        ),
        (
          label: 'home_create_receipt'.tr,
          icon: Icons.add_business_outlined,
          value: 'create_receipt',
        ),
      ],
    ];

    if (!mounted) return;
    if (desktop) {
      final panelActions = [
        for (final option in options)
          (
            label: option.label,
            icon: option.icon,
            onTap: () => _handleMenuSelection(option.value),
          ),
      ];
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'home_more'.tr,
        barrierColor: const Color(0x33071932),
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (dialogContext, _, _) {
          final size = MediaQuery.sizeOf(dialogContext);
          return SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: EdgeInsets.only(
                  left: _desktopRailExtended ? 216 : 84,
                  top: 78,
                  bottom: 18,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 360,
                    maxHeight: size.height * .78,
                  ),
                  child: _QuickActionsPanel(
                    actions: panelActions,
                    desktop: true,
                    title: 'home_more'.tr,
                    headerIcon: Icons.grid_view_rounded,
                    onSelected: (action) {
                      Navigator.pop(dialogContext);
                      action.onTap();
                    },
                    onClose: () => Navigator.pop(dialogContext),
                  ),
                ),
              ),
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final eased = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: eased,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(-.12, 0),
                end: Offset.zero,
              ).animate(eased),
              child: child,
            ),
          );
        },
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .78,
          ),
          decoration: const BoxDecoration(
            color: _AppColors.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(_Radius.lg),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  _Spacing.lg,
                  _Spacing.md,
                  _Spacing.lg,
                  _Spacing.md,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _AppColors.brand.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(_Radius.sm),
                      ),
                      child: const Icon(
                        Icons.grid_view_rounded,
                        color: _AppColors.brand,
                      ),
                    ),
                    const SizedBox(width: _Spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'home_more'.tr,
                            style: const TextStyle(
                              color: _AppColors.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'home_quick_access_sub'.tr,
                            style: const TextStyle(
                              color: _AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        sheetContext,
                      ).closeButtonTooltip,
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: _AppColors.border),
              Flexible(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const spacing = _Spacing.sm;
                    final itemWidth =
                        (constraints.maxWidth - _Spacing.lg * 2 - spacing) / 2;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(_Spacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: spacing,
                            runSpacing: spacing,
                            children: [
                              for (final option in options)
                                SizedBox(
                                  width: itemWidth,
                                  child: _moreActionTile(
                                    label: option.label,
                                    icon: option.icon,
                                    onTap: () {
                                      Navigator.pop(sheetContext);
                                      _handleMenuSelection(option.value);
                                    },
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: _Spacing.lg),
                          const Divider(color: _AppColors.border),
                          const SizedBox(height: _Spacing.sm),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              _handleMenuSelection('logout');
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _AppColors.negative,
                              side: BorderSide(
                                color: _AppColors.negative.withValues(
                                  alpha: .35,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: _Spacing.md,
                                vertical: _Spacing.md,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  _Radius.sm,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.logout_rounded),
                            label: Text('home_sign_out'.tr),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moreActionTile({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: _AppColors.canvas,
      borderRadius: BorderRadius.circular(_Radius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_Radius.sm),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(
            horizontal: _Spacing.md,
            vertical: _Spacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_Radius.sm),
            border: Border.all(color: _AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _AppColors.brand.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _AppColors.brand, size: 19),
              ),
              const SizedBox(width: _Spacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _AppColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
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
        height: compact ? 60 : 68,
        child: Row(
          children: [
            if (kIsWeb && _activeDestination != _HomeDestination.dashboard)
              IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () {
                  if (Get.key.currentState?.canPop() == true) {
                    Get.back();
                  } else {
                    Get.offNamed(AppRoutes.home);
                  }
                },
                color: Colors.white,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            Container(
              width: compact ? 36 : 40,
              height: compact ? 36 : 40,
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
            SizedBox(width: compact ? _Spacing.sm : _Spacing.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MJASI POS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 0.35,
                    ),
                  ),
                  Text(
                    _isPersonalMode
                        ? 'personal_title'.tr
                        : 'home_dashboard_label'.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: _Spacing.sm),
            _buildConnectivityIndicator(),
            if (!_isPersonalMode && _isSuperAdmin && !compact)
              _headerIconButton(
                icon: Icons.admin_panel_settings_outlined,
                tooltip: 'hub_title'.tr,
                onPressed: () => Get.toNamed(AppRoutes.adminHub),
              ),
            if (!_isPersonalMode && BusinessAccessService.hasBusinessAccess)
              _headerIconButton(
                icon: Icons.forum_outlined,
                tooltip: 'chat_title'.tr,
                onPressed: () => Get.toNamed(AppRoutes.chat),
              ),
            if (!compact) _buildLanguageButton(),
            if (!_isPersonalMode) const NotificationBell(),
            if (_isPersonalMode ||
                BusinessAccessService.can('profile', 'view') ||
                BusinessAccessService.isOwner.value)
              _headerIconButton(
                icon: _isPersonalMode
                    ? Icons.settings_outlined
                    : Icons.person_outline_rounded,
                tooltip: _isPersonalMode
                    ? 'personal_settings'.tr
                    : 'home_profile'.tr,
                onPressed: _isPersonalMode
                    ? () => Get.toNamed(AppRoutes.personalSettings)
                    : _openProfile,
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

  Widget _buildConnectivityIndicator() {
    final color = _isOnline ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    final label = _isOnline ? 'connection_online'.tr : 'connection_offline'.tr;
    return _BreathingConnectivityDot(color: color, label: label);
  }

  Widget _headerIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: .08),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_Radius.sm),
          ),
        ),
        icon: Icon(icon, color: Colors.white.withValues(alpha: 0.92), size: 20),
      ),
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
      itemBuilder: (context) => _isPersonalMode
          ? _buildPersonalMenuItems(compact)
          : [
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
                _menuItem(
                  'transactions',
                  'home_transactions'.tr,
                  Icons.swap_vert,
                ),
              if (BusinessAccessService.can('invoices', 'create'))
                _menuItem(
                  'generate_invoice',
                  'home_generate_invoice'.tr,
                  Icons.note_add_outlined,
                ),
              if (BusinessAccessService.can('invoices', 'view'))
                _menuItem(
                  'invoices',
                  'home_view_invoices'.tr,
                  Icons.receipt_long,
                ),
              if (_isSuperAdmin &&
                  BusinessAccessService.can('receipts', 'view'))
                _menuItem('receipts', 'home_view_receipts'.tr, Icons.receipt),
              if (BusinessAccessService.can('jobs', 'view'))
                _menuItem(
                  'jobs',
                  'home_manage_jobs'.tr,
                  Icons.account_balance_wallet_outlined,
                ),
              if (BusinessAccessService.can('analytics', 'view'))
                _menuItem(
                  'analytics',
                  'home_analytics'.tr,
                  Icons.analytics_outlined,
                ),
              if (BusinessAccessService.canUseBarPos)
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
                _menuItem(
                  'staff',
                  'home_manage_staff'.tr,
                  Icons.groups_2_outlined,
                ),
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
                  'admin_support',
                  'support_admin_title'.tr,
                  Icons.support_agent_rounded,
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
              if (_canSwitchBusiness)
                _menuItem(
                  'switch_business',
                  'business_select'.tr,
                  Icons.swap_horiz_rounded,
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

  List<PopupMenuEntry<String>> _buildPersonalMenuItems(bool compact) => [
    if (compact)
      _menuItem(
        'language_toggle',
        languageController.locale.languageCode == 'sw'
            ? 'language_english'.tr
            : 'language_swahili'.tr,
        Icons.language_rounded,
      ),
    if (compact) const PopupMenuDivider(),
    _menuItem(
      'personal_settings',
      'personal_settings'.tr,
      Icons.settings_outlined,
    ),
    _menuItem('about', 'home_about'.tr, Icons.info_outline),
    const PopupMenuDivider(),
    _menuItem('logout', 'home_sign_out'.tr, Icons.logout_rounded),
    _menuItem(
      'delete_account',
      'Delete account',
      Icons.delete_forever_outlined,
      destructive: true,
    ),
  ];

  Widget _buildLanguageButton({bool dark = false}) {
    final languageCode = languageController.locale.languageCode;
    final foregroundColor = dark
        ? const Color(0xFF10233F)
        : Colors.white.withValues(alpha: 0.9);
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
            color: foregroundColor,
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
              ).copyWith(color: foregroundColor),
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
    if (_isPersonalMode || !BusinessAccessService.can('profile', 'edit')) {
      return;
    }
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
        if (_isPersonalMode) {
          await Get.toNamed(AppRoutes.personalSettings);
        } else {
          _openProfile();
        }
      case 'personal_settings':
        await Get.toNamed(AppRoutes.personalSettings);
      case 'switch_business':
        await _selectBusiness();
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
      case 'tasks':
        await _openRestrictedRoute(AppRoutes.tasks);
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
      case 'admin_support':
        await Get.toNamed(AppRoutes.adminSupport);
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

  Future<void> _selectBusiness() async {
    final businesses = BusinessAccessService.availableBusinesses
        .where((business) => business.isActive)
        .toList();
    if (businesses.length < 2) return;

    final selectedId = await Get.dialog<String>(
      SimpleDialog(
        title: Text('business_select'.tr),
        children: [
          for (final business in businesses)
            SimpleDialogOption(
              onPressed: () => Get.back(result: business.businessId),
              child: Row(
                children: [
                  const Icon(
                    Icons.storefront_outlined,
                    color: MjasiColors.primaryBlue,
                  ),
                  const SizedBox(width: _Spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          business.businessName.isEmpty
                              ? business.businessId
                              : business.businessName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (business.shopNickname.isNotEmpty)
                          Text(
                            business.shopNickname,
                            style: const TextStyle(
                              color: _AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (business.businessId ==
                      BusinessAccessService.businessUid.value)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: MjasiColors.primaryBlue,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    if (selectedId == null ||
        selectedId == BusinessAccessService.businessUid.value) {
      return;
    }

    try {
      await BusinessAccessService.selectBusiness(selectedId);
      if (mounted) Get.offAllNamed(AppRoutes.home);
    } catch (error, stackTrace) {
      debugPrint('Could not switch dashboard business: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        Get.snackbar(
          'error'.tr,
          'business_switch_error'.tr,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
  }

  Future<void> _selectDashboardShop() async {
    if (!BusinessAccessService.isOwner.value ||
        !_canSelectDashboardShop) {
      return;
    }

    Widget shopOption({
      required String name,
      required String value,
      required IconData icon,
    }) {
      final isSelected = _selectedShopNickname == value;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Get.back(result: value),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            margin: const EdgeInsets.only(bottom: 9),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: isSelected
                  ? MjasiColors.primaryBlue.withValues(alpha: .08)
                  : const Color(0xFFF7F9FC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? MjasiColors.primaryBlue.withValues(alpha: .42)
                    : const Color(0xFFE8EDF4),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? MjasiColors.primaryBlue
                        : const Color(0xFFE9EFF8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected
                        ? Colors.white
                        : MjasiColors.primaryNavy,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: MjasiColors.textPrimary,
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color: isSelected
                      ? MjasiColors.primaryBlue
                      : MjasiColors.border,
                  size: 21,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final selectedShop = await Get.dialog<String>(
      Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 430,
            maxHeight: MediaQuery.sizeOf(context).height * .78,
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x260C2340),
                  blurRadius: 28,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            MjasiColors.primaryNavy,
                            MjasiColors.primaryBlue,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.storefront_rounded,
                        color: Colors.white,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'home_select_shop'.tr,
                            style: const TextStyle(
                              color: MjasiColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'home_select_shop_hint'.tr,
                            style: const TextStyle(
                              color: MjasiColors.textSecondary,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'close'.tr,
                      onPressed: () => Get.back(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        shopOption(
                          name: 'home_all_shops'.tr,
                          value: '',
                          icon: Icons.store_mall_directory_outlined,
                        ),
                        for (final shop in _availableShopNicknames)
                          shopOption(
                            name: shop,
                            value: shop,
                            icon: Icons.storefront_outlined,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selectedShop == null || selectedShop == _selectedShopNickname) return;
    setState(() {
      _selectedShopNickname = selectedShop;
      financeLoading = true;
    });
    await _loadFinanceSummary();
  }

  Future<void> _openRestrictedRoute(
    String route, {
    bool refreshFinance = false,
    _HomeDestination? destination,
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
    if (destination != null) {
      _selectDestination(destination);
      return;
    }
    final result = await Get.toNamed(
      route,
      arguments: route == AppRoutes.transactions
          ? {'shopNickname': _selectedShopNickname}
          : null,
    );
    if (route == AppRoutes.tasks && result == 'open_chat' && mounted) {
      _selectDestination(_HomeDestination.chat);
    }
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
    final greeting = 'home_greeting'.trParams({'name': displayName});

    return ClipRRect(
      borderRadius: BorderRadius.circular(_Radius.lg),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(color: _AppColors.brandDeep),
            ),
          ),
          // Content
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? _Spacing.lg : _Spacing.md,
              vertical: wide ? _Spacing.md : _Spacing.sm,
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
                              greeting,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: wide ? 20 : 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.45,
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
                            icon: staffCount != null
                                ? Icons.groups_2_rounded
                                : Icons.receipt_long_rounded,
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
                            icon: Icons.task_alt_rounded,
                            count: true,
                            onTap: () => _openRestrictedRoute(AppRoutes.tasks),
                          ),
                          const SizedBox(width: _Spacing.sm),
                          _heroStat(
                            'hs_net'.tr,
                            financeIncome - financeExpense,
                            const Color(0xFFFBBF24),
                            icon: Icons.account_balance_wallet_rounded,
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
    required IconData icon,
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
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_Radius.sm),
              border: Border.all(color: Colors.white.withValues(alpha: .08)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      icon,
                      size: 14,
                      color: Colors.white.withValues(alpha: .78),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.76),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    count ? amount.toInt().toString() : _formatAmount(amount),
                    style: TextStyle(
                      color: valueColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
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
            Row(
              children: [
                Expanded(
                  child: _amountTile(
                    title: 'income'.tr,
                    amount: financeIncome,
                    icon: Icons.south_west_rounded,
                    color: _AppColors.positive,
                    background: _AppColors.positiveBg,
                    actionLabel: 'home_view_income'.tr,
                    onTap: () =>
                        _openTransactionsByType(TransactionType.income),
                  ),
                ),
                const SizedBox(width: _Spacing.sm),
                Expanded(
                  child: _amountTile(
                    title: 'expenses'.tr,
                    amount: financeExpense,
                    icon: Icons.north_east_rounded,
                    color: _AppColors.negative,
                    background: _AppColors.negativeBg,
                    actionLabel: 'home_view_expenses'.tr,
                    onTap: () =>
                        _openTransactionsByType(TransactionType.expense),
                  ),
                ),
              ],
            ),
            const SizedBox(height: _Spacing.md),
            _buildNetAmount(net),
          ],
          const SizedBox(height: _Spacing.lg),
          if (BusinessAccessService.can('transactions', 'create'))
            Row(
              children: [
                Expanded(
                  child: _financeAction(
                    label: 'home_add_income'.tr,
                    icon: Icons.add_rounded,
                    color: _AppColors.positive,
                    onPressed: () =>
                        _openTransactionForm(TransactionType.income),
                  ),
                ),
                const SizedBox(width: _Spacing.sm),
                Expanded(
                  child: _financeAction(
                    label: 'home_add_expense'.tr,
                    icon: Icons.remove_rounded,
                    color: _AppColors.negative,
                    onPressed: () =>
                        _openTransactionForm(TransactionType.expense),
                  ),
                ),
              ],
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
          padding: EdgeInsets.all(_desktop ? _Spacing.md : _Spacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: _desktop ? 32 : 27,
                    height: _desktop ? 32 : 27,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(_Radius.sm),
                    ),
                    child: Icon(icon, color: color, size: _desktop ? 18 : 15),
                  ),
                  const SizedBox(width: _Spacing.xs),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: _desktop ? 12 : 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: _desktop ? _Spacing.md : _Spacing.sm),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'TSh ${_formatAmount(amount)}',
                  style: TextStyle(
                    color: _AppColors.ink,
                    fontSize: _desktop ? 22 : 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: _Spacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      actionLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
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
      child: FilledButton(
        onPressed: () async {
          if (!await _checkCurrentSubscriptionAccess()) {
            _showSubscriptionRequiredDialog();
          } else {
            onPressed();
          }
        },
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_Radius.sm),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
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
          DebtFilter.customerOwesShop,
        ),
        _DebtMetric(
          'home_debt_payable'.tr,
          'TZS ${debts.payableBalance.toStringAsFixed(0)}',
          Icons.call_made_rounded,
          _AppColors.warning,
          _AppColors.warningBg,
          DebtFilter.shopOwesOther,
        ),
        _DebtMetric(
          'debt_overdue'.tr,
          debts.overdueCount.toString(),
          Icons.event_busy_outlined,
          _AppColors.negative,
          _AppColors.negativeBg,
          DebtFilter.overdue,
        ),
      ];
      return LayoutBuilder(
        builder: (context, constraints) {
          const spacing = _Spacing.sm;
          return Row(
            children: [
              for (var i = 0; i < metrics.length; i++) ...[
                if (i > 0) const SizedBox(width: spacing),
                Expanded(
                  child: _debtMetricCard(
                    metrics[i],
                    wide: wide,
                    compact: constraints.maxWidth < 500,
                    onTap: () {
                      debts.filter.value = metrics[i].filter;
                      _openRestrictedRoute(AppRoutes.jobs);
                    },
                  ),
                ),
              ],
            ],
          );
        },
      );
    });
  }

  Widget _debtMetricCard(
    _DebtMetric metric, {
    bool wide = false,
    bool compact = false,
    required VoidCallback onTap,
  }) {
    return Material(
      color: metric.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_Radius.md),
        side: BorderSide(color: metric.color.withValues(alpha: .13)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_Radius.md),
        child: Padding(
          padding: EdgeInsets.all(compact ? 8 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: compact
                        ? 24
                        : wide
                        ? 34
                        : 28,
                    height: compact
                        ? 24
                        : wide
                        ? 34
                        : 28,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .78),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      metric.icon,
                      size: compact
                          ? 13
                          : wide
                          ? 17
                          : 14,
                      color: metric.color,
                    ),
                  ),
                  const SizedBox(width: _Spacing.xs),
                  Expanded(
                    child: Text(
                      metric.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _AppColors.inkSoft,
                        fontSize: compact
                            ? 9
                            : wide
                            ? 11.5
                            : 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: compact
                    ? 3
                    : wide
                    ? 10
                    : 6,
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  metric.value,
                  style: TextStyle(
                    color: metric.color,
                    fontSize: compact
                        ? 13
                        : wide
                        ? 19
                        : 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.35,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
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
      if (BusinessAccessService.canUseBarPos)
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
        'shopNickname': _selectedShopNickname,
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
        content: Text(
          _isOnline
              ? 'subscription_required_message'.tr
              : 'offline_subscription_grace_expired'.tr,
        ),
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
    final sw = Get.locale?.languageCode == 'sw';
    String t(String en, String swText) => sw ? swText : en;

    Widget link(IconData icon, String label, VoidCallback onTap) {
      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_Radius.md),
        ),
        leading: Icon(icon, color: _AppColors.brand, size: 22),
        title: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: _AppColors.ink,
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: _AppColors.muted),
        onTap: onTap,
      );
    }

    void open(String route) {
      Get.back();
      Get.toNamed(route);
    }

    Get.dialog(
      Dialog(
        backgroundColor: _AppColors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_AppColors.brandDeep, _AppColors.brand],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'MJASI POS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t(
                          'Manage income, expenses, invoices, receipts and jobs',
                          'Simamia mapato, matumizi, ankara, risiti na kazi',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                  child: Column(
                    children: [
                      link(
                        Icons.privacy_tip_outlined,
                        t('Privacy Policy', 'Sera ya Faragha'),
                        () => open(AppRoutes.privacy),
                      ),
                      link(
                        Icons.gavel_outlined,
                        t('Terms & Conditions', 'Masharti na Vigezo'),
                        () => open(AppRoutes.terms),
                      ),
                      link(
                        Icons.link_rounded,
                        t('All app links', 'Viungo vyote vya app'),
                        () => open(AppRoutes.appUrls),
                      ),
                      link(
                        Icons.support_agent_outlined,
                        t('Help & Support', 'Msaada'),
                        () => open(AppRoutes.support),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _AppColors.brand,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(_Radius.md),
                        ),
                      ),
                      onPressed: Get.back,
                      child: Text('close'.tr),
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
}

class _DebtMetric {
  const _DebtMetric(
    this.label,
    this.value,
    this.icon,
    this.color,
    this.background,
    this.filter,
  );

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;
  final DebtFilter filter;
}

typedef _QuickActionData = ({String label, IconData icon, VoidCallback onTap});

class _QuickActionsPanel extends StatelessWidget {
  const _QuickActionsPanel({
    required this.actions,
    required this.onSelected,
    required this.onClose,
    this.desktop = false,
    this.title,
    this.headerIcon = Icons.bolt_rounded,
  });

  final List<_QuickActionData> actions;
  final ValueChanged<_QuickActionData> onSelected;
  final VoidCallback onClose;
  final bool desktop;
  final String? title;
  final IconData headerIcon;

  @override
  Widget build(BuildContext context) {
    const iconColors = [
      Color(0xFF168A62),
      Color(0xFFE06B35),
      Color(0xFF3269D3),
      Color(0xFF8051C7),
      Color(0xFF168A9B),
      Color(0xFFC04468),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, Color(0xFFF5F8FF)],
              ),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xFFE5EBF5)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x26071932),
                  blurRadius: 28,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF1FF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFDDE8FA)),
                        ),
                        child: Icon(
                          headerIcon,
                          color: Color(0xFF3269D3),
                          size: 25,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title ?? 'home_quick_access'.tr,
                              style: const TextStyle(
                                color: Color(0xFF10233F),
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.25,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'home_quick_access_sub'.tr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: const Color(0xFF65738A),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onClose,
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        style: IconButton.styleFrom(
                          foregroundColor: const Color(0xFF53647C),
                          backgroundColor: const Color(0xFFF0F4FA),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 19),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  indent: 18,
                  endIndent: 18,
                  color: const Color(0xFFE8EDF5),
                ),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.all(desktop ? 12 : 16),
                    itemCount: actions.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: desktop ? 1 : 2,
                      mainAxisSpacing: 9,
                      crossAxisSpacing: 10,
                      childAspectRatio: desktop ? 5.0 : 1.7,
                    ),
                    itemBuilder: (context, index) {
                      final action = actions[index];
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(
                          milliseconds: 220 + ((index > 7 ? 7 : index) * 35),
                        ),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) => Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, 12 * (1 - value)),
                            child: child,
                          ),
                        ),
                        child: _QuickActionTile(
                          action: action,
                          color: iconColors[index % iconColors.length],
                          onTap: () => onSelected(action),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!desktop)
          CustomPaint(
            size: const Size(42, 22),
            painter: _QuickActionsTailPainter(),
          ),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.action,
    required this.color,
    required this.onTap,
  });

  final _QuickActionData action;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFBFE),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0xFFE6ECF5)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(action.icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  action.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF172942),
                    fontSize: 12,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: const Color(0xFF9AA7B9),
                size: 13,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionsTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Color(0xFFF5F8FF)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BreathingConnectivityDot extends StatefulWidget {
  const _BreathingConnectivityDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  State<_BreathingConnectivityDot> createState() =>
      _BreathingConnectivityDotState();
}

class _BreathingConnectivityDotState extends State<_BreathingConnectivityDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  late final Animation<double> _breath = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.label,
      child: Semantics(
        label: widget.label,
        child: SizedBox(
          width: 20,
          height: 20,
          child: AnimatedBuilder(
            animation: _breath,
            builder: (context, child) {
              final progress = _breath.value;
              final haloSize = 10 + progress * 8;
              return Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: haloSize,
                      height: haloSize,
                      decoration: BoxDecoration(
                        color: widget.color.withValues(
                          alpha: .28 * (1 - progress),
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                    child!,
                  ],
                ),
              );
            },
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: .45),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
