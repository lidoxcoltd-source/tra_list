import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/services/business_access_service.dart';
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
            return StockMessage(icon: Icons.error_outline, color: kStockBad, text: stockErrorText(snap.error!));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final all = snap.data!.where((p) => p.active).toList();
          final tracked = all.where((p) => p.tracked).toList();
          final low = tracked.where((p) => p.stockState == StockState.low).toList();
          final out = tracked.where((p) => p.stockState == StockState.out).toList();
          final value = tracked.fold<double>(0, (s, p) => s + (p.quantity > 0 ? p.quantity * p.costPrice : 0));
          final attention = [...out, ...low];

          final stats = [
            StatTile(
              icon: Icons.inventory_2_outlined,
              label: 'stk_total_products'.tr,
              value: '${all.length}',
              onTap: () => Get.to(() => const ProductsPage()),
            ),
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
              onTap: () => Get.to(() => const ProductsPage(initialFilter: 'low')),
            ),
            StatTile(
              icon: Icons.remove_shopping_cart_outlined,
              label: 'stk_out_of_stock'.tr,
              value: '${out.length}',
              color: kStockBad,
              onTap: () => Get.to(() => const ProductsPage(initialFilter: 'out')),
            ),
          ];

          return LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 900 ? stats.length : 2;
              final w = (c.maxWidth - 32 - (cols - 1) * 12) / cols;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [for (final s in stats) SizedBox(width: w, child: s)],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (BusinessAccessService.can('invoices', 'create'))
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: kStockOk),
                          onPressed: () => Get.to(() => const PosPage()),
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text('pos_title'.tr),
                        ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: kStockBlue),
                        onPressed: () => Get.to(() => const ProductsPage()),
                        icon: const Icon(Icons.list_alt),
                        label: Text('stk_products'.tr),
                      ),
                      if (canCreate)
                        OutlinedButton.icon(
                          onPressed: () => Get.to(() => const ProductFormPage()),
                          icon: const Icon(Icons.add),
                          label: Text('stk_add_product'.tr),
                        ),
                      if (canCreate)
                        OutlinedButton.icon(
                          onPressed: () => Get.to(() => const ReceiveStockPage()),
                          icon: const Icon(Icons.add_box_outlined),
                          label: Text('stk_receive'.tr),
                        ),
                      if (canEdit)
                        OutlinedButton.icon(
                          onPressed: () => Get.to(() => const AdjustStockPage()),
                          icon: const Icon(Icons.tune),
                          label: Text('stk_adjust'.tr),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'stk_needs_attention'.tr,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: kStockNavy),
                  ),
                  const SizedBox(height: 8),
                  if (attention.isEmpty)
                    StockMessage(icon: Icons.check_circle_outline, color: kStockOk, text: 'stk_all_good'.tr)
                  else
                    for (final p in attention.take(10))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: StockCard(
                          onTap: () => Get.to(() => ProductDetailsPage(productId: p.id!)),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                              Text('${formatQty(p.quantity)} ${unitLabel(p.unit)}  '),
                              StockStateChip(product: p),
                            ],
                          ),
                        ),
                      ),
                  const SizedBox(height: 20),
                  Text(
                    'stk_recent'.tr,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: kStockNavy),
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<List<StockMovement>>(
                    stream: service.watchMovements(limit: 8),
                    builder: (context, ms) {
                      if (!ms.hasData || ms.data!.isEmpty) {
                        return StockMessage(icon: Icons.history, text: 'stk_no_movements'.tr);
                      }
                      return Column(children: [for (final m in ms.data!) MovementTile(movement: m)]);
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
          tabs: [Tab(text: 'stk_movements'.tr), Tab(text: 'stk_purchases'.tr)],
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
          return StockMessage(icon: Icons.error_outline, color: kStockBad, text: stockErrorText(snap.error!));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final q = _query.trim().toLowerCase();
        final list = snap.data!.where((m) {
          if (_type != null && m.type != _type) return false;
          final d = m.createdAt;
          if (_range != null && d != null) {
            if (d.isBefore(_range!.start) || d.isAfter(_range!.end.add(const Duration(days: 1)))) {
              return false;
            }
          }
          return q.isEmpty || m.productName.toLowerCase().contains(q) || m.reason.toLowerCase().contains(q);
        }).toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: stockInput('stk_search'.tr, icon: Icons.search_rounded),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<MovementType?>(
                    tooltip: 'stk_adjust_type'.tr,
                    icon: Icon(Icons.filter_list, color: _type == null ? null : kStockBlue),
                    onSelected: (v) => setState(() => _type = v),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: null, child: Text('stk_filter_all'.tr)),
                      for (final t in MovementType.values)
                        PopupMenuItem(value: t, child: Text(t.labelKey.tr)),
                    ],
                  ),
                  IconButton(
                    tooltip: 'stk_date'.tr,
                    icon: Icon(Icons.date_range, color: _range == null ? null : kStockBlue),
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
                  ? StockMessage(icon: Icons.history, text: 'stk_no_movements'.tr)
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [for (final m in list) MovementTile(movement: m)],
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
          return StockMessage(icon: Icons.error_outline, color: kStockBad, text: stockErrorText(snap.error!));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        if (snap.data!.isEmpty) {
          return StockMessage(icon: Icons.local_shipping_outlined, text: 'stk_no_purchases'.tr);
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
                              p.supplier.isEmpty ? 'stk_purchases'.tr : p.supplier,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (canSeeCost)
                            Text('TZS ${formatMoney(p.total)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        ],
                      ),
                      Text(
                        [formatDate(p.date), if (p.reference.isNotEmpty) p.reference].join(' · '),
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
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
