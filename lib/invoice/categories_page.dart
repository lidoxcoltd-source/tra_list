import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tra_list/routes.dart';
import 'category_model.dart';
import 'category_service.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'transaction_model.dart';
import 'transaction_service.dart';

const _kPrimary = Color(0xFF1565C0);
const _kIncome = Color(0xFF2E7D32);
const _kExpense = Color(0xFFC62828);

String _fmt(String key, Map<String, String> values) {
  var text = key.tr;
  values.forEach((k, v) => text = text.replaceAll('@$k', v));
  return text;
}

String _keyOf(CategoryModel c) =>
    '${c.type.name}|${c.name.trim().toLowerCase()}';

List<CategoryModel> _withIds(QuerySnapshot<CategoryModel> snap) => snap.docs
    .map(
      (d) => CategoryModel(
        id: d.id,
        name: d.data().name,
        type: d.data().type,
      ),
    )
    .toList();

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  TransactionType? _filter;
  String _query = '';
  final Set<String> _selected = {};
  bool _busy = false;

  bool get _canDelete => BusinessAccessService.can('categories', 'delete');
  bool get _canEdit => BusinessAccessService.can('categories', 'edit');
  bool get _selecting => _selected.isNotEmpty;

  /// Ids of categories that repeat an earlier one (same name + type).
  Set<String> _duplicateIds(List<CategoryModel> all) {
    final seen = <String>{};
    final dups = <String>{};
    for (final c in all) {
      if (c.id == null) continue;
      if (!seen.add(_keyOf(c))) dups.add(c.id!);
    }
    return dups;
  }

  void _goBack() {
    if (_selecting) {
      setState(_selected.clear);
      return;
    }
    if (Navigator.of(context).canPop()) {
      Get.back();
    } else {
      Get.offAllNamed(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(
          _selecting
              ? _fmt('cat_selected', {'count': '${_selected.length}'})
              : 'cat_title'.tr,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: Icon(
            _selecting ? Icons.close_rounded : Icons.arrow_back_rounded,
          ),
          onPressed: _goBack,
        ),
        elevation: 0,
        backgroundColor: _selecting ? Colors.blueGrey.shade800 : _kPrimary,
        actions: [
          if (_selecting && _canDelete)
            IconButton(
              tooltip: 'cat_delete_selected'.tr,
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _busy ? null : _confirmDeleteSelected,
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<CategoryModel>>(
        stream: CategoryService.getCategoriesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _MessageState(
              icon: Icons.error_outline_rounded,
              color: _kExpense,
              text: 'cat_retry'.tr,
            );
          }
          final all = snapshot.data == null
              ? <CategoryModel>[]
              : _withIds(snapshot.data!);
          final dupIds = _duplicateIds(all);
          final q = _query.trim().toLowerCase();
          final categories = all.where((c) {
            if (_filter != null && c.type != _filter) return false;
            if (q.isNotEmpty && !c.name.toLowerCase().contains(q)) {
              return false;
            }
            return true;
          }).toList();

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                children: [
                  _buildHeader(all, dupIds),
                  Expanded(
                    child: categories.isEmpty
                        ? _MessageState(
                            icon: Icons.category_outlined,
                            color: Colors.grey,
                            text: 'cat_empty'.tr,
                          )
                        : LayoutBuilder(
                            builder: (context, c) {
                              final cols = c.maxWidth >= 800 ? 2 : 1;
                              return GridView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  96,
                                ),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: cols,
                                      mainAxisExtent: 72,
                                      mainAxisSpacing: 8,
                                      crossAxisSpacing: 12,
                                    ),
                                itemCount: categories.length,
                                itemBuilder: (context, index) => _buildTile(
                                  categories[index],
                                  dupIds.contains(categories[index].id),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton:
          !_selecting && BusinessAccessService.can('categories', 'create')
          ? FloatingActionButton.extended(
              onPressed: () => _showCategoryDialog(),
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: Text('add_category_title'.tr),
            )
          : null,
    );
  }

  Widget _buildHeader(List<CategoryModel> all, Set<String> dupIds) {
    Widget chip(String label, TransactionType? value) {
      return ChoiceChip(
        label: Text(label),
        selected: _filter == value,
        showCheckmark: false,
        selectedColor: _kPrimary,
        labelStyle: TextStyle(
          color: _filter == value ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w600,
        ),
        onSelected: (_) => setState(() => _filter = value),
      );
    }

    final incomeCount = all
        .where((c) => c.type == TransactionType.income)
        .length;
    final expenseCount = all.length - incomeCount;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'cat_search'.tr,
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFF5F7FA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    chip('cat_all'.tr, null),
                    chip('income'.tr, TransactionType.income),
                    chip('expense'.tr, TransactionType.expense),
                  ],
                ),
              ),
              Text(
                '${_fmt('cat_count', {'count': '${all.length}'})}'
                ' · $incomeCount ↓ · $expenseCount ↑',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
          if (dupIds.isNotEmpty && _canDelete) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.copy_all_rounded, color: Colors.orange.shade800),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _fmt('cat_duplicates', {'count': '${dupIds.length}'}),
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                    ),
                    onPressed: _busy
                        ? null
                        : () => _confirmRemoveDuplicates(all, dupIds),
                    child: Text('cat_remove_dups'.tr),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTile(CategoryModel category, bool isDuplicate) {
    final isIncome = category.type == TransactionType.income;
    final color = isIncome ? _kIncome : _kExpense;
    final selected = _selected.contains(category.id);

    return Material(
      color: selected ? const Color(0xFFE3EDF9) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _selecting && _canDelete
            ? () => _toggle(category)
            : (_canEdit ? () => _showCategoryDialog(category: category) : null),
        onLongPress: _canDelete ? () => _toggle(category) : null,
        child: Container(
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? _kPrimary
                  : (isDuplicate
                        ? Colors.orange.shade300
                        : Colors.grey.shade200),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              selected
                  ? const CircleAvatar(
                      backgroundColor: _kPrimary,
                      child: Icon(Icons.check_rounded, color: Colors.white),
                    )
                  : CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.12),
                      child: Icon(
                        isIncome
                            ? Icons.south_west_rounded
                            : Icons.north_east_rounded,
                        color: color,
                        size: 20,
                      ),
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Row(
                      children: [
                        Text(
                          (isIncome ? 'income' : 'expense').tr,
                          style: TextStyle(color: color, fontSize: 12),
                        ),
                        if (isDuplicate) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'cat_dup_badge'.tr,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (!_selecting) ...[
                if (_canEdit)
                  IconButton(
                    tooltip: 'edit'.tr,
                    icon: Icon(
                      Icons.edit_outlined,
                      color: Colors.grey.shade700,
                    ),
                    onPressed: () => _showCategoryDialog(category: category),
                  ),
                if (_canDelete)
                  IconButton(
                    tooltip: 'delete'.tr,
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: _kExpense,
                    ),
                    onPressed: () => _confirmDelete(category),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _toggle(CategoryModel c) {
    final id = c.id;
    if (id == null) return;
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _toast(String title, String message, {Color? color}) {
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: color,
      colorText: color == null ? null : Colors.white,
    );
  }

  /// Deletes [targets]; a category is only removed when another category with
  /// the same name + type remains, or when no transaction uses it.
  Future<void> _deleteMany(
    List<CategoryModel> all,
    List<CategoryModel> targets,
  ) async {
    setState(() => _busy = true);
    var deleted = 0;
    var skipped = 0;
    try {
      final deleting = targets.map((c) => c.id).toSet();
      for (final c in targets) {
        final hasTwin = all.any(
          (o) =>
              o.id != c.id &&
              !deleting.contains(o.id) &&
              _keyOf(o) == _keyOf(c),
        );
        if (!hasTwin && await TransactionService.isCategoryInUse(c.name)) {
          skipped++;
          continue;
        }
        await CategoryService.deleteCategory(c.id!);
        deleted++;
      }
    } catch (e) {
      _toast('cat_cannot_delete'.tr, '$e', color: Colors.orange);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _selected.clear();
        });
      }
    }
    if (deleted > 0 || skipped > 0) {
      _toast(
        'cat_success'.tr,
        _fmt('cat_bulk_result', {'ok': '$deleted', 'skipped': '$skipped'}),
        color: skipped > 0 ? Colors.orange : null,
      );
    }
  }

  Future<bool> _askConfirm(String title, String message) async {
    final ok = await Get.dialog<bool>(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kExpense),
            onPressed: () => Get.back(result: true),
            child: Text('delete'.tr),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _confirmRemoveDuplicates(
    List<CategoryModel> all,
    Set<String> dupIds,
  ) async {
    final ok = await _askConfirm(
      'cat_remove_dups'.tr,
      _fmt('cat_dup_confirm', {'count': '${dupIds.length}'}),
    );
    if (!ok) return;
    await _deleteMany(all, all.where((c) => dupIds.contains(c.id)).toList());
  }

  Future<void> _confirmDeleteSelected() async {
    final all = _withIds(await CategoryService.getCategoriesFromServer());
    final targets = all.where((c) => _selected.contains(c.id)).toList();
    if (targets.isEmpty) return;
    final ok = await _askConfirm(
      'cat_delete_selected'.tr,
      _fmt('cat_bulk_confirm', {'count': '${targets.length}'}),
    );
    if (!ok) return;
    await _deleteMany(all, targets);
  }

  Future<void> _confirmDelete(CategoryModel category) async {
    final ok = await _askConfirm(
      'cat_delete_title'.tr,
      _fmt('cat_delete_confirm', {'name': category.name}),
    );
    if (!ok) return;

    final all = _withIds(await CategoryService.getCategoriesFromServer());
    final hasTwin = all.any(
      (o) => o.id != category.id && _keyOf(o) == _keyOf(category),
    );
    if (!hasTwin && await TransactionService.isCategoryInUse(category.name)) {
      _toast(
        'cat_cannot_delete'.tr,
        _fmt('cat_in_use', {'name': category.name}),
        color: Colors.orange,
      );
      return;
    }
    try {
      await CategoryService.deleteCategory(category.id!);
      _toast('cat_success'.tr, _fmt('cat_deleted', {'name': category.name}));
    } catch (e) {
      _toast('cat_cannot_delete'.tr, '$e', color: Colors.orange);
    }
  }

  Future<void> _showCategoryDialog({CategoryModel? category}) async {
    final existing = _withIds(await CategoryService.getCategoriesFromServer());
    if (!mounted) return;

    final nameController = TextEditingController(text: category?.name);
    var type = category?.type ?? TransactionType.expense;
    String? error;

    await Get.dialog(
      StatefulBuilder(
        builder: (context, setState) {
          Widget typeOption(TransactionType value, Color color) {
            final selected = type == value;
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => type = value),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: selected
                        ? color.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? color : Colors.grey.shade300,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    (value == TransactionType.income ? 'income' : 'expense').tr,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: selected ? color : Colors.grey.shade700,
                    ),
                  ),
                ),
              ),
            );
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              category == null ? 'add_category_title'.tr : 'cat_edit_title'.tr,
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'cat_name'.tr,
                      errorText: error,
                      prefixIcon: const Icon(Icons.label_outline_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'cat_type'.tr,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      typeOption(TransactionType.expense, _kExpense),
                      const SizedBox(width: 10),
                      typeOption(TransactionType.income, _kIncome),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: Get.back, child: Text('cancel'.tr)),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _kPrimary),
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    setState(() => error = 'cat_name_required'.tr);
                    return;
                  }
                  final probe = CategoryModel(
                    id: category?.id,
                    name: name,
                    type: type,
                  );
                  final duplicate = existing.any(
                    (o) => o.id != category?.id && _keyOf(o) == _keyOf(probe),
                  );
                  if (duplicate) {
                    setState(() => error = 'cat_exists'.tr);
                    return;
                  }

                  try {
                    if (category == null) {
                      await CategoryService.addCategory(probe);
                    } else {
                      await CategoryService.updateCategory(category.id!, name);
                    }
                    Get.back();
                  } catch (e) {
                    setState(() => error = '$e');
                  }
                },
                child: Text('save'.tr),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: color.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
