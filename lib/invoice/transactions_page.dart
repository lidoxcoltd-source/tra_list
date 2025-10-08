import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tra_list/invoice/transaction_report_pdf.dart';
import 'add_transaction_page.dart';
import 'transaction_model.dart';
import 'transaction_service.dart';

enum FilterPeriod { all, today, week, month, custom }

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage>
    with TickerProviderStateMixin {
  FilterPeriod _filter = FilterPeriod.today;
  DateTime? _startDate;
  DateTime? _endDate;
  String _filterTitle = 'Today';

  // Pagination state
  final List<TransactionModel> _allFetchedTransactions = [];
  final List<TransactionModel> _transactions = [];
  DocumentSnapshot? _lastDoc;
  bool _loadingMore = false;
  bool _hasMore = true;
  final int _limit = 15;

  // Summary state
  double _currentIncome = 0;
  double _currentExpense = 0;
  double _currentNet = 0;

  bool _isPdfBusy = false;
  bool _isRefreshing = false;

  // small animation controller for number transitions
  late final AnimationController _animController;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  String _money(num v) {
    // Use the intl package for robust number formatting.
    return NumberFormat.currency(
      locale: 'en_US',
      symbol: '',
      decimalDigits: 2,
    ).format(v);
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = _startDate!.add(const Duration(days: 1));

    _fetchFirstPage();

    _searchController.addListener(() {
      _setSearchQuery(_searchController.text);
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchFirstPage() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      _allFetchedTransactions.clear();
      _transactions.clear();
      _lastDoc = null;
      _hasMore = true;
    });

    try {
      final snap = await TransactionService.getTransactions(
        limit: _limit,
        startDate: _startDate,
        endDate: _endDate,
      );
      _updateStateFromSnapshot(snap, isFirstPage: true);
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to fetch transactions: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _fetchNextPage() async {
    if (_loadingMore || !_hasMore || _lastDoc == null) return;
    setState(() => _loadingMore = true);

    try {
      final snap = await TransactionService.getTransactions(
        limit: _limit,
        startAfter: _lastDoc,
        startDate: _startDate,
        endDate: _endDate,
      );
      _updateStateFromSnapshot(snap, isFirstPage: false);
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to fetch more transactions: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _refreshNow() async {
    // small UX: briefly replay animation
    setState(() => _isRefreshing = true);
    _animController.forward(from: 0);
    await _fetchFirstPage();
    if (mounted) setState(() => _isRefreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: RefreshIndicator(
        onRefresh: _fetchFirstPage,
        child: CustomScrollView(
          slivers: [_buildSliverAppBar(), _buildTransactionList()],
        ),
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Get.to(() => const AddTransactionPage());
          _fetchFirstPage(); // Refresh list after adding
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Transaction'),
        backgroundColor: const Color(0xFFFFA000),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  void _updateStateFromSnapshot(
    QuerySnapshot<TransactionModel> snap, {
    required bool isFirstPage,
  }) {
    if (!mounted) return;

    if (snap.docs.isNotEmpty) {
      _lastDoc = snap.docs.last;
    }
    if (snap.docs.length < _limit) {
      _hasMore = false;
    }

    final newTransactions = snap.docs.map((d) => d.data()).toList();

    setState(() {
      if (isFirstPage) {
        _allFetchedTransactions.clear();
      }
      _allFetchedTransactions.addAll(newTransactions);
      _setSearchQuery(_searchQuery); // Re-apply search on new data
      _recalculateTotals();
    });
  }

  void _recalculateTotals() {
    final totalIncome = _transactions
        .where((t) => t.type == TransactionType.income)
        .fold<double>(0, (sum, t) => sum + t.amount);

    final totalExpense = _transactions
        .where((t) => t.type == TransactionType.expense)
        .fold<double>(0, (sum, t) => sum + t.amount);

    setState(() {
      _currentIncome = totalIncome;
      _currentExpense = totalExpense;
      _currentNet = totalIncome - totalExpense;
    });
    _animController.forward(from: 0);
  }

  Widget _buildFilterChip(FilterPeriod p, String label) {
    final selected = _filter == p;
    return ChoiceChip(
      label: Text(label),
      labelStyle: TextStyle(
        color: selected ? Colors.blue.shade800 : Colors.black87,
      ),
      selected: selected,
      onSelected: (_) => _setFilter(p),
      selectedColor: Colors.blue.shade200,
      backgroundColor: Colors.blue.shade50,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }

  Widget _buildSummaryRow() {
    // small reusable card builder
    Widget card(
      String title,
      String value,
      Color accent, {
      bool large = false,
    }) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Color(0x115A6CEA),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: large ? 14 : 12,
                  color: Colors.blueGrey.shade400,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      title == 'Income'
                          ? Icons.arrow_upward
                          : (title == 'Expenses'
                                ? Icons.arrow_downward_rounded
                                : Icons.show_chart),
                      size: 18,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 450),
                      transitionBuilder: (child, anim) =>
                          FadeTransition(opacity: anim, child: child),
                      child: Text(
                        value,
                        key: ValueKey(value),
                        style: TextStyle(
                          fontSize: large ? 20 : 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey.shade800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final income = 'TSH ${_money(_currentIncome)}';
    final expense = 'TSH ${_money(_currentExpense)}';
    final net = 'TSH ${_money(_currentNet.abs())}';

    return Row(
      children: [
        card('Income', income, Colors.green),
        const SizedBox(width: 8),
        card('Expenses', expense, Colors.red),
        const SizedBox(width: 8),
        // Net has custom styling
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: _currentNet >= 0
                  ? LinearGradient(
                      colors: [Color(0xFF66BB6A), Color(0xFF388E3C)],
                    )
                  : const LinearGradient(
                      colors: [Color(0xFFFFB74D), Color(0xFFFF8A65)],
                    ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Net',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _currentNet >= 0
                            ? Icons.trending_up
                            : Icons.trending_down,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 450),
                        transitionBuilder: (child, anim) =>
                            FadeTransition(opacity: anim, child: child),
                        child: Text(
                          (_currentNet >= 0 ? '' : '-') + net,
                          key: ValueKey(_currentNet),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionCard(TransactionModel t, int index) {
    final isExpense = t.type == TransactionType.expense;
    final accent = isExpense ? Colors.red.shade400 : Colors.green.shade400;

    // Dismissible for swipe-to-delete with undo
    return Dismissible(
      key: ValueKey(t.id ?? index),
      direction: DismissDirection.endToStart,
      background: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Colors.red.shade600,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDeleteDialog(t),
      onDismissed: (_) async {
        await _deleteTransaction(t);
      },
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showActions(t),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                // small avatar with icon
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isExpense ? Icons.trending_down : Icons.trending_up,
                    color: accent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.description,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            t.category,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('•', style: TextStyle(color: Colors.grey)),
                          const SizedBox(width: 8),
                          Text(
                            '${t.date.day}/${t.date.month}/${t.date.year}',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isExpense ? '-' : '+'}TSH ${_money(t.amount)}',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmDeleteDialog(TransactionModel t) async {
    // Ask the user to confirm and then delete
    final confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text(
          'This action is permanent. Are you sure you want to delete this transaction?',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    // If true, Dismissible will complete; false cancels
    return confirm;
  }

  Future<void> _deleteTransaction(TransactionModel t) async {
    try {
      if (t.id == null) return;
      await TransactionService.deleteTransaction(t.id!);
      setState(() {
        _allFetchedTransactions.removeWhere((item) => item.id == t.id);
        _transactions.removeWhere((item) => item.id == t.id);
        _recalculateTotals();
      });
      Get.snackbar(
        'Success',
        'Transaction deleted',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to delete transaction: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void _setFilter(FilterPeriod value) async {
    final now = DateTime.now();
    DateTime? start;
    DateTime? end;
    String title = 'All Time';

    switch (value) {
      case FilterPeriod.today:
        start = DateTime(now.year, now.month, now.day);
        end = start.add(const Duration(days: 1));
        title = 'Today';
        break;
      case FilterPeriod.week:
        start = now.subtract(Duration(days: now.weekday - 1));
        start = DateTime(start.year, start.month, start.day);
        end = start.add(const Duration(days: 7));
        title = 'This Week';
        break;
      case FilterPeriod.month:
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 1);
        title = 'This Month';
        break;
      case FilterPeriod.custom:
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: now.add(const Duration(days: 365)),
        );
        if (range != null) {
          start = range.start;
          end = range.end.add(const Duration(days: 1)); // inclusive
          title =
              '${start.day}/${start.month}/${start.year} - ${range.end.day}/${range.end.month}/${range.end.year}';
        } else {
          return; // User cancelled
        }
        break;
      case FilterPeriod.all:
        break;
    }

    setState(() {
      _filter = value;
      _startDate = start;
      _endDate = end;
      _filterTitle = title;
    });
    _fetchFirstPage();
  }

  Future<void> _exportPdf() async {
    setState(() => _isPdfBusy = true);
    try {
      final pathOrName = await TransactionReportPdf.generateAndSave(
        transactions: _transactions,
        totalIncome: _currentIncome,
        totalExpense: _currentExpense,
        netProfit: _currentNet,
        filterTitle: _filterTitle,
      );
      Get.snackbar(
        kIsWeb ? 'PDF downloaded' : 'PDF saved',
        pathOrName,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
    } catch (e) {
      Get.snackbar('Export failed', '$e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (mounted) setState(() => _isPdfBusy = false);
    }
  }

  Widget _buildLoader() {
    if (!_hasMore) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: Text('End of list')),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _loadingMore
            ? const CircularProgressIndicator()
            : ElevatedButton(
                onPressed: _fetchNextPage,
                child: const Text('Load More'),
              ),
      ),
    );
  }

  void _showActions(TransactionModel t) {
    Get.bottomSheet(
      SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit Transaction'),
              onTap: () {
                Get.back();
                Get.to(
                  () => AddTransactionPage(transaction: t),
                )?.then((_) => _fetchFirstPage());
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Transaction'),
              onTap: () async {
                Get.back(); // Close bottom sheet
                final confirm = await _confirmDeleteDialog(t);
                if (confirm == true) {
                  await _deleteTransaction(t);
                }
              },
            ),
          ],
        ),
      ),
      backgroundColor: Colors.white,
    );
  }

  void _setSearchQuery(String q) {
    setState(() {
      _searchQuery = q.trim().toLowerCase();
      if (_searchQuery.isEmpty) {
        _transactions.clear();
        _transactions.addAll(_allFetchedTransactions);
      } else {
        _transactions.clear();
        _transactions.addAll(
          _allFetchedTransactions.where((t) {
            return t.description.toLowerCase().contains(_searchQuery) ||
                t.category.toLowerCase().contains(_searchQuery);
          }),
        );
      }
    });
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      pinned: true,
      floating: true,
      snap: true,
      expandedHeight: 340,
      elevation: 2,
      backgroundColor: const Color(0xFF1976D2),
      foregroundColor: Colors.white,
      title: const Text('Income & Expense'),
      actions: [
        IconButton(
          tooltip: 'Export as PDF',
          onPressed: _transactions.isEmpty || _isPdfBusy ? null : _exportPdf,
          icon: _isPdfBusy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.picture_as_pdf_outlined),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'refresh') _refreshNow();
            if (v == 'clear_filters') _setFilter(FilterPeriod.all);
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'refresh', child: Text('Refresh')),
            PopupMenuItem(
              value: 'clear_filters',
              child: Text('Clear All Filters'),
            ),
          ],
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 60, left: 16, right: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _filterTitle,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  _buildSummaryRow(),
                ],
              ),
            ),
          ),
        ),
      ),

      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(150),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              // Search Field
              TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search by description or category...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Colors.white,
                    size: 20,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.15),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Filter Chips
              Wrap(
                spacing: 8.0, // Horizontal space between chips
                runSpacing: 4.0, // Vertical space between lines
                alignment: WrapAlignment.start,
                children: [
                  _buildFilterChip(FilterPeriod.all, 'All Time'),
                  _buildFilterChip(FilterPeriod.today, 'Today'),
                  _buildFilterChip(FilterPeriod.week, 'This Week'),
                  _buildFilterChip(FilterPeriod.month, 'This Month'),
                  ActionChip(
                    avatar: const Icon(Icons.calendar_today, size: 16),
                    label: const Text('Custom Range'),
                    onPressed: () => _setFilter(FilterPeriod.custom),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionList() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      sliver: _isRefreshing && _transactions.isEmpty
          ? const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          : _transactions.isEmpty
          ? SliverFillRemaining(
              child: Center(
                child: Text(
                  _searchQuery.isNotEmpty
                      ? 'No results for "$_searchQuery"'
                      : 'No transactions found for this period.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            )
          : SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                if (index == _transactions.length) return _buildLoader();
                return _buildTransactionCard(_transactions[index], index);
              }, childCount: _transactions.length + (_hasMore ? 1 : 0)),
            ),
    );
  }
}
