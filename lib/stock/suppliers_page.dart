import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/theme/app_theme.dart';

import 'stock_models.dart';
import 'stock_service.dart';
import 'stock_ui.dart';

typedef _SaveSupplier =
    Future<void> Function(String name, String phone, String location);

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  final _service = StockService.current();
  late final _suppliers = _service.watchSuppliers();
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openForm({StockSupplier? supplier}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SupplierFormSheet(
        supplier: supplier,
        onSave: (name, phone, location) async {
          if (supplier == null) {
            await _service.createSupplier(
              StockSupplier(
                id: '',
                name: name,
                phone: phone,
                location: location,
              ),
            );
            stockToast('stk_saved'.tr, 'stk_supplier_created'.tr);
          } else {
            await _service.updateSupplier(
              StockSupplier(
                id: supplier.id,
                name: name,
                phone: phone,
                location: location,
              ),
            );
            stockToast('stk_saved'.tr, 'stk_supplier_updated'.tr);
          }
        },
      ),
    );
  }

  Future<void> _deleteSupplier(StockSupplier supplier) async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: Text('stk_supplier_delete_title'.tr),
        content: Text(
          fmtText('stk_supplier_delete_confirm', {'name': supplier.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('stk_cancel'.tr),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kStockBad),
            onPressed: () => Get.back(result: true),
            child: Text('stk_delete'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteSupplier(supplier.id);
      stockToast('stk_deleted'.tr, supplier.name);
    } on StockException catch (error) {
      stockToast('stk_error'.tr, stockErrorText(error), error: true);
    } on FirebaseException catch (error) {
      stockToast('stk_error'.tr, error.message ?? error.code, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = BusinessAccessService.can('stock', 'create');
    final canEdit = BusinessAccessService.can('stock', 'edit');
    final canDelete = BusinessAccessService.can('stock', 'delete');
    return StockScaffold(
      title: 'stk_suppliers'.tr,
      maxWidth: 1000,
      actions: [
        if (canCreate)
          IconButton(
            tooltip: 'stk_add_supplier'.tr,
            onPressed: () => _openForm(),
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
      ],
      body: StreamBuilder<List<StockSupplier>>(
        stream: _suppliers,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return StockMessage(
              icon: Icons.error_outline_rounded,
              color: kStockBad,
              text: stockErrorText(snapshot.error!),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final suppliers = snapshot.data!;
          final query = _search.text.trim().toLowerCase();
          final filtered = suppliers.where((supplier) {
            if (query.isEmpty) return true;
            return supplier.name.toLowerCase().contains(query) ||
                supplier.phone.toLowerCase().contains(query) ||
                supplier.location.toLowerCase().contains(query);
          }).toList();

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [kStockNavy, kStockBlue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: kStockNavy.withValues(alpha: .16),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.local_shipping_outlined,
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
                              'stk_suppliers'.tr,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'stk_supplier_page_hint'.tr,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .78),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${suppliers.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration:
                      stockInput(
                        'stk_supplier_search'.tr,
                        icon: Icons.search_rounded,
                      ).copyWith(
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'stk_clear'.tr,
                                onPressed: () {
                                  _search.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                ),
                const SizedBox(height: 12),
                if (filtered.isEmpty)
                  Expanded(
                    child: StockMessage(
                      icon: suppliers.isEmpty
                          ? Icons.local_shipping_outlined
                          : Icons.search_off_rounded,
                      text: suppliers.isEmpty
                          ? 'stk_supplier_empty'.tr
                          : 'stk_supplier_no_results'.tr,
                      action: canCreate
                          ? OutlinedButton.icon(
                              onPressed: () => _openForm(),
                              icon: const Icon(Icons.add_rounded),
                              label: Text('stk_add_supplier'.tr),
                            )
                          : null,
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 9),
                      itemBuilder: (context, index) => _SupplierCard(
                        supplier: filtered[index],
                        canEdit: canEdit,
                        canDelete: canDelete,
                        onEdit: () => _openForm(supplier: filtered[index]),
                        onDelete: () => _deleteSupplier(filtered[index]),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({
    required this.supplier,
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
  });

  final StockSupplier supplier;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
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
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: kStockLight,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.storefront_outlined,
                color: kStockBlue,
                size: 22,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                supplier.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MjasiColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (canEdit)
              IconButton(
                tooltip: 'stk_edit_supplier'.tr,
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 19),
              ),
            if (canDelete)
              IconButton(
                tooltip: 'stk_delete'.tr,
                onPressed: onDelete,
                color: kStockBad,
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
              ),
          ],
        ),
        const Divider(height: 18),
        _supplierDetail(Icons.phone_outlined, supplier.phone),
        if (supplier.location.isNotEmpty) ...[
          const SizedBox(height: 8),
          _supplierDetail(Icons.location_on_outlined, supplier.location),
        ],
      ],
    ),
  );

  Widget _supplierDetail(IconData icon, String value) => Row(
    children: [
      Icon(icon, size: 17, color: MjasiColors.textSecondary),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: MjasiColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ],
  );
}

class _SupplierFormSheet extends StatefulWidget {
  const _SupplierFormSheet({required this.supplier, required this.onSave});

  final StockSupplier? supplier;
  final _SaveSupplier onSave;

  @override
  State<_SupplierFormSheet> createState() => _SupplierFormSheetState();
}

class _SupplierFormSheetState extends State<_SupplierFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.supplier?.name);
  late final _phone = TextEditingController(text: widget.supplier?.phone);
  late final _location = TextEditingController(text: widget.supplier?.location);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        _name.text.trim(),
        _phone.text.trim(),
        _location.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } on StockException catch (error) {
      stockToast('stk_error'.tr, stockErrorText(error), error: true);
    } on FirebaseException catch (error) {
      stockToast('stk_error'.tr, error.message ?? error.code, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final supplier = widget.supplier;
    return Padding(
      padding: const EdgeInsets.only(top: 44),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  18,
                  20,
                  20 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: kStockLight,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: const Icon(
                                Icons.storefront_outlined,
                                color: kStockBlue,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                supplier == null
                                    ? 'stk_add_supplier'.tr
                                    : 'stk_edit_supplier'.tr,
                                style: const TextStyle(
                                  color: MjasiColors.textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'stk_close'.tr,
                              onPressed: _saving
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _name,
                          maxLength: 120,
                          textCapitalization: TextCapitalization.words,
                          decoration: stockInput(
                            'stk_supplier_name'.tr,
                            icon: Icons.storefront_outlined,
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'stk_err_required'.tr
                              : null,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _phone,
                          maxLength: 40,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9+() \-]'),
                            ),
                          ],
                          decoration: stockInput(
                            'stk_supplier_phone'.tr,
                            icon: Icons.phone_outlined,
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'stk_err_required'.tr
                              : null,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _location,
                          maxLength: 240,
                          textCapitalization: TextCapitalization.words,
                          decoration: stockInput(
                            'stk_supplier_location'.tr,
                            icon: Icons.location_on_outlined,
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'stk_err_required'.tr
                              : null,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _saving
                                    ? null
                                    : () => Navigator.of(context).pop(),
                                child: Text('stk_cancel'.tr),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _saving ? null : _save,
                                icon: _saving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.check_rounded, size: 18),
                                label: Text('stk_save'.tr),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
