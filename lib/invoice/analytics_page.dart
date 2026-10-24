import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'transaction_model.dart';
import 'transaction_service.dart';
import 'category_service.dart';
import 'package:tra_list/services/profile_service.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:shimmer/shimmer.dart';
import 'package:tra_list/invoice/transaction_report_pdf.dart';
import 'package:tra_list/theme/app_theme.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tra_list/tasks/task_model.dart';
import 'package:tra_list/tasks/task_service.dart';
import 'package:tra_list/services/analytics_advice_service.dart';

enum ChartGranularity { day, week, month, year }

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage>
    with TickerProviderStateMixin {
  static const int _analyticsPageSize = 500;

  List<TransactionModel> _transactions = [];
  List<String> _availableShopNames = [];
  List<String> _availableCategories = [];
  String _selectedShopNickname = '';
  String _selectedCategory = '';
  bool _isLoading = true;
  bool _comparisonAvailable = false;
  String _selectedPeriod = 'transactions_today'.tr;
  String _selectedPeriodKey = 'today';
  TransactionType? _typeFilter; // New: Filter for income/expense
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  // Dynamic colors
  Color _brandColor = MjasiColors.primaryBlue;
  Color _accentColor = const Color(0xFFFFA000);

  // Animation controllers
  late AnimationController _chartAnimController;
  late AnimationController _cardAnimController;

  // Analytics data
  List<MapEntry<String, double>> _categoryChartData = [];
  Map<String, double> _categoryData = {};
  Map<String, int> _transactionFrequency = {};
  List<TimeData> _timeSeriesData = [];
  double _totalIncome = 0;
  double _totalExpense = 0;
  double _netFlow = 0;
  int _transactionCount = 0;
  double _previousIncome = 0;
  double _previousExpense = 0;
  double _previousNetFlow = 0;
  double _previousAllIncome = 0;
  double _previousAllExpense = 0;
  final Map<String, _ShopAnalyticsTotals> _shopTotals = {};
  Map<String, String> _staffNames = {};
  final Map<String, double> _posSalesByStaff = {};
  final Map<String, int> _posSaleCountsByStaff = {};
  int? _openTaskCount;
  int? _visibleTaskCount;
  int? _overdueTaskCount;
  int? _taskReviewCount;
  int? _posSaleCount;
  double? _posSalesTotal;
  String? _topSellingProduct;
  int? _topSellingProductOccurrences;
  final List<_AdviceRule> _adviceCatalog = [];
  int _analyticsRequest = 0;

  bool _isPdfBusy = false;
  bool _isExcelBusy = false;
  ChartGranularity _chartGranularity = ChartGranularity.day;

  @override
  void initState() {
    super.initState();
    _chartAnimController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _cardAnimController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _initializeDates();
    if (!BusinessAccessService.isOwner.value) {
      _selectedShopNickname = BusinessAccessService.shopNickname.value.trim();
    }
    _loadProfileColors();
    _loadAnalyticsFilters();
    _loadAnalyticsData();
    _loadAdviceCatalog();
  }

  Future<void> _loadAdviceCatalog() async {
    try {
      final json = await rootBundle.loadString('assets/analytics_advice.json');
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic> || decoded['advice'] is! List) {
        throw const FormatException(
          'Advice catalog must contain an advice list.',
        );
      }
      final rules = (decoded['advice'] as List).map((item) {
        if (item is! Map) {
          throw const FormatException('Advice entries must be objects.');
        }
        return _AdviceRule.fromJson(Map<String, dynamic>.from(item));
      }).toList();
      if (rules.map((rule) => rule.id).toSet().length != rules.length) {
        throw const FormatException('Advice ids must be unique.');
      }
      try {
        final customAdvice = await AnalyticsAdviceService.loadCustom();
        final rulesById = {for (final rule in rules) rule.id: rule};
        for (final advice in customAdvice) {
          rulesById[advice.id] = _AdviceRule.fromJson(advice.toMap());
        }
        rules
          ..clear()
          ..addAll(rulesById.values);
      } catch (error, stackTrace) {
        debugPrint('Could not load admin-managed advice: $error');
        debugPrintStack(stackTrace: stackTrace);
        if (mounted) {
          Get.snackbar('error'.tr, 'analytics_advice_catalog_load_error'.tr);
        }
      }
      if (!mounted) return;
      setState(() {
        _adviceCatalog
          ..clear()
          ..addAll(rules);
      });
    } catch (error, stackTrace) {
      debugPrint('Could not load analytics advice catalog: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        Get.snackbar('error'.tr, 'analytics_advice_catalog_load_error'.tr);
      }
    }
  }

  void _initializeDates() {
    final now = DateTime.now();
    // Default to today
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = _startDate.add(const Duration(days: 1));
  }

  Future<void> _loadProfileColors() async {
    try {
      final profile = await ProfileService.loadOrCreate();
      if (mounted && profile.containsKey('colors')) {
        final colors = profile['colors'] as Map<String, dynamic>;
        setState(() {
          _brandColor = Color(colors['brand'] as int? ?? 0xFF1976D2);
          _accentColor = Color(colors['accent'] as int? ?? 0xFFFFA000);
        });
      }
    } catch (e) {
      debugPrint('Failed to load profile colors: $e');
    }
  }

  Future<void> _loadAnalyticsData() async {
    final request = ++_analyticsRequest;
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _comparisonAvailable = false;
    });

    try {
      final transactions = <TransactionModel>[];
      DocumentSnapshot<TransactionModel>? cursor;
      while (true) {
        final snapshot =
            await TransactionService.getTransactions(
              startDate: _startDate,
              endDate: _endDate,
              limit: _analyticsPageSize,
              startAfter: cursor,
              shopNickname: _selectedShopNickname,
              category: _selectedCategory,
            ).timeout(
              const Duration(seconds: 30),
              onTimeout: () {
                throw TimeoutException('Data load timed out');
              },
            );
        transactions.addAll(snapshot.docs.map((doc) => doc.data()));
        if (snapshot.docs.length < _analyticsPageSize) break;
        cursor = snapshot.docs.last;
      }
      if (!mounted || request != _analyticsRequest) return;
      _transactions = transactions;
      _addTransactionShopsToOptions();
      _addTransactionCategoriesToOptions();
      _processAnalyticsData();
      await _loadOperationalInsights(request);
      await _loadPreviousPeriodTotals(request);

      _cardAnimController.forward();
      _chartAnimController.forward();
    } catch (e) {
      if (!mounted || request != _analyticsRequest) return;
      Get.snackbar(
        'Error',
        (e is TimeoutException
                ? 'Network timeout. Please check your connection.'
                : 'Failed to load analytics data: $e')
            .tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted && request == _analyticsRequest) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadAnalyticsFilters() async {
    if (BusinessAccessService.isOwner.value) {
      try {
        final profile = await ProfileService.loadOrCreate();
        var ownerShopName = profile['shopNickname']?.toString().trim() ?? '';
        if (ownerShopName.isEmpty) {
          ownerShopName = profile['name']?.toString().trim() ?? '';
        }
        final shopNames = <String>{if (ownerShopName.isNotEmpty) ownerShopName};
        final memberships = await FirebaseFirestore.instance
            .collection('employeeMemberships')
            .where('businessUid', isEqualTo: BusinessAccessService.businessId)
            .get();
        final staffNames = <String, String>{};
        for (final membership in memberships.docs) {
          final data = membership.data();
          final nickname = data['shopNickname']?.toString().trim() ?? '';
          final name = data['name']?.toString().trim() ?? '';
          if (nickname.isNotEmpty) shopNames.add(nickname);
          staffNames[membership.id] = name.isEmpty ? '—' : name;
        }
        if (mounted) {
          setState(() {
            _availableShopNames = shopNames.toList()..sort();
            _staffNames = staffNames;
          });
        }
      } catch (error, stackTrace) {
        debugPrint('Failed to load analytics shop filters: $error');
        debugPrintStack(stackTrace: stackTrace);
        if (mounted) {
          Get.snackbar('error'.tr, 'transactions_shops_load_error'.tr);
        }
      }
    }

    try {
      final snapshot = await CategoryService.getCategoriesFromServer();
      if (mounted) {
        setState(() {
          _availableCategories =
              snapshot.docs
                  .map((doc) => doc.data().name.trim())
                  .where((name) => name.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to load analytics category filters: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        Get.snackbar('error'.tr, 'transactions_categories_load_error'.tr);
      }
    }
  }

  void _addTransactionShopsToOptions() {
    if (!BusinessAccessService.isOwner.value) return;
    final names = _availableShopNames.toSet();
    names.addAll(
      _transactions
          .map((transaction) => transaction.shopNickname.trim())
          .where((name) => name.isNotEmpty),
    );
    _availableShopNames = names.toList()..sort();
  }

  void _addTransactionCategoriesToOptions() {
    final names = _availableCategories.toSet();
    names.addAll(
      _transactions
          .map((transaction) => transaction.category.trim())
          .where((name) => name.isNotEmpty),
    );
    _availableCategories = names.toList()..sort();
  }

  Future<void> _loadPreviousPeriodTotals(int request) async {
    final (previousStart, previousEnd) = _previousPeriodRange();
    if (!previousStart.isBefore(previousEnd)) return;

    try {
      final previousTotals = await TransactionService.getTotals(
        startDate: previousStart,
        endDate: previousEnd,
        shopNickname: _selectedShopNickname,
        category: _selectedCategory,
      ).timeout(const Duration(seconds: 30));
      if (!mounted || request != _analyticsRequest) return;

      final income = previousTotals['income'] ?? 0;
      final expense = previousTotals['expense'] ?? 0;
      setState(() {
        _previousAllIncome = income;
        _previousAllExpense = expense;
        _applyTypeFilterToPreviousTotals();
        _comparisonAvailable = true;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load analytics period comparison: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted && request == _analyticsRequest) {
        _comparisonAvailable = false;
        Get.snackbar('error'.tr, 'analytics_comparison_load_error'.tr);
      }
    }
  }

  (DateTime, DateTime) _previousPeriodRange() {
    switch (_selectedPeriodKey) {
      case 'Yesterday':
      case 'transactions_today':
        final previousDay = _startDate.subtract(const Duration(days: 1));
        return (previousDay, _startDate);
      case 'transactions_this_week':
        final previousWeek = _startDate.subtract(const Duration(days: 7));
        return (previousWeek, _startDate);
      case 'transactions_this_month':
        final previousMonth = DateTime(_startDate.year, _startDate.month - 1);
        return (previousMonth, _startDate);
      case 'analytics_last_3_months':
        final previousQuarter = DateTime(_startDate.year, _startDate.month - 3);
        return (previousQuarter, _startDate);
      case 'analytics_this_year':
        final previousYear = DateTime(_startDate.year - 1, 1);
        return (previousYear, _startDate);
      case 'transactions_custom_range':
        final periodLength = _endDate.difference(_startDate);
        return (_startDate.subtract(periodLength), _startDate);
      default:
        final previousDay = _startDate.subtract(const Duration(days: 1));
        return (previousDay, _startDate);
    }
  }

  void _applyTypeFilterToPreviousTotals() {
    _previousIncome = _typeFilter == TransactionType.expense
        ? 0
        : _previousAllIncome;
    _previousExpense = _typeFilter == TransactionType.income
        ? 0
        : _previousAllExpense;
    _previousNetFlow = _previousIncome - _previousExpense;
  }

  void _processAnalyticsData() {
    _categoryChartData.clear();
    _categoryData.clear();
    _transactionFrequency.clear();
    _timeSeriesData.clear();
    _shopTotals.clear();

    _totalIncome = 0;
    _totalExpense = 0;
    _transactionCount = 0;
    _netFlow = 0;

    final timeSeriesMap = <String, TimeData>{};

    final filteredTransactions = _transactions.where((t) {
      if (_typeFilter == null) return true;
      return t.type == _typeFilter;
    }).toList();

    var validTransactionCount = 0;
    for (final transaction in filteredTransactions) {
      if (transaction.amount < 0 || transaction.category.trim().isEmpty) {
        continue; // Skip invalid transactions
      }
      validTransactionCount++;

      if (transaction.type == TransactionType.income) {
        _totalIncome += transaction.amount;
      } else {
        _totalExpense += transaction.amount;
      }

      final shopName = transaction.shopNickname.trim().isEmpty
          ? 'transactions_shop_not_recorded'.tr
          : transaction.shopNickname.trim();
      final shopTotal = _shopTotals.putIfAbsent(
        shopName,
        _ShopAnalyticsTotals.new,
      );
      if (transaction.type == TransactionType.income) {
        shopTotal.income += transaction.amount;
      } else {
        shopTotal.expense += transaction.amount;
      }

      _categoryData[transaction.category] =
          (_categoryData[transaction.category] ?? 0) + transaction.amount;

      final String timeKey;
      final DateTime dateKey;

      switch (_chartGranularity) {
        case ChartGranularity.day:
          dateKey = DateTime(
            transaction.date.year,
            transaction.date.month,
            transaction.date.day,
          );
          timeKey = DateFormat('d MMM').format(transaction.date);
          break;
        case ChartGranularity.week:
          final startOfWeek = transaction.date.subtract(
            Duration(days: transaction.date.weekday - 1),
          );
          dateKey = DateTime(
            startOfWeek.year,
            startOfWeek.month,
            startOfWeek.day,
          );
          timeKey = DateFormat('d MMM').format(dateKey);
          break;
        case ChartGranularity.year:
          dateKey = DateTime(transaction.date.year);
          timeKey = DateFormat('yyyy').format(transaction.date);
          break;
        case ChartGranularity.month:
        default:
          dateKey = DateTime(transaction.date.year, transaction.date.month);
          timeKey = DateFormat('MMM yyyy').format(transaction.date);
          break;
      }

      timeSeriesMap.putIfAbsent(
        timeKey,
        () => TimeData(label: timeKey, income: 0, expense: 0, date: dateKey),
      );

      transaction.type == TransactionType.income
          ? timeSeriesMap[timeKey]!.income += transaction.amount
          : timeSeriesMap[timeKey]!.expense += transaction.amount;

      // Use English locale for keys to ensure consistency.
      final dayName = DateFormat('EEEE', 'en_US').format(transaction.date);
      _transactionFrequency[dayName] =
          (_transactionFrequency[dayName] ?? 0) + 1;
    }

    _transactionCount = validTransactionCount;
    _netFlow = _totalIncome - _totalExpense;

    _timeSeriesData = timeSeriesMap.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    _categoryChartData = _categoryData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  Future<void> _loadOperationalInsights(int request) async {
    _openTaskCount = null;
    _visibleTaskCount = null;
    _overdueTaskCount = null;
    _taskReviewCount = null;
    _posSaleCount = null;
    _posSalesTotal = null;
    _topSellingProduct = null;
    _topSellingProductOccurrences = null;
    _posSalesByStaff.clear();
    _posSaleCountsByStaff.clear();

    final errors = <String>[];
    if (BusinessAccessService.can('tasks', 'view') ||
        BusinessAccessService.isActive.value) {
      try {
        final tasks = await TaskService.watchTasks().first.timeout(
          const Duration(seconds: 12),
        );
        if (!mounted || request != _analyticsRequest) return;
        final visibleTasks = _selectedShopNickname.isEmpty
            ? tasks
            : tasks
                  .where((task) => task.assigneeShop == _selectedShopNickname)
                  .toList();
        _visibleTaskCount = visibleTasks.length;
        _openTaskCount = visibleTasks
            .where(
              (task) =>
                  task.status == TaskStatus.assigned ||
                  task.status == TaskStatus.inProgress ||
                  task.status == TaskStatus.returned,
            )
            .length;
        _overdueTaskCount = visibleTasks.where((task) => task.isOverdue).length;
        _taskReviewCount = visibleTasks
            .where((task) => task.status == TaskStatus.submitted)
            .length;
      } catch (error, stackTrace) {
        debugPrint('Could not load task insights: $error');
        debugPrintStack(stackTrace: stackTrace);
        errors.add('tasks');
      }
    }

    final canReadPosSales =
        BusinessAccessService.isOwner.value &&
        BusinessAccessService.can('invoices', 'view') &&
        _selectedShopNickname.isEmpty &&
        _selectedCategory.isEmpty &&
        _typeFilter != TransactionType.expense;
    if (canReadPosSales) {
      try {
        final invoices = FirebaseFirestore.instance
            .collection('users')
            .doc(BusinessAccessService.businessId)
            .collection('invoices');
        Query<Map<String, dynamic>> query = invoices
            .where(
              'createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate),
            )
            .where('createdAt', isLessThan: Timestamp.fromDate(_endDate))
            .where('source', isEqualTo: 'pos')
            .limit(_analyticsPageSize);
        DocumentSnapshot<Map<String, dynamic>>? cursor;
        var count = 0;
        var total = 0.0;
        final productOccurrences = <String, int>{};
        final salesByStaff = <String, double>{};
        final saleCountsByStaff = <String, int>{};
        while (true) {
          if (cursor != null) query = query.startAfterDocument(cursor);
          final snapshot = await query.get().timeout(
            const Duration(seconds: 20),
          );
          for (final doc in snapshot.docs) {
            final data = doc.data();
            if (data['kind'] != 'invoice') continue;
            final saleTotal = (data['total'] as num?)?.toDouble() ?? 0;
            count++;
            total += saleTotal;
            final staffUid = data['uid']?.toString().trim() ?? '';
            if (staffUid.isNotEmpty) {
              salesByStaff.update(
                staffUid,
                (amount) => amount + saleTotal,
                ifAbsent: () => saleTotal,
              );
              saleCountsByStaff.update(
                staffUid,
                (saleCount) => saleCount + 1,
                ifAbsent: () => 1,
              );
            }
            final items = data['items'];
            if (items is List) {
              for (final item in items.whereType<Map>()) {
                final name = (item['description'] ?? item['productId'] ?? '')
                    .toString()
                    .trim();
                if (name.isNotEmpty) {
                  productOccurrences.update(
                    name,
                    (occurrences) => occurrences + 1,
                    ifAbsent: () => 1,
                  );
                }
              }
            }
          }
          if (snapshot.docs.length < _analyticsPageSize) break;
          cursor = snapshot.docs.last;
        }
        if (!mounted || request != _analyticsRequest) return;
        _posSaleCount = count;
        _posSalesTotal = total;
        _posSalesByStaff
          ..clear()
          ..addAll(salesByStaff);
        _posSaleCountsByStaff
          ..clear()
          ..addAll(saleCountsByStaff);
        if (productOccurrences.isNotEmpty) {
          final topProduct = productOccurrences.entries.reduce(
            (first, second) => first.value >= second.value ? first : second,
          );
          _topSellingProduct = topProduct.key;
          _topSellingProductOccurrences = topProduct.value;
        }
      } catch (error, stackTrace) {
        if (request == _analyticsRequest) {
          _posSalesByStaff.clear();
          _posSaleCountsByStaff.clear();
        }
        debugPrint('Could not load POS sales insights: $error');
        debugPrintStack(stackTrace: stackTrace);
        errors.add('sales');
      }
    }

    if (!mounted || request != _analyticsRequest) return;
    if (errors.isNotEmpty) {
      Get.snackbar(
        'error'.tr,
        'analytics_operational_insights_error'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  @override
  void dispose() {
    _chartAnimController.dispose();
    _cardAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MjasiColors.background,
      appBar: AppBar(
        title: Text('home_analytics'.tr),
        actions: [
          if (!_isPdfBusy)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: _transactions.isEmpty ? null : _exportPdf,
              tooltip: 'Export PDF'.tr,
            ),
          if (_isPdfBusy)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(18.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: MjasiColors.primaryBlue,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading && _transactions.isEmpty
          ? _buildSkeletonLoader()
          : RefreshIndicator(
              onRefresh: _loadAnalyticsData,
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(constraints.maxWidth < 600 ? 12 : 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1280),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildAnalyticsFilters(),
                          const SizedBox(height: 20),
                          _buildOverviewCards(),
                          const SizedBox(height: 24),
                          if (_comparisonAvailable) ...[
                            _buildPeriodComparison(),
                            const SizedBox(height: 24),
                          ],
                          if (BusinessAccessService.isOwner.value &&
                              _selectedShopNickname.isEmpty) ...[
                            _buildShopComparison(),
                            const SizedBox(height: 24),
                          ],
                          _buildCashFlowChart(),
                          const SizedBox(height: 24),
                          _buildCategoryPieChart(),
                          const SizedBox(height: 24),
                          _buildCategoryAnalysis(),
                          const SizedBox(height: 24),
                          _buildTransactionFrequency(),
                          const SizedBox(height: 24),
                          _buildInsightsCards(),
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  bool get _hasActiveFilters =>
      _typeFilter != null ||
      _selectedCategory.isNotEmpty ||
      (BusinessAccessService.isOwner.value &&
          _selectedShopNickname.isNotEmpty) ||
      _selectedPeriodKey != 'today';

  Widget _buildPeriodSelector() {
    return PopupMenuButton<String>(
      onSelected: _changePeriod,
      tooltip: 'analytics_filter_period'.tr,
      itemBuilder: (context) => [
        PopupMenuItem(value: 'today', child: Text('transactions_today'.tr)),
        PopupMenuItem(value: 'Yesterday', child: Text('Yesterday'.tr)),
        PopupMenuItem(
          value: 'transactions_this_week',
          child: Text('transactions_this_week'.tr),
        ),
        PopupMenuItem(
          value: 'transactions_this_month',
          child: Text('transactions_this_month'.tr),
        ),
        PopupMenuItem(
          value: 'analytics_last_3_months',
          child: Text('analytics_last_3_months'.tr),
        ),
        PopupMenuItem(
          value: 'analytics_this_year',
          child: Text('analytics_this_year'.tr),
        ),
        PopupMenuItem(
          value: 'transactions_custom_range',
          child: Text('transactions_custom_range'.tr),
        ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: MjasiColors.lightBlue,
          borderRadius: BorderRadius.circular(MjasiRadius.sm),
          border: Border.all(
            color: MjasiColors.primaryBlue.withValues(alpha: .16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_month_outlined,
              color: MjasiColors.primaryBlue,
              size: 18,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _selectedPeriod,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MjasiColors.primaryNavy,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: MjasiColors.primaryBlue,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeFilter() {
    return SegmentedButton<TransactionType?>(
      segments: [
        ButtonSegment(
          value: null,
          label: Text('analytics_all'.tr),
          icon: const Icon(Icons.tune_rounded),
        ),
        ButtonSegment(
          value: TransactionType.income,
          label: Text('income'.tr),
          icon: const Icon(Icons.arrow_upward),
        ),
        ButtonSegment(
          value: TransactionType.expense,
          label: Text('expense'.tr),
          icon: const Icon(Icons.arrow_downward),
        ),
      ],
      selected: {_typeFilter},
      onSelectionChanged: (newSelection) {
        setState(() {
          _typeFilter = newSelection.first;
          _applyTypeFilterToPreviousTotals();
          _processAnalyticsData();
        });
      },
      style: SegmentedButton.styleFrom(
        backgroundColor: MjasiColors.surface,
        foregroundColor: MjasiColors.textSecondary,
        selectedForegroundColor: MjasiColors.primaryBlue,
        selectedBackgroundColor: MjasiColors.lightBlue,
        side: const BorderSide(color: MjasiColors.border),
      ),
    );
  }

  Widget _buildAnalyticsFilters() {
    final shopValue =
        _selectedShopNickname.isNotEmpty &&
            _availableShopNames.contains(_selectedShopNickname)
        ? _selectedShopNickname
        : '';
    final categoryValue =
        _selectedCategory.isNotEmpty &&
            _availableCategories.contains(_selectedCategory)
        ? _selectedCategory
        : '';
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: MjasiColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MjasiRadius.md),
        side: const BorderSide(color: MjasiColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(MjasiSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: MjasiColors.lightBlue,
                    borderRadius: BorderRadius.circular(MjasiRadius.sm),
                  ),
                  child: const Icon(
                    Icons.filter_alt_rounded,
                    color: MjasiColors.primaryBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: MjasiSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'analytics_filters'.tr,
                        style: const TextStyle(
                          color: MjasiColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'analytics_filters_subtitle'.tr,
                        style: const TextStyle(
                          color: MjasiColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_hasActiveFilters)
                  TextButton.icon(
                    onPressed: _resetAnalyticsFilters,
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: Text('analytics_clear_filters'.tr),
                    style: TextButton.styleFrom(
                      foregroundColor: MjasiColors.primaryBlue,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: MjasiSpacing.lg),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: MjasiSpacing.md,
              runSpacing: MjasiSpacing.sm,
              children: [
                Text(
                  'analytics_filter_period'.tr,
                  style: const TextStyle(
                    color: MjasiColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                _buildPeriodSelector(),
              ],
            ),
            const SizedBox(height: MjasiSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final categoryFilter = DropdownButtonFormField<String>(
                  initialValue: categoryValue,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'transactions_filter_category'.tr,
                    prefixIcon: const Icon(Icons.category_outlined),
                    filled: true,
                    fillColor: MjasiColors.background,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MjasiRadius.sm),
                      borderSide: const BorderSide(color: MjasiColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MjasiRadius.sm),
                      borderSide: const BorderSide(color: MjasiColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MjasiRadius.sm),
                      borderSide: const BorderSide(
                        color: MjasiColors.primaryBlue,
                        width: 1.5,
                      ),
                    ),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text('transactions_all_categories'.tr),
                    ),
                    for (final category in _availableCategories)
                      DropdownMenuItem(
                        value: category,
                        child: Text(category, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (category) {
                    if (category == null || category == _selectedCategory) {
                      return;
                    }
                    setState(() => _selectedCategory = category);
                    _loadAnalyticsData();
                  },
                );
                if (!BusinessAccessService.isOwner.value) {
                  return categoryFilter;
                }

                final shopFilter = DropdownButtonFormField<String>(
                  initialValue: shopValue,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'transactions_filter_shop'.tr,
                    prefixIcon: const Icon(Icons.storefront_outlined),
                    filled: true,
                    fillColor: MjasiColors.background,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MjasiRadius.sm),
                      borderSide: const BorderSide(color: MjasiColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MjasiRadius.sm),
                      borderSide: const BorderSide(color: MjasiColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MjasiRadius.sm),
                      borderSide: const BorderSide(
                        color: MjasiColors.primaryBlue,
                        width: 1.5,
                      ),
                    ),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text('transactions_all_shops'.tr),
                    ),
                    for (final shop in _availableShopNames)
                      DropdownMenuItem(
                        value: shop,
                        child: Text(shop, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (shop) {
                    if (shop == null || shop == _selectedShopNickname) return;
                    setState(() => _selectedShopNickname = shop);
                    _loadAnalyticsData();
                  },
                );
                if (constraints.maxWidth < 560) {
                  return Column(
                    children: [
                      shopFilter,
                      const SizedBox(height: MjasiSpacing.md),
                      categoryFilter,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: shopFilter),
                    const SizedBox(width: MjasiSpacing.md),
                    Expanded(child: categoryFilter),
                  ],
                );
              },
            ),
            const SizedBox(height: MjasiSpacing.lg),
            Text(
              'analytics_filter_type'.tr,
              style: const TextStyle(
                color: MjasiColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: MjasiSpacing.sm),
            _buildTypeFilter(),
          ],
        ),
      ),
    );
  }

  void _resetAnalyticsFilters() {
    setState(() {
      _selectedShopNickname = BusinessAccessService.isOwner.value
          ? ''
          : BusinessAccessService.shopNickname.value.trim();
      _selectedCategory = '';
      _typeFilter = null;
      _previousIncome = _previousAllIncome;
      _previousExpense = _previousAllExpense;
      _previousNetFlow = _previousAllIncome - _previousAllExpense;
    });
    _changePeriod('today');
  }

  Widget _buildPeriodComparison() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'analytics_period_comparison'.tr,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$_selectedPeriod · ${'analytics_previous_period'.tr}',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 14),
          _buildComparisonRow(
            'analytics_total_income'.tr,
            _totalIncome,
            _previousIncome,
            Colors.green,
          ),
          const Divider(height: 20),
          _buildComparisonRow(
            'analytics_total_expense'.tr,
            _totalExpense,
            _previousExpense,
            Colors.red,
          ),
          const Divider(height: 20),
          _buildComparisonRow(
            'net'.tr,
            _netFlow,
            _previousNetFlow,
            _brandColor,
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonRow(
    String label,
    double current,
    double previous,
    Color color,
  ) {
    final change = current - previous;
    final percentage = previous == 0
        ? (current == 0 ? '0%' : 'analytics_new'.tr)
        : '${change > 0 ? '+' : ''}${(change / previous.abs() * 100).toStringAsFixed(1)}%';
    final isExpense = label == 'analytics_total_expense'.tr;
    final changeColor = isExpense
        ? (change <= 0 ? Colors.green : Colors.red)
        : (change >= 0 ? Colors.green : Colors.red);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'TSH ${_formatMoney(current)}',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${'analytics_previous_short'.tr}: ${_formatMoney(previous)}  ·  $percentage',
              style: TextStyle(
                color: change == 0 ? Colors.grey : changeColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildShopComparison() {
    final isExpenseComparison = _typeFilter == TransactionType.expense;
    final shops = _shopTotals.entries.toList()
      ..sort(
        (a, b) => (isExpenseComparison ? b.value.expense : b.value.income)
            .compareTo(isExpenseComparison ? a.value.expense : a.value.income),
      );
    if (shops.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'analytics_shop_comparison'.tr,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          for (final entry in shops.take(5)) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${'net'.tr}: ${_formatMoney(entry.value.income - entry.value.expense)}',
                        style: TextStyle(
                          color: entry.value.income >= entry.value.expense
                              ? Colors.green
                              : Colors.red,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${'income'.tr}: ${_formatMoney(entry.value.income)}',
                          style: const TextStyle(
                            color: Colors.green,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${'expense'.tr}: ${_formatMoney(entry.value.expense)}',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (entry != shops.take(5).last) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Widget _buildSkeletonLoader() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: List.generate(5, (_) => _buildSkeletonCard()),
      ),
    );
  }

  Widget _buildOverviewCards() {
    return AnimatedBuilder(
      animation: _cardAnimController,
      builder: (context, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
            .animate(
              CurvedAnimation(
                parent: _cardAnimController,
                curve: Curves.easeOutCubic,
              ),
            ),
        child: FadeTransition(
          opacity: _cardAnimController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'analytics_financial_overview'.tr,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: MjasiColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _selectedPeriod,
                          style: const TextStyle(
                            color: MjasiColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _showBusinessSummary,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: Text('analytics_ai_summary'.tr),
                    style: FilledButton.styleFrom(
                      backgroundColor: MjasiColors.primaryNavy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(MjasiRadius.sm),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 12.0;
                  final columns = constraints.maxWidth < 520 ? 1 : 2;
                  final cardWidth =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                      columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      SizedBox(
                        width: cardWidth,
                        child: _buildMetricCard(
                          'analytics_total_income'.tr,
                          'TSH ${_formatMoney(_totalIncome)}',
                          Icons.south_west_rounded,
                          MjasiColors.success,
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _buildMetricCard(
                          'analytics_total_expense'.tr,
                          'TSH ${_formatMoney(_totalExpense)}',
                          Icons.north_east_rounded,
                          MjasiColors.error,
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _buildMetricCard(
                          'net'.tr,
                          '${_netFlow >= 0 ? '+' : '-'}TSH ${_formatMoney(_netFlow.abs())}',
                          _netFlow >= 0
                              ? Icons.account_balance_wallet_rounded
                              : Icons.warning_amber_rounded,
                          _netFlow >= 0
                              ? MjasiColors.primaryBlue
                              : MjasiColors.warning,
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _buildMetricCard(
                          'analytics_transactions'.tr,
                          '$_transactionCount',
                          Icons.receipt_long_rounded,
                          const Color(0xFF7C3AED),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Semantics(
      label: '$title: $value',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: MjasiColors.surface,
          borderRadius: BorderRadius.circular(MjasiRadius.md),
          border: Border.all(color: MjasiColors.border),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: .07),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withValues(alpha: .16),
                        color.withValues(alpha: .07),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(MjasiRadius.sm),
                  ),
                  child: Icon(icon, color: color, size: 21),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_outward_rounded,
                  color: color.withValues(alpha: .65),
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                color: MjasiColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: MjasiColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildBusinessSummaryText() {
    final insights = _generateInsights();
    final summaryLines = <String>[
      '${'analytics_ai_summary'.tr} — $_selectedPeriod',
      '${'analytics_total_income'.tr}: TSH ${_formatMoney(_totalIncome)}',
      '${'analytics_total_expense'.tr}: TSH ${_formatMoney(_totalExpense)}',
      '${'net'.tr}: ${_netFlow >= 0 ? '+' : '-'}TSH ${_formatMoney(_netFlow.abs())}',
      '${'analytics_transactions'.tr}: $_transactionCount',
    ];
    if (_categoryChartData.isNotEmpty) {
      final topCategory = _categoryChartData.first;
      summaryLines.add(
        '${'analytics_summary_top_category'.tr}: ${topCategory.key} '
        '(TSH ${_formatMoney(topCategory.value)})',
      );
    }
    summaryLines.add('');
    summaryLines.add('analytics_ai_insights'.tr);
    for (final insight in insights) {
      summaryLines.add('${insight.title}: ${insight.description}');
    }
    return summaryLines.join('\n');
  }

  Future<void> _shareBusinessSummary() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          title: 'analytics_ai_summary'.tr,
          subject: 'analytics_financial_overview'.tr,
          text: _buildBusinessSummaryText(),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Could not share analytics summary: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      Get.snackbar('error'.tr, 'analytics_summary_share_error'.tr);
    }
  }

  Future<void> _showBusinessSummary() async {
    final insights = _generateInsights();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MjasiRadius.lg),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [MjasiColors.primaryNavy, MjasiColors.primaryBlue],
                ),
                borderRadius: BorderRadius.circular(MjasiRadius.sm),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 21,
              ),
            ),
            const SizedBox(width: MjasiSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'analytics_ai_summary'.tr,
                    style: const TextStyle(
                      color: MjasiColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    _selectedPeriod,
                    style: const TextStyle(
                      color: MjasiColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
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
                _summaryMetric(
                  'analytics_total_income'.tr,
                  'TSH ${_formatMoney(_totalIncome)}',
                  Icons.south_west_rounded,
                  MjasiColors.success,
                ),
                _summaryMetric(
                  'analytics_total_expense'.tr,
                  'TSH ${_formatMoney(_totalExpense)}',
                  Icons.north_east_rounded,
                  MjasiColors.error,
                ),
                _summaryMetric(
                  'net'.tr,
                  '${_netFlow >= 0 ? '+' : '-'}TSH ${_formatMoney(_netFlow.abs())}',
                  Icons.account_balance_wallet_rounded,
                  _netFlow >= 0 ? MjasiColors.primaryBlue : MjasiColors.warning,
                ),
                _summaryMetric(
                  'analytics_transactions'.tr,
                  '$_transactionCount',
                  Icons.receipt_long_rounded,
                  const Color(0xFF7C3AED),
                ),
                if (_categoryChartData.isNotEmpty) ...[
                  const SizedBox(height: MjasiSpacing.sm),
                  Text(
                    'analytics_summary_top_category'.tr,
                    style: const TextStyle(
                      color: MjasiColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: MjasiSpacing.xs),
                  Text(
                    '${_categoryChartData.first.key} · '
                    'TSH ${_formatMoney(_categoryChartData.first.value)}',
                    style: const TextStyle(
                      color: MjasiColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: MjasiSpacing.md),
                Row(
                  children: [
                    const Icon(
                      Icons.lightbulb_outline_rounded,
                      color: MjasiColors.warning,
                      size: 20,
                    ),
                    const SizedBox(width: MjasiSpacing.sm),
                    Text(
                      'analytics_ai_insights'.tr,
                      style: const TextStyle(
                        color: MjasiColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MjasiSpacing.sm),
                for (final insight in insights)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: MjasiSpacing.sm),
                    padding: const EdgeInsets.symmetric(
                      horizontal: MjasiSpacing.md,
                      vertical: MjasiSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: insight.color.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(MjasiRadius.sm),
                      border: Border(
                        left: BorderSide(color: insight.color, width: 3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          insight.title,
                          style: TextStyle(
                            color: insight.color,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          insight.description,
                          style: const TextStyle(
                            color: MjasiColors.textPrimary,
                            height: 1.3,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: MjasiSpacing.sm),
                Text(
                  'analytics_summary_disclaimer'.tr,
                  style: const TextStyle(
                    color: MjasiColors.textSecondary,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('close'.tr),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _shareBusinessSummary();
            },
            icon: const Icon(Icons.share_rounded, size: 18),
            label: Text('analytics_share_summary'.tr),
            style: FilledButton.styleFrom(
              backgroundColor: MjasiColors.primaryBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryMetric(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MjasiSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: MjasiSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MjasiColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: MjasiColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCashFlowChart() {
    if (_timeSeriesData.isEmpty) {
      return _buildEmptyChart('analytics_no_cash_flow_data'.tr);
    }

    return AnimatedBuilder(
      animation: _chartAnimController,
      builder: (context, child) => FadeTransition(
        opacity: _chartAnimController,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'analytics_cash_flow_trend'.tr,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 250,
                child: SfCartesianChart(
                  primaryXAxis: CategoryAxis(
                    majorGridLines: const MajorGridLines(
                      width: 0,
                    ), // No tr needed for widgets
                    labelStyle: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 10,
                    ),
                  ),
                  primaryYAxis: NumericAxis(
                    numberFormat: NumberFormat.compact(),
                    majorGridLines: MajorGridLines(
                      // No tr needed for widgets
                      width: 0.5,
                      color: Colors.grey[300]!,
                    ),
                    labelStyle: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 10,
                    ),
                  ),
                  plotAreaBorderWidth: 0,
                  legend: const Legend(
                    isVisible: true, // No tr needed for widgets
                    position: LegendPosition.bottom,
                    overflowMode: LegendItemOverflowMode.wrap,
                  ),
                  tooltipBehavior: TooltipBehavior(
                    enable: true,
                    format: 'point.x : TSH point.y',
                    header: '',
                    canShowMarker: false,
                  ),
                  series: <CartesianSeries<TimeData, String>>[
                    SplineAreaSeries<TimeData, String>(
                      dataSource: _timeSeriesData,
                      xValueMapper: (TimeData data, _) => data.label,
                      yValueMapper: (TimeData data, _) => data.income,
                      name: 'income'.tr,
                      color: Colors.green.withOpacity(0.7),
                      borderColor: Colors.green,
                      borderWidth: 2,
                      // NEW: Add markers to data points for better visibility.
                      markerSettings: const MarkerSettings(
                        isVisible: true,
                        height: 5,
                        width: 5,
                        shape: DataMarkerType.circle,
                        borderColor: Colors.green,
                      ),
                      gradient: LinearGradient(
                        // NEW: A more pronounced gradient for a richer look.
                        colors: [
                          Colors.green.withOpacity(0.4),
                          Colors.green.withOpacity(0.05),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                    SplineAreaSeries<TimeData, String>(
                      dataSource: _timeSeriesData,
                      xValueMapper: (TimeData data, _) => data.label,
                      yValueMapper: (TimeData data, _) => data.expense,
                      name: 'expense'.tr,
                      color: Colors.red.withOpacity(0.7),
                      borderColor: Colors.red,
                      borderWidth: 2,
                      // NEW: Add markers to data points for better visibility.
                      markerSettings: const MarkerSettings(
                        isVisible: true,
                        height: 5,
                        width: 5,
                        shape: DataMarkerType.circle,
                        borderColor: Colors.red,
                      ),
                      gradient: LinearGradient(
                        // NEW: A more pronounced gradient for a richer look.
                        colors: [
                          Colors.red.withOpacity(0.4),
                          Colors.red.withOpacity(0.05),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.topCenter,
                      ),
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

  Widget _buildCategoryPieChart() {
    if (_categoryChartData.isEmpty)
      return _buildEmptyChart('analytics_no_category_data'.tr);

    // NEW: Logic to group smaller categories into "Other".
    final List<MapEntry<String, double>> chartDataSource;
    const int maxSlices = 5; // Show top 4 + "Other"

    if (_categoryChartData.length > maxSlices) {
      final topCategories = _categoryChartData.take(maxSlices - 1).toList();
      final otherValue = _categoryChartData
          .skip(maxSlices - 1)
          .fold(0.0, (sum, entry) => sum + entry.value);
      chartDataSource = [...topCategories, MapEntry('Other'.tr, otherValue)];
    } else {
      chartDataSource = _categoryChartData;
    }

    return AnimatedBuilder(
      animation: _chartAnimController,
      builder: (context, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
            .animate(
              CurvedAnimation(
                parent: _chartAnimController,
                curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
              ),
            ),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (_typeFilter == TransactionType.expense
                        ? 'analytics_top_spending_categories'
                        : _typeFilter == TransactionType.income
                        ? 'analytics_top_income_sources'
                        : 'analytics_category_distribution')
                    .tr,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 300,
                child: SfCircularChart(
                  legend: const Legend(
                    isVisible: true, // No tr needed for widgets
                    position: LegendPosition.bottom,
                    overflowMode: LegendItemOverflowMode.wrap,
                    textStyle: TextStyle(fontSize: 11),
                  ),
                  tooltipBehavior: TooltipBehavior(
                    enable: true,
                    format: 'point.x : TSH point.y (point.percentage)%',
                  ),
                  series: <CircularSeries>[
                    DoughnutSeries<MapEntry<String, double>, String>(
                      dataSource: chartDataSource,
                      xValueMapper: (MapEntry<String, double> data, _) =>
                          data.key,
                      yValueMapper: (MapEntry<String, double> data, _) =>
                          data.value,
                      dataLabelMapper: (MapEntry<String, double> data, _) =>
                          data.value >
                              0 // No tr needed for logic
                          ? '${((data.value / (_totalIncome + _totalExpense)) * 100).toStringAsFixed(1)}%'
                          : '',
                      dataLabelSettings: const DataLabelSettings(
                        isVisible: true, // No tr needed for widgets
                        labelPosition: ChartDataLabelPosition
                            .outside, // No tr needed for widgets
                        textStyle: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPointTap: (ChartPointDetails details) {
                        if (details.pointIndex == null) return;
                        final tappedEntry =
                            chartDataSource[details.pointIndex!];
                        // If "Other" is tapped, show a list of all other categories.
                        if (tappedEntry.key == 'Other'.tr) {
                          final otherCategories = _categoryChartData
                              .skip(maxSlices - 1)
                              .toList();
                          _showTransactionsForOtherCategories(otherCategories);
                        } else {
                          _showTransactionsForCategory(tappedEntry.key);
                        }
                      },
                      innerRadius: '50%',
                      pointColorMapper: (MapEntry<String, double> data, index) {
                        // NEW: Expanded color palette with reduced opacity for a softer look.
                        final List<Color> colors = [
                          _brandColor.withOpacity(0.8),
                          _accentColor.withOpacity(0.8),
                          Colors.green.withOpacity(0.8),
                          Colors.red.withOpacity(0.8),
                          Colors.purple.withOpacity(0.8),
                          Colors.teal.withOpacity(0.8),
                          Colors.orange.withOpacity(0.8),
                          Colors.blueGrey.withOpacity(0.8),
                        ];
                        return colors[index % colors.length];
                      },
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

  Widget _buildCategoryAnalysis() {
    if (_categoryChartData.isEmpty)
      return _buildEmptyChart('analytics_no_category_data'.tr);

    return AnimatedBuilder(
      animation: _chartAnimController,
      builder: (context, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
            .animate(
              CurvedAnimation(
                parent: _chartAnimController,
                curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
              ),
            ),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'analytics_top_categories'.tr,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 20),
              ..._categoryChartData.take(5).map((entry) {
                final percentage =
                    (entry.value / (_totalIncome + _totalExpense)) * 100;
                return _buildCategoryItem(entry.key, entry.value, percentage);
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryItem(String category, double amount, double percentage) {
    final total = _totalIncome + _totalExpense; // No tr needed for logic
    final safePercentage = total > 0 ? (amount / total) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  category, // No tr needed for variable
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                ),
              ),
              Text(
                'TSH ${_formatMoney(amount)}', // No tr needed for variable
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${percentage.toStringAsFixed(1)}%', // No tr needed for variable
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: safePercentage,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation(
              _brandColor,
            ), // No tr needed for variable
            minHeight: 4,
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionFrequency() {
    if (_transactionFrequency.isEmpty) {
      return _buildEmptyChart('analytics_no_frequency_data'.tr);
    }

    // NEW: Dynamically generate chart data based on the selected granularity.
    final List<ChartData> chartData;
    switch (_chartGranularity) {
      case ChartGranularity.day:
        // Use English day names as keys for lookup, then translate for display.
        const dayOrder = [
          'Monday',
          'Tuesday',
          'Wednesday',
          'Thursday',
          'Friday',
          'Saturday',
          'Sunday',
        ];
        chartData = dayOrder.map((day) {
          return ChartData(
            _getDayAbbreviation(
              day.tr,
            ), // Translate before getting abbreviation
            _transactionFrequency[day]?.toDouble() ?? 0,
          );
        }).toList();
        break;
      case ChartGranularity.week:
      case ChartGranularity.month:
      case ChartGranularity.year:
        // For week, month, and year, the data is already processed in _timeSeriesData.
        // We just need to map it to ChartData.
        chartData = _timeSeriesData.map((data) {
          // Sum income and expense transactions for total frequency. // No tr needed for logic
          final totalTransactions = _transactions.where((t) {
            if (_typeFilter != null && t.type != _typeFilter) return false;
            final String timeKey;
            switch (_chartGranularity) {
              case ChartGranularity.week:
                final startOfWeek = t.date.subtract(
                  Duration(days: t.date.weekday - 1),
                );
                timeKey = DateFormat('d MMM').format(startOfWeek);
                break;
              case ChartGranularity.year:
                timeKey = DateFormat('yyyy').format(t.date);
                break;
              default: // month
                timeKey = DateFormat('MMM yyyy').format(t.date);
            }
            return timeKey == data.label;
          }).length;
          return ChartData(data.label, totalTransactions.toDouble());
        }).toList();
        break;
    }

    return AnimatedBuilder(
      animation: _chartAnimController,
      builder: (context, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
            .animate(
              CurvedAnimation(
                parent: _chartAnimController,
                curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic),
              ),
            ),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'analytics_transaction_pattern'.tr,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ChartGranularity>(
                  segments: [
                    ButtonSegment(
                      // No tr needed for widgets
                      value: ChartGranularity.day,
                      label: Text('Day'.tr),
                    ),
                    ButtonSegment(
                      value: ChartGranularity.week,
                      label: Text('Week'.tr), // No tr needed for widgets
                    ),
                    ButtonSegment(
                      value: ChartGranularity.month,
                      label: Text('Month'.tr), // No tr needed for widgets
                    ),
                    ButtonSegment(
                      value: ChartGranularity.year,
                      label: Text('Year'.tr), // No tr needed for widgets
                    ),
                  ],
                  selected: {_chartGranularity},
                  onSelectionChanged: _onGranularityChanged,
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: _accentColor.withOpacity(0.2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 200,
                child: SfCartesianChart(
                  primaryXAxis: CategoryAxis(
                    majorGridLines: const MajorGridLines(
                      width: 0,
                    ), // No tr needed for widgets
                    labelStyle: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 10,
                    ),
                  ),
                  primaryYAxis: NumericAxis(
                    majorGridLines: MajorGridLines(
                      width: 0.5, // No tr needed for widgets
                      color: Colors.grey[300]!,
                    ),
                    labelStyle: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 10,
                    ),
                  ),
                  plotAreaBorderWidth: 0,
                  tooltipBehavior: TooltipBehavior(
                    enable: true, // No tr needed for widgets
                    format: 'point.x : point.y transactions',
                  ),
                  series: <CartesianSeries<ChartData, String>>[
                    ColumnSeries<ChartData, String>(
                      dataSource: chartData,
                      xValueMapper: (ChartData data, _) => data.x,
                      yValueMapper: (ChartData data, _) => data.y,
                      color: _brandColor, // No tr needed for variable
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(4),
                      ),
                      dataLabelSettings: const DataLabelSettings(
                        isVisible: true, // No tr needed for widgets
                        textStyle: TextStyle(fontSize: 10),
                      ),
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

  Widget _buildInsightsCards() {
    final insights = _generateInsights();

    return AnimatedBuilder(
      animation: _cardAnimController,
      builder: (context, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
            .animate(
              CurvedAnimation(
                parent: _cardAnimController,
                curve: const Interval(0.7, 1.0, curve: Curves.easeOutCubic),
              ),
            ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'analytics_ai_insights'.tr,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 16),
            ...insights.map((insight) => _buildInsightCard(insight)),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightCard(InsightData insight) {
    return Container(
      // No tr needed for widgets
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: insight.color, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            insight.icon,
            color: insight.color,
            size: 24,
          ), // No tr needed for variables
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title, // No tr needed for variable
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  insight.description, // No tr needed for variable
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyChart(String message) {
    return Container(
      // No tr needed for widgets
      height: 200,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 48,
              color: Colors.grey[400],
            ), // No tr needed for widgets
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                color: Colors.grey[600],
              ), // No tr needed for variable
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonCard() {
    return Container(
      // No tr needed for widgets
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 120,
            height: 16,
            color: Colors.white,
          ), // No tr needed for widgets
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 100,
            color: Colors.white,
          ), // No tr needed for widgets
        ],
      ),
    );
  }

  List<InsightData> _generateInsights() {
    final businessInsights = <InsightData>[];
    // No tr needed for logic
    // 1. Cash Flow Analysis
    if (_totalIncome > 0 || _totalExpense > 0) {
      if (_netFlow > 0) {
        businessInsights.add(
          InsightData(
            title: 'analytics_positive_cash_flow'.tr,
            description:
                '${'analytics_positive_cash_flow_desc'.tr} TSH ${_formatMoney(_netFlow)}. ${'analytics_healthy_financial_position'.tr}',
            icon: Icons.trending_up,
            color: Colors.green,
          ),
        );
      } else if (_netFlow < 0) {
        businessInsights.add(
          InsightData(
            title: 'analytics_negative_cash_flow'.tr,
            description:
                '${'analytics_negative_cash_flow_desc'.tr} TSH ${_formatMoney(_netFlow.abs())}. ${'analytics_negative_cash_flow_suggestion'.tr}',
            icon: Icons.trending_down,
            color: Colors.red,
          ),
        );
      } else {
        businessInsights.add(
          InsightData(
            title: 'analytics_balanced_budget'.tr,
            description: 'analytics_balanced_budget_desc'.tr,
            icon: Icons.account_balance,
            color: Colors.blue,
          ),
        );
      }
    }
    // No tr needed for logic
    // 2. Spending Habit Analysis
    final expenseCategoryTotals = <String, double>{};
    for (final transaction in _transactions) {
      if (_typeFilter == TransactionType.income ||
          transaction.type != TransactionType.expense ||
          transaction.amount < 0 ||
          transaction.category.trim().isEmpty) {
        continue;
      }
      expenseCategoryTotals.update(
        transaction.category,
        (amount) => amount + transaction.amount,
        ifAbsent: () => transaction.amount,
      );
    }
    final expenseCategories = expenseCategoryTotals.entries.toList();

    if (expenseCategories.isNotEmpty) {
      expenseCategories.sort((a, b) => b.value.compareTo(a.value));
      final topExpenseCategory = expenseCategories.first;
      final percentage = _totalExpense > 0
          ? (topExpenseCategory.value / _totalExpense) * 100
          : 0;

      businessInsights.add(
        InsightData(
          title: 'analytics_top_spending_area'.tr,
          description:
              '${'analytics_top_spending_area_desc1'.tr} "${topExpenseCategory.key}", ${'analytics_top_spending_area_desc2'.tr} ${percentage.toStringAsFixed(1)}% ${'analytics_top_spending_area_desc3'.tr}',
          icon: Icons.pie_chart,
          color: _brandColor,
        ),
      );

      // Suggestion if one category is dominant // No tr needed for logic
      if (percentage > 40) {
        businessInsights.add(
          InsightData(
            title: 'analytics_suggestion_diversify_spending'.tr,
            description:
                '${'analytics_suggestion_diversify_spending_desc'.tr} "${topExpenseCategory.key}". ${'analytics_suggestion_diversify_spending_suggestion'.tr}',
            icon: Icons.lightbulb_outline,
            color: Colors.orange,
          ),
        );
      }
    }
    // No tr needed for logic
    // 3. Transaction Frequency Analysis
    if (_transactionFrequency.isNotEmpty) {
      final busiestDay = _transactionFrequency.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );
      businessInsights.add(
        InsightData(
          title: 'analytics_busiest_day'.tr,
          description:
              '${'analytics_busiest_day_desc'.tr} ${busiestDay.key}s. ${'analytics_busiest_day_suggestion'.tr}',
          icon: Icons.calendar_today,
          color: _accentColor,
        ),
      );
    }

    // 4. Average Transaction Value // No tr needed for logic
    final expenseTransactions = _transactions
        .where(
          (transaction) =>
              transaction.type == TransactionType.expense &&
              transaction.amount >= 0,
        )
        .toList();
    if (_typeFilter != TransactionType.income &&
        expenseTransactions.isNotEmpty) {
      final avgExpense =
          expenseTransactions
              .map((transaction) => transaction.amount)
              .reduce((first, second) => first + second) /
          expenseTransactions.length;

      businessInsights.add(
        InsightData(
          title: 'analytics_avg_expense_value'.tr,
          description:
              '${'analytics_avg_expense_value_desc'.tr} TSH ${_formatMoney(avgExpense)}. ${'analytics_avg_expense_value_suggestion'.tr}',
          icon: Icons.calculate_outlined,
          color: Colors.purple,
        ),
      );
    }

    final seed = _insightRotationSeed();
    final insights = <InsightData>[...businessInsights];

    if (BusinessAccessService.isOwner.value && _staffNames.isNotEmpty) {
      final staffInsights = <InsightData>[];
      final staffIncome = <String, double>{};
      final staffTransactions = <String, int>{};
      for (final transaction in _transactions) {
        if (transaction.type != TransactionType.income ||
            transaction.amount < 0 ||
            !_staffNames.containsKey(transaction.uid)) {
          continue;
        }
        staffIncome.update(
          transaction.uid,
          (amount) => amount + transaction.amount,
          ifAbsent: () => transaction.amount,
        );
        staffTransactions.update(
          transaction.uid,
          (previousCount) => previousCount + 1,
          ifAbsent: () => 1,
        );
      }
      if (staffIncome.isNotEmpty) {
        final topStaff = staffIncome.entries.reduce(
          (first, second) => first.value >= second.value ? first : second,
        );
        staffInsights.add(
          InsightData(
            title: 'analytics_staff_activity'.tr,
            description: 'analytics_staff_activity_desc'.trParams({
              'name': _staffNames[topStaff.key] ?? '—',
              'amount': _formatMoney(topStaff.value),
              'count': '${staffTransactions[topStaff.key] ?? 0}',
            }),
            icon: Icons.badge_outlined,
            color: const Color(0xFF0F766E),
          ),
        );
      }
      final staffPosSales = _posSalesByStaff.entries
          .where((entry) => _staffNames.containsKey(entry.key))
          .toList();
      if (staffPosSales.isNotEmpty) {
        final topPosStaff = staffPosSales.reduce(
          (first, second) => first.value >= second.value ? first : second,
        );
        staffInsights.add(
          InsightData(
            title: 'analytics_staff_pos_activity'.tr,
            description: 'analytics_staff_pos_activity_desc'.trParams({
              'name': _staffNames[topPosStaff.key] ?? '—',
              'amount': _formatMoney(topPosStaff.value),
              'count': '${_posSaleCountsByStaff[topPosStaff.key] ?? 0}',
            }),
            icon: Icons.storefront_outlined,
            color: const Color(0xFF0F766E),
          ),
        );
      }
      insights.addAll(staffInsights);
    }

    if (_visibleTaskCount != null && _visibleTaskCount! > 0) {
      final taskInsights = <InsightData>[];
      if ((_overdueTaskCount ?? 0) > 0) {
        taskInsights.add(
          InsightData(
            title: 'analytics_overdue_tasks'.tr,
            description: 'analytics_overdue_tasks_desc'.trParams({
              'count': '$_overdueTaskCount',
            }),
            icon: Icons.warning_amber_rounded,
            color: MjasiColors.error,
          ),
        );
      }
      if ((_taskReviewCount ?? 0) > 0) {
        taskInsights.add(
          InsightData(
            title: 'analytics_tasks_for_review'.tr,
            description: 'analytics_tasks_for_review_desc'.trParams({
              'count': '$_taskReviewCount',
            }),
            icon: Icons.fact_check_outlined,
            color: const Color(0xFF7C3AED),
          ),
        );
      }
      if ((_openTaskCount ?? 0) == 0) {
        taskInsights.add(
          InsightData(
            title: 'analytics_no_open_tasks'.tr,
            description: 'analytics_no_open_tasks_desc'.tr,
            icon: Icons.task_alt_rounded,
            color: MjasiColors.success,
          ),
        );
      } else {
        taskInsights.add(
          InsightData(
            title: 'analytics_open_tasks'.tr,
            description: 'analytics_open_tasks_desc'.trParams({
              'count': '$_openTaskCount',
            }),
            icon: Icons.pending_actions_rounded,
            color: MjasiColors.primaryBlue,
          ),
        );
      }
      insights.addAll(taskInsights);
    }

    if ((_posSaleCount ?? 0) > 0) {
      final salesDescription = StringBuffer(
        'analytics_pos_sales_desc'.trParams({
          'count': '$_posSaleCount',
          'total': _formatMoney(_posSalesTotal ?? 0),
        }),
      );
      if (_topSellingProduct != null) {
        salesDescription
          ..write(' ')
          ..write(
            'analytics_pos_top_product_desc'.trParams({
              'product': _topSellingProduct!,
              'count': '$_topSellingProductOccurrences',
            }),
          );
      }
      insights.add(
        InsightData(
          title: 'analytics_pos_sales'.tr,
          description: salesDescription.toString(),
          icon: Icons.point_of_sale_rounded,
          color: const Color(0xFF2563EB),
        ),
      );
    } else if (_posSaleCount == 0) {
      insights.add(
        InsightData(
          title: 'analytics_pos_sales'.tr,
          description: 'analytics_pos_no_sales_desc'.tr,
          icon: Icons.point_of_sale_rounded,
          color: Colors.blueGrey,
        ),
      );
    }

    final adviceMetrics = _buildAdviceMetrics();
    final adviceValues = _buildAdviceValues(adviceMetrics);
    final language = Get.locale?.languageCode == 'sw' ? 'sw' : 'en';
    for (final rule in _adviceCatalog) {
      if (!rule.enabled || !rule.matches(adviceMetrics)) continue;
      final title = rule.title[language] ?? rule.title['en'];
      final description = rule.description[language] ?? rule.description['en'];
      if (title == null || description == null) continue;
      insights.add(
        InsightData(
          title: _fillAdviceValues(title, adviceValues),
          description: _fillAdviceValues(description, adviceValues),
          icon: _adviceIcon(rule.category),
          color: _adviceColor(rule.category),
        ),
      );
    }

    if (insights.isEmpty) {
      insights.add(
        InsightData(
          title: 'analytics_not_enough_data'.tr,
          description: 'analytics_not_enough_data_desc'.tr,
          icon: Icons.add_chart,
          color: Colors.grey,
        ),
      );
    }

    insights.shuffle(math.Random(seed));
    return insights;
  }

  Map<String, double> _buildAdviceMetrics() {
    final filteredTransactions = _transactions.where((transaction) {
      if (_typeFilter != null && transaction.type != _typeFilter) return false;
      return transaction.amount >= 0 && transaction.category.trim().isNotEmpty;
    });
    var incomeCount = 0;
    var expenseCount = 0;
    for (final transaction in filteredTransactions) {
      if (transaction.type == TransactionType.income) {
        incomeCount++;
      } else {
        expenseCount++;
      }
    }

    final expenseTotalsByCategory = <String, double>{};
    if (_typeFilter != TransactionType.income) {
      for (final transaction in _transactions) {
        if (transaction.type != TransactionType.expense ||
            transaction.amount < 0 ||
            transaction.category.trim().isEmpty) {
          continue;
        }
        expenseTotalsByCategory.update(
          transaction.category,
          (amount) => amount + transaction.amount,
          ifAbsent: () => transaction.amount,
        );
      }
    }
    final largestExpenseCategory = expenseTotalsByCategory.values.fold<double>(
      0,
      (largest, amount) => math.max(largest, amount).toDouble(),
    );
    final topExpenseShare = _totalExpense > 0
        ? largestExpenseCategory / _totalExpense * 100
        : 0.0;

    final metrics = <String, double>{
      'income': _totalIncome,
      'expenses': _totalExpense,
      'net': _netFlow,
      'transactionCount': _transactionCount.toDouble(),
      'incomeTransactionCount': incomeCount.toDouble(),
      'expenseTransactionCount': expenseCount.toDouble(),
      'averageIncome': incomeCount == 0 ? 0 : _totalIncome / incomeCount,
      'averageExpense': expenseCount == 0 ? 0 : _totalExpense / expenseCount,
      'topExpenseSharePercent': topExpenseShare,
    };
    if (_visibleTaskCount != null) {
      metrics.addAll({
        'activeTasks': (_openTaskCount ?? 0).toDouble(),
        'overdueTasks': (_overdueTaskCount ?? 0).toDouble(),
        'tasksForReview': (_taskReviewCount ?? 0).toDouble(),
      });
    }
    if (_posSaleCount != null) {
      metrics.addAll({
        'posSalesCount': _posSaleCount!.toDouble(),
        'posSalesTotal': _posSalesTotal ?? 0,
      });
    }
    if (BusinessAccessService.isOwner.value) {
      metrics['staffCount'] = _staffNames.length.toDouble();
    }
    if (_comparisonAvailable && _previousIncome > 0) {
      metrics['incomeChangePercent'] = _percentChange(
        _previousIncome,
        _totalIncome,
      );
    }
    if (_comparisonAvailable && _previousExpense > 0) {
      metrics['expenseChangePercent'] = _percentChange(
        _previousExpense,
        _totalExpense,
      );
    }
    return metrics;
  }

  double _percentChange(double previous, double current) {
    if (previous == 0) return current == 0 ? 0 : 100;
    return ((current - previous) / previous) * 100;
  }

  Map<String, String> _buildAdviceValues(Map<String, double> metrics) => {
    for (final entry in metrics.entries)
      entry.key:
          entry.key.toLowerCase().contains('count') ||
              entry.key == 'activeTasks' ||
              entry.key == 'overdueTasks' ||
              entry.key == 'tasksForReview' ||
              entry.key == 'posSalesCount' ||
              entry.key == 'staffCount'
          ? entry.value.round().toString()
          : entry.key.toLowerCase().contains('percent')
          ? entry.value.toStringAsFixed(1)
          : _formatMoney(entry.value),
  };

  String _fillAdviceValues(String text, Map<String, String> values) {
    return text.replaceAllMapped(RegExp(r'\{([a-zA-Z0-9_]+)\}'), (match) {
      return values[match.group(1)] ?? match.group(0)!;
    });
  }

  IconData _adviceIcon(String category) => switch (category) {
    'tasks' => Icons.task_alt_rounded,
    'sales' => Icons.point_of_sale_rounded,
    'staff' => Icons.groups_rounded,
    'records' => Icons.receipt_long_rounded,
    'costs' => Icons.savings_outlined,
    'growth' => Icons.trending_up_rounded,
    _ => Icons.lightbulb_outline_rounded,
  };

  Color _adviceColor(String category) => switch (category) {
    'tasks' => const Color(0xFF7C3AED),
    'sales' => const Color(0xFF2563EB),
    'staff' => const Color(0xFF0F766E),
    'records' => const Color(0xFF64748B),
    'costs' => MjasiColors.warning,
    'growth' => MjasiColors.success,
    _ => _brandColor,
  };

  int _insightRotationSeed() {
    final now = DateTime.now();
    var seed = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(2000)).inDays;
    seed += DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
    ).difference(DateTime(2000)).inDays;
    final filterKey =
        '$_selectedShopNickname|$_selectedCategory|${_typeFilter?.name ?? "all"}';
    for (final codeUnit in filterKey.codeUnits) {
      seed = (seed * 31 + codeUnit) & 0x7fffffff;
    }
    return seed;
  }

  String _formatMoney(double amount) {
    return NumberFormat('#,##0.00').format(amount);
  }

  String _getDayAbbreviation(String fullDay) {
    switch (fullDay) {
      case 'Monday':
      case 'Jumatatu': // Handle both English and Swahili
        return 'Mon';
      case 'Tuesday':
      case 'Jumanne':
        return 'Tue';
      case 'Wednesday':
      case 'Jumatano':
        return 'Wed';
      case 'Thursday':
      case 'Alhamisi':
        return 'Thu';
      case 'Friday':
      case 'Ijumaa':
        return 'Fri';
      case 'Saturday':
      case 'Jumamosi':
        return 'Sat';
      case 'Sunday':
      case 'Jumapili':
        return 'Sun';
      default:
        if (fullDay.length >= 3) return fullDay.substring(0, 3);
        return fullDay;
    }
  }

  void _onGranularityChanged(Set<ChartGranularity> newSelection) {
    if (newSelection.isEmpty) return;
    setState(() {
      _chartGranularity = newSelection.first;
      _processAnalyticsData();
      // restart chart animation for visual feedback
      _chartAnimController.forward(from: 0);
    });
  }

  void _changePeriod(String period) async {
    final previousSelectedPeriod = _selectedPeriod;
    setState(() => _selectedPeriod = period);

    final now = DateTime.now();

    switch (period) {
      case 'today':
        _selectedPeriod = 'transactions_today'.tr;
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = _startDate.add(const Duration(days: 1));
        break;
      case 'Yesterday':
        _selectedPeriod = 'Yesterday'.tr;
        final yesterday = now.subtract(const Duration(days: 1));
        _startDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
        _endDate = DateTime(
          now.year,
          now.month,
          now.day,
        ); // Exclusive end date (start of today)
        break;
      case 'transactions_this_week':
        _selectedPeriod = 'transactions_this_week'.tr;
        final startOfWeek = now.subtract(
          Duration(days: now.weekday - 1),
        ); // No tr needed for logic
        _startDate = DateTime(
          startOfWeek.year,
          startOfWeek.month,
          startOfWeek.day,
        );
        _endDate = _startDate.add(const Duration(days: 7));
        break;
      case 'transactions_this_month':
        _selectedPeriod = 'transactions_this_month'.tr;
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month + 1, 1);
        break;
      // FIX: Use the translation key instead of a hardcoded string
      case 'analytics_last_3_months':
        _selectedPeriod = 'analytics_last_3_months'.tr;
        _startDate = DateTime(now.year, now.month - 2, 1);
        _endDate = DateTime(now.year, now.month + 1, 1);
        break;
      case 'analytics_this_year':
        _selectedPeriod = 'analytics_this_year'.tr;
        _startDate = DateTime(now.year, 1, 1);
        _endDate = DateTime(now.year + 1, 1, 1);
        break;
      case 'transactions_custom_range':
        _selectedPeriod = 'transactions_custom_range'.tr;
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: now.add(const Duration(days: 365)),
        );
        if (range != null) {
          _startDate = range.start;
          _endDate = range.end.add(const Duration(days: 1));
          _selectedPeriod =
              '${DateFormat.yMd().format(_startDate)} - ${DateFormat.yMd().format(range.end)}';
        } else {
          setState(() => _selectedPeriod = previousSelectedPeriod);
          return;
        }
        break;
    }

    _selectedPeriodKey = period;
    _loadAnalyticsData();
  }

  Future<void> _exportPdf() async {
    setState(() => _isPdfBusy = true);
    try {
      final activeFilters = [
        if (_selectedShopNickname.isNotEmpty) _selectedShopNickname,
        if (_selectedCategory.isNotEmpty) _selectedCategory,
      ];
      final pathOrName = await TransactionReportPdf.generateAndSave(
        transactions: _transactions.where((t) {
          if (_typeFilter == null) return true; // No tr needed for logic
          return t.type == _typeFilter;
        }).toList(),
        totalIncome: _totalIncome,
        totalExpense: _totalExpense,
        netProfit: _netFlow,
        filterTitle:
            '${'analytics_report_title'.tr}: $_selectedPeriod${activeFilters.isEmpty ? '' : ' · ${activeFilters.join(' · ')}'}',
      );
      Get.snackbar(
        'PDF saved'.tr, // No tr needed for variable
        pathOrName,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
    } catch (e) {
      Get.snackbar(
        // No tr needed for error message
        'PDF Export Error'.tr,
        '$e',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _isPdfBusy = false);
    }
  }

  void _showTransactionsForCategory(String category) {
    final categoryTransactions = _transactions
        .where(
          (t) =>
              t.category == category &&
              (_typeFilter == null || t.type == _typeFilter),
        )
        .toList();

    Get.bottomSheet(
      Container(
        height: MediaQuery.of(context).size.height * 0.6,
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${'analytics_transactions_for'.tr} "$category"', // No tr needed for variable
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: categoryTransactions.length,
                itemBuilder: (context, index) {
                  final t = categoryTransactions[index];
                  final isExpense = t.type == TransactionType.expense;
                  return ListTile(
                    leading: Icon(
                      isExpense ? Icons.arrow_downward : Icons.arrow_upward,
                      color: isExpense ? Colors.red : Colors.green,
                    ),
                    title: Text(t.description),
                    subtitle: Text(DateFormat.yMMMd().format(t.date)),
                    trailing: Text(
                      '${isExpense ? '-' : '+'}TSH ${_formatMoney(t.amount)}',
                      style: TextStyle(
                        color: isExpense ? Colors.red : Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Get.back(),
                child: Text('close'.tr),
              ),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  // NEW: A bottom sheet to show the list of categories grouped under "Other".
  void _showTransactionsForOtherCategories(
    List<MapEntry<String, double>> otherCategories,
  ) {
    Get.bottomSheet(
      Container(
        height: MediaQuery.of(context).size.height * 0.6,
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${'details'.tr} for "${'Other'.tr}"',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: otherCategories.length,
                itemBuilder: (context, index) {
                  final entry = otherCategories[index];
                  return ListTile(
                    title: Text(entry.key),
                    trailing: Text(
                      'TSH ${_formatMoney(entry.value)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      // Close the "Other" sheet and open the specific category sheet.
                      Get.back();
                      _showTransactionsForCategory(entry.key);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Get.back(),
                child: Text('close'.tr),
              ),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }
}

class TimeData {
  final String label;
  double income;
  double expense;
  final DateTime date;

  TimeData({
    required this.label,
    required this.income,
    required this.expense,
    required this.date,
  });
}

class _ShopAnalyticsTotals {
  double income = 0;
  double expense = 0;
}

class InsightData {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  InsightData({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}

class _AdviceRule {
  const _AdviceRule({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.conditions,
    this.enabled = true,
  });

  final String id;
  final String category;
  final Map<String, String> title;
  final Map<String, String> description;
  final List<_AdviceCondition> conditions;
  final bool enabled;

  factory _AdviceRule.fromJson(Map<String, dynamic> json) {
    final conditions = json['when'];
    if (conditions is! List || conditions.isEmpty) {
      throw FormatException(
        'Advice "${json['id']}" needs at least one condition.',
      );
    }
    return _AdviceRule(
      id: _requiredString(json, 'id'),
      category: _requiredString(json, 'category'),
      title: _localizedStrings(json, 'title'),
      description: _localizedStrings(json, 'description'),
      enabled: json['enabled'] != false,
      conditions: conditions.map((condition) {
        if (condition is! Map) {
          throw FormatException(
            'Advice "${json['id']}" has an invalid condition.',
          );
        }
        return _AdviceCondition.fromJson(Map<String, dynamic>.from(condition));
      }).toList(),
    );
  }

  bool matches(Map<String, double> metrics) =>
      conditions.every((condition) => condition.matches(metrics));
}

class _AdviceCondition {
  const _AdviceCondition({
    required this.metric,
    required this.operator,
    required this.value,
  });

  final String metric;
  final String operator;
  final double value;

  factory _AdviceCondition.fromJson(Map<String, dynamic> json) {
    final metric = json['metric'];
    final operator = json['operator'];
    final value = json['value'];
    if (metric is! String ||
        operator is! String ||
        value is! num ||
        !const {'gt', 'gte', 'lt', 'lte', 'eq'}.contains(operator)) {
      throw const FormatException(
        'Advice condition has invalid metric, operator or value.',
      );
    }
    return _AdviceCondition(
      metric: metric,
      operator: operator,
      value: value.toDouble(),
    );
  }

  bool matches(Map<String, double> metrics) {
    final metricValue = metrics[metric];
    if (metricValue == null) return false;
    return switch (operator) {
      'gt' => metricValue > value,
      'gte' => metricValue >= value,
      'lt' => metricValue < value,
      'lte' => metricValue <= value,
      'eq' => metricValue == value,
      _ => false,
    };
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Advice entry is missing "$key".');
  }
  return value;
}

Map<String, String> _localizedStrings(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map) {
    throw FormatException(
      'Advice "${json['id']}" needs localized "$key" text.',
    );
  }
  final localized = {
    for (final entry in value.entries)
      entry.key.toString(): entry.value.toString(),
  };
  if (!localized.containsKey('en') || !localized.containsKey('sw')) {
    throw FormatException(
      'Advice "${json['id']}" needs both English and Swahili "$key" text.',
    );
  }
  return localized;
}

class ChartData {
  final String x;
  final double y;

  ChartData(this.x, this.y);
}
