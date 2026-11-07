import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/pdf/invoice_pdf.dart';
import 'package:tra_list/services/pdf/pdf_saver.dart' as pdf_saver;
import 'package:tra_list/services/profile_service.dart';
import 'stock_models.dart';
import 'stock_service.dart';
import 'stock_ui.dart';

class BarOrdersPage extends StatefulWidget {
  const BarOrdersPage({super.key});

  @override
  State<BarOrdersPage> createState() => _BarOrdersPageState();
}

class _BarOrdersPageState extends State<BarOrdersPage> {
  final _service = StockService.current();
  final _selected = <String>{};
  bool _busy = false;

  Future<void> _changeOrder(
    Map<String, dynamic> order, {
    required bool serve,
  }) async {
    final id = order['id'].toString();
    setState(() => _busy = true);
    try {
      if (serve) {
        await _service.serveBarOrder(id);
      } else {
        await _service.cancelBarOrder(id);
      }
      if (!mounted) return;
      setState(() => _selected.remove(id));
      stockToast(
        serve ? 'bar_order_served'.tr : 'bar_order_cancelled'.tr,
        order['tableNumber']?.toString() ?? '',
      );
    } catch (error) {
      if (mounted) {
        stockToast('stk_error'.tr, stockErrorText(error), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _settle(List<Map<String, dynamic>> orders) async {
    if (_busy || orders.isEmpty || BusinessAccessService.isBarBartender) return;
    final payment = await _choosePayment();
    if (payment == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final company = await ProfileService.loadOrCreate();
      final now = DateTime.now();
      String two(int value) => value.toString().padLeft(2, '0');
      final number =
          'BAR-${now.year % 100}${two(now.month)}${two(now.day)}-'
          '${two(now.hour)}${two(now.minute)}${two(now.second)}'
          '${now.millisecond.toString().padLeft(3, '0')}';
      final receipt = await _service.settleBarOrders(
        orderIds: orders.map((order) => order['id'].toString()).toList(),
        invoiceNumber: number,
        paymentMethod: payment,
        company: company,
      );
      if (!mounted) return;
      setState(() => _selected.clear());
      await _showReceipt(receipt, number);
    } catch (error) {
      if (mounted) {
        stockToast('stk_error'.tr, stockErrorText(error), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _choosePayment() {
    var method = 'cash';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('bar_choose_payment'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in const ['cash', 'mobile', 'card'])
                RadioListTile<String>(
                  value: option,
                  groupValue: method,
                  title: Text('pos_$option'.tr),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => method = value);
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('stk_cancel'.tr),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, method),
              child: Text('bar_settle'.tr),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showReceipt(Map<String, dynamic> receipt, String number) {
    var working = false;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: kStockOk),
              const SizedBox(width: 8),
              Expanded(child: Text('bar_bill_paid'.tr)),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: kStockNavy,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MEZA ${receipt['tableNumber'] ?? '—'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Muhudumu: ${receipt['waiterName']?.toString().isNotEmpty == true ? receipt['waiterName'] : '—'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        number,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      Text(
                        'TZS ${formatMoney((receipt['total'] as num?) ?? 0)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Receipt preview',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                SizedBox(
                  height: 420,
                  child: FutureBuilder<Uint8List>(
                    future: InvoicePdf.generateBytes(receipt),
                    builder: (context, snapshot) {
                      if (snapshot.hasError)
                        return Center(
                          child: Text(stockErrorText(snapshot.error!)),
                        );
                      if (!snapshot.hasData)
                        return const Center(child: CircularProgressIndicator());
                      return PdfPreview(
                        build: (_) async => snapshot.data!,
                        pdfFileName: 'Receipt_$number.pdf',
                        canChangePageFormat: false,
                        canChangeOrientation: false,
                        allowPrinting: false,
                        allowSharing: false,
                        maxPageWidth: 380,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: working
                  ? null
                  : () => _receiptAction(receipt, number, (busy) {
                      if (dialogContext.mounted) {
                        setDialogState(() => working = busy);
                      }
                    }, 'print'),
              icon: const Icon(Icons.print_outlined),
              label: Text('pos_print'.tr),
            ),
            TextButton.icon(
              onPressed: working
                  ? null
                  : () => _receiptAction(receipt, number, (busy) {
                      if (dialogContext.mounted) {
                        setDialogState(() => working = busy);
                      }
                    }, 'save'),
              icon: const Icon(Icons.download_outlined),
              label: Text('pos_save_receipt'.tr),
            ),
            TextButton.icon(
              onPressed: working
                  ? null
                  : () => _receiptAction(receipt, number, (busy) {
                      if (dialogContext.mounted) {
                        setDialogState(() => working = busy);
                      }
                    }, 'share'),
              icon: const Icon(Icons.share_outlined),
              label: Text('pos_share_receipt'.tr),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('stk_ok'.tr),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _receiptAction(
    Map<String, dynamic> receipt,
    String number,
    void Function(bool) setBusy,
    String action,
  ) async {
    setBusy(true);
    try {
      final bytes = await InvoicePdf.generateBytes(receipt);
      final fileName =
          'Receipt_${number.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}.pdf';
      if (action == 'print') {
        await Printing.layoutPdf(onLayout: (_) async => bytes);
      } else if (action == 'save') {
        await pdf_saver.savePdf(bytes, fileName);
        if (mounted) stockToast('pos_receipt_saved'.tr, fileName);
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                bytes,
                mimeType: 'application/pdf',
                name: fileName,
              ),
            ],
            fileNameOverrides: [fileName],
            title: number,
            subject: number,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        stockToast('stk_error'.tr, '$error', error: true);
      }
    } finally {
      setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    final isBarBartender = BusinessAccessService.isBarBartender;
    return StockScaffold(
      title: 'bar_orders'.tr,
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _service.watchBarOrders(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return StockMessage(
              icon: Icons.error_outline,
              color: kStockBad,
              text: stockErrorText(snapshot.error!),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final active = snapshot.data!
              .where(
                (order) =>
                    order['status'] == 'pending' || order['status'] == 'served',
              )
              .toList();
          if (active.isEmpty) {
            return StockMessage(
              icon: Icons.room_service_outlined,
              text: 'bar_no_orders'.tr,
            );
          }
          final selectedOrders = active
              .where(
                (order) => !isBarBartender && _selected.contains(order['id']),
              )
              .toList();
          return Column(
            children: [
              if (selectedOrders.isNotEmpty && !isBarBartender)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _settle(selectedOrders),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: Text(
                        '${'bar_settle'.tr} · '
                        'TZS ${formatMoney(selectedOrders.fold<double>(0, (sum, order) => sum + ((order['total'] as num?)?.toDouble() ?? 0)))}',
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: active.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _orderCard(active[index], selectedOrders),
                ),
              ),
            ],
          );
        },
      ),
    );
  });

  Widget _orderCard(
    Map<String, dynamic> order,
    List<Map<String, dynamic>> selectedOrders,
  ) {
    final id = order['id'].toString();
    final status = order['status']?.toString() ?? '';
    final isServed = status == 'served';
    final isOwner = BusinessAccessService.isOwner.value;
    final isWaiter = BusinessAccessService.isBarWaiter;
    final isBartender = BusinessAccessService.isBarBartender;
    final isOrderCreator =
        order['createdBy'] == FirebaseAuth.instance.currentUser?.uid;
    final canApprove = isOwner || isWaiter;
    final canCancel = isOwner || isWaiter || (isBartender && isOrderCreator);
    final isSelected = _selected.contains(id);
    final selectedTable = selectedOrders.isEmpty
        ? ''
        : selectedOrders.first['tableNumber']?.toString() ?? '';
    final table = order['tableNumber']?.toString() ?? '';
    final attendant =
        (order['servedByName']?.toString().trim().isNotEmpty ?? false)
        ? order['servedByName'].toString()
        : (order['createdByName']?.toString() ?? '');
    final selectable =
        isServed && (selectedOrders.isEmpty || selectedTable == table);
    final items = (order['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final createdAt = order['createdAt'];
    final createdText = createdAt is Timestamp
        ? createdAt.toDate().toLocal().toString().substring(0, 16)
        : '';
    return StockCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [kStockNavy, Color(0xFF244A70)],
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                if (isServed && !BusinessAccessService.isBarBartender)
                  Checkbox(
                    value: isSelected,
                    activeColor: Colors.white,
                    checkColor: kStockNavy,
                    onChanged: !selectable && !isSelected
                        ? null
                        : (value) => setState(() {
                            if (value == true) {
                              _selected.add(id);
                            } else {
                              _selected.remove(id);
                            }
                          }),
                  )
                else
                  Icon(
                    isServed
                        ? Icons.check_circle_outline
                        : Icons.pending_actions_outlined,
                    color: Colors.white,
                    size: 27,
                  ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MEZA',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .72),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        table.isEmpty ? '—' : table,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    (isServed ? 'bar_status_served' : 'bar_status_pending').tr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if ((order['customerName']?.toString() ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 11),
              child: _detailLine(
                Icons.person_outline,
                'Mteja',
                order['customerName'].toString(),
              ),
            ),
          if (attendant.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: _detailLine(
                Icons.room_service_outlined,
                isServed ? 'Amethibitisha' : 'Aliyeingiza oda',
                attendant,
                prominent: true,
              ),
            ),
          if (createdText.isNotEmpty)
            Text(
              createdText,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          const Divider(height: 16),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${formatQty((item['quantity'] as num?) ?? 0)} '
                      '${unitLabel(item['unit']?.toString() ?? '')} '
                      '${item['name'] ?? ''}',
                    ),
                  ),
                  Text(
                    'TZS ${formatMoney((item['amount'] as num?) ?? 0)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'TZS ${formatMoney((order['total'] as num?) ?? 0)}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: kStockNavy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (!isServed && canCancel)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _changeOrder(order, serve: false),
                  child: Text('stk_cancel'.tr),
                ),
              if (!isServed && canApprove) ...[
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _changeOrder(order, serve: true),
                  child: Text('bar_mark_served'.tr),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailLine(
    IconData icon,
    String label,
    String value, {
    bool prominent = false,
  }) => Row(
    children: [
      Icon(
        icon,
        size: prominent ? 19 : 16,
        color: prominent ? kStockBlue : Colors.black54,
      ),
      const SizedBox(width: 7),
      Text(
        '$label: ',
        style: TextStyle(fontSize: prominent ? 13 : 12, color: Colors.black54),
      ),
      Expanded(
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: prominent ? 15 : 13,
            fontWeight: prominent ? FontWeight.w800 : FontWeight.w500,
            color: kStockNavy,
          ),
        ),
      ),
    ],
  );
}
