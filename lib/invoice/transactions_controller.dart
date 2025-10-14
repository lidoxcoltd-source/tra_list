import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'add_transaction_page.dart';
import 'analytics_page.dart';
import 'transaction_excel_export.dart';
import 'transaction_model.dart';
import 'transaction_report_pdf.dart';
import 'transaction_service.dart';
import 'package:tra_list/services/profile_service.dart';
import 'package:tra_list/services/offline_service.dart';

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
  final RxBool isPdfBusy = false.obs;
  final RxBool isExcelBusy = false.obs;
  final RxBool isFetching = false.obs;
  final RxBool isSearching = false.obs;

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

    loadProfileColors();
    fetchFirstPage();

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
      );
      _updateStateFromSnapshot(snap, isFirstPage: true);
    } catch (e) {
      Get.snackbar('error'.tr, 'Failed to fetch transactions: $e');
    } finally {
      isFetching.value = false;
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
      );
      _updateStateFromSnapshot(snap, isFirstPage: false);
    } catch (e) {
      Get.snackbar('error'.tr, 'Failed to fetch more transactions: $e');
    } finally {
      loadingMore.value = false;
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
    applyAllFilters();
    _recalculateTotals();
    _groupTransactions();
  }

  void _recalculateTotals() {
    final totalIncome = allFetchedTransactions
        .where((t) => t.type == TransactionType.income)
        .fold<double>(0, (sum, t) => sum + t.amount);

    final totalExpense = allFetchedTransactions
        .where((t) => t.type == TransactionType.expense)
        .fold<double>(0, (sum, t) => sum + t.amount);

    currentIncome.value = totalIncome;
    currentExpense.value = totalExpense;
    currentNet.value = totalIncome - totalExpense;
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
        default:
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
    _recalculateTotals(); // Recalculate totals based on the filtered list
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
    fetchFirstPage();
  }

  void filterBySingleDay(DateTime date) {
    filter.value = FilterPeriod.singleDay;
    startDate.value = date;
    endDate.value = date.add(const Duration(days: 1));
    filterTitle.value = DateFormat.yMMMMd().format(date);
    fetchFirstPage();
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

  void setSummaryFilter(SummaryFilter newSummaryFilter) {
    if (summaryFilter.value == newSummaryFilter) {
      summaryFilter.value = SummaryFilter.all;
    } else {
      summaryFilter.value = newSummaryFilter;
    }
    applyAllFilters();
  }

  Future<void> deleteTransaction(TransactionModel t) async {
    try {
      if (t.id == null) return;
      // Optimistic deletion from UI
      final index = allFetchedTransactions.indexWhere(
        (item) => item.id == t.id,
      );
      if (index != -1) {
        allFetchedTransactions.removeAt(index);
        applyAllFilters();
        _recalculateTotals();
      }

      // Perform actual deletion
      await OfflineService.deleteTransactionOffline(t.id!);
      await TransactionService.deleteTransaction(t.id!);

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
      // If deletion fails, refresh to get the item back
      fetchFirstPage();
    }
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
