import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/theme/app_theme.dart';
import 'stock_models.dart';
import 'stock_media.dart';
import 'stock_service.dart';
import 'stock_ui.dart';

double _num(String s) => double.tryParse(s.trim().replaceAll(',', '')) ?? 0;

class _LineCtl {
  _LineCtl(this.product);
  final Product product;
  final qty = TextEditingController();
  late final cost = TextEditingController(
    text: product.costPrice > 0 ? formatQty(product.costPrice) : '',
  );
  void dispose() {
    qty.dispose();
    cost.dispose();
  }
}

class ReceiveStockPage extends StatefulWidget {
  const ReceiveStockPage({super.key, this.initialProductId});
  final String? initialProductId;

  @override
  State<ReceiveStockPage> createState() => _ReceiveStockPageState();
}

class _ReceiveStockPageState extends State<ReceiveStockPage> {
  final _service = StockService.current();
  final _supplier = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();
  final _lines = <_LineCtl>[];
  List<Product> _products = [];
  DateTime _date = DateTime.now();
  bool _expense = false;
  bool _saving = false;
  // Generated once per form so a retry after a timeout cannot double-receive.
  final String _purchaseId = StockService.current().products.doc().id;

  @override
  void initState() {
    super.initState();
    _service.watchProducts().first.then((list) {
      if (!mounted) return;
      _products = list;
      final id = widget.initialProductId;
      if (id != null) {
        final p = list.where((e) => e.id == id).firstOrNull;
        if (p != null) setState(() => _lines.add(_LineCtl(p)));
      }
    });
  }

  @override
  void dispose() {
    _supplier.dispose();
    _reference.dispose();
    _note.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  double get _total =>
      _lines.fold(0, (s, l) => s + _num(l.qty.text) * _num(l.cost.text));

  Future<void> _addLine() async {
    final p = await pickProduct(context, _products, trackedOnly: true);
    if (p == null) return;
    if (_lines.any((l) => l.product.id == p.id)) return;
    setState(() => _lines.add(_LineCtl(p)));
  }

  Future<void> _scanLine() async {
    final p = await scanForProduct(context, _products, trackedOnly: true);
    if (p == null) return;
    final existing = _lines.where((l) => l.product.id == p.id).firstOrNull;
    setState(() {
      if (existing == null) {
        _lines.add(_LineCtl(p)..qty.text = '1');
      } else {
        // Scanning the same item again adds one more.
        existing.qty.text = formatQty(_num(existing.qty.text) + 1);
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _service.receiveStock(
        purchaseId: _purchaseId,
        supplier: _supplier.text.trim(),
        reference: _reference.text.trim(),
        date: _date,
        note: _note.text.trim(),
        recordExpense: _expense,
        lines: [
          for (final l in _lines)
            PurchaseLine(
              productId: l.product.id!,
              productName: l.product.name,
              quantity: _num(l.qty.text),
              unitCost: _num(l.cost.text),
            ),
        ],
      );
      stockToast('stk_saved'.tr, 'stk_received_ok'.tr);
      Get.back();
    } catch (e) {
      stockToast('stk_error'.tr, stockErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dec = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    return StockScaffold(
      title: 'stk_receive'.tr,
      maxWidth: 900,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StockSectionHeading(title: 'stk_purchase_details'.tr),
          StockCard(
            child: Column(
              children: [
                TextField(
                  controller: _supplier,
                  decoration: stockInput(
                    'stk_supplier'.tr,
                    icon: Icons.local_shipping_outlined,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _reference,
                  decoration: stockInput(
                    'stk_reference'.tr,
                    icon: Icons.receipt_long_outlined,
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setState(() => _date = d);
                  },
                  child: InputDecorator(
                    decoration: stockInput('stk_date'.tr, icon: Icons.event),
                    child: Text(formatDate(_date)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          StockSectionHeading(title: 'stk_received_items'.tr),
          for (var i = 0; i < _lines.length; i++)
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
                            '${_lines[i].product.name} (${unitLabel(_lines[i].product.unit)})',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              setState(() => _lines.removeAt(i).dispose()),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _lines[i].qty,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: dec,
                            decoration: stockInput('stk_quantity'.tr),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _lines[i].cost,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: dec,
                            decoration: stockInput(
                              'stk_unit_cost'.tr,
                              suffix: 'TZS',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kStockNavy),
                onPressed: _scanLine,
                icon: const Icon(Icons.qr_code_scanner),
                label: Text('stk_scan'.tr),
              ),
              OutlinedButton.icon(
                onPressed: _addLine,
                icon: const Icon(Icons.add),
                label: Text('stk_add_line'.tr),
              ),
            ],
          ),
          const SizedBox(height: 12),
          StockCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _note,
                  decoration: stockInput('stk_note'.tr, icon: Icons.notes),
                ),
                if (BusinessAccessService.can('transactions', 'create'))
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('stk_record_expense'.tr),
                    value: _expense,
                    onChanged: (v) => setState(() => _expense = v),
                  ),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'stk_total'.tr,
                        style: const TextStyle(
                          color: MjasiColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      'TZS ${formatMoney(_total)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: kStockNavy,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: kStockBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _saving || _lines.isEmpty ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: Text('stk_confirm_receipt'.tr),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdjustStockPage extends StatefulWidget {
  const AdjustStockPage({super.key, this.productId});
  final String? productId;

  @override
  State<AdjustStockPage> createState() => _AdjustStockPageState();
}

class _AdjustStockPageState extends State<AdjustStockPage> {
  final _service = StockService.current();
  final _qty = TextEditingController();
  final _reason = TextEditingController();
  final _note = TextEditingController();
  List<Product> _products = [];
  Product? _product;
  MovementType _type = MovementType.adjustmentOut;
  bool _saving = false;
  final String _operationId = StockService.current().products.doc().id;

  @override
  void initState() {
    super.initState();
    _service.watchProducts().first.then((list) {
      if (!mounted) return;
      _products = list;
      final id = widget.productId;
      if (id != null)
        setState(() => _product = list.where((e) => e.id == id).firstOrNull);
    });
  }

  @override
  void dispose() {
    _qty.dispose();
    _reason.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final p = _product;
    if (p == null) return;
    setState(() => _saving = true);
    try {
      await _service.adjustStock(
        productId: p.id!,
        type: _type,
        quantity: _num(_qty.text),
        reason: _reason.text.trim(),
        note: _note.text.trim(),
        operationId: _operationId,
      );
      stockToast('stk_saved'.tr, p.name);
      Get.back();
    } catch (e) {
      stockToast('stk_error'.tr, stockErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;
    return StockScaffold(
      title: 'stk_adjust'.tr,
      maxWidth: 700,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StockSectionHeading(title: 'stk_adjustment_details'.tr),
          StockCard(
            child: Column(
              children: [
                InkWell(
                  onTap: () async {
                    final sel = await pickProduct(
                      context,
                      _products,
                      trackedOnly: true,
                    );
                    if (sel != null) setState(() => _product = sel);
                  },
                  child: InputDecorator(
                    decoration:
                        stockInput(
                          'stk_product'.tr,
                          icon: Icons.inventory_2_outlined,
                        ).copyWith(
                          suffixIcon: IconButton(
                            tooltip: 'stk_scan'.tr,
                            icon: const Icon(Icons.qr_code_scanner),
                            onPressed: () async {
                              final sel = await scanForProduct(
                                context,
                                _products,
                                trackedOnly: true,
                              );
                              if (sel != null) setState(() => _product = sel);
                            },
                          ),
                        ),
                    child: Text(
                      p == null
                          ? 'stk_select_product'.tr
                          : '${p.name} — ${formatQty(p.quantity)} ${unitLabel(p.unit)}',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<MovementType>(
                  initialValue: _type,
                  decoration: stockInput(
                    'stk_adjust_type'.tr,
                    icon: Icons.tune,
                  ),
                  items: [
                    for (final t in MovementType.manual)
                      DropdownMenuItem(value: t, child: Text(t.labelKey.tr)),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _qty,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: stockInput(
                    _type == MovementType.correction
                        ? 'stk_counted_qty'.tr
                        : 'stk_quantity'.tr,
                    icon: Icons.numbers,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _reason,
                  decoration: stockInput(
                    'stk_reason'.tr,
                    icon: Icons.help_outline,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  decoration: stockInput('stk_note'.tr, icon: Icons.notes),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: kStockBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _saving || p == null ? null : _save,
              icon: const Icon(Icons.check),
              label: Text('stk_save'.tr),
            ),
          ),
        ],
      ),
    );
  }
}
