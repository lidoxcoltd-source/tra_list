import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'transaction_model.dart';
import 'transaction_service.dart';
import 'package:tra_list/services/profile_service.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage>
    with TickerProviderStateMixin {
  List<TransactionModel> _transactions = [];
  bool _isLoading = true;
  String _selectedPeriod = 'This Month';
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  
  // Dynamic colors
  Color _brandColor = const Color(0xFF1976D2);
  Color _accentColor = const Color(0xFFFFA000);
  
  // Animation controllers
  late AnimationController _chartAnimController;
  late AnimationController _cardAnimController;
  
  // Analytics data
  Map<String, double> _categoryData = {};
  List<MonthlyData> _monthlyData = [];
  Map<String, int> _transactionFrequency = {};
  double _averageTransaction = 0;
  double _totalIncome = 0;
  double _totalExpense = 0;
  double _netFlow = 0;
  int _transactionCount = 0;
  
  @override
  void initState() {
    super.initState();
    _chartAnimController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _cardAnimController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _initializeDates();
    _loadProfileColors();
    _loadAnalyticsData();
  }
  
  void _initializeDates() {
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month + 1, 1);
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
      final snapshot = await TransactionService.getTransactions(
        startDate: _startDate,
        endDate: _endDate,
        limit: 1000, // Get more data for analytics
      );
      
      _transactions = snapshot.docs.map((doc) => doc.data()).toList();
      _processAnalyticsData();
      
      // Start animations
      _cardAnimController.forward();
      _chartAnimController.forward();
      
    } catch (e) {
      Get.snackbar('Error', 'Failed to load analytics data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  void _processAnalyticsData() {
    if (_transactions.isEmpty) return;
    
    // Reset data
    _categoryData.clear();
    _monthlyData.clear();
    _transactionFrequency.clear();
    
    _totalIncome = 0;
    _totalExpense = 0;
    _transactionCount = _transactions.length;
    
    // Process transactions
    final monthlyMap = <String, MonthlyData>{};
    
    for (final transaction in _transactions) {
      // Calculate totals
      if (transaction.type == TransactionType.income) {
        _totalIncome += transaction.amount;
      } else {
        _totalExpense += transaction.amount;
      }
      
      // Category analysis
      _categoryData[transaction.category] = 
          (_categoryData[transaction.category] ?? 0) + transaction.amount;
      
      // Monthly analysis
      final monthKey = DateFormat('MMM yyyy').format(transaction.date);
      if (!monthlyMap.containsKey(monthKey)) {
        monthlyMap[monthKey] = MonthlyData(
          month: monthKey,
          income: 0,
          expense: 0,
          date: DateTime(transaction.date.year, transaction.date.month),
        );
      }
      
      if (transaction.type == TransactionType.income) {
        monthlyMap[monthKey]!.income += transaction.amount;
      } else {
        monthlyMap[monthKey]!.expense += transaction.amount;
      }
      
      // Transaction frequency by day of week
      final dayName = DateFormat('EEEE').format(transaction.date);
      _transactionFrequency[dayName] = 
          (_transactionFrequency[dayName] ?? 0) + 1;
    }
    
    _netFlow = _totalIncome - _totalExpense;
    _averageTransaction = _transactionCount > 0 
        ? (_totalIncome + _totalExpense) / _transactionCount 
        : 0;
    
    // Sort monthly data
    _monthlyData = monthlyMap.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
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
        title: Text('Analytics & Insights'),
        backgroundColor: _brandColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            onSelected: _changePeriod,
            itemBuilder: (context) => [
              PopupMenuItem(value: 'This Week', child: Text('This Week')),
              PopupMenuItem(value: 'This Month', child: Text('This Month')),
              PopupMenuItem(value: 'Last 3 Months', child: Text('Last 3 Months')),
              PopupMenuItem(value: 'This Year', child: Text('This Year')),
              PopupMenuItem(value: 'Custom', child: Text('Custom Range')),
            ],
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_selectedPeriod, style: TextStyle(fontSize: 14)),
                  Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAnalyticsData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                    const SizedBox(height: 100), // Bottom padding
                  ],
                ),
              ),
            ),
    );
  }
  
  Widget _buildOverviewCards() {
    return AnimatedBuilder(
      animation: _cardAnimController,
      builder: (context, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.3),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _cardAnimController,
          curve: Curves.easeOutCubic,
        )),
        child: FadeTransition(
          opacity: _cardAnimController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Financial Overview',
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
                      'Total Income',
                      'TSH ${_formatMoney(_totalIncome)}',
                      Icons.trending_up,
                      Colors.green,
                      _totalIncome,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricCard(
                      'Total Expense',
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
                      'Net Flow',
                      '${_netFlow >= 0 ? '+' : '-'}TSH ${_formatMoney(_netFlow.abs())}',
                      _netFlow >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                      _netFlow >= 0 ? Colors.green : Colors.orange,
                      _netFlow.abs(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricCard(
                      'Transactions',
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
  
  Widget _buildMetricCard(String title, String value, IconData icon, Color color, double amount) {
    return Container(
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
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCashFlowChart() {
    if (_monthlyData.isEmpty) {
      return _buildEmptyChart('No data available for cash flow analysis');
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
                'Cash Flow Trend',
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
                    majorGridLines: const MajorGridLines(width: 0),
                    labelStyle: TextStyle(color: Colors.grey[600], fontSize: 10),
                  ),
                  primaryYAxis: NumericAxis(
                    numberFormat: NumberFormat.compact(),
                    majorGridLines: MajorGridLines(
                      width: 0.5,
                      color: Colors.grey[300]!,
                    ),
                    labelStyle: TextStyle(color: Colors.grey[600], fontSize: 10),
                  ),
                  plotAreaBorderWidth: 0,
                  legend: Legend(
                    isVisible: true,
                    position: LegendPosition.bottom,
                    overflowMode: LegendItemOverflowMode.wrap,
                  ),
                  tooltipBehavior: TooltipBehavior(
                    enable: true,
                    format: 'point.x : TSH point.y',
                    header: '',
                    canShowMarker: false,
                  ),
                  series: <ChartSeries<MonthlyData, String>>[
                    SplineAreaSeries<MonthlyData, String>(
                      dataSource: _monthlyData,
                      xValueMapper: (MonthlyData data, _) => data.month.substring(0, 3),
                      yValueMapper: (MonthlyData data, _) => data.income,
                      name: 'Income',
                      color: Colors.green.withOpacity(0.7),
                      borderColor: Colors.green,
                      borderWidth: 2,
                      gradient: LinearGradient(
                        colors: [
                          Colors.green.withOpacity(0.1),
                          Colors.green.withOpacity(0.3),
                        ],
                        stops: const [0.0, 1.0],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                    SplineAreaSeries<MonthlyData, String>(
                      dataSource: _monthlyData,
                      xValueMapper: (MonthlyData data, _) => data.month.substring(0, 3),
                      yValueMapper: (MonthlyData data, _) => data.expense,
                      name: 'Expense',
                      color: Colors.red.withOpacity(0.7),
                      borderColor: Colors.red,
                      borderWidth: 2,
                      gradient: LinearGradient(
                        colors: [
                          Colors.red.withOpacity(0.1),
                          Colors.red.withOpacity(0.3),
                        ],
                        stops: const [0.0, 1.0],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }
  
  Widget _buildCategoryPieChart() {
    if (_categoryData.isEmpty) {
      return _buildEmptyChart('No category data available');
    }
    
    // Get top 5 categories
    final sortedCategories = _categoryData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCategories = sortedCategories.take(5).toList();
    
    return AnimatedBuilder(
      animation: _chartAnimController,
      builder: (context, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.3),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _chartAnimController,
          curve: Interval(0.2, 1.0, curve: Curves.easeOutCubic),
        )),
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
                'Category Distribution',
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
                  legend: Legend(
                    isVisible: true,
                    position: LegendPosition.right,
                    overflowMode: LegendItemOverflowMode.wrap,
                    textStyle: TextStyle(fontSize: 11),
                  ),
                  tooltipBehavior: TooltipBehavior(
                    enable: true,
                    format: 'point.x : TSH point.y (point.percentage%)',
                  ),
                  series: <CircularSeries>[
                    DoughnutSeries<MapEntry<String, double>, String>(
                      dataSource: topCategories,
                      xValueMapper: (MapEntry<String, double> data, _) => data.key,
                      yValueMapper: (MapEntry<String, double> data, _) => data.value,
                      dataLabelMapper: (MapEntry<String, double> data, _) => 
                          '${((data.value / (_totalIncome + _totalExpense)) * 100).toStringAsFixed(1)}%',
                      dataLabelSettings: const DataLabelSettings(
                        isVisible: true,
                        labelPosition: ChartDataLabelPosition.outside,
                        textStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      innerRadius: '50%',
                      pointColorMapper: (MapEntry<String, double> data, index) {
                        final colors = [
                          _brandColor,
                          _accentColor,
                          Colors.green,
                          Colors.red,
                          Colors.purple,
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
      );
  }
  
  Widget _buildCategoryAnalysis() {
    if (_categoryData.isEmpty) {
      return _buildEmptyChart('No category data available');
    }
    
    final sortedCategories = _categoryData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return AnimatedBuilder(
      animation: _chartAnimController,
      builder: (context, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.3),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _chartAnimController,
          curve: Interval(0.3, 1.0, curve: Curves.easeOutCubic),
        )),
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
                'Top Categories',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 20),
              ...sortedCategories.take(5).map((entry) {
                final percentage = (entry.value / (_totalIncome + _totalExpense)) * 100;
                return _buildCategoryItem(entry.key, entry.value, percentage);
              }),
            ],
          ),
        ),
      );
  }
  
  Widget _buildCategoryItem(String category, double amount, double percentage) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  category,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                ),
              ),
              Text(
                'TSH ${_formatMoney(amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${percentage.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: percentage / 100,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation(_brandColor),
            minHeight: 4,
          ),
        ],
      ),
    );
  }
  
  Widget _buildTransactionFrequency() {
    if (_transactionFrequency.isEmpty) {
      return _buildEmptyChart('No frequency data available');
    }
    
    // Convert to chart data
    const dayOrder = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final chartData = dayOrder.map((day) {
      return ChartData(_getDayAbbreviation(day), _transactionFrequency[day]?.toDouble() ?? 0);
    }).toList();
    
    return AnimatedBuilder(
      animation: _chartAnimController,
      builder: (context, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.3),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _chartAnimController,
          curve: Interval(0.5, 1.0, curve: Curves.easeOutCubic),
        )),
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
                'Transaction Pattern',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 200,
                child: SfCartesianChart(
                  primaryXAxis: CategoryAxis(
                    majorGridLines: const MajorGridLines(width: 0),
                    labelStyle: TextStyle(color: Colors.grey[600], fontSize: 10),
                  ),
                  primaryYAxis: NumericAxis(
                    majorGridLines: MajorGridLines(
                      width: 0.5,
                      color: Colors.grey[300]!
                    ),
                    labelStyle: TextStyle(color: Colors.grey[600], fontSize: 10),
                  ),
                  plotAreaBorderWidth: 0,
                  tooltipBehavior: TooltipBehavior(
                    enable: true,
                    format: 'point.x : point.y transactions',
                  ),
                  series: <ChartSeries<ChartData, String>>[
                    ColumnSeries<ChartData, String>(
                      dataSource: chartData,
                      xValueMapper: (ChartData data, _) => data.x,
                      yValueMapper: (ChartData data, _) => data.y,
                      color: _brandColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(4),
                      ),
                      dataLabelSettings: const DataLabelSettings(
                        isVisible: true,
                        textStyle: TextStyle(fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }
  
  Widget _buildInsightsCards() {
    final insights = _generateInsights();
    
    return AnimatedBuilder(
      animation: _cardAnimController,
      builder: (context, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.3),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _cardAnimController,
          curve: Interval(0.7, 1.0, curve: Curves.easeOutCubic),
        )),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI Insights',
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
      );
  }
  
  Widget _buildInsightCard(InsightData insight) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.left(color: insight.color, width: 4),
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
          Icon(insight.icon, color: insight.color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  insight.description,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
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
            Icon(Icons.analytics_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  List<InsightData> _generateInsights() {
    final insights = <InsightData>[];
    
    // Cash flow insight
    if (_netFlow > 0) {
      insights.add(InsightData(
        title: 'Positive Cash Flow',
        description: 'Great! Your income exceeds expenses by TSH ${_formatMoney(_netFlow)}',
        icon: Icons.trending_up,
        color: Colors.green,
      ));
    } else if (_netFlow < 0) {
      insights.add(InsightData(
        title: 'Negative Cash Flow',
        description: 'Consider reviewing expenses. You\'re spending TSH ${_formatMoney(_netFlow.abs())} more than earning',
        icon: Icons.trending_down,
        color: Colors.red,
      ));
    }
    
    // Category insights
    if (_categoryData.isNotEmpty) {
      final topCategory = _categoryData.entries.reduce((a, b) => a.value > b.value ? a : b);
      final percentage = (topCategory.value / (_totalIncome + _totalExpense)) * 100;
      
      insights.add(InsightData(
        title: 'Top Spending Category',
        description: '${topCategory.key} accounts for ${percentage.toStringAsFixed(1)}% of your transactions',
        icon: Icons.category,
        color: _brandColor,
      ));
    }
    
    // Transaction frequency insight
    if (_transactionFrequency.isNotEmpty) {
      final busiestDay = _transactionFrequency.entries.reduce((a, b) => a.value > b.value ? a : b);
      insights.add(InsightData(
        title: 'Most Active Day',
        description: 'You make most transactions on ${busiestDay.key}s (${busiestDay.value} transactions)',
        icon: Icons.calendar_today,
        color: _accentColor,
      ));
    }
    
    // Average transaction insight
    if (_averageTransaction > 0) {
      insights.add(InsightData(
        title: 'Average Transaction',
        description: 'Your average transaction amount is TSH ${_formatMoney(_averageTransaction)}',
        icon: Icons.calculate,
        color: Colors.blue,
      ));
    }
    
    return insights;
  }
  
  String _formatMoney(double amount) {
    return NumberFormat('#,##0.00').format(amount);
  }
  
  String _getDayAbbreviation(String fullDay) {
    switch (fullDay) {
      case 'Monday': return 'Mon';
      case 'Tuesday': return 'Tue';
      case 'Wednesday': return 'Wed';
      case 'Thursday': return 'Thu';
      case 'Friday': return 'Fri';
      case 'Saturday': return 'Sat';
      case 'Sunday': return 'Sun';
      default: return fullDay.substring(0, 3);
    }
  }
  
  void _changePeriod(String period) async {
    setState(() => _selectedPeriod = period);
    
    final now = DateTime.now();
    
    switch (period) {
      case 'This Week':
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        _startDate = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
        _endDate = _startDate.add(const Duration(days: 7));
        break;
      case 'This Month':
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month + 1, 1);
        break;
      case 'Last 3 Months':
        _startDate = DateTime(now.year, now.month - 2, 1);
        _endDate = DateTime(now.year, now.month + 1, 1);
        break;
      case 'This Year':
        _startDate = DateTime(now.year, 1, 1);
        _endDate = DateTime(now.year + 1, 1, 1);
        break;
      case 'Custom':
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: now.add(const Duration(days: 365)),
        );
        if (range != null) {
          _startDate = range.start;
          _endDate = range.end.add(const Duration(days: 1));
        } else {
          return;
        }
        break;
    }
    
    _loadAnalyticsData();
  }
}

// Data models
class MonthlyData {
  final String month;
  final double income;
  final double expense;
  final DateTime date;
  
  MonthlyData({
    required this.month,
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
