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
import 'package:tra_list/services/push_service.dart';
import 'services/subscription_controller.dart';

enum _FinancePeriod { today, yesterday, thisWeek, thisMonth }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const Color _ink = Color(0xFF19313A);
  static const Color _muted = Color(0xFF75838A);
  static const Color _canvas = Color(0xFFF5F7F8);
  static const Color _brand = Color(0xFF0E5962);

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
  _FinancePeriod _financePeriod = _FinancePeriod.today;
  int _financeRequest = 0;

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

  bool _desktop = false;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: _canvas,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 800;
                  _desktop = wide;
                  return RefreshIndicator(
                    onRefresh: _loadFinanceSummary,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? 32 : 16,
                        vertical: wide ? 32 : 20,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth >= 1100 ? 1040 : 860,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'home_finance_summary'.tr,
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: wide ? 24 : 21,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${'home_month_to_date'.tr} · $_currentMonthLabel',
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 18),
                              if (BusinessAccessService.can(
                                    'transactions',
                                    'view',
                                  ) ||
                                  BusinessAccessService.can(
                                    'analytics',
                                    'view',
                                  )) ...[
                                _buildFinanceCard(wide),
                                const SizedBox(height: 22),
                              ],
                              if (BusinessAccessService.can('jobs', 'view'))
                                _sectionHeading(
                                  'home_jobs_overview'.tr,
                                  'home_jobs_overview_sub'.tr,
                                ),
                              if (BusinessAccessService.can(
                                'jobs',
                                'view',
                              )) ...[
                                const SizedBox(height: 11),
                                _buildDebtMetrics(wide),
                                const SizedBox(height: 22),
                              ],
                              const SizedBox(height: 22),
                              _sectionHeading(
                                'home_quick_access'.tr,
                                'home_quick_access_sub'.tr,
                              ),
                              const SizedBox(height: 11),
                              _buildQuickActions(),
                              const SizedBox(height: 16),
                              if (BusinessAccessService.can(
                                'transactions',
                                'view',
                              )) ...[
                                Text(
                                  'home_transactions'.tr,
                                  style: const TextStyle(
                                    color: _ink,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 11),
                                _buildTransactionsButton(),
                                const SizedBox(height: 16),
                              ],
                              if (BusinessAccessService.isOwner.value)
                                _buildSubscriptionLink(),
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

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0A3F46), _brand, Color(0xFF17808B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Color(0x330E5962),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
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
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      letterSpacing: 0.2,
                    ),
                  ),
                  if (shopNickname.isNotEmpty && storeName.isNotEmpty)
                    Text(
                      storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (subscriptionBadge.isNotEmpty &&
              MediaQuery.sizeOf(context).width > 500)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _buildPlanBadge(),
            ),
          _buildLanguageButton(),
          const NotificationBell(),
          if (BusinessAccessService.can('profile', 'view') ||
              BusinessAccessService.isOwner.value)
            IconButton(
              tooltip: 'home_profile'.tr,
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ProfilePage())),
              icon: const Icon(
                Icons.person_outline_rounded,
                color: Colors.white,
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'home_more'.tr,
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            offset: const Offset(0, 48),
            onSelected: _handleMenuSelection,
            itemBuilder: (context) => [
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
              _menuItem('logout', 'home_sign_out'.tr, Icons.logout_rounded),
              if (!_isSuperAdmin)
                _menuItem(
                  'delete_account',
                  'Delete account',
                  Icons.delete_forever_outlined,
                ),
            ],
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      offset: const Offset(0, 48),
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.language_rounded, color: Colors.white),
          if (MediaQuery.sizeOf(context).width >= 360) ...[
            const SizedBox(width: 3),
            Text(
              languageCode == 'sw' ? 'SW' : 'EN',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
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
            const Icon(Icons.check_rounded, size: 18, color: _brand),
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

  PopupMenuItem<String> _menuItem(String value, String title, IconData icon) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: value == 'logout' ? Colors.red : _muted),
          const SizedBox(width: 10),
          Text(title),
        ],
      ),
    );
  }

  Future<void> _handleMenuSelection(String value) async {
    switch (value) {
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
      case 'categories':
        await _openRestrictedRoute(AppRoutes.categories);
      case 'staff':
        await _openRestrictedRoute(AppRoutes.staff);
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

  Widget _buildPlanBadge() {
    final color = isSubscribed
        ? const Color(0xFF267A54)
        : isTrial
        ? const Color(0xFF98620B)
        : _muted;
    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: isSubscribed ? const Color(0xFFE8F5ED) : const Color(0xFFFFF4DF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        subscriptionBadge,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _sectionHeading(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _ink,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
      ],
    );
  }

  Widget _buildDebtMetrics(bool wide) {
    final debts = debtController;
    if (debts == null) return const SizedBox.shrink();
    return Obx(() {
      final metrics = [
        _DebtMetric(
          'home_debt_receivable'.tr,
          'TZS ${debts.receivableBalance.toStringAsFixed(0)}',
          Icons.call_received_rounded,
          const Color(0xFF176C55),
          const Color(0xFFE5F3ED),
        ),
        _DebtMetric(
          'home_debt_payable'.tr,
          'TZS ${debts.payableBalance.toStringAsFixed(0)}',
          Icons.call_made_rounded,
          const Color(0xFF8C5A17),
          const Color(0xFFFBF1E2),
        ),
        _DebtMetric(
          'debt_overdue'.tr,
          debts.overdueCount.toString(),
          Icons.event_busy_outlined,
          const Color(0xFFB14444),
          const Color(0xFFFAEEEE),
        ),
      ];
      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = wide && constraints.maxWidth >= 620 ? 3 : 2;
          const spacing = 10.0;
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
      padding: EdgeInsets.symmetric(
        horizontal: wide ? 20 : 12,
        vertical: wide ? 22 : 13,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(wide ? 16 : 13),
        border: Border.all(color: const Color(0xFFE5EAEC)),
      ),
      child: Row(
        children: [
          Container(
            width: wide ? 48 : 34,
            height: wide ? 48 : 34,
            decoration: BoxDecoration(
              color: metric.background,
              borderRadius: BorderRadius.circular(wide ? 13 : 10),
            ),
            child: Icon(metric.icon, size: wide ? 24 : 18, color: metric.color),
          ),
          SizedBox(width: wide ? 14 : 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.value,
                  style: TextStyle(
                    color: _ink,
                    fontSize: wide ? 24 : 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _muted, fontSize: wide ? 13 : 10.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final actions = <Widget>[
      if (BusinessAccessService.can('transactions', 'create'))
        _quickAction(
          'home_add_income'.tr,
          Icons.add_circle_outline_rounded,
          () => _openTransactionForm(TransactionType.income),
        ),
      if (BusinessAccessService.can('transactions', 'create'))
        _quickAction(
          'home_add_expense'.tr,
          Icons.remove_circle_outline_rounded,
          () => _openTransactionForm(TransactionType.expense),
        ),
      if (BusinessAccessService.can('invoices', 'create'))
        _quickAction(
          'home_generate_invoice'.tr,
          Icons.note_add_outlined,
          () => _openRestrictedRoute(AppRoutes.invoice),
        ),
      if (BusinessAccessService.can('invoices', 'view'))
        _quickAction(
          'home_view_invoices'.tr,
          Icons.receipt_long_outlined,
          () => _openRestrictedRoute(AppRoutes.invoicesList),
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
          Icons.account_balance_wallet_outlined,
          () => _openRestrictedRoute(AppRoutes.jobs),
        ),
      if (BusinessAccessService.can('analytics', 'view'))
        _quickAction(
          'home_analytics'.tr,
          Icons.analytics_outlined,
          () => _openRestrictedRoute(AppRoutes.analytics),
        ),
      if (BusinessAccessService.can('categories', 'view'))
        _quickAction(
          'home_manage_categories'.tr,
          Icons.category_outlined,
          () => _openRestrictedRoute(AppRoutes.categories),
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
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 620
            ? 3
            : 2;
        const spacing = 9.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: actions
              .map((action) => SizedBox(width: width, child: action))
              .toList(),
        );
      },
    );
  }

  Widget _quickAction(
    String title,
    IconData icon,
    VoidCallback onTap, {
    bool? wide,
  }) {
    wide ??= _desktop;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(wide ? 16 : 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(wide ? 16 : 12),
        child: Container(
          constraints: BoxConstraints(minHeight: wide ? 84 : 48),
          padding: EdgeInsets.symmetric(
            horizontal: wide ? 18 : 11,
            vertical: wide ? 16 : 9,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(wide ? 16 : 12),
            border: Border.all(color: const Color(0xFFE5EAEC)),
          ),
          child: Row(
            children: [
              Icon(icon, size: wide ? 26 : 18, color: _brand),
              SizedBox(width: wide ? 14 : 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _ink,
                    fontSize: wide ? 14.5 : 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinanceCard(bool wide) {
    final net = financeIncome - financeExpense;
    return Container(
      padding: EdgeInsets.all(wide ? 22 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5EAEC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PopupMenuButton<_FinancePeriod>(
                tooltip: 'home_finance_period'.tr,
                onSelected: _selectFinancePeriod,
                itemBuilder: (context) => _FinancePeriod.values
                    .map(
                      (period) => PopupMenuItem<_FinancePeriod>(
                        value: period,
                        child: Text(_financePeriodLabel(period)),
                      ),
                    )
                    .toList(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.calendar_month_outlined,
                      size: 17,
                      color: _muted,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _financePeriodLabel(_financePeriod),
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: _muted, size: 19),
                  ],
                ),
              ),
              const Spacer(),
              if (financeLoading)
                const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  tooltip: 'refresh'.tr,
                  onPressed: _loadFinanceSummary,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (financeError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                financeError!,
                style: const TextStyle(color: Color(0xFF9B3E35), fontSize: 13),
              ),
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 450;
                final incomeCard = _amountCard(
                  title: 'income'.tr,
                  amount: financeIncome,
                  icon: Icons.south_west_rounded,
                  color: const Color(0xFF237A52),
                  background: const Color(0xFFEAF5EE),
                  actionLabel: 'home_view_income'.tr,
                  onTap: () => _openTransactionsByType(TransactionType.income),
                );
                final expenseCard = _amountCard(
                  title: 'expenses'.tr,
                  amount: financeExpense,
                  icon: Icons.north_east_rounded,
                  color: const Color(0xFFB64D4D),
                  background: const Color(0xFFFAEEEE),
                  actionLabel: 'home_view_expenses'.tr,
                  onTap: () => _openTransactionsByType(TransactionType.expense),
                );
                if (stacked) {
                  return Column(
                    children: [
                      incomeCard,
                      const SizedBox(height: 10),
                      expenseCard,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: incomeCard),
                    const SizedBox(width: 12),
                    Expanded(child: expenseCard),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            _buildNetAmount(net),
          ],
          const SizedBox(height: 12),
          if (BusinessAccessService.can('transactions', 'create'))
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 450;
                final buttons = [
                  _financeAction(
                    label: 'home_add_income'.tr,
                    icon: Icons.add_rounded,
                    color: const Color(0xFF237A52),
                    onPressed: () =>
                        _openTransactionForm(TransactionType.income),
                  ),
                  _financeAction(
                    label: 'home_add_expense'.tr,
                    icon: Icons.remove_rounded,
                    color: const Color(0xFFB64D4D),
                    onPressed: () =>
                        _openTransactionForm(TransactionType.expense),
                  ),
                ];
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      buttons[0],
                      const SizedBox(height: 9),
                      buttons[1],
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: buttons[0]),
                    const SizedBox(width: 12),
                    Expanded(child: buttons[1]),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _amountCard({
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
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: _desktop ? 20 : 13,
            vertical: _desktop ? 22 : 14,
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: _desktop ? 26 : 19),
              SizedBox(width: _desktop ? 14 : 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontSize: _desktop ? 13.5 : 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'TSh ${_formatAmount(amount)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _ink,
                        fontSize: _desktop ? 26 : 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Text(
                          actionLabel,
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 13,
                          color: color,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNetAmount(double net) {
    final isPositive = net >= 0;
    return Row(
      children: [
        Text(
          'home_net_cash_flow'.tr,
          style: const TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          '${isPositive ? '' : '-'}TSh ${_formatAmount(net.abs())}',
          style: TextStyle(
            color: isPositive
                ? const Color(0xFF237A52)
                : const Color(0xFFB64D4D),
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _financeAction({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 50,
      child: FilledButton.icon(
        onPressed: () async {
          if (!await _checkCurrentSubscriptionAccess()) {
            _showSubscriptionRequiredDialog();
          } else {
            onPressed();
          }
        },
        icon: Icon(icon, size: 19),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
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

  Widget _buildTransactionsButton() {
    return OutlinedButton.icon(
      onPressed: () =>
          _openRestrictedRoute(AppRoutes.transactions, refreshFinance: true),
      icon: const Icon(Icons.receipt_long_outlined, size: 18),
      label: Text('home_view_all_transactions'.tr),
      style: OutlinedButton.styleFrom(
        foregroundColor: _brand,
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFDCE4E6)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildSubscriptionLink() {
    return TextButton.icon(
      onPressed: () async {
        await Get.toNamed(AppRoutes.subscription);
        await _loadSubscriptionStatus();
      },
      icon: const Icon(Icons.workspace_premium_outlined, size: 18),
      label: Text(
        isSubscribed || isTrial
            ? 'home_manage_subscription'.tr
            : 'home_subscription'.tr,
      ),
      style: TextButton.styleFrom(foregroundColor: _brand),
    );
  }

  void _showSubscriptionRequiredDialog() {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.lock_outline, color: _brand),
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
              style: FilledButton.styleFrom(backgroundColor: _brand),
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
