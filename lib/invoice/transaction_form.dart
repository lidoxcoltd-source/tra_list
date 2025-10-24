import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:tra_list/invoice/category_model.dart';
import 'package:tra_list/invoice/transaction_service.dart';
import 'package:tra_list/invoice/category_service.dart';
import 'package:tra_list/invoice/add_transaction_controller.dart';
import 'package:tra_list/invoice/advance_invoice_page.dart';
import 'package:tra_list/invoice/transaction_model.dart';

class TransactionForm extends StatelessWidget {
  final AddTransactionController controller;
  final Future<void> Function(Future<void> Function() saveAction) onSave;
  final VoidCallback onCancel;
  final bool isSaving;

  const TransactionForm({
    super.key,
    required this.controller,
    this.isSaving = false,
    required this.onSave,
    required this.onCancel,
  });

  Future<void> _save() async {
    debugPrint('TransactionForm._save called');
    if (_formKey.currentState?.validate() ?? false) {
      await onSave(controller.save);
    }
  }

  // Use a final GlobalKey here for a StatelessWidget.
  static final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    final isNew = controller.isNewTransaction;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(isNew),
          const SizedBox(height: 16),
          _buildTypeToggle(),
          const SizedBox(height: 16),
          _buildDescriptionField(),
          const SizedBox(height: 16),
          _buildAmountField(context),
          const SizedBox(height: 16),
          _buildCategorySelector(),
          const SizedBox(height: 16),
          _buildDateField(),
          const Spacer(),
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isNew) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          isNew ? 'add_transaction_title'.tr : 'edit_transaction_title'.tr,
          style: Get.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: onCancel,
          tooltip: 'cancel'.tr,
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(onPressed: onCancel, child: Text('cancel'.tr)),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: Obx(
            () => ElevatedButton.icon(
              onPressed: isSaving ? null : _save,
              icon: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(isSaving ? 'Saving...' : 'save_transaction'.tr),
              style: ElevatedButton.styleFrom(
                backgroundColor: controller.brandColor.value,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeToggle() {
    return Obx(
      () => SegmentedButton<bool>(
        segments: [
          ButtonSegment(
            value: true,
            label: Text('expense'.tr),
            icon: const Icon(Icons.arrow_downward),
          ),
          ButtonSegment(
            value: false,
            label: Text('income'.tr),
            icon: const Icon(Icons.arrow_upward),
          ),
        ],
        selected: {controller.isExpense.value},
        onSelectionChanged: (selection) {
          controller.isExpense.value = selection.first;
        },
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: controller.isExpense.value
              ? Colors.red.withOpacity(0.1)
              : Colors.green.withOpacity(0.1),
          selectedForegroundColor: controller.isExpense.value
              ? Colors.red.shade700
              : Colors.green.shade700,
          foregroundColor: Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildDescriptionField() {
    return TextFormField(
      controller: controller.descC,
      decoration: InputDecoration(
        labelText: 'description'.tr,
        prefixIcon: const Icon(Icons.description_outlined),
      ),
      validator: (v) =>
          (v == null || v.isEmpty) ? 'Description is required' : null,
    );
  }

  Widget _buildAmountField(BuildContext context) {
    return TextFormField(
      controller: controller.amountC,
      decoration: InputDecoration(
        labelText: 'amount'.tr,
        prefixIcon: const Icon(Icons.monetization_on_outlined),
        prefixText: 'TSH ',
      ),
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      keyboardType: const TextInputType.numberWithOptions(decimal: false),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        ThousandsSeparatorInputFormatter(),
      ],
      validator: (v) {
        if (v == null || v.isEmpty) return 'Amount is required';
        if (double.tryParse(v.replaceAll(',', '')) == null)
          return 'Invalid number';
        return null;
      },
    );
  }

  Widget _buildCategorySelector() {
    return Obx(
      () => TextFormField(
        key: ValueKey(controller.selectedCategory.value), // Rebuild on change
        initialValue: controller.selectedCategory.value.isEmpty
            ? null
            : controller.selectedCategory.value,
        readOnly: true,
        onTap: _showSearchableCategoryPicker,
        decoration: InputDecoration(
          labelText: 'category'.tr,
          prefixIcon: const Icon(Icons.category_outlined),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        validator: (v) =>
            (v == null || v.isEmpty) ? 'Category is required' : null,
      ),
    );
  }

  Future<void> _showSearchableCategoryPicker() async {
    final searchController = TextEditingController();
    final RxList<CategoryModel> filteredCategories = <CategoryModel>[].obs;

    final allCategories = controller.isExpense.value
        ? controller.expenseCategories
        : controller.incomeCategories;
    filteredCategories.assignAll(allCategories);

    searchController.addListener(() {
      final query = searchController.text.toLowerCase();
      if (query.isEmpty) {
        filteredCategories.assignAll(allCategories);
      } else {
        filteredCategories.assignAll(
          allCategories.where((c) => c.name.toLowerCase().contains(query)),
        );
      }
    });

    await Get.bottomSheet(
      Container(
        height: Get.height * 0.7,
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: TextField(
                controller: searchController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '${'search'.tr} ${'categories'.tr}',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'add_category_title'.tr,
                    onPressed: () {
                      Get.back(); // Close search sheet first
                      _showAddCategoryDialog();
                    },
                  ),
                ),
              ),
            ),
            Expanded(
              child: Obx(
                () => filteredCategories.isEmpty
                    ? Center(
                        child: Text(
                          'No categories found. Try adding one.',
                          style: Get.textTheme.bodyMedium,
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredCategories.length,
                        itemBuilder: (context, index) {
                          final category = filteredCategories[index];
                          return ListTile(
                            title: Text(category.name),
                            onTap: () {
                              controller.selectedCategory.value = category.name;
                              Get.back();
                            },
                            onLongPress: () {
                              Get.back(); // Close search sheet first
                              _showCategoryActions(category);
                            },
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  Widget _buildDateField() {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.calendar_today_outlined),
      title: Text('date'.tr),
      subtitle: Obx(
        () => Text(DateFormat.yMMMMd().format(controller.selectedDate.value)),
      ),
      trailing: TextButton(onPressed: _selectDate, child: Text('edit'.tr)),
      onTap: _selectDate,
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: Get.context!,
      initialDate: controller.selectedDate.value,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != controller.selectedDate.value) {
      controller.selectedDate.value = picked;
    }
  }

  Future<void> _showAddCategoryDialog() async {
    final nameController = TextEditingController();
    final newCategoryName = await Get.dialog<String>(
      AlertDialog(
        title: Text('add_category_title'.tr),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(labelText: 'category_name'.tr),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text('cancel'.tr)),
          ElevatedButton(
            onPressed: () => Get.back(result: nameController.text.trim()),
            child: Text('save'.tr),
          ),
        ],
      ),
    );

    if (newCategoryName != null && newCategoryName.isNotEmpty) {
      await controller.addNewCategory(newCategoryName);
    }
  }

  /// Shows a dialog to edit or delete a category.
  void _showCategoryActions(CategoryModel category) {
    Get.bottomSheet(
      SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text('Edit "${category.name}"'),
              onTap: () {
                Get.back(); // Close the bottom sheet
                _showEditCategoryDialog(category);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(
                'Delete "${category.name}"',
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () {
                Get.back(); // Close the bottom sheet
                _confirmDeleteCategory(category);
              },
            ),
          ],
        ),
      ),
      backgroundColor: Colors.white,
    );
  }

  /// Shows a dialog to edit an existing category's name.
  Future<void> _showEditCategoryDialog(CategoryModel category) async {
    final nameController = TextEditingController(text: category.name);

    final newName = await Get.dialog<String>(
      AlertDialog(
        title: Text('Edit Category'.tr),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(labelText: 'category_name'.tr),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text('cancel'.tr)),
          ElevatedButton(
            onPressed: () => Get.back(result: nameController.text.trim()),
            child: Text('save'.tr),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != category.name) {
      try {
        await CategoryService.updateCategory(category.id!, newName);
        // If the edited category was selected, update the selection
        if (controller.selectedCategory.value == category.name) {
          controller.selectedCategory.value = newName;
        }
        await controller.loadCategories(); // Refresh the list
        Get.snackbar('Success', 'Category updated successfully');
      } catch (e) {
        Get.snackbar('Error', 'Failed to update category: $e');
      }
    }
  }

  /// Confirms and handles the deletion of a category.
  Future<void> _confirmDeleteCategory(CategoryModel category) async {
    // 1. Check if the category is in use
    final isInUse = await TransactionService.isCategoryInUse(category.name);

    // 2. If in use, show an error and stop.
    if (isInUse) {
      Get.snackbar(
        'Cannot Delete',
        'Category "${category.name}" is used by existing transactions.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    // 3. If not in use, ask for confirmation.
    final confirm = await Get.dialog<bool>(
      AlertDialog(
        title: Text('Delete Category'.tr),
        content: Text(
          'Are you sure you want to delete "${category.name}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    // 4. If confirmed, proceed with deletion.
    if (confirm == true) {
      try {
        await CategoryService.deleteCategory(category.id!);
        // If the deleted category was selected, clear the selection
        if (controller.selectedCategory.value == category.name) {
          controller.selectedCategory.value = '';
        }
        await controller.loadCategories(); // Refresh the list
        Get.snackbar(
          'Success',
          'Category "${category.name}" has been deleted.',
          snackPosition: SnackPosition.BOTTOM,
        );
      } catch (e) {
        Get.snackbar('Error', 'Failed to delete category: $e');
      }
    }
  }
}
