import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'add_transaction_page.dart';
import 'transaction_excel_export.dart';
import 'transaction_model.dart';
import 'transaction_report_pdf.dart';
import 'transaction_service.dart';
import 'category_service.dart';
import 'package:tra_list/services/profile_service.dart';
import 'package:tra_list/services/business_access_service.dart';

enum FilterPeriod { all, today, yesterday, week, month, custom, singleDay }

enum SummaryFilter { all, income, expense }

enum SortOption { dateDesc, dateAsc, amountDesc, amountAsc }

class TransactionsController extends GetxController {
  // Filter and Date State
  final Rx<FilterPeriod> filter = FilterPeriod.today.obs;
  final Rx<DateTime?> startDate = Rx<DateTime?>(null);
  final Rx<DateTime?> endDate = Rx<DateTime?>(null);
  final RxString filterTitle = 'transactions_today'.tr.obs;

  // Pagination State
  final RxList<TransactionModel> allFetchedTransactions =
      <TransactionModel>[].obs;
  final RxList<TransactionModel> transactions = <TransactionModel>[].obs;
  DocumentSnapshot? lastDoc;
  final RxBool loadingMore = false.obs;
  final RxBool hasMore = true.obs;
  final int _limit = 15;

  // Summary State
  final RxDouble currentIncome = 0.0.obs;
  final RxDouble currentExpense = 0.0.obs;
  final RxDouble currentNet = 0.0.obs;

  // UI State
  final Rx<SummaryFilter> summaryFilter = SummaryFilter.all.obs;
  final Rx<SortOption> sortOption = SortOption.dateDesc.obs;
  final RxList<String> availableShopNames = <String>[].obs;
  final RxString selectedShopNickname = ''.obs;
  final RxList<String> availableCategories = <String>[].obs;
  final RxString selectedCategory = ''.obs;
  final RxBool isPdfBusy = false.obs;
  final RxBool isExcelBusy = false.obs;
  final RxBool isFetching = false.obs;
  final RxBool isSearching = false.obs;

  // Desktop UI State
  final RxBool showAddForm = false.obs;
  final Rx<TransactionType?> formInitialType = Rx<TransactionType?>(null);
  final Rx<TransactionModel?> editingTransaction = Rx<TransactionModel?>(null);

  // Controllers
  final ScrollController scrollController = ScrollController();
  final TextEditingController searchController = TextEditingController();
  String _searchQuery = '';

  // Grouped Data for UI
  final RxMap<DateTime, List<TransactionModel>> groupedTransactions =
      <DateTime, List<TransactionModel>>{}.obs;

  // Theming
  final Rx<Color> brandColor = const Color(0xFF1976D2).obs;
  final Rx<Color> accentColor = const Color(0xFFFFA000).obs;

  @override
  void onInit() {
    super.onInit();
    final now = DateTime.now();
    startDate.value = DateTime(now.year, now.month, now.day);
    endDate.value = startDate.value!.add(const Duration(days: 1));
    if (!BusinessAccessService.isOwner.value) {
      selectedShopNickname.value = BusinessAccessService.shopNickname.value
          .trim();
    }

    loadProfileColors();
    // Fetch totals and the first page of data concurrently.
    Future.wait([
      fetchFirstPage(),
      _fetchAndSetTotals(),
      loadShopNames(),
      loadCategoryNames(),
    ]);

    scrollController.addListener(() {
      if (scrollController.position.pixels >=
          scrollController.position.maxScrollExtent - 200) {
        fetchNextPage();
      }
    });
    searchController.addListener(() {
      applyAllFilters(searchQuery: searchController.text);
    });
  }

  Future<void> loadShopNames() async {
    final names = <String>{};
    try {
      if (BusinessAccessService.isOwner.value) {
        final profile = await ProfileService.loadOrCreate();
        var shopNickname = profile['shopNickname']?.toString().trim() ?? '';
        if (shopNickname.isEmpty) {
          shopNickname = profile['name']?.toString().trim() ?? '';
        }
        if (shopNickname.isNotEmpty) names.add(shopNickname);

        final memberships = await FirebaseFirestore.instance
            .collection('employeeMemberships')
            .where('businessUid', isEqualTo: BusinessAccessService.businessId)
            .get();
        for (final membership in memberships.docs) {
          final name =
              membership.data()['shopNickname']?.toString().trim() ?? '';
          if (name.isNotEmpty) names.add(name);
        }
      } else {
        final shopNickname = BusinessAccessService.shopNickname.value.trim();
        if (shopNickname.isNotEmpty) names.add(shopNickname);
      }
      for (final transaction in allFetchedTransactions) {
        if (transaction.shopNickname.trim().isNotEmpty) {
          names.add(transaction.shopNickname.trim());
        }
      }
      availableShopNames.assignAll(names.toList()..sort());
    } catch (error, stackTrace) {
      debugPrint('Failed to load transaction shop names: $error');
      debugPrintStack(stackTrace: stackTrace);
      Get.snackbar('error'.tr, 'transactions_shops_load_error'.tr);
    }
  }

  Future<void> loadCategoryNames() async {
    final names = <String>{};
    try {
      final categories = await CategoryService.getCategoriesFromServer();
      names.addAll(
        categories.docs
            .map((category) => category.data().name.trim())
            .where((name) => name.isNotEmpty),
      );
      names.addAll(
        allFetchedTransactions
            .map((transaction) => transaction.category.trim())
            .where((name) => name.isNotEmpty),
      );
      availableCategories.assignAll(names.toList()..sort());
    } catch (error, stackTrace) {
      debugPrint('Failed to load transaction category names: $error');
      debugPrintStack(stackTrace: stackTrace);
      final transactionCategories =
          allFetchedTransactions
              .map((transaction) => transaction.category.trim())
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      availableCategories.assignAll(transactionCategories);
      Get.snackbar('error'.tr, 'transactions_categories_load_error'.tr);
    }
  }

  @override
  void onClose() {
    scrollController.dispose();
    searchController.dispose();
    super.onClose();
  }

  Future<void> loadProfileColors() async {
    try {
      final profile = await ProfileService.loadOrCreate();
      if (profile.containsKey('colors')) {
        final colors = profile['colors'] as Map<String, dynamic>;
        brandColor.value = Color(colors['brand'] as int? ?? 0xFF1976D2);
        accentColor.value = Color(colors['accent'] as int? ?? 0xFFFFA000);
      }
    } catch (e) {
      debugPrint('Failed to load profile colors: $e');
    }
  }

  void showAddTransactionForm(TransactionType type) {
    formInitialType.value = type;
    editingTransaction.value = null; // Ensure we're not editing
    showAddForm.value = true;
  }

  void editTransactionOnDesktop(TransactionModel transaction) {
    editingTransaction.value = transaction;
    showAddForm.value = true;
  }

  void hideAddTransactionForm() {
    editingTransaction.value = null;
    showAddForm.value = false;
    formInitialType.value = null;
    Get.snackbar(
      'success'.tr,
      'Transaction saved successfully'.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
    fetchFirstPage(); // Refresh list after form is closed
  }

  Future<void> fetchFirstPage() async {
    if (isFetching.value) return;
    isFetching.value = true;
    allFetchedTransactions.clear();
    transactions.clear();
    lastDoc = null;
    hasMore.value = true;

    try {
      final snap = await TransactionService.getTransactions(
        limit: _limit,
        startDate: startDate.value,
        endDate: endDate.value,
        shopNickname: selectedShopNickname.value,
        category: selectedCategory.value,
      );
      _updateStateFromSnapshot(snap, isFirstPage: true);
    } catch (e) {
      // In case of error, ensure hasMore is false to prevent infinite loops
      // if the view is not scrollable.
      hasMore.value = false;
      Get.snackbar('error'.tr, 'Failed to fetch transactions: $e');
    } finally {
      isFetching.value = false;
      // After the first fetch, check if the content is scrollable.
      // Also, fetch the totals for the current date range.
      // If not, and there's more data, fetch the next page.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchMoreIfContentNotScrollable();
      });
    }
  }

  Future<void> fetchNextPage() async {
    if (loadingMore.value || !hasMore.value || lastDoc == null) return;
    loadingMore.value = true;

    try {
      final snap = await TransactionService.getTransactions(
        limit: _limit,
        startAfter: lastDoc,
        startDate: startDate.value,
        endDate: endDate.value,
        shopNickname: selectedShopNickname.value,
        category: selectedCategory.value,
      );
      _updateStateFromSnapshot(snap, isFirstPage: false);
    } catch (e) {
      Get.snackbar('error'.tr, 'Failed to fetch more transactions: $e');
    } finally {
      loadingMore.value = false;
      // Also check after fetching the next page.
      await _fetchMoreIfContentNotScrollable();
    }
  }

  void _updateStateFromSnapshot(
    QuerySnapshot<TransactionModel> snap, {
    required bool isFirstPage,
  }) {
    if (snap.docs.isNotEmpty) {
      lastDoc = snap.docs.last;
    }
    if (snap.docs.length < _limit) {
      hasMore.value = false;
    }

    final newTransactions = snap.docs.map((d) => d.data()).toList();

    if (isFirstPage) {
      allFetchedTransactions.clear();
    }
    allFetchedTransactions.addAll(newTransactions);
    final fetchedShopNames = newTransactions
        .map((transaction) => transaction.shopNickname.trim())
        .where((shopNickname) => shopNickname.isNotEmpty)
        .toSet();
    availableShopNames.addAll(
      fetchedShopNames.where(
        (shopNickname) => !availableShopNames.contains(shopNickname),
      ),
    );
    availableShopNames.sort();
    final fetchedCategories = newTransactions
        .map((transaction) => transaction.category.trim())
        .where((category) => category.isNotEmpty)
        .toSet();
    availableCategories.addAll(
      fetchedCategories.where(
        (category) => !availableCategories.contains(category),
      ),
    );
    availableCategories.sort();
    applyAllFilters();
    _recalculateTotals();
    _groupTransactions();
  }

  /// Checks if the scrollable content is enough to fill the viewport.
  /// If not, and if more data is available, it fetches the next page.
  Future<void> _fetchMoreIfContentNotScrollable() async {
    // This function is called after a frame is rendered.
    // We need to wait for the frame to complete before checking scroll extent.
    await WidgetsBinding.instance.endOfFrame;

    // If the view is not scrollable and there's more data, fetch next page.
    if (scrollController.hasClients &&
        scrollController.position.maxScrollExtent <= 0 &&
        hasMore.value) {
      await fetchNextPage();
    }
  }

  void _recalculateTotals() {
    // This now only calculates totals for the currently *visible* (filtered) transactions.
    // The overall totals are fetched by `_fetchAndSetTotals`.
    // This method is kept for filtering purposes if needed, but the main display
    // now relies on the more accurate server-side aggregation.
  }

  Future<void> _fetchAndSetTotals() async {
    try {
      final totals = await TransactionService.getTotals(
        startDate: startDate.value,
        endDate: endDate.value,
        shopNickname: selectedShopNickname.value,
        category: selectedCategory.value,
      );
      currentIncome.value = totals['income'] ?? 0.0;
      currentExpense.value = totals['expense'] ?? 0.0;
      currentNet.value = (totals['income'] ?? 0.0) - (totals['expense'] ?? 0.0);
    } catch (e) {
      debugPrint('Failed to fetch totals: $e');
      Get.snackbar('Error', 'Could not fetch summary totals: $e');
      // Reset to zero on error to keep UI consistent.
      currentIncome.value = 0.0;
      currentExpense.value = 0.0;
      currentNet.value = 0.0;
    }
  }

  void _groupTransactions() {
    final grouped = <DateTime, List<TransactionModel>>{};
    for (final t in transactions) {
      final dateKey = DateTime(t.date.year, t.date.month, t.date.day);
      if (grouped[dateKey] == null) {
        grouped[dateKey] = [];
      }
      grouped[dateKey]!.add(t);
    }
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    groupedTransactions.value = {
      for (var key in sortedKeys) key: grouped[key]!,
    };
  }

  void applyAllFilters({String? searchQuery}) {
    if (searchQuery != null) {
      _searchQuery = searchQuery.trim().toLowerCase();
    }

    allFetchedTransactions.sort((a, b) {
      switch (sortOption.value) {
        case SortOption.dateAsc:
          return a.date.compareTo(b.date);
        case SortOption.amountDesc:
          return b.amount.compareTo(a.amount);
        case SortOption.amountAsc:
          return a.amount.compareTo(b.amount);
        case SortOption.dateDesc:
          return b.date.compareTo(a.date);
      }
    });

    Iterable<TransactionModel> filtered = allFetchedTransactions;

    if (summaryFilter.value == SummaryFilter.income) {
      filtered = filtered.where((t) => t.type == TransactionType.income);
    } else if (summaryFilter.value == SummaryFilter.expense) {
      filtered = filtered.where((t) => t.type == TransactionType.expense);
    }

    if (_searchQuery.isEmpty) {
      transactions.assignAll(filtered);
    } else {
      transactions.assignAll(
        filtered.where((t) {
          return t.description.toLowerCase().contains(_searchQuery) ||
              t.category.toLowerCase().contains(_searchQuery);
        }),
      );
    }
    _groupTransactions();
  }

  void setFilter(FilterPeriod value) async {
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
      case FilterPeriod.yesterday:
        final yesterday = now.subtract(const Duration(days: 1));
        start = DateTime(yesterday.year, yesterday.month, yesterday.day);
        end = start.add(const Duration(days: 1));
        title = 'yesterday'.tr;
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
        start = startDate.value ?? DateTime(now.year, now.month, now.day);
        end = start.add(const Duration(days: 1));
        title = DateFormat.yMMMMd().format(start);
        break;
      case FilterPeriod.custom:
        final range = await showDateRangePicker(
          context: Get.context!,
          firstDate: DateTime(2020),
          lastDate: now.add(const Duration(days: 365)),
        );
        if (range != null) {
          start = range.start;
          end = range.end.add(const Duration(days: 1));
          title =
              '${start.day}/${start.month}/${start.year} - ${range.end.day}/${range.end.month}/${range.end.year}';
        } else {
          return;
        }
        break;
      case FilterPeriod.all:
        break;
    }

    filter.value = value;
    startDate.value = start;
    endDate.value = end;
    filterTitle.value = title;
    // Fetch totals and the first page of data concurrently.
    await Future.wait([fetchFirstPage(), _fetchAndSetTotals()]);
  }

  void filterBySingleDay(DateTime date) {
    filter.value = FilterPeriod.singleDay;
    startDate.value = date;
    endDate.value = date.add(const Duration(days: 1));
    filterTitle.value = DateFormat.yMMMMd().format(date);
    Future.wait([fetchFirstPage(), _fetchAndSetTotals()]);
  }

  void clearSingleDayFilter() {
    setFilter(FilterPeriod.today);
  }

  void toggleSearch() {
    isSearching.toggle();
    if (!isSearching.value) {
      searchController.clear();
    }
  }

  void setSortOption(SortOption newSortOption) {
    if (sortOption.value != newSortOption) {
      sortOption.value = newSortOption;
      applyAllFilters();
    }
  }

  Future<void> setShopFilter(String shopNickname) async {
    if (!BusinessAccessService.isOwner.value) return;
    if (selectedShopNickname.value == shopNickname) return;
    selectedShopNickname.value = shopNickname;
    await Future.wait([fetchFirstPage(), _fetchAndSetTotals()]);
  }

  Future<void> setCategoryFilter(String category) async {
    if (selectedCategory.value == category) return;
    selectedCategory.value = category;
    await Future.wait([fetchFirstPage(), _fetchAndSetTotals()]);
  }

  void setSummaryFilter(SummaryFilter newSummaryFilter) {
    if (summaryFilter.value == newSummaryFilter) {
      summaryFilter.value = SummaryFilter.all;
    } else {
      summaryFilter.value = newSummaryFilter;
    }
    applyAllFilters();
  }

  void selectSummaryFilter(SummaryFilter newSummaryFilter) {
    summaryFilter.value = newSummaryFilter;
    applyAllFilters();
  }

  Future<void> showActions(TransactionModel t) async {
    final canEdit = BusinessAccessService.can('transactions', 'edit');
    final canDelete = BusinessAccessService.can('transactions', 'delete');
    if (!canEdit && !canDelete) return;
    await Get.bottomSheet(
      SafeArea(
        child: Wrap(
          children: [
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit),
                title: Text('edit_transaction_title'.tr),
                onTap: () async {
                  Get.back();
                  final result = await Get.to(
                    () => AddTransactionPage(transaction: t),
                  );
                  if (result == true) {
                    fetchFirstPage();
                  }
                },
              ),
            if (canDelete)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text('transactions_delete_title'.tr),
                onTap: () async {
                  Get.back();
                  final confirm = await _confirmDeleteDialog();
                  if (confirm == true) {
                    await deleteTransaction(t);
                  }
                },
              ),
          ],
        ),
      ),
      backgroundColor: Colors.white,
    );
  }

  Future<bool?> confirmDelete(TransactionModel t) async {
    final confirm = await _confirmDeleteDialog();
    if (confirm == true) {
      await deleteTransaction(t);
    }
    return confirm;
  }

  Future<void> deleteTransaction(TransactionModel t) async {
    if (!BusinessAccessService.can('transactions', 'delete')) {
      Get.snackbar('error'.tr, 'staff_no_permission'.tr);
      return;
    }
    if (t.id == null) return;

    // Store the transaction and its original index for undo
    final index = allFetchedTransactions.indexWhere((item) => item.id == t.id);
    if (index == -1) return;
    final removedTransaction = allFetchedTransactions[index];

    // Optimistic deletion from UI
    allFetchedTransactions.removeAt(index);
    applyAllFilters();
    _recalculateTotals();

    // Show snackbar with Undo action
    // Use GetSnackBar so we can react to status changes (CLOSED) instead of the
    // nonexistent `onClosed` parameter on Get.snackbar.
    bool _undoPressed = false;
    Get.showSnackbar(
      GetSnackBar(
        titleText: Text(
          'transactions_deleted_success'.tr,
          style: const TextStyle(color: Colors.white),
        ),
        messageText: Text(
          'You can undo this action.'.tr,
          style: const TextStyle(color: Colors.white),
        ),
        snackPosition: SnackPosition.BOTTOM,
        mainButton: TextButton(
          onPressed: () {
            // Undo action: re-insert the transaction and close the snackbar
            if (Get.isSnackbarOpen) Get.back();
            _undoPressed = true;
            allFetchedTransactions.insert(index, removedTransaction);
            applyAllFilters();
            _recalculateTotals();
          },
          child: Text('undo'.tr, style: const TextStyle(color: Colors.white)),
        ),
        duration: const Duration(seconds: 5),
      ),
    );
    // After the snackbar duration, if the user didn't undo, perform deletion.
    Future.delayed(const Duration(seconds: 5), () async {
      if (!_undoPressed) {
        try {
          await TransactionService.deleteTransaction(t.id!);
        } catch (e) {
          Get.snackbar('error'.tr, 'Failed to delete transaction: $e');
          // If deletion fails, refresh to get the item back
          fetchFirstPage();
        }
      }
    });
  }

  Future<bool?> _confirmDeleteDialog() async {
    return await Get.dialog<bool>(
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
  }

  Future<void> exportPdf() async {
    isPdfBusy.value = true;
    try {
      final pathOrName = await TransactionReportPdf.generateAndSave(
        transactions: transactions,
        totalIncome: currentIncome.value,
        totalExpense: currentExpense.value,
        netProfit: currentNet.value,
        filterTitle: filterTitle.value,
      );
      Get.snackbar(
        kIsWeb ? 'PDF downloaded' : 'PDF saved',
        pathOrName,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
    } catch (e) {
      Get.snackbar('transactions_export_pdf'.tr, '$e');
    } finally {
      isPdfBusy.value = false;
    }
  }

  Future<void> exportExcel() async {
    isExcelBusy.value = true;
    try {
      final pathOrName = await TransactionExcelExport.generateAndSave(
        transactions: transactions,
        totalIncome: currentIncome.value,
        totalExpense: currentExpense.value,
        netProfit: currentNet.value,
        filterTitle: filterTitle.value,
      );
      Get.snackbar(
        kIsWeb ? 'Excel downloaded' : 'Excel saved',
        pathOrName,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
    } catch (e) {
      Get.snackbar('Export Excel', 'Failed to export Excel: $e');
    } finally {
      isExcelBusy.value = false;
    }
  }

  // Static helpers for UI that don't depend on state
  static String money(num v) {
    return NumberFormat.currency(
      locale: 'en_US',
      symbol: '',
      decimalDigits: 2,
    ).format(v);
  }

  static String formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (date == today) return 'today'.tr;
    if (date == yesterday) return 'yesterday'.tr;
    return DateFormat.yMMMMd(Get.locale.toString()).format(date);
  }
}
