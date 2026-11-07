import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/stock/stock_service.dart';

enum _SalesSort { amount, orders, name }

class BarSalesLiveSummary extends StatefulWidget {
  const BarSalesLiveSummary({super.key});

  @override
  State<BarSalesLiveSummary> createState() => _BarSalesLiveSummaryState();
}

class _BarSalesLiveSummaryState extends State<BarSalesLiveSummary> {
  _SalesSort _sort = _SalesSort.amount;
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    if (!BusinessAccessService.barModeEnabled.value ||
        !BusinessAccessService.canUseBarPos) {
      return const SizedBox.shrink();
    }
    final start = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: StockService.current().watchBarOrders(),
      builder: (context, ordersSnapshot) {
        if (ordersSnapshot.hasError) return _errorCard();
        final staff = <String, _BarStaffSales>{};
        var total = 0.0;
        var orderCount = 0;
        var units = 0.0;
        final orders = ordersSnapshot.data ?? const [];
        for (final order in orders) {
          final status = order['status']?.toString();
          if (status != 'served' && status != 'paid') continue;
          if (!_isOnDate(
            order['servedAt'] ?? order['paidAt'] ?? order['createdAt'],
            start,
          )) {
            continue;
          }
          final value = (order['total'] as num?)?.toDouble() ?? 0;
          final lines = order['items'] as List? ?? const [];
          final quantity = lines.whereType<Map>().fold<double>(
            0,
            (sum, line) => sum + ((line['quantity'] as num?)?.toDouble() ?? 0),
          );
          total += value;
          orderCount++;
          units += quantity;
          _addStaff(
            staff,
            uid: order['createdBy']?.toString() ?? '',
            name: order['createdByName']?.toString() ?? 'Mhudumu',
            value: value,
            quantity: quantity,
            category: 'Oda zilizowekwa',
            includeStaff: true,
            currentUid: userId,
          );
          final servedBy = order['servedBy']?.toString() ?? '';
          if (servedBy.isNotEmpty && servedBy != order['createdBy']) {
            _addStaff(
              staff,
              uid: servedBy,
              name: order['servedByName']?.toString() ?? 'Waiter',
              value: value,
              quantity: quantity,
              category: 'Oda zilizothibitishwa',
              includeStaff: true,
              currentUid: userId,
            );
          }
        }
        final rows = staff.values.toList()..sort(_compare);
        return _card(
          rows: rows,
          total: total,
          orderCount: orderCount,
          units: units,
          loading: !ordersSnapshot.hasData,
          selectedDate: start,
        );
      },
    );
  }

  bool _isOnDate(Object? value, DateTime selectedDate) {
    final date = value is Timestamp ? value.toDate() : null;
    return date != null &&
        date.year == selectedDate.year &&
        date.month == selectedDate.month &&
        date.day == selectedDate.day;
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(now) ? now : _selectedDate,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      helpText: 'Chagua tarehe ya mauzo',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: const Color(0xFF16855B),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedDate = picked);
  }

  String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  void _addStaff(
    Map<String, _BarStaffSales> staff, {
    required String uid,
    required String name,
    required double value,
    required double quantity,
    required String category,
    required bool includeStaff,
    required String currentUid,
  }) {
    if (uid.isEmpty || (!includeStaff && uid != currentUid)) return;
    final row = staff.putIfAbsent(uid, () => _BarStaffSales(uid, name));
    row.amount += value;
    row.quantity += quantity;
    row.orders++;
    row.categories.add(category);
  }

  int _compare(_BarStaffSales a, _BarStaffSales b) => switch (_sort) {
    _SalesSort.amount => b.amount.compareTo(a.amount),
    _SalesSort.orders => b.orders.compareTo(a.orders),
    _SalesSort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  };

  Widget _card({
    required List<_BarStaffSales> rows,
    required double total,
    required int orderCount,
    required double units,
    required bool loading,
    required DateTime selectedDate,
  }) {
    String money(num value) => value.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x0C10233F), blurRadius: 14, offset: Offset(0, 5)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: const Color(0xFFE9F7F1), borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.point_of_sale_rounded, color: Color(0xFF16855B)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text('Mauzo ya bar', style: const TextStyle(color: Color(0xFF152A45), fontSize: 15, fontWeight: FontWeight.w800))),
          const Icon(Icons.circle, size: 9, color: Color(0xFF19A974)),
          const SizedBox(width: 4),
          const Text('LIVE', style: TextStyle(color: Color(0xFF16855B), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .8)),
          PopupMenuButton<_SalesSort>(
            tooltip: 'Panga wafanyakazi',
            icon: const Icon(Icons.sort_rounded, color: Color(0xFF51647C)),
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _SalesSort.amount, child: Text('Panga kwa kiasi')),
              PopupMenuItem(value: _SalesSort.orders, child: Text('Panga kwa oda')),
              PopupMenuItem(value: _SalesSort.name, child: Text('Panga kwa jina')),
            ],
          ),
        ]),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _selectDate,
            icon: const Icon(Icons.calendar_month_rounded, size: 17),
            label: Text(_dateLabel(selectedDate)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF315B9B),
              side: const BorderSide(color: Color(0xFFDCE5F0)),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFF10233F), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('JUMLA YA MAUZO', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .8)),
              const SizedBox(height: 4),
              Text('TZS ${money(total)}', style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$orderCount oda / mauzo', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('${units.toStringAsFixed(units == units.roundToDouble() ? 0 : 1)} bidhaa', style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          const Expanded(child: Text('MAUZO KWA MFANYAKAZI', style: TextStyle(color: Color(0xFF718096), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .7))),
          if (loading) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: 5),
        if (rows.isEmpty && !loading)
          Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('Hakuna mauzo yaliyothibitishwa tarehe ${_dateLabel(selectedDate)}.', style: const TextStyle(color: Color(0xFF718096), fontSize: 12)))
        else
          for (final row in rows) _staffRow(row, money),
      ]),
    );
  }

  Widget _staffRow(_BarStaffSales staff, String Function(num) money) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      CircleAvatar(
        radius: 19,
        backgroundColor: const Color(0xFFE9F0FC),
        child: Text(_initials(staff.name), style: const TextStyle(color: Color(0xFF315B9B), fontSize: 11, fontWeight: FontWeight.w800)),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(staff.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF24364D), fontSize: 12, fontWeight: FontWeight.w800)),
        Text('${staff.orders} mauzo · ${staff.quantity.toStringAsFixed(staff.quantity == staff.quantity.roundToDouble() ? 0 : 1)} bidhaa · ${staff.categories.join(', ')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF718096), fontSize: 10)),
      ])),
      const SizedBox(width: 6),
      Text('TZS ${money(staff.amount)}', style: const TextStyle(color: Color(0xFF16855B), fontSize: 12, fontWeight: FontWeight.w900)),
    ]),
  );

  Widget _errorCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: const Color(0xFFFFF1F1), borderRadius: BorderRadius.circular(14)),
    child: const Text('Imeshindikana kupakia rekodi za mauzo ya bar.', style: TextStyle(color: Color(0xFFB42336), fontSize: 12)),
  );

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    final initials = parts.take(2).map((part) => String.fromCharCode(part.runes.first).toUpperCase()).join();
    return initials.isEmpty ? '?' : initials;
  }
}

class _BarStaffSales {
  _BarStaffSales(this.uid, this.name);
  final String uid;
  final String name;
  double amount = 0;
  double quantity = 0;
  int orders = 0;
  final Set<String> categories = {};
}
