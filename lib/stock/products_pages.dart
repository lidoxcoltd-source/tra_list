import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/theme/app_theme.dart';
import 'stock_models.dart';
import 'stock_media.dart';
import 'stock_service.dart';
import 'stock_ui.dart';
import 'stock_operations_pages.dart';

bool get _canSeeCost => BusinessAccessService.can('stock', 'edit');

double _num(String s) => double.tryParse(s.trim().replaceAll(',', '')) ?? 0;

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key, this.initialFilter = 'all'});
  final String initialFilter;

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _service = StockService.current();
  late String _filter = widget.initialFilter;
  String _query = '';
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final canCreate = BusinessAccessService.can('stock', 'create');
    return StockScaffold(
      title: 'stk_products'.tr,
      fab: canCreate
          ? FloatingActionButton.extended(
              backgroundColor: kStockBlue,
              foregroundColor: Colors.white,
              onPressed: () => Get.to(() => const ProductFormPage()),
              icon: const Icon(Icons.add),
              label: Text('stk_add_product'.tr),
            )
          : null,
      body: StreamBuilder<List<Product>>(
        stream: _service.watchProducts(),
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
          final all = snap.data!;
          final list = all.where((p) {
            if (p.active == _showArchived) return false;
            if (_filter == 'low' &&
                !(p.tracked && p.stockState == StockState.low)) {
              return false;
            }
            if (_filter == 'out' &&
                !(p.tracked && p.stockState == StockState.out)) {
              return false;
            }
            return q.isEmpty ||
                p.name.toLowerCase().contains(q) ||
                p.sku.toLowerCase().contains(q) ||
                p.barcode.toLowerCase().contains(q) ||
                p.category.toLowerCase().contains(q);
          }).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: TextField(
                  decoration:
                      stockInput(
                        'stk_search'.tr,
                        icon: Icons.search_rounded,
                      ).copyWith(
                        hintText: 'stk_search'.tr,
                        filled: true,
                        fillColor: Colors.white,
                        suffixIcon: IconButton(
                          tooltip: 'stk_scan'.tr,
                          style: IconButton.styleFrom(
                            foregroundColor: kStockBlue,
                            backgroundColor: kStockLight,
                          ),
                          icon: const Icon(Icons.qr_code_scanner),
                          onPressed: () async {
                            final p = await scanForProduct(context, all);
                            if (p != null && context.mounted) {
                              Get.to(
                                () => ProductDetailsPage(productId: p.id!),
                              );
                            }
                          },
                        ),
                      ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  children: [
                    for (final f in const ['all', 'low', 'out'])
                      Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: ChoiceChip(
                          label: Text('stk_filter_$f'.tr),
                          selected: _filter == f,
                          showCheckmark: false,
                          backgroundColor: Colors.white,
                          selectedColor: kStockNavy,
                          side: BorderSide(
                            color: _filter == f
                                ? kStockNavy
                                : MjasiColors.border,
                          ),
                          labelStyle: TextStyle(
                            color: _filter == f
                                ? Colors.white
                                : MjasiColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: FilterChip(
                        label: Text('stk_archived'.tr),
                        selected: _showArchived,
                        showCheckmark: false,
                        backgroundColor: Colors.white,
                        selectedColor: kStockLight,
                        side: BorderSide(
                          color: _showArchived
                              ? kStockBlue
                              : MjasiColors.border,
                        ),
                        labelStyle: const TextStyle(
                          color: kStockNavy,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onSelected: (v) => setState(() => _showArchived = v),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? StockMessage(
                        icon: Icons.inventory_2_outlined,
                        text: 'stk_no_products'.tr,
                      )
                    : LayoutBuilder(
                        builder: (context, c) {
                          final cols = c.maxWidth >= 1100
                              ? 3
                              : c.maxWidth >= 640
                              ? 2
                              : 1;
                          return GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: cols,
                                  mainAxisExtent: 112,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                            itemCount: list.length,
                            itemBuilder: (_, i) =>
                                _ProductTile(product: list[i]),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    return StockCard(
      onTap: () => Get.to(() => ProductDetailsPage(productId: p.id!)),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      child: Row(
        children: [
          ProductImage(url: p.imageUrl, size: 64, radius: 15),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: MjasiColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: MjasiColors.textSecondary.withValues(alpha: .8),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${p.sku}${p.category.isEmpty ? '' : ' · ${p.category}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MjasiColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: StockStateChip(product: p),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                p.tracked ? formatQty(p.quantity) : '—',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                  color: MjasiColors.textPrimary,
                ),
              ),
              Text(
                unitLabel(p.unit),
                style: const TextStyle(
                  color: MjasiColors.textSecondary,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'TZS ${formatMoney(p.sellPrice)}',
                style: const TextStyle(
                  color: kStockBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ProductFormPage extends StatefulWidget {
  const ProductFormPage({super.key, this.product});
  final Product? product;

  @override
  State<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends State<ProductFormPage> {
  final _service = StockService.current();
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.product?.name);
  late final _sku = TextEditingController(text: widget.product?.sku);
  late final _barcode = TextEditingController(text: widget.product?.barcode);
  late final _category = TextEditingController(text: widget.product?.category);
  late final _desc = TextEditingController(text: widget.product?.description);
  late final _supplier = TextEditingController(text: widget.product?.supplier);
  late final _sell = TextEditingController(
    text: widget.product == null ? '' : formatQty(widget.product!.sellPrice),
  );
  late final _threshold = TextEditingController(
    text: widget.product == null
        ? '0'
        : formatQty(widget.product!.lowStockThreshold),
  );
  final _openQty = TextEditingController();
  final _openCost = TextEditingController();
  late String _unit = widget.product?.unit ?? 'piece';
  late bool _tracked = widget.product?.tracked ?? true;
  late bool _allowNegative = widget.product?.allowNegative ?? false;
  bool _saving = false;
  bool _uploading = false;
  late String _imageUrl = widget.product?.imageUrl ?? '';
  String? _skuError;
  String? _barcodeError;

  bool get _editing => widget.product != null;

  Future<void> _pickImage() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      final url = await pickAndUploadProductImage(context);
      if (url != null && mounted) setState(() => _imageUrl = url);
    } catch (e) {
      stockToast('stk_error'.tr, stockErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _scanInto(TextEditingController c) async {
    final code = await scanCode(context);
    if (code != null && code.isNotEmpty && mounted) {
      setState(() => c.text = code);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _sku,
      _barcode,
      _category,
      _desc,
      _supplier,
      _sell,
      _threshold,
      _openQty,
      _openCost,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _skuError = null;
      _barcodeError = null;
    });
    if (!_key.currentState!.validate() || _saving) return;
    final old = widget.product;
    if (old == null ||
        Product.nameKey(old.name) != Product.nameKey(_name.text)) {
      try {
        final all = await _service.watchProducts().first;
        final similar = findSimilarNames(all, _name.text, excludeId: old?.id);
        if (similar.isNotEmpty && mounted) {
          final ok = await Get.dialog<bool>(
            AlertDialog(
              title: Text('stk_similar_title'.tr),
              content: Text(
                '${'stk_similar_body'.tr}\n\n${similar.take(5).map((e) => '• ${e.name}').join('\n')}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Get.back(result: false),
                  child: Text('stk_cancel'.tr),
                ),
                FilledButton(
                  onPressed: () => Get.back(result: true),
                  child: Text('stk_continue'.tr),
                ),
              ],
            ),
          );
          if (ok != true) return;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _saving = true);
    final p = Product(
      id: old?.id,
      name: _name.text.trim(),
      sku: _sku.text.trim(),
      barcode: _barcode.text.trim(),
      category: _category.text.trim(),
      description: _desc.text.trim(),
      unit: _unit,
      costPrice: old?.costPrice ?? 0,
      sellPrice: _num(_sell.text),
      quantity: old?.quantity ?? 0,
      lowStockThreshold: _num(_threshold.text),
      tracked: _tracked,
      allowNegative: _allowNegative,
      supplier: _supplier.text.trim(),
      imageUrl: _imageUrl,
      active: old?.active ?? true,
    );
    try {
      if (_editing) {
        await _service.updateProduct(old!.id!, p);
        stockToast('stk_saved'.tr, p.name);
        Get.back();
      } else {
        final id = await _service.createProduct(
          p,
          openingQuantity: _tracked ? _num(_openQty.text) : 0,
          openingCost: _num(_openCost.text),
        );
        stockToast('stk_saved'.tr, p.name);
        Get.off(() => ProductDetailsPage(productId: id));
      }
    } catch (e) {
      if (e is StockException &&
          (e.messageKey == 'stk_err_sku_exists' ||
              e.messageKey == 'stk_err_barcode_exists')) {
        setState(() {
          if (e.messageKey == 'stk_err_sku_exists') {
            _skuError = stockErrorText(e);
          } else {
            _barcodeError = stockErrorText(e);
          }
        });
        _key.currentState!.validate();
      } else {
        stockToast('stk_error'.tr, stockErrorText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? required(String? v) =>
        (v == null || v.trim().isEmpty) ? 'stk_err_required'.tr : null;
    String? money(String? v) =>
        (v != null &&
            v.trim().isNotEmpty &&
            (double.tryParse(v.trim()) == null || _num(v) < 0))
        ? 'stk_err_qty'.tr
        : null;
    final dec = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    final width = MediaQuery.of(context).size.width;
    final twoCol = width >= 800;

    Widget row(List<Widget> kids) => twoCol
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < kids.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: kids[i]),
              ],
            ],
          )
        : Column(
            children: kids
                .map(
                  (k) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: k,
                  ),
                )
                .toList(),
          );

    return StockScaffold(
      title: _editing ? 'stk_edit_product'.tr : 'stk_add_product'.tr,
      maxWidth: 900,
      body: Form(
        key: _key,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            StockCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          ProductImage(url: _imageUrl, size: 88, radius: 14),
                          if (_uploading) const CircularProgressIndicator(),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _uploading ? null : _pickImage,
                              icon: const Icon(Icons.add_a_photo_outlined),
                              label: Text(
                                _imageUrl.isEmpty
                                    ? 'stk_add_photo'.tr
                                    : 'stk_change_photo'.tr,
                              ),
                            ),
                            if (_imageUrl.isNotEmpty)
                              TextButton.icon(
                                onPressed: _uploading
                                    ? null
                                    : () => setState(() => _imageUrl = ''),
                                icon: const Icon(Icons.delete_outline),
                                label: Text('stk_remove_photo'.tr),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  StockSectionHeading(title: 'stk_product_information'.tr),
                  row([
                    TextFormField(
                      controller: _name,
                      decoration: stockInput(
                        'stk_name'.tr,
                        icon: Icons.label_outline,
                      ),
                      validator: required,
                    ),
                    TextFormField(
                      controller: _sku,
                      decoration:
                          stockInput(
                            'stk_sku'.tr,
                            icon: Icons.qr_code_2,
                          ).copyWith(
                            suffixIcon: IconButton(
                              tooltip: 'stk_scan'.tr,
                              icon: const Icon(Icons.qr_code_scanner),
                              onPressed: () => _scanInto(_sku),
                            ),
                          ),
                      validator: (v) => required(v) ?? _skuError,
                      onChanged: (_) => _skuError = null,
                    ),
                  ]),
                  if (twoCol) const SizedBox(height: 12),
                  row([
                    TextFormField(
                      controller: _barcode,
                      decoration:
                          stockInput(
                            'stk_barcode'.tr,
                            icon: Icons.barcode_reader,
                          ).copyWith(
                            suffixIcon: IconButton(
                              tooltip: 'stk_scan'.tr,
                              icon: const Icon(Icons.qr_code_scanner),
                              onPressed: () => _scanInto(_barcode),
                            ),
                          ),
                      validator: (_) => _barcodeError,
                      onChanged: (_) => _barcodeError = null,
                    ),
                    TextFormField(
                      controller: _category,
                      decoration: stockInput(
                        'stk_category'.tr,
                        icon: Icons.category_outlined,
                      ),
                    ),
                  ]),
                  if (twoCol) const SizedBox(height: 12),
                  StockSectionHeading(title: 'stk_pricing_stock'.tr),
                  row([
                    DropdownButtonFormField<String>(
                      initialValue: stockUnits.contains(_unit)
                          ? _unit
                          : 'piece',
                      decoration: stockInput(
                        'stk_unit'.tr,
                        icon: Icons.straighten,
                      ),
                      items: [
                        for (final u in stockUnits)
                          DropdownMenuItem(value: u, child: Text(unitLabel(u))),
                      ],
                      onChanged: _editing
                          ? null
                          : (v) => setState(() => _unit = v ?? 'piece'),
                    ),
                    TextFormField(
                      controller: _sell,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: dec,
                      decoration: stockInput(
                        'stk_sell_price'.tr,
                        icon: Icons.sell_outlined,
                        suffix: 'TZS',
                      ),
                      validator: money,
                    ),
                    TextFormField(
                      controller: _threshold,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: dec,
                      decoration: stockInput(
                        'stk_threshold'.tr,
                        icon: Icons.notifications_active_outlined,
                      ),
                      validator: money,
                    ),
                  ]),
                  if (twoCol) const SizedBox(height: 12),
                  StockSectionHeading(title: 'stk_additional_details'.tr),
                  row([
                    TextFormField(
                      controller: _supplier,
                      decoration: stockInput(
                        'stk_supplier'.tr,
                        icon: Icons.local_shipping_outlined,
                      ),
                    ),
                  ]),
                  TextFormField(
                    controller: _desc,
                    maxLines: 2,
                    decoration: stockInput(
                      'stk_description'.tr,
                      icon: Icons.notes,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('stk_track'.tr),
                    subtitle: Text('stk_track_hint'.tr),
                    value: _tracked,
                    onChanged: (v) => setState(() => _tracked = v),
                  ),
                  if (_tracked)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('stk_allow_negative'.tr),
                      subtitle: Text('stk_allow_negative_hint'.tr),
                      value: _allowNegative,
                      onChanged: (v) => setState(() => _allowNegative = v),
                    ),
                ],
              ),
            ),
            if (!_editing && _tracked) ...[
              const SizedBox(height: 16),
              StockCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'stk_opening_stock'.tr,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: kStockNavy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'stk_opening_help'.tr,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    row([
                      TextFormField(
                        controller: _openQty,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: dec,
                        decoration:
                            stockInput(
                              'stk_quantity'.tr,
                              icon: Icons.inventory_2_outlined,
                            ).copyWith(
                              helperText: 'stk_quantity_help'.tr,
                              helperMaxLines: 2,
                            ),
                        validator: money,
                      ),
                      if (_canSeeCost)
                        TextFormField(
                          controller: _openCost,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: dec,
                          decoration:
                              stockInput(
                                'stk_unit_cost'.tr,
                                icon: Icons.payments_outlined,
                                suffix: 'TZS',
                              ).copyWith(
                                helperText: 'stk_unit_cost_help'.tr,
                                helperMaxLines: 2,
                              ),
                          validator: money,
                        ),
                    ]),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kStockBlue),
                onPressed: _saving ? null : _save,
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
                label: Text('stk_save'.tr),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductDetailsPage extends StatelessWidget {
  const ProductDetailsPage({super.key, required this.productId});
  final String productId;

  @override
  Widget build(BuildContext context) {
    final service = StockService.current();
    return StreamBuilder<List<Product>>(
      stream: service.watchProducts(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return StockScaffold(
            title: 'stk_product'.tr,
            body: snap.hasError
                ? StockMessage(
                    icon: Icons.error_outline,
                    color: kStockBad,
                    text: stockErrorText(snap.error!),
                  )
                : const Center(child: CircularProgressIndicator()),
          );
        }
        final p = snap.data!.where((e) => e.id == productId).firstOrNull;
        if (p == null) {
          return StockScaffold(
            title: 'stk_product'.tr,
            body: StockMessage(
              icon: Icons.search_off,
              text: 'stk_err_product_missing'.tr,
            ),
          );
        }
        final canEdit = BusinessAccessService.can('stock', 'edit');
        final canCreate = BusinessAccessService.can('stock', 'create');
        return StockScaffold(
          title: p.name,
          maxWidth: 900,
          actions: [
            if (canEdit)
              IconButton(
                tooltip: 'stk_edit_product'.tr,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Get.to(() => ProductFormPage(product: p)),
              ),
            if (canEdit && p.active && p.tracked)
              IconButton(
                tooltip: 'stk_merge'.tr,
                icon: const Icon(Icons.merge_type),
                onPressed: () async {
                  final target = await pickProduct(
                    context,
                    snap.data!.where((e) => e.id != p.id).toList(),
                    trackedOnly: true,
                  );
                  if (target == null) return;
                  final ok = await Get.dialog<bool>(
                    AlertDialog(
                      title: Text('stk_merge'.tr),
                      content: Text(
                        'stk_merge_confirm'.tr
                            .replaceAll('@source', p.name)
                            .replaceAll('@target', target.name),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Get.back(result: false),
                          child: Text('stk_cancel'.tr),
                        ),
                        FilledButton(
                          onPressed: () => Get.back(result: true),
                          child: Text('stk_merge'.tr),
                        ),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  try {
                    await service.mergeProducts(
                      sourceId: p.id!,
                      targetId: target.id!,
                    );
                    stockToast('stk_saved'.tr, target.name);
                    Get.back();
                  } catch (e) {
                    stockToast('stk_error'.tr, stockErrorText(e), error: true);
                  }
                },
              ),
            if (canEdit)
              IconButton(
                tooltip: p.active ? 'stk_archive'.tr : 'stk_restore'.tr,
                icon: Icon(
                  p.active ? Icons.archive_outlined : Icons.unarchive_outlined,
                ),
                onPressed: () async {
                  try {
                    await service.setActive(p.id!, !p.active);
                  } catch (e) {
                    stockToast('stk_error'.tr, stockErrorText(e), error: true);
                  }
                },
              ),
          ],
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              StockCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (p.imageUrl.isNotEmpty) ...[
                          ProductImage(url: p.imageUrl, size: 72, radius: 12),
                          const SizedBox(width: 14),
                        ],
                        Expanded(
                          child: Text(
                            p.tracked
                                ? '${formatQty(p.quantity)} ${unitLabel(p.unit)}'
                                : 'stk_not_tracked'.tr,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: kStockNavy,
                            ),
                          ),
                        ),
                        StockStateChip(product: p),
                      ],
                    ),
                    if (!p.active)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'stk_archived'.tr,
                          style: const TextStyle(color: kStockWarn),
                        ),
                      ),
                    const Divider(height: 24),
                    StockSectionHeading(title: 'stk_product_information'.tr),
                    _kv('stk_sku'.tr, p.sku),
                    if (p.barcode.isNotEmpty) _kv('stk_barcode'.tr, p.barcode),
                    if (p.category.isNotEmpty)
                      _kv('stk_category'.tr, p.category),
                    if (p.supplier.isNotEmpty)
                      _kv('stk_supplier'.tr, p.supplier),
                    _kv('stk_sell_price'.tr, 'TZS ${formatMoney(p.sellPrice)}'),
                    if (_canSeeCost) ...[
                      _kv('stk_avg_cost'.tr, 'TZS ${formatMoney(p.costPrice)}'),
                      if (p.tracked)
                        _kv(
                          'stk_stock_value'.tr,
                          'TZS ${formatMoney(p.quantity * p.costPrice)}',
                        ),
                    ],
                    if (p.tracked)
                      _kv('stk_threshold'.tr, formatQty(p.lowStockThreshold)),
                    if (p.description.isNotEmpty)
                      _kv('stk_description'.tr, p.description),
                  ],
                ),
              ),
              if (p.tracked && p.active) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canCreate)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: kStockBlue,
                        ),
                        onPressed: () => Get.to(
                          () => ReceiveStockPage(initialProductId: p.id),
                        ),
                        icon: const Icon(Icons.add_box_outlined),
                        label: Text('stk_receive'.tr),
                      ),
                    if (canEdit)
                      OutlinedButton.icon(
                        onPressed: () =>
                            Get.to(() => AdjustStockPage(productId: p.id)),
                        icon: const Icon(Icons.tune),
                        label: Text('stk_adjust'.tr),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'stk_history'.tr,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: kStockNavy,
                ),
              ),
              const SizedBox(height: 8),
              if (BusinessAccessService.can('stock', 'view'))
                StreamBuilder<List<StockMovement>>(
                  stream: service.watchProductMovements(p.id!),
                  builder: (context, ms) {
                    if (ms.hasError) {
                      return StockMessage(
                        icon: Icons.error_outline,
                        color: kStockBad,
                        text: stockErrorText(ms.error!),
                      );
                    }
                    if (!ms.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (ms.data!.isEmpty) {
                      return StockMessage(
                        icon: Icons.history,
                        text: 'stk_no_movements'.tr,
                      );
                    }
                    return Column(
                      children: [
                        for (final m in ms.data!)
                          MovementTile(movement: m, showProduct: false),
                      ],
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 430;
      final label = Text(
        k,
        style: const TextStyle(color: MjasiColors.textSecondary, fontSize: 12),
      );
      final value = Text(
        v,
        textAlign: compact ? TextAlign.start : TextAlign.end,
        style: const TextStyle(
          color: MjasiColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [label, const SizedBox(height: 3), value],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: label),
                  const SizedBox(width: 12),
                  Flexible(child: value),
                ],
              ),
      );
    },
  );
}

class MovementTile extends StatelessWidget {
  const MovementTile({
    super.key,
    required this.movement,
    this.showProduct = true,
  });
  final StockMovement movement;
  final bool showProduct;

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final up = m.quantityChange >= 0;
    final color = up ? kStockOk : kStockBad;
    final detail = [
      if (m.reason.isNotEmpty) m.reason,
      if (m.userName.isNotEmpty) m.userName,
      formatDateTime(m.createdAt),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StockCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              up ? Icons.south_west_rounded : Icons.north_east_rounded,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    showProduct
                        ? '${m.productName} · ${m.type.labelKey.tr}'
                        : m.type.labelKey.tr,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    detail,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${up ? '+' : ''}${formatQty(m.quantityChange)}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '→ ${formatQty(m.resultingQuantity)}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
