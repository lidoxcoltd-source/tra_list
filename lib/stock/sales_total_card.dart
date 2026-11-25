import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'stock_models.dart';
import 'stock_service.dart';
import 'stock_ui.dart';

enum _SalesTotalPeriod { today, thisWeek, thisMonth }

class StockSalesTotalCard extends StatefulWidget {
  const StockSalesTotalCard({
    super.key,
    required this.service,
    required this.canViewSales,
  });

  final StockService service;
  final bool canViewSales;

  @override
  State<StockSalesTotalCard> createState() => _StockSalesTotalCardState();
}

class _StockSalesTotalCardState extends State<StockSalesTotalCard> {
  _SalesTotalPeriod _period = _SalesTotalPeriod.today;
  Stream<List<ProductSaleRecord>>? _sales;
  Timer? _dayBoundaryTimer;

  @override
  void initState() {
    super.initState();
    _watchSales();
    _scheduleDayBoundaryRefresh();
  }

  @override
  void dispose() {
    _dayBoundaryTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StockSalesTotalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service ||
        oldWidget.canViewSales != widget.canViewSales) {
      _watchSales();
    }
  }

  void _watchSales() {
    _sales = widget.canViewSales
        ? widget.service.watchProductSalesSince(_periodStart())
        : null;
  }

  void _scheduleDayBoundaryRefresh() {
    _dayBoundaryTimer?.cancel();
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _dayBoundaryTimer = Timer(tomorrow.difference(now), () {
      if (!mounted) return;
      setState(_watchSales);
      _scheduleDayBoundaryRefresh();
    });
  }

  DateTime _periodStart() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      _SalesTotalPeriod.today => today,
      _SalesTotalPeriod.thisWeek => today.subtract(
        Duration(days: today.weekday - DateTime.monday),
      ),
      _SalesTotalPeriod.thisMonth => DateTime(now.year, now.month),
    };
  }

  String get _periodLabel => switch (_period) {
    _SalesTotalPeriod.today => 'stk_sales_today'.tr,
    _SalesTotalPeriod.thisWeek => 'stk_sales_this_week'.tr,
    _SalesTotalPeriod.thisMonth => 'stk_sales_this_month'.tr,
  };

  Widget _card({required Widget child}) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: kStockNavy.withValues(alpha: .18),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kStockNavy, kStockBlue],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -54,
              right: -32,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .06),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              right: 74,
              bottom: -96,
              child: Container(
                width: 142,
                height: 142,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .045),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Padding(padding: const EdgeInsets.all(16), child: child),
          ],
        ),
      ),
    ),
  );

  Widget _heading({double? total, bool loading = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.point_of_sale_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'stk_total_sales'.tr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _periodLabel,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .75),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      if (loading)
        const Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 25,
            height: 25,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        )
      else
        FittedBox(
          alignment: Alignment.centerLeft,
          fit: BoxFit.scaleDown,
          child: Text(
            total == null ? '—' : 'TZS ${formatMoney(total)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -.5,
            ),
          ),
        ),
    ],
  );

  Widget _periodPicker() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: .12)),
    ),
    child: DropdownButton<_SalesTotalPeriod>(
      value: _period,
      isDense: true,
      underline: const SizedBox.shrink(),
      dropdownColor: Colors.white,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
      icon: const Icon(
        Icons.keyboard_arrow_down_rounded,
        color: Colors.white,
        size: 19,
      ),
      items: [
        DropdownMenuItem(
          value: _SalesTotalPeriod.today,
          child: Text(
            'stk_sales_today'.tr,
            style: const TextStyle(color: kStockNavy),
          ),
        ),
        DropdownMenuItem(
          value: _SalesTotalPeriod.thisWeek,
          child: Text(
            'stk_sales_this_week'.tr,
            style: const TextStyle(color: kStockNavy),
          ),
        ),
        DropdownMenuItem(
          value: _SalesTotalPeriod.thisMonth,
          child: Text(
            'stk_sales_this_month'.tr,
            style: const TextStyle(color: kStockNavy),
          ),
        ),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _period = value;
          _watchSales();
        });
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_sales == null) {
      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading(),
            const SizedBox(height: 8),
            Text(
              'stk_sales_total_permission'.tr,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .78),
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<List<ProductSaleRecord>>(
      stream: _sales,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _heading(),
                const SizedBox(height: 8),
                Text(
                  stockErrorText(snapshot.error!),
                  style: const TextStyle(
                    color: Color(0xFFFFD1D1),
                    fontSize: 11,
                  ),
                ),
                Align(alignment: Alignment.centerRight, child: _periodPicker()),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _heading(loading: true),
                Align(alignment: Alignment.centerRight, child: _periodPicker()),
              ],
            ),
          );
        }

        final sales = snapshot.data!;
        final total = sales.fold<double>(0, (sum, sale) => sum + sale.amount);
        final invoiceCount = sales.map((sale) => sale.invoiceId).toSet().length;

        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _heading(total: total),
              const SizedBox(height: 12),
              Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .12),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 15,
                            color: Colors.white.withValues(alpha: .82),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'stk_sales_total_count'.trParams({
                                'count': '$invoiceCount',
                              }),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  _periodPicker(),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
