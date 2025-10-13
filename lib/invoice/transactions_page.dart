import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/invoice/transaction_report_pdf.dart';
import 'package:tra_list/invoice/transaction_excel_export.dart'; // Add this import
import 'package:tra_list/services/profile_service.dart';
import 'add_transaction_page.dart';
import 'transaction_model.dart';
import 'transaction_service.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'analytics_page.dart';

enum FilterPeriod { all, today, week, month, custom, singleDay }

// NEW: Enum to manage the summary card filter state.
enum SummaryFilter { all, income, expense }

// NEW: Enum for advanced sorting options.
enum SortOption { dateDesc, dateAsc, amountDesc, amountAsc }

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
  String _filterTitle = 'transactions_today'.tr;

  // Pagination state
  // This holds all transactions fetched from Firestore for the current filter.
  final List<TransactionModel> _allFetchedTransactions = [];
  // This holds the transactions currently displayed (after search filtering).
  final List<TransactionModel> _transactions = [];
  DocumentSnapshot? _lastDoc;
  bool _loadingMore = false;
  bool _hasMore = true;
  final int _limit = 15;

  // Summary state
  double _currentIncome = 0;
  double _currentExpense = 0;
  double _currentNet = 0;

  // NEW: State for the summary card filter.
  SummaryFilter _summaryFilter = SummaryFilter.all;

  // NEW: State for sorting option.
  SortOption _sortOption = SortOption.dateDesc;

  bool _isPdfBusy = false;
  bool _isExcelBusy = false; // Add this line
  // _isFetching combines initial load and refresh states.
  bool _isFetching = false;
  // Removed _isRefreshing, as _isFetching serves the same purpose.

  // small animation controller for number transitions
  late final AnimationController _animController;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // NEW: Grouped transactions for the list view
  Map<DateTime, List<TransactionModel>> _groupedTransactions = {};

  // Dynamic colors from profile
  Color _brandColor = const Color(0xFF1976D2);
  Color _accentColor = const Color(0xFFFFA000);

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

    _loadProfileColors();
    _fetchFirstPage();

    _searchController.addListener(() {
      _setSearchQuery(_searchController.text);
    });
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

  @override
  void dispose() {
    _animController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchFirstPage() async {
    if (_isFetching) return;
    setState(() {
      _isFetching = true;
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
        'error'.tr,
        'Failed to fetch transactions: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _isFetching = false);
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
        'error'.tr,
        'Failed to fetch more transactions: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _refreshNow() async {
    // small UX: briefly replay animation
    setState(() => _isFetching = true);
    _animController.forward(from: 0);
    await _fetchFirstPage();
    if (mounted) setState(() => _isFetching = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: RefreshIndicator(
        // Keep RefreshIndicator at the top level
        onRefresh: _fetchFirstPage,
        child: CustomScrollView(
          slivers: [
            _buildSliverAppBar(),
            _buildFilterChipsSliver(),
            _buildTransactionList(),
          ],
        ),
      ),
      // NEW: Replaced two FABs with a cleaner SpeedDial FAB.
      floatingActionButton: SpeedDial(
        icon: Icons.add,
        activeIcon: Icons.close,
        backgroundColor: _brandColor,
        foregroundColor: Colors.white,
        overlayColor: Colors.black,
        overlayOpacity: 0.4,
        spacing: 12,
        children: [
          SpeedDialChild(
            child: const Icon(Icons.arrow_downward, color: Colors.white),
            backgroundColor: Colors.red.shade500,
            label: 'expense'.tr,
            onTap: () async {
              final result = await Get.to(
                () => const AddTransactionPage(
                  initialType: TransactionType.expense,
                ),
              );
              if (result == true) _fetchFirstPage();
            },
          ),
          SpeedDialChild(
            child: const Icon(Icons.arrow_upward, color: Colors.white),
            backgroundColor: Colors.green.shade600,
            label: 'income'.tr,
            onTap: () async {
              final result = await Get.to(
                () => const AddTransactionPage(
                  initialType: TransactionType.income,
                ),
              );
              if (result == true) _fetchFirstPage();
            },
          ),
        ],
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
      _applyAllFilters(); // Re-apply all filters on new data
      _recalculateTotals();
      _groupTransactions(); // NEW: Group transactions after fetching/filtering
    });
  }

  void _recalculateTotals() {
    final totalIncome = _transactions
        .where(
          (t) => t.type == TransactionType.income,
        ) // This should be based on _allFetchedTransactions
        .fold<double>(0, (sum, t) => sum + t.amount);

    final totalExpense = _transactions
        .where(
          (t) => t.type == TransactionType.expense,
        ) // This should be based on _allFetchedTransactions
        .fold<double>(0, (sum, t) => sum + t.amount);

    setState(() {
      _currentIncome = totalIncome;
      _currentExpense = totalExpense;
      _currentNet = totalIncome - totalExpense;
    });
    _animController.forward(from: 0);
  }

  // NEW: Groups transactions by date for the list view.
  void _groupTransactions() {
    final grouped = <DateTime, List<TransactionModel>>{};
    for (final t in _transactions) {
      final dateKey = DateTime(t.date.year, t.date.month, t.date.day);
      if (grouped[dateKey] == null) {
        grouped[dateKey] = [];
      }
      grouped[dateKey]!.add(t);
    }
    // Sort the groups by date descending
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    _groupedTransactions = {for (var key in sortedKeys) key: grouped[key]!};
  }

  // NEW: Helper to format date group headers.
  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (date == today) return 'Today';
    if (date == yesterday) return 'Yesterday';
    return DateFormat.yMMMMd().format(date); // e.g., "October 29, 2023"
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
      selectedColor: _accentColor.withOpacity(0.3),
      backgroundColor: _brandColor.withOpacity(0.1),
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }

  Widget _buildSummaryRow() {
    final income = 'TSH ${_money(_currentIncome)}';
    final expense = 'TSH ${_money(_currentExpense)}';
    final net = 'TSH ${_money(_currentNet.abs())}';

    return LayoutBuilder(
      builder: (context, constraints) {
        // Use a Column layout on narrow screens
        final bool useVerticalLayout = constraints.maxWidth < 450;

        final incomeCard = _SummaryCard(
          title: 'income'.tr,
          value: income,
          accent: Colors.green,
          isSelected: _summaryFilter == SummaryFilter.income,
          onTap: () {
            setState(() {
              _summaryFilter = _summaryFilter == SummaryFilter.income
                  ? SummaryFilter.all
                  : SummaryFilter.income;
            });
            _applyAllFilters();
          },
        );

        final expenseCard = _SummaryCard(
          title: 'expenses'.tr,
          value: expense,
          accent: Colors.red,
          isSelected: _summaryFilter == SummaryFilter.expense,
          onTap: () {
            setState(() {
              _summaryFilter = _summaryFilter == SummaryFilter.expense
                  ? SummaryFilter.all
                  : SummaryFilter.expense;
            });
            _applyAllFilters();
          },
        );

        final netCard = _SummaryCard(
          title: 'net'.tr,
          value: (_currentNet >= 0 ? '' : '-') + net,
          accent: _currentNet >= 0 ? Colors.green : Colors.orange,
          currentNet: _currentNet,
          isSelected: _summaryFilter == SummaryFilter.all,
          onTap: () {
            setState(() => _summaryFilter = SummaryFilter.all);
            _applyAllFilters();
          },
        );

        if (useVerticalLayout) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: incomeCard),
                  const SizedBox(width: 8),
                  Expanded(child: expenseCard),
                ],
              ),
              const SizedBox(height: 8),
              netCard,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: incomeCard),
            const SizedBox(width: 8),
            Expanded(child: expenseCard),
            const SizedBox(width: 8),
            Expanded(child: netCard),
          ],
        );
      },
    );
  }

  Widget _buildTransactionCard(TransactionModel t, int index) {
    final isExpense = t.type == TransactionType.expense;
    final accent = isExpense ? Colors.red.shade400 : Colors.green.shade400;

    // Dismissible for swipe-to-delete with undo
    return Dismissible(
      // Keep Dismissible for swipe actions
      key: ValueKey(t.id ?? index),
      direction: DismissDirection.horizontal,
      background: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: Colors.blue.shade600,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.edit, color: Colors.white),
      ),
      secondaryBackground: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Colors.red.shade600,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Edit action
          Get.to(() => AddTransactionPage(transaction: t))?.then((result) {
            // Only refresh if the transaction was actually saved.
            if (result == true) _fetchFirstPage();
          });
          return false; // Do not dismiss the item
        } else {
          // Delete action
          return await _confirmDeleteDialog(t);
        }
      },
      onDismissed: (_) async {
        await _deleteTransaction(t);
      },
      child: Card(
        // REDESIGN: Cleaner card with no border
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200, width: 0.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showActions(t),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                // REDESIGN: Avatar with icon
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
                      Text(
                        t.category,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
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
                        // Bolder amount
                        color: accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      DateFormat.jm().format(t.date), // e.g., "5:08 PM"
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
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
        title: Text('transactions_delete_title'.tr),
        content: Text('transactions_delete_confirm'.tr),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: Text('delete'.tr, style: const TextStyle(color: Colors.red)),
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
        // Also remove from the main fetched list to prevent re-appearance
        _allFetchedTransactions.removeWhere((item) => item.id == t.id);
        _transactions.removeWhere((item) => item.id == t.id);
        _recalculateTotals();
      });
      Get.snackbar(
        'success'.tr,
        'transactions_deleted_success'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'error'.tr,
        'Failed to delete transaction: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void _setFilter(FilterPeriod value) async {
    final now = DateTime.now();
    DateTime? start;
    DateTime? end;
    String title = 'transactions_all_time'.tr;

    switch (value) {
      case FilterPeriod.today:
        start = DateTime(now.year, now.month, now.day);
        end = start.add(const Duration(days: 1));
        title = 'transactions_today'.tr;
        break;
      case FilterPeriod.week:
        start = now.subtract(Duration(days: now.weekday - 1));
        start = DateTime(start.year, start.month, start.day);
        end = start.add(const Duration(days: 7));
        title = 'transactions_this_week'.tr;
        break;
      case FilterPeriod.month:
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 1);
        title = 'transactions_this_month'.tr;
        break;
      case FilterPeriod.singleDay:
        // Use already-selected single-day range if available, otherwise default to today.
        start = _startDate ?? DateTime(now.year, now.month, now.day);
        end = start.add(const Duration(days: 1));
        title = DateFormat.yMMMMd().format(start);
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

  // NEW: A dedicated method to filter for a single day when a date header is tapped.
  void _filterBySingleDay(DateTime date) {
    setState(() {
      _filter = FilterPeriod.singleDay;
      _startDate = date;
      _endDate = date.add(const Duration(days: 1));
      _filterTitle = DateFormat.yMMMMd().format(date);
    });
    _fetchFirstPage();
  }

  // NEW: A method to clear the single day filter and go back to the previous filter.
  void _clearSingleDayFilter() {
    // For simplicity, we'll default back to 'Today'.
    // A more complex implementation could store the previous filter state.
    _setFilter(FilterPeriod.today);
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
      Get.snackbar(
        'transactions_export_pdf'.tr,
        '$e',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _isPdfBusy = false);
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _isExcelBusy = true);
    try {
      final pathOrName = await TransactionExcelExport.generateAndSave(
        transactions: _transactions,
        totalIncome: _currentIncome,
        totalExpense: _currentExpense,
        netProfit: _currentNet,
        filterTitle: _filterTitle,
      );
      Get.snackbar(
        kIsWeb ? 'Excel downloaded' : 'Excel saved',
        pathOrName,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
    } catch (e) {
      Get.snackbar(
        'Export Excel',
        'Failed to export Excel: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _isExcelBusy = false);
    }
  }

  Widget _buildLoader() {
    if (!_hasMore) {
      return Padding(
        padding: EdgeInsets.all(
          16.0,
        ), // This is a const constructor, so it's fine.
        child: Center(child: Text('transactions_end_of_list'.tr)),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _loadingMore
            ? const CircularProgressIndicator()
            : ElevatedButton(
                onPressed: _fetchNextPage,
                child: Text('transactions_load_more'.tr),
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
              title: Text('edit_transaction_title'.tr),
              onTap: () {
                Get.back();
                Get.to(() => AddTransactionPage(transaction: t))?.then((
                  result,
                ) {
                  if (result == true) _fetchFirstPage();
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text('transactions_delete_title'.tr),
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
    // Renaming to reflect its broader role
    _applyAllFilters(searchQuery: q);
  }

  // NEW: A unified method to apply all active filters.
  void _applyAllFilters({String? searchQuery}) {
    setState(() {
      if (searchQuery != null) {
        _searchQuery = searchQuery.trim().toLowerCase();
      }

      // Sort the base list first
      _allFetchedTransactions.sort((a, b) {
        switch (_sortOption) {
          case SortOption.dateAsc:
            return a.date.compareTo(b.date);
          case SortOption.amountDesc:
            return b.amount.compareTo(a.amount);
          case SortOption.amountAsc:
            return a.amount.compareTo(b.amount);
          case SortOption.dateDesc:
          default:
            return b.date.compareTo(a.date);
        }
      });

      // Start with all transactions for the current period
      Iterable<TransactionModel> filtered = _allFetchedTransactions;

      // Apply summary filter (income/expense)
      if (_summaryFilter == SummaryFilter.income) {
        filtered = filtered.where((t) => t.type == TransactionType.income);
      } else if (_summaryFilter == SummaryFilter.expense) {
        filtered = filtered.where((t) => t.type == TransactionType.expense);
      }

      // Apply search query
      if (_searchQuery.isEmpty) {
        _transactions.assignAll(filtered);
      } else {
        _transactions.assignAll(
          filtered.where((t) {
            return t.description.toLowerCase().contains(_searchQuery) ||
                t.category.toLowerCase().contains(_searchQuery);
          }),
        );
      }
      _groupTransactions(); // Re-group after filtering
    });
  }

  Widget _buildSliverAppBar() {
    // Make the expanded height adaptive to the screen size.
    final screenWidth = MediaQuery.of(context).size.width;
    final isVerticalSummary = screenWidth < 450;

    // Calculate height based on content.
    // Card height is roughly 100px (16*2 padding + content).
    // Title + padding + summary row(s).
    final summaryHeight = isVerticalSummary
        ? 100.0 +
              8.0 +
              100.0 // Two rows of cards + spacing
        : 100.0; // Single row of cards
    final topContentHeight =
        14.0 + 12.0 + summaryHeight; // Title + spacing + summary
    final totalPadding =
        MediaQuery.of(context).padding.top +
        kToolbarHeight +
        8.0; // Top and bottom padding
    final adaptiveHeight = totalPadding + topContentHeight;

    return SliverAppBar(
      pinned: true,
      floating: true,
      snap: true,
      expandedHeight: adaptiveHeight,
      elevation: 1,
      backgroundColor: _brandColor,
      foregroundColor: Colors.white,
      title: _isSearching
          // NEW: Animated search bar transition
          ? Hero(
              tag: 'search_field',
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '${'search'.tr}...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                  border: InputBorder.none,
                ),
              ),
            )
          : Text('transactions_title'.tr),
      actions: [
        // Show a compact clear action in the toolbar when single-day filter is active
        if (_filter == FilterPeriod.singleDay && !_isSearching)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: TextButton.icon(
              onPressed: _clearSingleDayFilter,
              icon: const Icon(Icons.close, color: Colors.white, size: 18),
              label: Text('Clear', style: const TextStyle(color: Colors.white)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        IconButton(
          tooltip: 'search'.tr,
          onPressed: () {
            setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _searchController.clear();
              }
            });
          },
          icon: Hero(
            tag: 'search_icon',
            child: Icon(_isSearching ? Icons.close : Icons.search),
          ),
        ),
        if (!_isSearching)
          PopupMenuButton<SortOption>(
            tooltip: 'Sort by',
            icon: const Icon(Icons.sort),
            onSelected: (newSortOption) {
              if (_sortOption != newSortOption) {
                setState(() {
                  _sortOption = newSortOption;
                });
                _applyAllFilters(); // Re-sort and re-group the list
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                enabled: false,
                child: Text(
                  'Sort by',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              CheckedPopupMenuItem(
                value: SortOption.dateDesc,
                checked: _sortOption == SortOption.dateDesc,
                child: const Text('Date (Newest First)'),
              ),
              CheckedPopupMenuItem(
                value: SortOption.dateAsc,
                checked: _sortOption == SortOption.dateAsc,
                child: const Text('Date (Oldest First)'),
              ),
              CheckedPopupMenuItem(
                value: SortOption.amountDesc,
                checked: _sortOption == SortOption.amountDesc,
                child: const Text('Amount (Highest First)'),
              ),
              CheckedPopupMenuItem(
                value: SortOption.amountAsc,
                checked: _sortOption == SortOption.amountAsc,
                child: const Text('Amount (Lowest First)'),
              ),
            ],
          ),
        if (!_isSearching)
          IconButton(
            tooltip: 'transactions_export_pdf'.tr,
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
        if (!_isSearching)
          IconButton(
            tooltip: 'Export as Excel',
            onPressed: _transactions.isEmpty || _isExcelBusy
                ? null
                : _exportExcel,
            icon: _isExcelBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.table_chart_outlined),
          ),
        if (!_isSearching)
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'refresh') _refreshNow();
              if (v == 'clear_filters') _setFilter(FilterPeriod.all);
              if (v == 'export_excel') _exportExcel();
              if (v == 'export_pdf') _exportPdf();
              if (v == 'analytics') {
                Get.to(() => const AnalyticsPage());
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'refresh', child: Text('refresh'.tr)),
              PopupMenuItem(
                value: 'clear_filters',
                child: Text('transactions_clear_filters'.tr),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'export_pdf',
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf_outlined, size: 20),
                    const SizedBox(width: 8),
                    const Text('Export PDF'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'export_excel',
                child: Row(
                  children: [
                    const Icon(Icons.table_chart_outlined, size: 20),
                    const SizedBox(width: 8),
                    const Text('Export Excel'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'analytics',
                child: Row(
                  children: [
                    const Icon(Icons.analytics_outlined, size: 20),
                    const SizedBox(width: 8),
                    const Text('Analytics'),
                  ],
                ),
              ),
            ],
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_brandColor, _accentColor.withOpacity(0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: SafeArea(
                child: Padding(
                  // Use MediaQuery to get status bar height + toolbar height for accurate top padding
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + kToolbarHeight,
                    left: 16,
                    right: 16,
                    bottom: 8, // Add some bottom padding
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _filterTitle,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildSummaryRow(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // NEW: Show a "Clear Filter" button when a single day is selected.
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChipsSliver() {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _SliverFilterChipsDelegate(
        minHeight: 70,
        maxHeight: 100, // Adjusted for a single row of chips
        child: Container(
          color: _brandColor, // Match app bar color
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            alignment: WrapAlignment.start,
            children: [
              _buildFilterChip(FilterPeriod.all, 'transactions_all_time'.tr),
              _buildFilterChip(FilterPeriod.today, 'transactions_today'.tr),
              _buildFilterChip(FilterPeriod.week, 'transactions_this_week'.tr),
              _buildFilterChip(
                FilterPeriod.month,
                'transactions_this_month'.tr,
              ),
              ActionChip(
                avatar: const Icon(Icons.calendar_today, size: 16),
                label: Text('transactions_custom_range'.tr),
                onPressed: () => _setFilter(FilterPeriod.custom),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionList() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        120,
      ), // More bottom padding for FAB
      sliver: _isFetching && _transactions.isEmpty
          ? const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          : _transactions.isEmpty
          ? SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 60,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _searchQuery.isNotEmpty
                          ? '${'transactions_no_transactions'.tr} for "$_searchQuery"'
                          : 'transactions_no_transactions'.tr,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            )
          // NEW: Use SliverMainAxisGroup to group items by date
          : SliverMainAxisGroup(
              slivers: _groupedTransactions.entries.map((entry) {
                final date = entry.key;
                final transactionsInGroup = entry.value;
                return _TransactionGroup(
                  onHeaderTap: () => _filterBySingleDay(date),
                  header: _formatDateHeader(date),
                  children: transactionsInGroup
                      .map(
                        (t) => _buildTransactionCard(
                          t,
                          _allFetchedTransactions.indexOf(t),
                        ),
                      )
                      .toList(),
                );
              }).toList(),
            ),
    );
  }
}

// NEW: A custom Sliver widget to group a header and a list of children.
class _TransactionGroup extends StatelessWidget {
  final String header;
  final List<Widget> children;
  final VoidCallback onHeaderTap;

  const _TransactionGroup({
    required this.header,
    required this.children,
    required this.onHeaderTap,
  });

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverPersistentHeader(
          pinned: false, // Keep headers from sticking
          delegate: _SliverHeaderDelegate(
            child: InkWell(
              onTap: onHeaderTap,
              child: Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 8),
                child: Text(
                  header,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => children[index],
            childCount: children.length,
          ),
        ),
      ],
    );
  }
}

/// A delegate for creating a persistent header for the filter chips.
class _SliverFilterChipsDelegate extends SliverPersistentHeaderDelegate {
  _SliverFilterChipsDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });

  final double minHeight;
  final double maxHeight;
  final Widget child;

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => (minHeight > maxHeight) ? minHeight : maxHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(_SliverFilterChipsDelegate oldDelegate) {
    return maxHeight != oldDelegate.maxHeight ||
        minHeight != oldDelegate.minHeight ||
        child != oldDelegate.child;
  }
}

// NEW: A simple delegate for the date group headers.
class _SliverHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _SliverHeaderDelegate({required this.child});

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  double get maxExtent => 50;

  @override
  double get minExtent => 50;

  @override
  bool shouldRebuild(covariant _SliverHeaderDelegate oldDelegate) {
    return child != oldDelegate.child;
  }
}

/// REDESIGN: The summary cards at the top of the page.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.accent,
    required this.isSelected,
    required this.onTap,
    this.currentNet = 0,
  });

  final String title;
  final String value;
  final Color accent;
  final bool isSelected;
  final VoidCallback onTap;
  final double currentNet;

  @override
  Widget build(BuildContext context) {
    final bool isNetCard = title == 'net'.tr;

    final Widget cardContent;

    if (isNetCard) {
      // Special styling for the "Net" card
      cardContent = Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: currentNet >= 0
              ? const LinearGradient(
                  colors: [Color(0xFF66BB6A), Color(0xFF388E3C)],
                )
              : const LinearGradient(
                  colors: [Color(0xFFFFB74D), Color(0xFFFF8A65)],
                ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: _buildCardContent(
          title: title,
          value: value,
          iconBgColor: Colors.white.withOpacity(0.15),
          iconFgColor: Colors.white,
          valueColor: Colors.white,
        ),
      );
    } else {
      // Standard styling for Income/Expense cards
      cardContent = Container(
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
        child: _buildCardContent(
          title: title,
          value: value,
          iconBgColor: accent.withOpacity(0.12),
          iconFgColor: accent,
          valueColor: Colors.blueGrey.shade800,
        ),
      );
    }

    // Wrap the content with InkWell for tap effects and AnimatedOpacity for selection feedback.
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isSelected ? 1.0 : 0.65,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: cardContent,
        ),
      ),
    );
  }

  Widget _buildCardContent({
    required String title,
    required String value,
    required Color iconBgColor,
    required Color iconFgColor,
    required Color valueColor,
  }) {
    final bool isNetCard = title == 'net'.tr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: isNetCard ? Colors.white70 : Colors.blueGrey.shade400,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isNetCard
                    ? (currentNet >= 0
                          ? Icons.trending_up
                          : Icons.trending_down)
                    : (title == 'income'.tr
                          ? Icons.account_balance_wallet_outlined
                          : Icons.payment_outlined),
                size: 18,
                color: iconFgColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: valueColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
