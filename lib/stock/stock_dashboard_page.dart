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
import 'daily_business_brief_card.dart';

class StockDashboardPage extends StatelessWidget {
  const StockDashboardPage({super.key});

  @override
  Widget build(BuildContext context) => Obx(() {
    if (BusinessAccessService.isBarBartender) return const PosPage();
    final service = StockService.current();
    final canCreate = BusinessAccessService.can('stock', 'create');
    final canEdit = BusinessAccessService.can('stock', 'edit');
    return DefaultTabController(
      length: 4,
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
                  if (BusinessAccessService.canUseBarPos)
                    (
                      label: 'pos_title'.tr,
                      icon: Icons.qr_code_scanner,
                      onTap: () => Get.to(() => const PosPage()),
                      primary: true,
                    ),
                  if (BusinessAccessService.barModeEnabled.value &&
                      BusinessAccessService.canUseBarPos)
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
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                          tabs: [
                            Tab(height: 44, text: 'stk_overview_tab'.tr),
                            Tab(height: 44, text: 'stk_alerts_tab'.tr),
                            Tab(height: 44, text: 'stk_sold_items'.tr),
                            Tab(height: 44, text: 'stk_recent_tab'.tr),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: TabBarView(
                          children: [
                            ListView(
                              padding: const EdgeInsets.only(bottom: 8),
                              children: [
                                if (BusinessAccessService.can(
                                  'dailyBrief',
                                  'view',
                                )) ...[
                                  const DailyBusinessBriefCard(),
                                  const SizedBox(height: 10),
                                ],
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
                                        color: kStockNavy.withValues(
                                          alpha: .14,
                                        ),
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
                                          color: Colors.white.withValues(
                                            alpha: .14,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.inventory_2_outlined,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'stk_catalog_title'.tr,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              fmtText('stk_catalog_summary', {
                                                'count': '${all.length}',
                                                'low': '${attention.length}',
                                              }),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white.withValues(
                                                  alpha: .82,
                                                ),
                                                fontSize: 11,
                                                height: 1.3,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
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
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 38,
                                              height: 38,
                                            ),
                                        padding: EdgeInsets.zero,
                                        tooltip: 'stk_products'.tr,
                                        style: IconButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          backgroundColor: Colors.white
                                              .withValues(alpha: .14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
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
                                LayoutBuilder(
                                  builder: (context, statConstraints) {
                                    final columns =
                                        statConstraints.maxWidth < 520
                                        ? 2
                                        : stats.length;
                                    const spacing = 8.0;
                                    final tileWidth =
                                        (statConstraints.maxWidth -
                                            spacing * (columns - 1)) /
                                        columns;
                                    return Wrap(
                                      spacing: spacing,
                                      runSpacing: spacing,
                                      children: [
                                        for (final stat in stats)
                                          SizedBox(
                                            width: tileWidth,
                                            child: stat,
                                          ),
                                      ],
                                    );
                                  },
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
                                    columns: constraints.maxWidth >= 720
                                        ? 4
                                        : 2,
                                  ),
                                ],
                              ],
                            ),
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
                            _StockSalesSummary(
                              service: service,
                              products: all,
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

enum _SoldProductsSort { mostSold, leastSold, name }

class _StockSalesSummary extends StatefulWidget {
  const _StockSalesSummary({required this.service, required this.products});

  final StockService service;
  final List<Product> products;

  @override
  State<_StockSalesSummary> createState() => _StockSalesSummaryState();
}

class _StockSalesSummaryState extends State<_StockSalesSummary> {
  int _days = 30;
  _SoldProductsSort _sort = _SoldProductsSort.mostSold;
  late Stream<List<StockMovement>> _movements;

  @override
  void initState() {
    super.initState();
    _movements = _watchMovements();
  }

  @override
  void didUpdateWidget(covariant _StockSalesSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      _movements = _watchMovements();
    }
  }

  Stream<List<StockMovement>> _watchMovements() => widget.service
      .watchMovementsSince(DateTime.now().subtract(Duration(days: _days)));

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StockMovement>>(
      stream: _movements,
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

        final productsById = {
          for (final product in widget.products)
            if (product.id != null) product.id!: product,
        };
        final totals = <String, _SoldProductTotal>{};
        for (final movement in snap.data!) {
          if (movement.type != MovementType.sale ||
              movement.quantityChange >= 0) {
            continue;
          }
          final key = movement.productId.isNotEmpty
              ? movement.productId
              : movement.productName.trim().toLowerCase();
          if (key.isEmpty) continue;
          final current = totals[key];
          if (current == null) {
            totals[key] = _SoldProductTotal(
              productId: movement.productId,
              name: movement.productName,
              quantity: movement.quantityChange.abs(),
            );
          } else {
            current.quantity += movement.quantityChange.abs();
          }
        }

        final soldProducts = totals.values.toList();
        switch (_sort) {
          case _SoldProductsSort.mostSold:
            soldProducts.sort((a, b) => b.quantity.compareTo(a.quantity));
            break;
          case _SoldProductsSort.leastSold:
            soldProducts.sort((a, b) => a.quantity.compareTo(b.quantity));
            break;
          case _SoldProductsSort.name:
            soldProducts.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
            break;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StockCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: kStockLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.trending_up_rounded,
                          color: kStockBlue,
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'stk_sold_summary'.tr,
                              style: const TextStyle(
                                color: MjasiColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              fmtText('stk_sold_totals', {
                                'products': '${soldProducts.length}',
                              }),
                              style: const TextStyle(
                                color: MjasiColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _salesDropdown<int>(
                          label: 'stk_period'.tr,
                          value: _days,
                          items: {
                            7: 'stk_last_days'.trParams({'days': '7'}),
                            30: 'stk_last_days'.trParams({'days': '30'}),
                            90: 'stk_last_days'.trParams({'days': '90'}),
                          },
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _days = value;
                                _movements = _watchMovements();
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _salesDropdown<_SoldProductsSort>(
                          label: 'stk_sort_by'.tr,
                          value: _sort,
                          items: {
                            _SoldProductsSort.mostSold:
                                'stk_sort_most_sold'.tr,
                            _SoldProductsSort.leastSold:
                                'stk_sort_least_sold'.tr,
                            _SoldProductsSort.name: 'stk_sort_name'.tr,
                          },
                          onChanged: (value) {
                            if (value != null) setState(() => _sort = value);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (soldProducts.isEmpty)
              Expanded(
                child: StockMessage(
                  icon: Icons.point_of_sale_outlined,
                  text: 'stk_no_sales_in_period'.tr,
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: soldProducts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final item = soldProducts[index];
                    final product = productsById[item.productId];
                    return StockCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: index == 0 &&
                                      _sort == _SoldProductsSort.mostSold
                                  ? const Color(0xFFFFF3D6)
                                  : kStockLight,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(
                              index == 0 &&
                                      _sort == _SoldProductsSort.mostSold
                                  ? Icons.emoji_events_outlined
                                  : Icons.inventory_2_outlined,
                              color: index == 0 &&
                                      _sort == _SoldProductsSort.mostSold
                                  ? kStockWarn
                                  : kStockBlue,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: MjasiColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (product != null && product.tracked) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    fmtText('stk_current_stock_count', {
                                      'quantity': formatQty(product.quantity),
                                      'unit': unitLabel(product.unit),
                                    }),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: MjasiColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatQty(item.quantity),
                                style: const TextStyle(
                                  color: MjasiColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                product == null
                                    ? 'stk_sold_quantity_label'.tr
                                    : '${'stk_sold_quantity_label'.tr} · ${unitLabel(product.unit)}',
                                style: const TextStyle(
                                  color: MjasiColors.textSecondary,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _salesDropdown<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
  }) => InputDecorator(
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.fromLTRB(10, 7, 8, 2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: MjasiColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: MjasiColors.border),
      ),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        isDense: true,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
        items: [
          for (final entry in items.entries)
            DropdownMenuItem<T>(
              value: entry.key,
              child: Text(
                entry.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
        onChanged: onChanged,
      ),
    ),
  );
}

class _SoldProductTotal {
  _SoldProductTotal({
    required this.productId,
    required this.name,
    required this.quantity,
  });

  final String productId;
  final String name;
  double quantity;
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
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
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
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
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
