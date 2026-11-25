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
import 'product_sales_page.dart';
import 'sales_total_card.dart';
import 'suppliers_page.dart';

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
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: const Border(top: BorderSide(color: MjasiColors.border)),
            boxShadow: [
              BoxShadow(
                color: kStockNavy.withValues(alpha: .06),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Material(
              color: Colors.transparent,
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
                  Tab(
                    icon: const Icon(Icons.dashboard_outlined),
                    text: 'stk_overview_tab'.tr,
                  ),
                  Tab(
                    icon: const Icon(Icons.warning_amber_rounded),
                    text: 'stk_alerts_tab'.tr,
                  ),
                  Tab(
                    icon: const Icon(Icons.point_of_sale_rounded),
                    text: 'stk_sold_items'.tr,
                  ),
                  Tab(
                    icon: const Icon(Icons.history_rounded),
                    text: 'stk_recent_tab'.tr,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'stk_products'.tr,
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => Get.to(() => const ProductsPage()),
          ),
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
                    primary: true,
                  ),
                  (
                    label: 'stk_suppliers'.tr,
                    icon: Icons.local_shipping_outlined,
                    onTap: () => Get.to(() => const SuppliersPage()),
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
                      Expanded(
                        child: TabBarView(
                          children: [
                            ListView(
                              padding: const EdgeInsets.only(bottom: 8),
                              children: [
                                StockSalesTotalCard(
                                  service: service,
                                  canViewSales: BusinessAccessService.can(
                                    'invoices',
                                    'view',
                                  ),
                                ),
                                const SizedBox(height: 10),
                                InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () =>
                                      Get.to(() => const ProductsPage()),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Colors.white, Color(0xFFF2F7FF)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: const Color(0xFFDCE7F5),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: kStockNavy.withValues(
                                            alpha: .05,
                                          ),
                                          blurRadius: 14,
                                          offset: const Offset(0, 5),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: kStockLight,
                                            borderRadius: BorderRadius.circular(
                                              13,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.inventory_2_outlined,
                                            color: kStockBlue,
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
                                                  color: MjasiColors.textPrimary,
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
                                                style: const TextStyle(
                                                  color:
                                                      MjasiColors.textSecondary,
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
                                            color: kStockNavy,
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
                                            foregroundColor: kStockBlue,
                                            backgroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(
                                                12,
                                              ),
                                              side: const BorderSide(
                                                color: MjasiColors.border,
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
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                border: Border.all(
                                                  color: MjasiColors.border,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: kStockNavy
                                                        .withValues(
                                                          alpha: .035,
                                                        ),
                                                    blurRadius: 10,
                                                    offset: const Offset(0, 3),
                                                  ),
                                                ],
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                child: stat,
                                              ),
                                            ),
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
                                    trailing: TextButton.icon(
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        foregroundColor: kStockBlue,
                                      ),
                                      onPressed: () =>
                                          Get.to(() => const ProductsPage()),
                                      icon: const Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 14,
                                      ),
                                      label: Text(
                                        'stk_products'.tr,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
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
                                        const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final product = attention[index];
                                      return Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(
                                            color: MjasiColors.border,
                                          ),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          child: StockCard(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            onTap: () => Get.to(
                                              () => ProductDetailsPage(
                                                productId: product.id!,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 36,
                                                  height: 36,
                                                  decoration: BoxDecoration(
                                                    color:
                                                        product.stockState ==
                                                            StockState.out
                                                        ? MjasiColors
                                                              .errorBackground
                                                        : MjasiColors
                                                              .warningBackground,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          11,
                                                        ),
                                                  ),
                                                  child: Icon(
                                                    product.stockState ==
                                                            StockState.out
                                                        ? Icons
                                                              .remove_shopping_cart_outlined
                                                        : Icons
                                                              .warning_amber_rounded,
                                                    size: 18,
                                                    color:
                                                        product.stockState ==
                                                            StockState.out
                                                        ? kStockBad
                                                        : kStockWarn,
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        product.name,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          color: MjasiColors
                                                              .textPrimary,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 3),
                                                      Text(
                                                        '${formatQty(product.quantity)} ${unitLabel(product.unit)}',
                                                        style: const TextStyle(
                                                          color: MjasiColors
                                                              .textSecondary,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                StockStateChip(
                                                  product: product,
                                                ),
                                                const SizedBox(width: 2),
                                                const Icon(
                                                  Icons.chevron_right_rounded,
                                                  color:
                                                      MjasiColors.textSecondary,
                                                  size: 19,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                            StockSalesSummary(
                              service: service,
                              products: all,
                              canViewStockValue: canEdit,
                              canViewSalesHistory: BusinessAccessService.can(
                                'invoices',
                                'view',
                              ),
                            ),
                            StreamBuilder<List<StockMovement>>(
                              stream: service.watchMovements(limit: 25),
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
                                return _RecentMovementsView(
                                  movements: movements.data!,
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

class _RecentMovementsView extends StatelessWidget {
  const _RecentMovementsView({required this.movements});

  final List<StockMovement> movements;

  @override
  Widget build(BuildContext context) {
    final productCount = movements
        .map((movement) => movement.productId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: MjasiColors.border),
            boxShadow: [
              BoxShadow(
                color: kStockNavy.withValues(alpha: .05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: kStockLight,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
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
                          'stk_recent'.tr,
                          style: const TextStyle(
                            color: MjasiColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          fmtText('stk_recent_activity_summary', {
                            'count': '${movements.length}',
                            'products': '$productCount',
                          }),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: MjasiColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: movements.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final movement = movements[index];
              return _RecentMovementCard(movement: movement);
            },
          ),
        ),
      ],
    );
  }
}

class _RecentMovementCard extends StatelessWidget {
  const _RecentMovementCard({required this.movement});

  final StockMovement movement;

  @override
  Widget build(BuildContext context) {
    final increase = movement.quantityChange > 0;
    final decrease = movement.quantityChange < 0;
    final color = increase
        ? kStockOk
        : decrease
        ? kStockBad
        : kStockBlue;
    final icon = increase
        ? Icons.arrow_upward_rounded
        : decrease
        ? Icons.arrow_downward_rounded
        : Icons.tune_rounded;
    final details = <Widget>[
      if (movement.reason.isNotEmpty)
        _movementDetail(
          Icons.info_outline_rounded,
          'stk_movement_reason'.tr,
          movement.reason,
        ),
      if (movement.note.isNotEmpty)
        _movementDetail(
          Icons.sticky_note_2_outlined,
          'stk_note'.tr,
          movement.note,
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MjasiColors.border),
        boxShadow: [
          BoxShadow(
            color: kStockNavy.withValues(alpha: .035),
            blurRadius: 9,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movement.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MjasiColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        movement.type.labelKey.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${increase ? '+' : ''}${formatQty(movement.quantityChange)}',
                    style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: MjasiColors.background,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _stockBalance(
                    label: 'stk_stock_before'.tr,
                    quantity: movement.previousQuantity,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: MjasiColors.textSecondary,
                    size: 17,
                  ),
                ),
                Expanded(
                  child: _stockBalance(
                    label: 'stk_stock_after'.tr,
                    quantity: movement.resultingQuantity,
                    alignEnd: true,
                  ),
                ),
              ],
            ),
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final detail in details) detail,
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 5,
            children: [
              _metadata(
                Icons.schedule_rounded,
                formatDateTime(movement.createdAt),
              ),
              if (movement.userName.isNotEmpty)
                _metadata(Icons.person_outline_rounded, movement.userName),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stockBalance({
    required String label,
    required double quantity,
    bool alignEnd = false,
  }) => Column(
    crossAxisAlignment: alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: MjasiColors.textSecondary, fontSize: 9),
      ),
      const SizedBox(height: 2),
      Text(
        formatQty(quantity),
        style: const TextStyle(
          color: MjasiColors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );

  Widget _movementDetail(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: MjasiColors.textSecondary, size: 14),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(
            color: MjasiColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MjasiColors.textPrimary,
              fontSize: 10,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _metadata(IconData icon, String value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: MjasiColors.textSecondary),
      const SizedBox(width: 4),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: MjasiColors.textSecondary, fontSize: 10),
      ),
    ],
  );
}

enum SoldProductsSort { newestSale, oldestSale, mostSold, leastSold, name }

class StockSalesSummary extends StatefulWidget {
  const StockSalesSummary({
    super.key,
    required this.service,
    required this.products,
    required this.canViewStockValue,
    required this.canViewSalesHistory,
  });

  final StockService service;
  final List<Product> products;
  final bool canViewStockValue;
  final bool canViewSalesHistory;

  @override
  State<StockSalesSummary> createState() => StockSalesSummaryState();
}

class StockSalesSummaryState extends State<StockSalesSummary> {
  int _days = 30;
  SoldProductsSort _sort = SoldProductsSort.newestSale;
  late Stream<List<StockMovement>> _movements;
  Stream<List<ProductSaleRecord>>? _sales;

  @override
  void initState() {
    super.initState();
    _resetStreams();
  }

  @override
  void didUpdateWidget(covariant StockSalesSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service ||
        oldWidget.canViewStockValue != widget.canViewStockValue ||
        oldWidget.canViewSalesHistory != widget.canViewSalesHistory) {
      _resetStreams();
    }
  }

  void _resetStreams() {
    final since = DateTime.now().subtract(Duration(days: _days));
    _movements = widget.service.watchMovementsSince(since);
    _sales = widget.canViewSalesHistory
        ? widget.service.watchProductSalesSince(since)
        : null;
  }

  double? _grossProfitForSales(
    List<ProductSaleRecord> sales,
    List<StockMovement> movements,
  ) {
    final soldQuantities = <(String, String), double>{};
    for (final sale in sales) {
      final key = (sale.invoiceId, sale.productId);
      soldQuantities.update(
        key,
        (quantity) => quantity + sale.quantity,
        ifAbsent: () => sale.quantity,
      );
    }

    final movementQuantities = <(String, String), double>{};
    final movementCosts = <(String, String), double>{};
    final missingCosts = <(String, String)>{};
    for (final movement in movements) {
      if (movement.type != MovementType.sale || movement.quantityChange >= 0) {
        continue;
      }
      final key = (movement.refId, movement.productId);
      if (!soldQuantities.containsKey(key)) continue;
      final quantity = movement.quantityChange.abs();
      movementQuantities.update(
        key,
        (total) => total + quantity,
        ifAbsent: () => quantity,
      );
      final unitCost = movement.unitCost;
      if (unitCost == null || !unitCost.isFinite || unitCost < 0) {
        missingCosts.add(key);
      } else {
        movementCosts.update(
          key,
          (total) => total + quantity * unitCost,
          ifAbsent: () => quantity * unitCost,
        );
      }
    }

    var costOfGoodsSold = 0.0;
    for (final entry in soldQuantities.entries) {
      final movementQuantity = movementQuantities[entry.key];
      if (movementQuantity == null ||
          (movementQuantity - entry.value).abs() > 0.001 ||
          missingCosts.contains(entry.key)) {
        return null;
      }
      costOfGoodsSold += movementCosts[entry.key] ?? 0;
    }

    final revenue = sales.fold<double>(0, (sum, sale) => sum + sale.amount);
    return roundMoney(revenue - costOfGoodsSold);
  }

  @override
  Widget build(BuildContext context) {
    final productsById = {
      for (final product in widget.products)
        if (product.id != null) product.id!: product,
    };

    if (_sales != null) {
      return StreamBuilder<List<ProductSaleRecord>>(
        stream: _sales,
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

          final totals = <String, SoldProductTotal>{};
          for (final sale in snap.data!) {
            final current = totals.putIfAbsent(
              sale.productId,
              () => SoldProductTotal(
                productId: sale.productId,
                name: sale.productName,
                quantity: 0,
                revenue: 0,
              ),
            );
            current
              ..quantity += sale.quantity
              ..revenue = (current.revenue ?? 0) + sale.amount
              ..sales.add(sale);
            _updateLastSold(current, sale.createdAt);
          }
          final sales = snap.data!;
          final totalSoldAmount = sales.fold<double>(
            0,
            (sum, sale) => sum + sale.amount,
          );
          if (!widget.canViewStockValue) {
            return _buildSummary(
              totals.values.toList(),
              productsById,
              canOpenHistory: true,
              totalSoldAmount: totalSoldAmount,
            );
          }

          return StreamBuilder<List<StockMovement>>(
            stream: _movements,
            builder: (context, costSnapshot) {
              if (!costSnapshot.hasData && !costSnapshot.hasError) {
                return const Center(child: CircularProgressIndicator());
              }
              final profit = costSnapshot.hasError
                  ? null
                  : _grossProfitForSales(sales, costSnapshot.data!);
              return _buildSummary(
                totals.values.toList(),
                productsById,
                canOpenHistory: true,
                totalSoldAmount: totalSoldAmount,
                grossProfit: profit,
                financialError: costSnapshot.hasError
                    ? stockErrorText(costSnapshot.error!)
                    : null,
              );
            },
          );
        },
      );
    }

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

        final totals = <String, SoldProductTotal>{};
        for (final movement in snap.data!) {
          if (movement.type != MovementType.sale ||
              movement.quantityChange >= 0) {
            continue;
          }
          final key = movement.productId.isNotEmpty
              ? movement.productId
              : movement.productName.trim().toLowerCase();
          if (key.isEmpty) continue;
          final current = totals.putIfAbsent(
            key,
            () => SoldProductTotal(
              productId: movement.productId,
              name: movement.productName,
              quantity: 0,
            ),
          );
          current.quantity += movement.quantityChange.abs();
          _updateLastSold(current, movement.createdAt);
        }
        return _buildSummary(
          totals.values.toList(),
          productsById,
          canOpenHistory: false,
        );
      },
    );
  }

  void _updateLastSold(SoldProductTotal total, DateTime? date) {
    if (date != null &&
        (total.lastSoldAt == null || date.isAfter(total.lastSoldAt!))) {
      total.lastSoldAt = date;
    }
  }

  Widget _buildSummary(
    List<SoldProductTotal> soldProducts,
    Map<String, Product> productsById, {
    required bool canOpenHistory,
    double? totalSoldAmount,
    double? grossProfit,
    String? financialError,
  }) {
    final stockValue = widget.canViewStockValue
        ? productsById.values.fold<double>(
            0,
            (total, product) =>
                total +
                (product.tracked && product.quantity > 0
                    ? product.quantity * product.costPrice
                    : 0),
          )
        : null;
    final canShowProfit = widget.canViewStockValue && canOpenHistory;
    final profitUnavailable =
        canShowProfit && grossProfit == null && financialError == null;
    final rankedProducts = [...soldProducts];
    final soldProductIds = soldProducts
        .map((product) => product.productId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final soldProductNames = soldProducts
        .map((product) => product.name.toLowerCase())
        .toSet();
    for (final product in productsById.values) {
      final id = product.id;
      if (id == null ||
          soldProductIds.contains(id) ||
          soldProductNames.contains(product.name.toLowerCase())) {
        continue;
      }
      rankedProducts.add(
        SoldProductTotal(productId: id, name: product.name, quantity: 0),
      );
    }

    final mostSoldProducts = [...soldProducts]
      ..sort((a, b) {
        final byQuantity = b.quantity.compareTo(a.quantity);
        return byQuantity != 0
            ? byQuantity
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final leastSoldProducts = [...rankedProducts]
      ..sort((a, b) {
        final byQuantity = a.quantity.compareTo(b.quantity);
        return byQuantity != 0
            ? byQuantity
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final mostSold = mostSoldProducts.firstOrNull;
    final leastSold = leastSoldProducts.firstOrNull;

    switch (_sort) {
      case SoldProductsSort.newestSale:
        soldProducts.sort(_compareSaleDate);
        break;
      case SoldProductsSort.oldestSale:
        soldProducts.sort((a, b) => _compareSaleDate(a, b, newestFirst: false));
        break;
      case SoldProductsSort.mostSold:
        soldProducts.sort((a, b) => b.quantity.compareTo(a.quantity));
        break;
      case SoldProductsSort.leastSold:
        soldProducts.sort((a, b) => a.quantity.compareTo(b.quantity));
        break;
      case SoldProductsSort.name:
        soldProducts.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: MjasiColors.border),
            boxShadow: [
              BoxShadow(
                color: kStockNavy.withValues(alpha: .04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: StockCard(
            padding: const EdgeInsets.all(14),
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
                if (totalSoldAmount != null ||
                    stockValue != null ||
                    canShowProfit) ...[
                  const SizedBox(height: 12),
                  _financialSummary(
                    totalSoldAmount: totalSoldAmount,
                    stockValue: stockValue,
                    grossProfit: grossProfit,
                    showProfit: canShowProfit,
                  ),
                ],
                if (financialError != null || profitUnavailable) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        financialError == null
                            ? Icons.info_outline_rounded
                            : Icons.error_outline_rounded,
                        color: financialError == null
                            ? MjasiColors.textSecondary
                            : kStockBad,
                        size: 15,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          financialError ?? 'stk_profit_missing_cost_data'.tr,
                          style: TextStyle(
                            color: financialError == null
                                ? MjasiColors.textSecondary
                                : kStockBad,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    _salesRankTile(
                      title: 'stk_top_selling_product'.tr,
                      product: mostSold,
                      icon: Icons.trending_up_rounded,
                      color: kStockOk,
                      background: const Color(0xFFF0FAF5),
                    ),
                    const SizedBox(width: 8),
                    _salesRankTile(
                      title: 'stk_least_selling_product'.tr,
                      product: leastSold,
                      icon: Icons.trending_down_rounded,
                      color: kStockWarn,
                      background: const Color(0xFFFFF8E8),
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
                              _resetStreams();
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _salesDropdown<SoldProductsSort>(
                        label: 'stk_sort_by'.tr,
                        value: _sort,
                        items: {
                          SoldProductsSort.newestSale:
                              'stk_sort_newest_sale'.tr,
                          SoldProductsSort.oldestSale:
                              'stk_sort_oldest_sale'.tr,
                          SoldProductsSort.mostSold: 'stk_sort_most_sold'.tr,
                          SoldProductsSort.leastSold: 'stk_sort_least_sold'.tr,
                          SoldProductsSort.name: 'stk_sort_name'.tr,
                        },
                        onChanged: (value) {
                          if (value != null) setState(() => _sort = value);
                        },
                      ),
                    ),
                  ],
                ),
                if (!canOpenHistory) ...[
                  const SizedBox(height: 8),
                  Text(
                    'stk_sales_history_permission'.tr,
                    style: const TextStyle(
                      color: MjasiColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
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
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = soldProducts[index];
                final product = productsById[item.productId];
                final isTopSeller =
                    index == 0 && _sort == SoldProductsSort.mostSold;
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: MjasiColors.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: StockCard(
                      onTap: canOpenHistory && item.sales.isNotEmpty
                          ? () => Get.to(
                              () => ProductSalesHistoryPage(
                                productName: item.name,
                                productUnit: product?.unit ?? '',
                                days: _days,
                                sales: item.sales,
                              ),
                            )
                          : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isTopSeller
                                  ? const Color(0xFFFFF3D6)
                                  : kStockLight,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isTopSeller
                                  ? Icons.emoji_events_outlined
                                  : Icons.inventory_2_outlined,
                              color: isTopSeller ? kStockWarn : kStockBlue,
                              size: 19,
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
                                if (item.lastSoldAt != null) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    fmtText('stk_last_sold_at', {
                                      'date': formatDateTime(
                                        item.lastSoldAt!.toLocal(),
                                      ),
                                    }),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: MjasiColors.textSecondary,
                                      fontSize: 10,
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
                                  fontSize: 17,
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
                              if (item.revenue != null) ...[
                                const SizedBox(height: 3),
                                Text(
                                  'TZS ${formatMoney(item.revenue!)}',
                                  style: const TextStyle(
                                    color: kStockBlue,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'stk_sales_revenue'.tr,
                                  style: const TextStyle(
                                    color: MjasiColors.textSecondary,
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (canOpenHistory && item.sales.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: MjasiColors.textSecondary,
                              size: 19,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _financialSummary({
    required double? totalSoldAmount,
    required double? stockValue,
    required double? grossProfit,
    required bool showProfit,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (totalSoldAmount != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [kStockNavy, kStockBlue],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.payments_outlined,
                  color: Colors.white,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'stk_total_sold_amount'.tr,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .8),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'TZS ${formatMoney(totalSoldAmount)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      if (stockValue != null || showProfit) ...[
        if (totalSoldAmount != null) const SizedBox(height: 8),
        Row(
          children: [
            if (stockValue != null)
              Expanded(
                child: _financialMetric(
                  label: 'stk_total_stock_value'.tr,
                  amount: stockValue,
                  icon: Icons.inventory_2_outlined,
                  color: kStockBlue,
                ),
              ),
            if (stockValue != null && showProfit) const SizedBox(width: 8),
            if (showProfit)
              Expanded(
                child: _financialMetric(
                  label: 'stk_gross_profit'.tr,
                  amount: grossProfit,
                  icon: Icons.trending_up_rounded,
                  color: kStockOk,
                ),
              ),
          ],
        ),
      ],
    ],
  );

  Widget _financialMetric({
    required String label,
    required double? amount,
    required IconData icon,
    required Color color,
  }) => Container(
    constraints: const BoxConstraints(minHeight: 76),
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: color.withValues(alpha: .14)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        FittedBox(
          alignment: Alignment.centerLeft,
          fit: BoxFit.scaleDown,
          child: Text(
            amount == null ? '—' : 'TZS ${formatMoney(amount)}',
            style: const TextStyle(
              color: MjasiColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _salesRankTile({
    required String title,
    required SoldProductTotal? product,
    required IconData icon,
    required Color color,
    required Color background,
  }) => Expanded(
    child: Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            product?.name ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MjasiColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            product == null
                ? '—'
                : '${formatQty(product.quantity)} ${'stk_sold_quantity_label'.tr}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MjasiColors.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    ),
  );

  int _compareSaleDate(
    SoldProductTotal a,
    SoldProductTotal b, {
    bool newestFirst = true,
  }) {
    final aDate = a.lastSoldAt;
    final bDate = b.lastSoldAt;
    if (aDate == null) return bDate == null ? 0 : 1;
    if (bDate == null) return -1;
    return newestFirst ? bDate.compareTo(aDate) : aDate.compareTo(bDate);
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

class SoldProductTotal {
  SoldProductTotal({
    required this.productId,
    required this.name,
    required this.quantity,
    this.revenue,
  });

  final String productId;
  final String name;
  double quantity;
  double? revenue;
  DateTime? lastSoldAt;
  final List<ProductSaleRecord> sales = [];
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
    this.trailing,
  });

  final String title;
  final IconData icon;
  final List<({String label, IconData icon, VoidCallback onTap, bool primary})>
  actions;
  final int columns;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: MjasiColors.border),
      boxShadow: [
        BoxShadow(
          color: kStockNavy.withValues(alpha: .035),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 17, color: kStockBlue),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: MjasiColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (trailing != null) trailing!,
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
        actions: [
          IconButton(
            tooltip: 'stk_products'.tr,
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => Get.to(() => const ProductsPage()),
          ),
        ],
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
