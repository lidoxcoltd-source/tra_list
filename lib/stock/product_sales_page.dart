import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/theme/app_theme.dart';

import 'stock_models.dart';
import 'stock_ui.dart';

enum _SaleHistorySort { newestFirst, oldestFirst }

class ProductSalesHistoryPage extends StatefulWidget {
  const ProductSalesHistoryPage({
    super.key,
    required this.productName,
    required this.productUnit,
    required this.days,
    required this.sales,
  });

  final String productName;
  final String productUnit;
  final int days;
  final List<ProductSaleRecord> sales;

  @override
  State<ProductSalesHistoryPage> createState() =>
      _ProductSalesHistoryPageState();
}

class _ProductSalesHistoryPageState extends State<ProductSalesHistoryPage> {
  _SaleHistorySort _sort = _SaleHistorySort.newestFirst;

  @override
  Widget build(BuildContext context) {
    final sales = [...widget.sales]
      ..sort((a, b) {
        final aDate = a.createdAt;
        final bDate = b.createdAt;
        if (aDate == null) return bDate == null ? 0 : 1;
        if (bDate == null) return -1;
        return _sort == _SaleHistorySort.newestFirst
            ? bDate.compareTo(aDate)
            : aDate.compareTo(bDate);
      });
    final total = sales.fold<double>(0, (sum, sale) => sum + sale.amount);

    return StockScaffold(
      title: widget.productName,
      maxWidth: 820,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StockCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'stk_sales_history'.tr,
                    style: const TextStyle(
                      color: MjasiColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    fmtText('stk_sales_history_summary', {
                      'count': '${sales.length}',
                      'amount': formatMoney(total),
                    }),
                    style: const TextStyle(
                      color: MjasiColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'stk_last_days'.trParams({'days': '${widget.days}'}),
                    style: const TextStyle(
                      color: MjasiColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: stockInput('stk_sort_by'.tr),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<_SaleHistorySort>(
                  value: _sort,
                  isExpanded: true,
                  isDense: true,
                  items: [
                    DropdownMenuItem(
                      value: _SaleHistorySort.newestFirst,
                      child: Text('stk_sort_newest_sale'.tr),
                    ),
                    DropdownMenuItem(
                      value: _SaleHistorySort.oldestFirst,
                      child: Text('stk_sort_oldest_sale'.tr),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _sort = value);
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (sales.isEmpty)
              Expanded(
                child: StockMessage(
                  icon: Icons.receipt_long_outlined,
                  text: 'stk_no_product_sales'.tr,
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: sales.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final sale = sales[index];
                    final quantity = formatQty(sale.quantity);
                    final unit = widget.productUnit.isEmpty
                        ? ''
                        : ' ${unitLabel(widget.productUnit)}';
                    final placedAt = sale.createdAt == null
                        ? null
                        : formatDateTime(sale.createdAt!.toLocal());

                    return StockCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.receipt_long_outlined,
                                color: kStockBlue,
                                size: 19,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  fmtText('stk_sale_receipt', {
                                    'number': sale.invoiceNumber,
                                  }),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: MjasiColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (placedAt != null) ...[
                            const SizedBox(height: 5),
                            Text(
                              fmtText('stk_sale_placed_at', {'date': placedAt}),
                              style: const TextStyle(
                                color: MjasiColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                          if (sale.customerName.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              fmtText('stk_sale_customer', {
                                'name': sale.customerName,
                              }),
                              style: const TextStyle(
                                color: MjasiColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                          const Divider(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  fmtText('stk_sale_quantity', {
                                    'quantity': '$quantity$unit',
                                  }),
                                  style: const TextStyle(
                                    color: MjasiColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Text(
                                'TZS ${formatMoney(sale.amount)}',
                                style: const TextStyle(
                                  color: MjasiColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            fmtText('stk_sale_unit_price', {
                              'price': formatMoney(sale.unitPrice),
                            }),
                            style: const TextStyle(
                              color: MjasiColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
