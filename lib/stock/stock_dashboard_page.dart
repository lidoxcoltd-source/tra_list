import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/theme/app_theme.dart';
import 'products_pages.dart';
import 'pos_page.dart';
import 'stock_models.dart';
import 'stock_operations_pages.dart';
import 'stock_service.dart';
import 'stock_ui.dart';
import 'bar_orders_page.dart';

class StockDashboardPage extends StatelessWidget {
  const StockDashboardPage({super.key});

  @override
  Widget build(BuildContext context) => Obx(() {
    if (BusinessAccessService.isBarBartender) return const PosPage();
    final service = StockService.current();
    final canCreate = BusinessAccessService.can('stock', 'create');
    final canEdit = BusinessAccessService.can('stock', 'edit');
    return DefaultTabController(
      length: 2,
      child: StockScaffold(
        title: 'stk_title'.tr,
        actions: [
          IconButton(
            tooltip: 'stk_history'.tr,
            icon: const Icon(Icons.history),
            onPressed: () => Get.to(() => const StockHistoryPage()),
          ),
        ],
        body: StreamBuilder<List<Product>>(
          stream: service.watchProducts(),
          builder: (context, snap) {
            if (snap.hasError) {
              return StockMessage(
                icon: Icons.error_outline,
                color: kStockBad,
                text: stockErrorText(snap.error!),
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final all = snap.data!.where((p) => p.active).toList();
            final tracked = all.where((p) => p.tracked).toList();
            final low = tracked
                .where((p) => p.stockState == StockState.low)
                .toList();
            final out = tracked
                .where((p) => p.stockState == StockState.out)
                .toList();
            final value = tracked.fold<double>(
              0,
              (sum, p) => sum + (p.quantity > 0 ? p.quantity * p.costPrice : 0),
            );
            final attention = [...out, ...low];
            final stats = [
              if (canEdit)
                StatTile(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'stk_stock_value'.tr,
                  value: 'TZS ${formatMoney(value)}',
                  color: kStockNavy,
                ),
              StatTile(
                icon: Icons.warning_amber_rounded,
                label: 'stk_low_stock'.tr,
                value: '${low.length}',
                color: kStockWarn,
                onTap: () =>
                    Get.to(() => const ProductsPage(initialFilter: 'low')),
              ),
              StatTile(
                icon: Icons.remove_shopping_cart_outlined,
                label: 'stk_out_of_stock'.tr,
                value: '${out.length}',
                color: kStockBad,
                onTap: () =>
                    Get.to(() => const ProductsPage(initialFilter: 'out')),
              ),
            ];
            final salesActions =
                <
                  ({
                    String label,
                    IconData icon,
                    VoidCallback onTap,
                    bool primary,
                  })
                >[
                  if (BusinessAccessService.can('invoices', 'create'))
                    (
                      label: 'pos_title'.tr,
                      icon: Icons.qr_code_scanner,
                      onTap: () => Get.to(() => const PosPage()),
                      primary: true,
                    ),
                  if (BusinessAccessService.barModeEnabled.value &&
                      BusinessAccessService.can('invoices', 'create'))
                    (
                      label: 'bar_orders'.tr,
                      icon: Icons.room_service_outlined,
                      onTap: () => Get.to(() => const BarOrdersPage()),
                      primary: false,
                    ),
                ];
            final inventoryActions =
                <
                  ({
                    String label,
                    IconData icon,
                    VoidCallback onTap,
                    bool primary,
                  })
                >[
                  (
                    label: 'stk_products'.tr,
                    icon: Icons.inventory_2_outlined,
                    onTap: () => Get.to(() => const ProductsPage()),
                    primary: false,
                  ),
                  if (canCreate)
                    (
                      label: 'stk_add_product'.tr,
                      icon: Icons.add_box_outlined,
                      onTap: () => Get.to(() => const ProductFormPage()),
                      primary: false,
                    ),
                  if (canCreate)
                    (
                      label: 'stk_receive'.tr,
                      icon: Icons.move_to_inbox_outlined,
                      onTap: () => Get.to(() => const ReceiveStockPage()),
                      primary: false,
                    ),
                  if (canEdit)
                    (
                      label: 'stk_adjust'.tr,
                      icon: Icons.tune_rounded,
                      onTap: () => Get.to(() => const AdjustStockPage()),
                      primary: false,
                    ),
                ];

            return LayoutBuilder(
              builder: (context, constraints) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [kStockNavy, kStockBlue],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: kStockNavy.withValues(alpha: .14),
                              blurRadius: 16,
                              offset: const Offset(0, 7),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .14),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.inventory_2_outlined,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${'stk_total_products'.tr}\n${'stk_catalog_title'.tr}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .82),
                                  fontSize: 11,
                                  height: 1.35,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Text(
                              '${all.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                height: 1,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              constraints: const BoxConstraints.tightFor(
                                width: 38,
                                height: 38,
                              ),
                              padding: EdgeInsets.zero,
                              tooltip: 'stk_products'.tr,
                              style: IconButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.white.withValues(
                                  alpha: .14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () =>
                                  Get.to(() => const ProductsPage()),
                              icon: const Icon(
                                Icons.arrow_forward_rounded,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          for (var i = 0; i < stats.length; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(child: stats[i]),
                          ],
                        ],
                      ),
                      if (salesActions.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _StockActionGroup(
                          title: 'stk_sales_group'.tr,
                          icon: Icons.point_of_sale_outlined,
                          actions: salesActions,
                          columns: 2,
                        ),
                      ],
                      if (inventoryActions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _StockActionGroup(
                          title: 'stk_inventory_group'.tr,
                          icon: Icons.tune_rounded,
                          actions: inventoryActions,
                          columns: constraints.maxWidth >= 720 ? 4 : 2,
                        ),
                      ],
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: MjasiColors.border),
                        ),
                        child: TabBar(
                          dividerColor: Colors.transparent,
                          indicatorSize: TabBarIndicatorSize.tab,
                          indicator: BoxDecoration(
                            color: kStockLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          labelColor: kStockBlue,
                          unselectedLabelColor: MjasiColors.textSecondary,
                          labelStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                          tabs: [
                            Tab(
                              height: 42,
                              text:
                                  '${'stk_needs_attention'.tr} (${attention.length})',
                            ),
                            Tab(height: 42, text: 'stk_recent'.tr),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: TabBarView(
                          children: [
                            attention.isEmpty
                                ? StockMessage(
                                    icon: Icons.check_circle_outline,
                                    color: kStockOk,
                                    text: 'stk_all_good'.tr,
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    itemCount: attention.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 6),
                                    itemBuilder: (context, index) {
                                      final product = attention[index];
                                      return StockCard(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        onTap: () => Get.to(
                                          () => ProductDetailsPage(
                                            productId: product.id!,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 30,
                                              height: 30,
                                              decoration: BoxDecoration(
                                                color:
                                                    product.stockState ==
                                                        StockState.out
                                                    ? MjasiColors
                                                          .errorBackground
                                                    : MjasiColors
                                                          .warningBackground,
                                                borderRadius:
                                                    BorderRadius.circular(9),
                                              ),
                                              child: Icon(
                                                product.stockState ==
                                                        StockState.out
                                                    ? Icons
                                                          .remove_shopping_cart_outlined
                                                    : Icons
                                                          .warning_amber_rounded,
                                                size: 17,
                                                color:
                                                    product.stockState ==
                                                        StockState.out
                                                    ? kStockBad
                                                    : kStockWarn,
                                              ),
                                            ),
                                            const SizedBox(width: 9),
                                            Expanded(
                                              child: Text(
                                                product.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color:
                                                      MjasiColors.textPrimary,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '${formatQty(product.quantity)} ${unitLabel(product.unit)}',
                                              style: const TextStyle(
                                                color:
                                                    MjasiColors.textSecondary,
                                                fontSize: 11,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            StockStateChip(product: product),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                            StreamBuilder<List<StockMovement>>(
                              stream: service.watchMovements(limit: 8),
                              builder: (context, movements) {
                                if (movements.hasError) {
                                  return StockMessage(
                                    icon: Icons.error_outline,
                                    color: kStockBad,
                                    text: stockErrorText(movements.error!),
                                  );
                                }
                                if (!movements.hasData) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                if (movements.data!.isEmpty) {
                                  return StockMessage(
                                    icon: Icons.history,
                                    text: 'stk_no_movements'.tr,
                                  );
                                }
                                return ListView(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  children: [
                                    for (final movement in movements.data!)
                                      MovementTile(movement: movement),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  });
}

class StockHistoryPage extends StatefulWidget {
  const StockHistoryPage({super.key});

  @override
  State<StockHistoryPage> createState() => _StockHistoryPageState();
}

class _StockQuickAction extends StatelessWidget {
  const _StockQuickAction({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.primary,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final foreground = primary ? Colors.white : kStockNavy;
    return Material(
      color: primary ? kStockBlue : MjasiColors.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: primary ? kStockBlue : MjasiColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: foreground, size: 17),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 11,
                    height: 1.1,
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
}

class _StockActionGroup extends StatelessWidget {
  const _StockActionGroup({
    required this.title,
    required this.icon,
    required this.actions,
    required this.columns,
  });

  final String title;
  final IconData icon;
  final List<({String label, IconData icon, VoidCallback onTap, bool primary})>
  actions;
  final int columns;

  @override
  Widget build(BuildContext context) => StockCard(
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 17, color: kStockBlue),
            const SizedBox(width: 7),
            Text(
              title,
              style: const TextStyle(
                color: MjasiColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 7.0;
            final itemWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final action in actions)
                  SizedBox(
                    width: itemWidth,
                    child: _StockQuickAction(
                      label: action.label,
                      icon: action.icon,
                      primary: action.primary,
                      onTap: action.onTap,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _StockHistoryPageState extends State<StockHistoryPage> {
  final _service = StockService.current();
  MovementType? _type;
  String _query = '';
  DateTimeRange? _range;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: StockScaffold(
        title: 'stk_history'.tr,
        maxWidth: 900,
        bottom: TabBar(
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: 'stk_movements'.tr),
            Tab(text: 'stk_purchases'.tr),
          ],
        ),
        body: TabBarView(children: [_movements(), _purchases()]),
      ),
    );
  }

  Widget _movements() {
    return StreamBuilder<List<StockMovement>>(
      stream: _service.watchMovements(limit: 500),
      builder: (context, snap) {
        if (snap.hasError) {
          return StockMessage(
            icon: Icons.error_outline,
            color: kStockBad,
            text: stockErrorText(snap.error!),
          );
        }
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final q = _query.trim().toLowerCase();
        final list = snap.data!.where((m) {
          if (_type != null && m.type != _type) return false;
          final d = m.createdAt;
          if (_range != null && d != null) {
            if (d.isBefore(_range!.start) ||
                d.isAfter(_range!.end.add(const Duration(days: 1)))) {
              return false;
            }
          }
          return q.isEmpty ||
              m.productName.toLowerCase().contains(q) ||
              m.reason.toLowerCase().contains(q);
        }).toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: stockInput(
                        'stk_search'.tr,
                        icon: Icons.search_rounded,
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<MovementType?>(
                    tooltip: 'stk_adjust_type'.tr,
                    icon: Icon(
                      Icons.filter_list,
                      color: _type == null ? null : kStockBlue,
                    ),
                    onSelected: (v) => setState(() => _type = v),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: null,
                        child: Text('stk_filter_all'.tr),
                      ),
                      for (final t in MovementType.values)
                        PopupMenuItem(value: t, child: Text(t.labelKey.tr)),
                    ],
                  ),
                  IconButton(
                    tooltip: 'stk_date'.tr,
                    icon: Icon(
                      Icons.date_range,
                      color: _range == null ? null : kStockBlue,
                    ),
                    onPressed: () async {
                      if (_range != null) {
                        setState(() => _range = null);
                        return;
                      }
                      final r = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (r != null) setState(() => _range = r);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? StockMessage(
                      icon: Icons.history,
                      text: 'stk_no_movements'.tr,
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final m in list) MovementTile(movement: m),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _purchases() {
    final canSeeCost = BusinessAccessService.can('stock', 'edit');
    return StreamBuilder<List<Purchase>>(
      stream: _service.watchPurchases(),
      builder: (context, snap) {
        if (snap.hasError) {
          return StockMessage(
            icon: Icons.error_outline,
            color: kStockBad,
            text: stockErrorText(snap.error!),
          );
        }
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        if (snap.data!.isEmpty) {
          return StockMessage(
            icon: Icons.local_shipping_outlined,
            text: 'stk_no_purchases'.tr,
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final p in snap.data!)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: StockCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.supplier.isEmpty
                                  ? 'stk_purchases'.tr
                                  : p.supplier,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (canSeeCost)
                            Text(
                              'TZS ${formatMoney(p.total)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                        ],
                      ),
                      Text(
                        [
                          formatDate(p.date),
                          if (p.reference.isNotEmpty) p.reference,
                        ].join(' · '),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final l in p.lines)
                        Text(
                          '${l['productName']}  ×  ${formatQty((l['quantity'] as num?) ?? 0)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
