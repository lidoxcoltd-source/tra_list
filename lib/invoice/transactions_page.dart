import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/date_symbol_data_local.dart';
import 'package:tra_list/invoice/transaction_form.dart' hide AddTransactionPage;
import 'package:tra_list/routes.dart';
import 'package:tra_list/invoice/transaction_report_pdf.dart';
import 'package:tra_list/invoice/transaction_excel_export.dart'; // Add this import
import 'add_transaction_page.dart';
import 'transaction_model.dart';
import 'transaction_service.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'analytics_page.dart';
import 'transactions_controller.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  final TransactionsController controller = Get.put(TransactionsController());
  bool _isDesktopSaving = false;

  @override
  Widget build(BuildContext context) {
    // Initialize controller
    // Initialize date formatting for the current locale.
    initializeDateFormatting(Get.locale?.toString());

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 850;
        if (isDesktop) {
          return _buildDesktopLayout(context);
        } else {
          return _buildMobileLayout(context);
        }
      },
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: RefreshIndicator(
        onRefresh: controller.fetchFirstPage,
        child: CustomScrollView(
          controller: controller.scrollController,
          slivers: [
            _buildSliverAppBar(context),
            _buildFilterChipsSliver(),
            _buildTransactionListSliver(),
          ],
        ),
      ),
      floatingActionButton: _buildSpeedDialFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: _buildDesktopAppBar(),
      body: Row(
        children: [
          // Left Panel
          Container(
            width: 320,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Obx(() {
              if (controller.showAddForm.value) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TransactionForm(
                    transaction: controller.editingTransaction.value,
                    initialType: controller.formInitialType.value,
                    isSaving: _isDesktopSaving,
                    onSave: (saveAction) async {
                      setState(() => _isDesktopSaving = true);
                      try {
                        await saveAction();
                        controller.hideAddTransactionForm();
                      } finally {
                        if (mounted) {
                          setState(() => _isDesktopSaving = false);
                        }
                      }
                    },
                    onCancel: controller.hideAddTransactionForm,
                  ),
                );
              } else {
                return Column(
                  children: [
                    // Moved summary and filters to the top
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _buildSummaryRow(),
                    ),
                    Divider(height: 1, color: Colors.white.withOpacity(0.1)),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _buildFilterChipsPanel(),
                    ),
                    Divider(height: 1, color: Colors.white.withOpacity(0.1)),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _buildDesktopActionButtons(),
                    ),
                  ],
                );
              }
            }),
          ),
          // Right Panel
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.fetchFirstPage,
              child: _buildTransactionListDesktop(),
            ),
          ),
        ],
      ),
    );
  }

  Obx _buildSpeedDialFab() {
    // Use Obx to rebuild the FAB when brandColor changes.
    return Obx(
      () => SpeedDial(
        icon: Icons.add,
        activeIcon: Icons.close,
        backgroundColor: controller.brandColor.value,
        foregroundColor: Colors.white,
        overlayColor: Colors.black,
        overlayOpacity: 0.4,
        spacing: 12,
        children: _getSpeedDialChildren(),
      ),
    );
  }

  List<SpeedDialChild> _getSpeedDialChildren() {
    return [
      SpeedDialChild(
        child: const Icon(Icons.arrow_downward, color: Colors.white),
        backgroundColor: Colors.red.shade500,
        label: 'expense'.tr,
        onTap: () async {
          final result = await Get.to(
            () =>
                const AddTransactionPage(initialType: TransactionType.expense),
          );
          if (result == true) controller.fetchFirstPage();
        },
      ),
      SpeedDialChild(
        child: const Icon(Icons.arrow_upward, color: Colors.white),
        backgroundColor: Colors.green.shade600,
        label: 'income'.tr,
        onTap: () async {
          final result = await Get.to(
            () => const AddTransactionPage(initialType: TransactionType.income),
          );
          if (result == true) controller.fetchFirstPage();
        },
      ),
    ];
  }

  Widget _buildSummaryRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use a Column layout on narrow screens
        final bool useVerticalLayout = constraints.maxWidth < 450;

        final incomeCard = Obx(
          () => _SummaryCard(
            title: 'income'.tr,
            value:
                'TSH ${TransactionsController.money(controller.currentIncome.value)}',
            accent: Colors.green,
            isSelected: controller.summaryFilter.value == SummaryFilter.income,
            onTap: () => controller.setSummaryFilter(SummaryFilter.income),
          ),
        );

        final expenseCard = Obx(
          () => _SummaryCard(
            title: 'expenses'.tr,
            value:
                'TSH ${TransactionsController.money(controller.currentExpense.value)}',
            accent: Colors.red,
            isSelected: controller.summaryFilter.value == SummaryFilter.expense,
            onTap: () => controller.setSummaryFilter(SummaryFilter.expense),
          ),
        );

        final netCard = Obx(() {
          final netValue = controller.currentNet.value;
          final netString =
              'TSH ${TransactionsController.money(netValue.abs())}';
          return _SummaryCard(
            title: 'net'.tr,
            value: (netValue >= 0 ? '' : '-') + netString,
            accent: netValue >= 0 ? Colors.green : Colors.orange,
            currentNet: netValue,
            isSelected: controller.summaryFilter.value == SummaryFilter.all,
            onTap: () => controller.setSummaryFilter(SummaryFilter.all),
          );
        });

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
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
        ), // No tr needed for widgets
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: Colors.blue.shade600,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.edit, color: Colors.white),
      ),
      secondaryBackground: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
        ), // No tr needed for widgets
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
          // For desktop, we can use the form on the left.
          if (Get.width > 850) {
            controller.editTransactionOnDesktop(t);
          } else {
            final result = await Get.to(
              () => AddTransactionPage(transaction: t),
            );
            // Only refresh if the transaction was actually saved.
            if (result == true) controller.fetchFirstPage();
          }
          return false; // Do not dismiss the item
        } else {
          // Delete action
          return await controller.confirmDelete(t);
        }
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
          onTap: () => controller.showActions(t),
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
                      '${isExpense ? '-' : '+'}TSH ${TransactionsController.money(t.amount)}',
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

  // This widget is no longer used, but I'll leave it here in case you want to
  // re-implement a "Load More" button instead of infinite scrolling.
  Widget _buildLoader() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20.0),
        child: Center(
          child: controller.loadingMore.value
              ? const CircularProgressIndicator()
              : controller.hasMore.value
              ? ElevatedButton(
                  onPressed: controller.fetchNextPage,
                  child: Text('transactions_load_more'.tr),
                )
              : Text(
                  'transactions_end_of_list'.tr,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
        ),
      ),
    );
  }

  AppBar _buildDesktopAppBar() {
    return AppBar(
      elevation: 1,
      backgroundColor: controller.brandColor.value,
      foregroundColor: Colors.white,
      title: Obx(
        () => controller.isSearching.value
            ? Hero(
                tag: 'search_field',
                child: TextField(
                  controller: controller.searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: '${'search'.tr}...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                    border: InputBorder.none,
                  ),
                ),
              )
            : Text(
                '${'transactions_title'.tr} - ${controller.filterTitle.value}',
              ),
      ),
      actions: _buildAppBarActions(),
    );
  }

  Widget _buildDesktopActionButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.arrow_upward),
          label: Text('transactions_add_income'.tr),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade600,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: () async {
            final result = await Get.to(
              () =>
                  const AddTransactionPage(initialType: TransactionType.income),
            );
            if (result == true) controller.fetchFirstPage();
          },
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          icon: const Icon(Icons.arrow_downward),
          label: Text('transactions_add_expense'.tr),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade500,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: () async {
            final result = await Get.to(
              () => const AddTransactionPage(
                initialType: TransactionType.expense,
              ),
            );
            if (result == true) controller.fetchFirstPage();
          },
        ),
      ],
    );
  }

  Widget _buildSliverAppBar(BuildContext context) {
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

    return Obx(
      () => SliverAppBar(
        pinned: true,
        floating: true,
        snap: true,
        expandedHeight: adaptiveHeight,
        elevation: 1,
        backgroundColor: controller.brandColor.value,
        foregroundColor: Colors.white,
        title: controller.isSearching.value
            // NEW: Animated search bar transition
            ? Hero(
                tag: 'search_field',
                child: TextField(
                  controller: controller.searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: '${'search'.tr}...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                    border: InputBorder.none,
                  ),
                ),
              )
            : Text('transactions_title'.tr), // No tr needed for variables
        actions: _buildAppBarActions(),
        flexibleSpace: FlexibleSpaceBar(
          background: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    // No tr needed for variables
                    colors: [
                      controller.brandColor.value,
                      controller.accentColor.value.withOpacity(0.8),
                    ],
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
                            controller.filterTitle.value,
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
      ),
    );
  }

  List<Widget> _buildAppBarActions() {
    return [
      // Show a compact clear action in the toolbar when single-day filter is active
      if (controller.filter.value == FilterPeriod.singleDay &&
          !controller.isSearching.value)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: TextButton.icon(
            onPressed: controller.clearSingleDayFilter,
            icon: const Icon(Icons.close, color: Colors.white, size: 18),
            label: Text(
              'clear'.tr,
              style: const TextStyle(color: Colors.white),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      IconButton(
        tooltip: 'search'.tr,
        onPressed: controller.toggleSearch,
        icon: Hero(
          tag: 'search_icon',
          child: Icon(
            controller.isSearching.value ? Icons.close : Icons.search,
          ),
        ),
      ),
      if (!controller.isSearching.value)
        PopupMenuButton<SortOption>(
          tooltip: 'Sort by'.tr,
          icon: const Icon(Icons.sort),
          onSelected: (newSortOption) {
            if (controller.sortOption.value != newSortOption) {
              controller.sortOption.value = newSortOption;
              controller.applyAllFilters(); // Re-sort and re-group the list
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              enabled: false,
              child: Text(
                'Sort by'.tr,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            CheckedPopupMenuItem(
              value: SortOption.dateDesc,
              checked: controller.sortOption.value == SortOption.dateDesc,
              child: Text('Date (Newest First)'.tr),
            ),
            CheckedPopupMenuItem(
              value: SortOption.dateAsc,
              checked: controller.sortOption.value == SortOption.dateAsc,
              child: Text('Date (Oldest First)'.tr),
            ),
            CheckedPopupMenuItem(
              value: SortOption.amountDesc,
              checked: controller.sortOption.value == SortOption.amountDesc,
              child: Text('Amount (Highest First)'.tr),
            ),
            CheckedPopupMenuItem(
              value: SortOption.amountAsc,
              checked: controller.sortOption.value == SortOption.amountAsc,
              child: Text('Amount (Lowest First)'.tr),
            ),
          ],
        ),
      if (!controller.isSearching.value)
        IconButton(
          tooltip: 'transactions_export_pdf'.tr,
          onPressed:
              controller.transactions.isEmpty || controller.isPdfBusy.value
              ? null
              : controller.exportPdf,
          icon: controller.isPdfBusy.value
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ), // No tr needed for widgets
                )
              : const Icon(Icons.picture_as_pdf_outlined),
        ),
      if (!controller.isSearching.value)
        IconButton(
          tooltip: 'Export as Excel'.tr,
          onPressed:
              controller.transactions.isEmpty || controller.isExcelBusy.value
              ? null
              : controller.exportExcel,
          icon: controller.isExcelBusy.value
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ) // No tr needed for widgets
              : const Icon(Icons.table_chart_outlined),
        ),
      if (!controller.isSearching.value)
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'refresh') controller.fetchFirstPage();
            if (v == 'clear_filters') controller.setFilter(FilterPeriod.all);
            if (v == 'export_excel') controller.exportExcel();
            if (v == 'export_pdf') controller.exportPdf();
            if (v == 'analytics') {
              Get.to(() => const AnalyticsPage());
            }
          }, // No tr needed for logic
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
                  const Icon(
                    Icons.picture_as_pdf_outlined,
                    size: 20,
                  ), // No tr needed for widgets
                  const SizedBox(width: 8), // No tr needed for widgets
                  Text('Export PDF'.tr),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'export_excel',
              child: Row(
                children: [
                  const Icon(Icons.table_chart_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text('Export Excel'.tr),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'analytics',
              child: Row(
                children: [
                  const Icon(Icons.analytics_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text('Analytics'.tr),
                ],
              ),
            ),
          ],
        ),
    ];
  }

  Widget _buildFilterChipsSliver() {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _SliverFilterChipsDelegate(
        minHeight: 70,
        maxHeight: 100, // Adjusted for a single row of chips
        child: Obx(
          () => Container(
            color: controller.brandColor.value, // Match app bar color
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            alignment: Alignment.centerLeft,
            child: _buildFilterChipsPanel(),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChipsPanel() {
    return Wrap(
      spacing: 8.0,
      runSpacing: 4.0,
      alignment: WrapAlignment.start,
      children: [
        _buildFilterChip(FilterPeriod.all, 'transactions_all_time'.tr),
        _buildFilterChip(FilterPeriod.today, 'transactions_today'.tr),
        _buildFilterChip(FilterPeriod.yesterday, 'yesterday'.tr),
        _buildFilterChip(FilterPeriod.week, 'transactions_this_week'.tr),
        _buildFilterChip(FilterPeriod.month, 'transactions_this_month'.tr),
        ActionChip(
          avatar: const Icon(Icons.calendar_today, size: 16),
          label: Text('transactions_custom_range'.tr),
          onPressed: () => controller.setFilter(FilterPeriod.custom),
        ),
      ],
    );
  }

  Widget _buildTransactionListSliver() {
    return Obx(
      () => SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          120,
        ), // More bottom padding for FAB
        sliver: controller.isFetching.value && controller.transactions.isEmpty
            ? const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            : controller.transactions.isEmpty
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
                        controller.searchController.text.isNotEmpty
                            ? '${'transactions_no_transactions'.tr} for "${controller.searchController.text}"'
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
                slivers: controller.groupedTransactions.entries.map((entry) {
                  final date = entry.key;
                  final transactionsInGroup = entry.value;
                  return _TransactionGroup(
                    onHeaderTap: () => controller.filterBySingleDay(date),
                    header: TransactionsController.formatDateHeader(date),
                    children: transactionsInGroup
                        .map(
                          (t) => _buildTransactionCard(
                            t,
                            controller.allFetchedTransactions.indexOf(t),
                          ),
                        )
                        .toList(),
                  );
                }).toList(),
              ),
      ),
    );
  }

  Widget _buildTransactionListDesktop() {
    return Obx(() {
      if (controller.isFetching.value && controller.transactions.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (controller.transactions.isEmpty) {
        return Center(
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
                controller.searchController.text.isNotEmpty
                    ? '${'transactions_no_transactions'.tr} for "${controller.searchController.text}"'
                    : 'transactions_no_transactions'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
              ),
            ],
          ),
        );
      }
      return ListView.builder(
        controller: controller.scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        itemCount: controller.groupedTransactions.length,
        itemBuilder: (context, index) {
          final entry = controller.groupedTransactions.entries.elementAt(index);
          final date = entry.key;
          final transactionsInGroup = entry.value;
          return _TransactionGroup(
            onHeaderTap: () => controller.filterBySingleDay(date),
            header: TransactionsController.formatDateHeader(date),
            children: transactionsInGroup
                .map(
                  (t) => _buildTransactionCard(
                    t,
                    controller.allFetchedTransactions.indexOf(t),
                  ),
                )
                .toList(),
          );
        },
      );
    });
  }

  Widget _buildFilterChip(FilterPeriod p, String label) {
    final selected = controller.filter.value == p;
    return ChoiceChip(
      label: Text(label),
      labelStyle: TextStyle(
        color: selected ? Colors.blue.shade800 : Colors.black87,
      ),
      selected: selected,
      onSelected: (_) => controller.setFilter(p),
      selectedColor: controller.accentColor.value.withOpacity(0.3),
      backgroundColor: controller.brandColor.value.withOpacity(0.1),
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }
}

// NEW: A custom Sliver widget to group a header and a list of children.
class _TransactionGroup extends StatelessWidget {
  // Can be used for both sliver and non-sliver lists
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
    // If the parent is a regular ListView, use a Column.
    // If it's a CustomScrollView, use SliverMainAxisGroup.
    final isSliver =
        context.findAncestorWidgetOfExactType<CustomScrollView>() != null;

    final headerWidget = InkWell(
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
    );

    if (!isSliver) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [headerWidget, ...children],
      );
    }

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
