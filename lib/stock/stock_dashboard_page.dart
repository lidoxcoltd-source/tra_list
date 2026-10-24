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

class StockDashboardPage extends StatelessWidget {
  const StockDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = StockService.current();
    final canCreate = BusinessAccessService.can('stock', 'create');
    final canEdit = BusinessAccessService.can('stock', 'edit');
    return StockScaffold(
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
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
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
            (s, p) => s + (p.quantity > 0 ? p.quantity * p.costPrice : 0),
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

          return LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 1000 ? stats.length : 2;
              final w = (c.maxWidth - (cols - 1) * 12) / cols;
              final quickActions =
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

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: kStockNavy,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1A071B3A),
                          blurRadius: 16,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.inventory_2_outlined,
                            color: Colors.white,
                            size: 23,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'stk_total_products'.tr,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .72),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${all.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'stk_products'.tr,
                          style: IconButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.white.withValues(
                              alpha: .12,
                            ),
                          ),
                          onPressed: () => Get.to(() => const ProductsPage()),
                          icon: const Icon(Icons.arrow_forward_rounded),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final s in stats) SizedBox(width: w, child: s),
                    ],
                  ),
                  const SizedBox(height: 16),
                  StockSectionHeading(title: 'home_quick_access'.tr),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final action in quickActions)
                        SizedBox(
                          width: w,
                          child: _StockQuickAction(
                            label: action.label,
                            icon: action.icon,
                            primary: action.primary,
                            onTap: action.onTap,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  StockSectionHeading(title: 'stk_needs_attention'.tr),
                  if (attention.isEmpty)
                    StockMessage(
                      icon: Icons.check_circle_outline,
                      color: kStockOk,
                      text: 'stk_all_good'.tr,
                    )
                  else
                    for (final p in attention.take(10))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: StockCard(
                          onTap: () => Get.to(
                            () => ProductDetailsPage(productId: p.id!),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                '${formatQty(p.quantity)} ${unitLabel(p.unit)}  ',
                              ),
                              StockStateChip(product: p),
                            ],
                          ),
                        ),
                      ),
                  const SizedBox(height: 20),
                  StockSectionHeading(title: 'stk_recent'.tr),
                  StreamBuilder<List<StockMovement>>(
                    stream: service.watchMovements(limit: 8),
                    builder: (context, ms) {
                      if (!ms.hasData || ms.data!.isEmpty) {
                        return StockMessage(
                          icon: Icons.history,
                          text: 'stk_no_movements'.tr,
                        );
                      }
                      return Column(
                        children: [
                          for (final m in ms.data!) MovementTile(movement: m),
                        ],
                      );
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
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
      color: primary ? kStockBlue : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: primary ? kStockBlue : MjasiColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: foreground, size: 19),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12,
                    height: 1.15,
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
