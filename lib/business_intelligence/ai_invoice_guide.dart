import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:tra_list/business_intelligence/ai_document_draft.dart';
import 'package:tra_list/stock/stock_models.dart';

enum _Step {
  customer,
  name,
  number,
  issue,
  due,
  item,
  quantity,
  price,
  more,
  terms,
  summary,
}

String formatAiInvoiceSummary(AiDocumentDraft draft) {
  final format = NumberFormat('#,##0.####');
  final total = draft.invoiceItems.fold<double>(
    0,
    (sum, item) => sum + item.quantity * item.unitPrice,
  );
  String date(DateTime? value) => value == null
      ? 'bi_invoice_summary_default_date'.tr
      : '${value.day}/${value.month}/${value.year}';
  return [
    '${'bi_invoice_summary_customer'.tr}: ${draft.customer}',
    '${'bi_invoice_summary_name'.tr}: ${draft.invoiceName ?? '-'}',
    '${'bi_invoice_summary_number'.tr}: ${draft.invoiceNumber ?? 'bi_invoice_summary_auto'.tr}',
    '${'bi_invoice_summary_issue'.tr}: ${date(draft.issueDate)}',
    '${'bi_invoice_summary_due'.tr}: ${date(draft.dueDate)}',
    for (final item in draft.invoiceItems)
      '${item.description} (${(item.productId == null ? 'bi_invoice_manual_item' : 'bi_invoice_stock_item').tr}): ${format.format(item.quantity)} × ${format.format(item.unitPrice)} = ${format.format(item.quantity * item.unitPrice)}',
    '${'bi_invoice_summary_total'.tr}: TZS ${format.format(total)}',
    '${'bi_invoice_summary_terms'.tr}: ${draft.terms ?? '-'}',
    'bi_invoice_stock_effect'.tr,
  ].join('\n');
}

class AiInvoiceGuide extends StatefulWidget {
  const AiInvoiceGuide({
    super.key,
    required this.onCancel,
    required this.onComplete,
    required this.enabled,
    this.pickStock,
  });

  final VoidCallback onCancel;
  final void Function(AiDocumentDraft draft) onComplete;
  final bool enabled;
  final Future<Product?> Function()? pickStock;

  @override
  State<AiInvoiceGuide> createState() => _AiInvoiceGuideState();
}

class _AiInvoiceGuideState extends State<AiInvoiceGuide> {
  final _input = TextEditingController();
  final _items = <AiInvoiceItem>[];
  _Step _step = _Step.customer;
  String? _customer, _name, _number, _description, _error;
  DateTime? _issue, _due;
  double? _quantity;
  AiDocumentDraft? _draft;
  Product? _product;
  bool _picking = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  bool get _optional => {
    _Step.name,
    _Step.number,
    _Step.issue,
    _Step.due,
    _Step.terms,
  }.contains(_step);

  DateTime? _parseDate(String text) {
    final match = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(text);
    if (match == null) return null;
    final day = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final year = int.parse(match[3]!);
    if (year < 2020 || year > 2100) return null;
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  double? _parseNumber(String text, {required bool allowZero}) {
    if (!RegExp(r'^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$').hasMatch(text)) {
      return null;
    }
    final value = double.tryParse(text.replaceAll(',', ''));
    if (value == null ||
        !value.isFinite ||
        value > 1000000000000 ||
        (allowZero ? value < 0 : value <= 0)) {
      return null;
    }
    return value;
  }

  void _next({bool skip = false}) {
    if (!widget.enabled || _picking) return;
    final value = skip ? '' : _input.text.trim();
    if (value.isEmpty && !skip ||
        skip && !_optional ||
        value.length > (_step == _Step.name ? 32 : 300)) {
      setState(() => _error = 'bi_invoice_guide_invalid'.tr);
      return;
    }
    _Step next;
    switch (_step) {
      case _Step.customer:
        _customer = value;
        next = _Step.name;
      case _Step.name:
        _name = value.isEmpty ? null : value;
        next = _Step.number;
      case _Step.number:
        _number = value.isEmpty ? null : value;
        next = _Step.issue;
      case _Step.issue:
      case _Step.due:
        final date = value.isEmpty ? null : _parseDate(value);
        if (value.isNotEmpty && date == null) {
          setState(() => _error = 'bi_invoice_guide_date_invalid'.tr);
          return;
        }
        if (_step == _Step.issue) {
          _issue = date;
          next = _Step.due;
        } else {
          _due = date;
          next = _Step.item;
        }
      case _Step.item:
        _description = value;
        if (_product?.name != value) _product = null;
        next = _Step.quantity;
      case _Step.quantity:
        final number = _parseNumber(value, allowZero: false);
        if (number == null) {
          setState(() => _error = 'bi_invoice_guide_number_invalid'.tr);
          return;
        }
        _quantity = number;
        next = _Step.price;
      case _Step.price:
        final price = _parseNumber(value, allowZero: true);
        if (price == null) {
          setState(() => _error = 'bi_invoice_guide_number_invalid'.tr);
          return;
        }
        _items.add(
          AiInvoiceItem(
            description: _description!,
            quantity: _quantity!,
            unitPrice: price,
            productId: _product?.id,
          ),
        );
        _product = null;
        next = _Step.more;
      case _Step.more:
        return;
      case _Step.terms:
        final now = DateTime.now();
        _draft = AiDocumentDraft(
          kind: AiDocumentKind.invoice,
          customer: _customer,
          invoiceName: _name,
          invoiceNumber: _number,
          issueDate: _issue ?? DateTime(now.year, now.month, now.day),
          dueDate: _due ?? DateTime(now.year, now.month, now.day),
          terms: value.isEmpty ? null : value,
          invoiceItems: List.unmodifiable(_items),
        );
        next = _Step.summary;
      case _Step.summary:
        return;
    }
    _input.clear();
    setState(() {
      _error = null;
      _step = next;
    });
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Card(
        color: const Color(0xFF25213D),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'bi_invoice_guide_title'.tr,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'bi_invoice_guide_${_step.name}'.tr,
                style: const TextStyle(color: Colors.white),
              ),
              if (_step == _Step.summary) ...[
                const SizedBox(height: 8),
                _summary(),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: widget.enabled
                      ? () => widget.onComplete(_draft!)
                      : null,
                  child: Text('bi_invoice_save'.tr),
                ),
                TextField(
                  controller: _input,
                  enabled: widget.enabled && !_picking,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white,
                  onSubmitted: (value) {
                    if (widget.enabled &&
                        {
                          'save',
                          'hifadhi',
                        }.contains(value.trim().toLowerCase())) {
                      widget.onComplete(_draft!);
                    } else {
                      setState(() => _error = 'bi_invoice_save_instruction'.tr);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'bi_invoice_save_instruction'.tr,
                    labelStyle: const TextStyle(color: Colors.white70),
                    errorText: _error,
                    errorStyle: const TextStyle(color: Color(0xFFFFB4AB)),
                    filled: true,
                    fillColor: const Color(0xFF19162C),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ] else if (_step == _Step.more) ...[
                const SizedBox(height: 8),
                Text(
                  'bi_invoice_guide_item_count'.trParams({
                    'count': '${_items.length}',
                  }),
                  style: const TextStyle(color: Colors.white70),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    if (_items.length < 30)
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFDACFFF),
                        ),
                        onPressed: widget.enabled && !_picking
                            ? () => setState(() => _step = _Step.item)
                            : null,
                        child: Text('bi_invoice_guide_add'.tr),
                      ),
                    FilledButton(
                      onPressed: widget.enabled
                          ? () => setState(() => _step = _Step.terms)
                          : null,
                      child: Text('bi_invoice_guide_done'.tr),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 8),
                if (_step == _Step.item && widget.pickStock != null)
                  TextButton.icon(
                    onPressed: !widget.enabled || _picking
                        ? null
                        : () async {
                            setState(() => _picking = true);
                            try {
                              final product = await widget.pickStock!();
                              if (!mounted ||
                                  !widget.enabled ||
                                  product == null) {
                                return;
                              }
                              if (product.id == null ||
                                  product.name.trim().isEmpty ||
                                  !product.tracked) {
                                setState(
                                  () => _error = 'bi_invoice_stock_invalid'.tr,
                                );
                                return;
                              }
                              setState(() {
                                _product = product;
                                _input.text = product.name;
                                _error = null;
                              });
                            } finally {
                              if (mounted) setState(() => _picking = false);
                            }
                          },
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: Text('bi_invoice_choose_stock'.tr),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFDACFFF),
                    ),
                  ),
                if (_step == _Step.item && _product != null)
                  Text(
                    'bi_invoice_stock_selected'.tr,
                    style: const TextStyle(color: Colors.white70),
                  ),
                TextField(
                  controller: _input,
                  enabled: widget.enabled && !_picking,
                  maxLength: _step == _Step.name ? 32 : 300,
                  keyboardType: _step == _Step.quantity || _step == _Step.price
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.text,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white,
                  onChanged: (value) {
                    if (_step == _Step.item &&
                        _product != null &&
                        value != _product!.name) {
                      setState(() => _product = null);
                    }
                  },
                  onSubmitted: (_) => _next(),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF19162C),
                    counterText: '',
                    errorText: _error,
                    errorStyle: const TextStyle(color: Color(0xFFFFB4AB)),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    if (_optional)
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFDACFFF),
                        ),
                        onPressed: widget.enabled
                            ? () => _next(skip: true)
                            : null,
                        child: Text('bi_invoice_guide_skip'.tr),
                      ),
                    FilledButton(
                      onPressed: widget.enabled && !_picking ? _next : null,
                      child: Text(
                        (_step == _Step.terms
                                ? 'bi_invoice_guide_open'
                                : 'bi_invoice_guide_next')
                            .tr,
                      ),
                    ),
                  ],
                ),
              ],
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFDACFFF),
                ),
                onPressed: widget.enabled && !_picking ? widget.onCancel : null,
                child: Text('cancel'.tr),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _summary() {
    return SelectableText(
      formatAiInvoiceSummary(_draft!),
      style: const TextStyle(color: Colors.white),
    );
  }
}
