import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'transaction_model.dart';
import 'transaction_service.dart';
import 'package:tra_list/services/profile_service.dart';
import 'package:shimmer/shimmer.dart';
import 'package:tra_list/invoice/transaction_report_pdf.dart';
import 'package:tra_list/invoice/transaction_excel_export.dart';

enum ChartGranularity { day, week, month, year }

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage>
    with TickerProviderStateMixin {
  List<TransactionModel> _transactions = [];
  bool _isLoading = true;
  String _selectedPeriod = 'transactions_today'.tr;
  TransactionType? _typeFilter; // New: Filter for income/expense
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  // Dynamic colors
  Color _brandColor = const Color(0xFF1976D2);
  Color _accentColor = const Color(0xFFFFA000);

  // Animation controllers
  late AnimationController _chartAnimController;
  late AnimationController _cardAnimController;

  // Analytics data
  List<MapEntry<String, double>> _categoryChartData = [];
  Map<String, double> _categoryData = {};
  Map<String, int> _transactionFrequency = {};
  List<TimeData> _timeSeriesData = [];
  double _averageTransaction = 0;
  double _totalIncome = 0;
  double _totalExpense = 0;
  double _netFlow = 0;
  int _transactionCount = 0;

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
    _loadProfileColors();
    _loadAnalyticsData();
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
    setState(() => _isLoading = true);

    try {
      final snapshot =
          await TransactionService.getTransactions(
            startDate: _startDate,
            endDate: _endDate,
            limit: 1000,
          ).timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw TimeoutException('Data load timed out');
            },
          );

      _transactions = snapshot.docs.map((doc) => doc.data()).toList();
      _processAnalyticsData();

      _cardAnimController.forward();
      _chartAnimController.forward();
    } catch (e) {
      Get.snackbar(
        'Error',
        (e is TimeoutException
                ? 'Network timeout. Please check your connection.'
                : 'Failed to load analytics data: $e')
            .tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _processAnalyticsData() {
    if (_transactions.isEmpty) return;

    _categoryChartData.clear();
    _categoryData.clear();
    _transactionFrequency.clear();
    _timeSeriesData.clear();

    _totalIncome = 0;
    _totalExpense = 0;
    _transactionCount = _transactions.length;

    // Removed unused monthlyMap (MonthlyData was not defined)
    final timeSeriesMap = <String, TimeData>{};
    double totalAmount = 0;

    final filteredTransactions = _transactions.where((t) {
      if (_typeFilter == null) return true;
      return t.type == _typeFilter;
    }).toList();

    for (final transaction in filteredTransactions) {
      if (transaction.amount < 0 ||
          transaction.date == null ||
          transaction.category == null) {
        continue; // Skip invalid transactions
      }

      if (transaction.type == TransactionType.income) {
        _totalIncome += transaction.amount;
      } else {
        _totalExpense += transaction.amount;
      }

      totalAmount += transaction.amount;

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

    _netFlow = _totalIncome - _totalExpense;
    _averageTransaction = _transactionCount > 0
        ? totalAmount / _transactionCount
        : 0;

    _timeSeriesData = timeSeriesMap.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    _categoryChartData = _categoryData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _transactionCount = filteredTransactions.length;
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
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        title: Text('home_analytics'.tr),
        backgroundColor: _brandColor,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50.0),
          child: _buildTypeFilter(),
        ),
        actions: [
          if (!_isPdfBusy)
            IconButton(
              icon: const Icon(
                Icons.picture_as_pdf_outlined,
              ), // No tr needed for widgets
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
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
          PopupMenuButton<String>(
            onSelected: _changePeriod,
            itemBuilder: (context) => [
              // NEW: Added "Yesterday" option
              PopupMenuItem(value: 'Yesterday', child: Text('Yesterday'.tr)),
              // No tr needed for logic
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
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _selectedPeriod,
                    style: const TextStyle(fontSize: 14),
                  ), // No tr needed for variables
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _isLoading && _transactions.isEmpty
          ? _buildSkeletonLoader()
          : RefreshIndicator(
              onRefresh: _loadAnalyticsData,
              child: SingleChildScrollView(
                physics:
                    const AlwaysScrollableScrollPhysics(), // No tr needed for widgets
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildOverviewCards(),
                    const SizedBox(height: 24),
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
    );
  }

  Widget _buildTypeFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: _brandColor, // No tr needed for variables
      child: SegmentedButton<TransactionType?>(
        segments: [
          ButtonSegment(
            value: null, // No tr needed for logic
            label: Text('analytics_all'.tr),
            icon: const Icon(Icons.all_inclusive),
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
            // No tr needed for logic
            _typeFilter = newSelection.first;
            _processAnalyticsData(); // Re-process with the new filter
          });
        },
        style: SegmentedButton.styleFrom(
          backgroundColor: _brandColor.withOpacity(0.5),
          foregroundColor: Colors.white.withOpacity(0.7),
          selectedForegroundColor: _brandColor,
          selectedBackgroundColor: Colors.white,
        ),
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
              Text(
                'analytics_financial_overview'.tr,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      'analytics_total_income'.tr,
                      'TSH ${_formatMoney(_totalIncome)}',
                      Icons.trending_up,
                      Colors.green,
                      _totalIncome,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricCard(
                      'analytics_total_expense'.tr,
                      'TSH ${_formatMoney(_totalExpense)}',
                      Icons.trending_down,
                      Colors.red,
                      _totalExpense,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      'net'.tr,
                      '${_netFlow >= 0 ? '+' : '-'}TSH ${_formatMoney(_netFlow.abs())}',
                      _netFlow >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                      _netFlow >= 0 ? Colors.green : Colors.orange,
                      _netFlow.abs(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricCard(
                      'analytics_transactions'.tr,
                      '$_transactionCount',
                      Icons.receipt_long,
                      _brandColor,
                      _transactionCount.toDouble(),
                    ),
                  ),
                ],
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
    IconData icon, // No tr needed for widgets
    Color color,
    double amount,
  ) {
    return Semantics(
      label: '$title: $value',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // No tr needed for widgets
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const Spacer(),
                Icon(Icons.more_horiz, color: Colors.grey[400], size: 20),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                // No tr needed for variables
                color: Colors.grey[600],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  // No tr needed for variables
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ),
          ],
        ),
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
    final insights = <InsightData>[];
    // No tr needed for logic
    // 1. Cash Flow Analysis
    if (_totalIncome > 0 || _totalExpense > 0) {
      if (_netFlow > 0) {
        insights.add(
          InsightData(
            title: 'analytics_positive_cash_flow'.tr,
            description:
                '${'analytics_positive_cash_flow_desc'.tr} TSH ${_formatMoney(_netFlow)}. ${'analytics_healthy_financial_position'.tr}',
            icon: Icons.trending_up,
            color: Colors.green,
          ),
        );
      } else if (_netFlow < 0) {
        insights.add(
          InsightData(
            title: 'analytics_negative_cash_flow'.tr,
            description:
                '${'analytics_negative_cash_flow_desc'.tr} TSH ${_formatMoney(_netFlow.abs())}. ${'analytics_negative_cash_flow_suggestion'.tr}',
            icon: Icons.trending_down,
            color: Colors.red,
          ),
        );
      } else {
        insights.add(
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
    final expenseCategories = _categoryData.entries
        .where(
          (entry) => _transactions.any(
            (t) => t.category == entry.key && t.type == TransactionType.expense,
          ),
        )
        .toList();

    if (expenseCategories.isNotEmpty) {
      expenseCategories.sort((a, b) => b.value.compareTo(a.value));
      final topExpenseCategory = expenseCategories.first;
      final percentage = _totalExpense > 0
          ? (topExpenseCategory.value / _totalExpense) * 100
          : 0;

      insights.add(
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
        insights.add(
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
      insights.add(
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
    if (_averageTransaction > 0) {
      final avgExpense =
          _transactions
              .where((t) => t.type == TransactionType.expense)
              .isNotEmpty
          ? _transactions
                    .where((t) => t.type == TransactionType.expense)
                    .map((t) => t.amount)
                    .reduce((a, b) => a + b) /
                _transactions
                    .where((t) => t.type == TransactionType.expense)
                    .length
          : 0.0;

      insights.add(
        InsightData(
          title: 'analytics_avg_expense_value'.tr,
          description:
              '${'analytics_avg_expense_value_desc'.tr} TSH ${_formatMoney(avgExpense)}. ${'analytics_avg_expense_value_suggestion'.tr}',
          icon: Icons.calculate_outlined,
          color: Colors.purple,
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

    return insights;
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
    setState(() => _selectedPeriod = period);

    final now = DateTime.now();

    switch (period) {
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
          return;
        }
        break;
    }

    _loadAnalyticsData();
  }

  Future<void> _exportPdf() async {
    setState(() => _isPdfBusy = true);
    try {
      final pathOrName = await TransactionReportPdf.generateAndSave(
        transactions: _transactions.where((t) {
          if (_typeFilter == null) return true; // No tr needed for logic
          return t.type == _typeFilter;
        }).toList(),
        totalIncome: _totalIncome,
        totalExpense: _totalExpense,
        netProfit: _netFlow,
        filterTitle: '${'analytics_report_title'.tr}: $_selectedPeriod',
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

class ChartData {
  final String x;
  final double y;

  ChartData(this.x, this.y);
}
