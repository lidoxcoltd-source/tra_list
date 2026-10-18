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

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  // null = all, otherwise filter by type
  TransactionType? _filter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(
          'cat_title'.tr,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Get.back();
            } else {
              Get.offAllNamed(AppRoutes.home);
            }
          },
        ),
        elevation: 0,
        backgroundColor: _kPrimary,
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
          final all = snapshot.data?.docs ?? [];
          final categories = _filter == null
              ? all
              : all.where((d) => d.data().type == _filter).toList();

          return Column(
            children: [
              _buildHeader(all.length),
              Expanded(
                child: categories.isEmpty
                    ? _MessageState(
                        icon: Icons.category_outlined,
                        color: Colors.grey,
                        text: 'cat_empty'.tr,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                        itemCount: categories.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _buildTile(categories[index].data()),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: BusinessAccessService.can('categories', 'create')
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

  Widget _buildHeader(int total) {
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

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              children: [
                chip('cat_all'.tr, null),
                chip('income'.tr, TransactionType.income),
                chip('expense'.tr, TransactionType.expense),
              ],
            ),
          ),
          Text(
            _fmt('cat_count', {'count': '$total'}),
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(CategoryModel category) {
    final isIncome = category.type == TransactionType.income;
    final color = isIncome ? _kIncome : _kExpense;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 12, right: 4),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(
            isIncome ? Icons.south_west_rounded : Icons.north_east_rounded,
            color: color,
            size: 20,
          ),
        ),
        title: Text(
          category.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          (isIncome ? 'income' : 'expense').tr,
          style: TextStyle(color: color, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'edit'.tr,
              icon: Icon(Icons.edit_outlined, color: Colors.grey.shade700),
              onPressed: () => _showCategoryDialog(category: category),
            ),
            IconButton(
              tooltip: 'delete'.tr,
              icon: const Icon(Icons.delete_outline_rounded, color: _kExpense),
              onPressed: () => _confirmDelete(category),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(CategoryModel category) {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('cat_delete_title'.tr),
        content: Text(_fmt('cat_delete_confirm', {'name': category.name})),
        actions: [
          TextButton(onPressed: Get.back, child: Text('cancel'.tr)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kExpense),
            onPressed: () async {
              Get.back();

              final isInUse = await TransactionService.isCategoryInUse(
                category.name,
              );

              if (isInUse) {
                Get.snackbar(
                  'cat_cannot_delete'.tr,
                  _fmt('cat_in_use', {'name': category.name}),
                  snackPosition: SnackPosition.BOTTOM,
                  backgroundColor: Colors.orange,
                  colorText: Colors.white,
                );
              } else {
                await CategoryService.deleteCategory(category.id!);
                Get.snackbar(
                  'cat_success'.tr,
                  _fmt('cat_deleted', {'name': category.name}),
                  snackPosition: SnackPosition.BOTTOM,
                );
              }
            },
            child: Text('delete'.tr),
          ),
        ],
      ),
    );
  }

  void _showCategoryDialog({CategoryModel? category}) {
    final nameController = TextEditingController(text: category?.name);
    var type = category?.type ?? TransactionType.expense;
    String? error;

    Get.dialog(
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
            content: Column(
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

                  final newCategory = CategoryModel(
                    id: category?.id,
                    name: name,
                    type: type,
                  );

                  if (category == null) {
                    await CategoryService.addCategory(newCategory);
                  } else {
                    await CategoryService.updateCategory(category.id!, name);
                  }
                  Get.back();
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
