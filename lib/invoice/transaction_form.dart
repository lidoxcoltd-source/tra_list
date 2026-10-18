import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:tra_list/invoice/category_model.dart';
import 'package:tra_list/invoice/transaction_service.dart';
import 'package:tra_list/invoice/category_service.dart';
import 'package:tra_list/invoice/add_transaction_controller.dart';
import 'package:tra_list/invoice/advance_invoice_page.dart';
import 'package:tra_list/services/business_access_service.dart';

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
    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.only(top: 8, bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTypeToggle(),
                  const SizedBox(height: 20),
                  _buildDescriptionField(),
                  const SizedBox(height: 16),
                  _buildAmountField(context),
                  const SizedBox(height: 16),
                  _buildCategorySelector(),
                  const SizedBox(height: 12),
                  _buildDateField(),
                ],
              ),
            ),
          ),
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
      decoration: const BoxDecoration(
        color: Color(0xFFF4F7F7),
        border: Border(top: BorderSide(color: Color(0xFFE1E8E9))),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: isSaving ? null : onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF52656A),
                minimumSize: const Size.fromHeight(52),
                side: const BorderSide(color: Color(0xFFD5DFE1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text('cancel'.tr),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Obx(() {
              final permission = controller.isNewTransaction
                  ? 'create'
                  : 'edit';
              final canSave = BusinessAccessService.can(
                'transactions',
                permission,
              );
              return ElevatedButton.icon(
                onPressed: isSaving || !canSave ? null : _save,
                icon: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 20),
                label: Text(
                  isSaving ? 'Saving...' : 'save_transaction'.tr,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: controller.brandColor.value,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: controller.brandColor.value
                      .withValues(alpha: 0.6),
                  minimumSize: const Size.fromHeight(52),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeToggle() {
    return Obx(() {
      final isExpense = controller.isExpense.value;
      final selectedColor = isExpense
          ? const Color(0xFFB64D4D)
          : const Color(0xFF237A52);
      return Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE1E8E9)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: true,
              label: Text('expense'.tr),
              icon: const Icon(Icons.north_east_rounded),
            ),
            ButtonSegment(
              value: false,
              label: Text('income'.tr),
              icon: const Icon(Icons.south_west_rounded),
            ),
          ],
          selected: {isExpense},
          onSelectionChanged: (selection) {
            final nextIsExpense = selection.first;
            if (isExpense != nextIsExpense) {
              controller.isExpense.value = nextIsExpense;
              controller.selectedCategory.value = '';
            }
          },
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: isExpense
                ? const Color(0xFFFAEEEE)
                : const Color(0xFFEAF5EE),
            selectedForegroundColor: selectedColor,
            foregroundColor: const Color(0xFF75838A),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            side: BorderSide.none,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildDescriptionField() {
    return TextFormField(
      controller: controller.descC,
      decoration: InputDecoration(
        labelText: 'description'.tr,
        prefixIcon: const Icon(Icons.notes_rounded),
        filled: true,
        fillColor: Colors.white,
        border: _fieldBorder(),
        enabledBorder: _fieldBorder(),
        focusedBorder: _fieldBorder(color: const Color(0xFF0E5962), width: 1.5),
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
        prefixIcon: const Icon(Icons.payments_outlined),
        prefixText: 'TSH ',
        filled: true,
        fillColor: Colors.white,
        border: _fieldBorder(),
        enabledBorder: _fieldBorder(),
        focusedBorder: _fieldBorder(color: const Color(0xFF0E5962), width: 1.5),
      ),
      style: const TextStyle(
        color: Color(0xFF19313A),
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: false),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        ThousandsSeparatorInputFormatter(),
      ],
      validator: (v) {
        if (v == null || v.isEmpty) return 'Amount is required';
        if (double.tryParse(v.replaceAll(',', '')) == null) {
          return 'Invalid number';
        }
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
          suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
          filled: true,
          fillColor: Colors.white,
          border: _fieldBorder(),
          enabledBorder: _fieldBorder(),
          focusedBorder: _fieldBorder(
            color: const Color(0xFF0E5962),
            width: 1.5,
          ),
        ),
        validator: (v) =>
            (v == null || v.isEmpty) ? 'Category is required' : null,
      ),
    );
  }

  OutlineInputBorder _fieldBorder({
    Color color = const Color(0xFFE1E8E9),
    double width = 1,
  }) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  Future<void> _showSearchableCategoryPicker() async {
    final searchController = TextEditingController();
    final searchQuery = ''.obs;
    final categoriesRefresh = controller.loadCategories();
    try {
      await Get.bottomSheet(
        SafeArea(
          top: false,
          child: Container(
            height: Get.height * 0.82,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F9F9),
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Column(
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD5DFE1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5F0F0),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.category_rounded,
                        color: Color(0xFF0E5962),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'categories'.tr,
                            style: const TextStyle(
                              color: Color(0xFF19313A),
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Obx(
                            () => Text(
                              controller.isExpense.value
                                  ? 'expense'.tr
                                  : 'income'.tr,
                              style: const TextStyle(
                                color: Color(0xFF75838A),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Obx(
                      () => IconButton(
                        onPressed: controller.categoriesLoading.value
                            ? null
                            : controller.loadCategories,
                        tooltip: 'categories_retry'.tr,
                        icon: controller.categoriesLoading.value
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF0E5962),
                                ),
                              )
                            : const Icon(Icons.refresh_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF0E5962),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: Get.back,
                      tooltip: 'cancel'.tr,
                      icon: const Icon(Icons.close_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF52656A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: searchController,
                  autofocus: true,
                  onChanged: (value) => searchQuery.value = value.trim(),
                  decoration: InputDecoration(
                    labelText: '${'search'.tr} ${'categories'.tr}',
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF0E5962),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(color: Color(0xFFE1E8E9)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(color: Color(0xFFE1E8E9)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xFF0E5962),
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: BusinessAccessService.can('categories', 'create')
                        ? () async {
                            final name = await _showAddCategoryDialog();
                            if (name == null || name.isEmpty) return;
                            await controller.addNewCategory(name);
                            searchController.clear();
                            searchQuery.value = '';
                          }
                        : null,
                    icon: const Icon(Icons.add_rounded),
                    label: Text('add_category_title'.tr),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0E5962),
                      backgroundColor: const Color(0xFFEAF2F2),
                      minimumSize: const Size.fromHeight(48),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: Obx(() {
                    final categories = controller.isExpense.value
                        ? controller.expenseCategories
                        : controller.incomeCategories;
                    final query = searchQuery.value.toLowerCase();
                    final filteredCategories = categories
                        .where(
                          (category) =>
                              category.name.toLowerCase().contains(query),
                        )
                        .toList();

                    if (controller.categoriesLoading.value &&
                        categories.isEmpty) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF0E5962),
                        ),
                      );
                    }

                    if (filteredCategories.isEmpty) {
                      final hasLoadError =
                          controller.categoriesError.value.isNotEmpty;
                      return Center(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: const Color(0xFFE7ECEE)),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 58,
                                height: 58,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF2F2),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Icon(
                                  hasLoadError
                                      ? Icons.cloud_off_outlined
                                      : Icons.sell_outlined,
                                  size: 27,
                                  color: const Color(0xFF0E5962),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                hasLoadError
                                    ? controller.categoriesError.value
                                    : query.isEmpty
                                    ? 'categories_empty'.tr
                                    : 'category_search_empty'.tr,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF52656A),
                                  height: 1.4,
                                ),
                              ),
                              if (hasLoadError) ...[
                                const SizedBox(height: 10),
                                TextButton.icon(
                                  onPressed: controller.loadCategories,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: Text('categories_retry'.tr),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF0E5962),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }

                    return Column(
                      children: [
                        if (controller.categoriesError.value.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: controller.loadCategories,
                              icon: const Icon(Icons.refresh_rounded, size: 17),
                              label: Text('categories_retry'.tr),
                            ),
                          ),
                        Expanded(
                          child: ListView.separated(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            itemCount: filteredCategories.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final category = filteredCategories[index];
                              final isSelected =
                                  controller.selectedCategory.value ==
                                  category.name;
                              return Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(15),
                                child: InkWell(
                                  onTap: () {
                                    controller.selectedCategory.value =
                                        category.name;
                                    Get.back();
                                  },
                                  onLongPress: () {
                                    if (!BusinessAccessService.can(
                                          'categories',
                                          'edit',
                                        ) &&
                                        !BusinessAccessService.can(
                                          'categories',
                                          'delete',
                                        )) {
                                      return;
                                    }
                                    Get.back();
                                    _showCategoryActions(category);
                                  },
                                  borderRadius: BorderRadius.circular(15),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF0E5962)
                                            : const Color(0xFFE7ECEE),
                                        width: isSelected ? 1.4 : 1,
                                      ),
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFFE5F0F0)
                                                : const Color(0xFFF2F5F5),
                                            borderRadius: BorderRadius.circular(
                                              13,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.sell_outlined,
                                            color: isSelected
                                                ? const Color(0xFF0E5962)
                                                : const Color(0xFF75838A),
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            category.name,
                                            style: const TextStyle(
                                              color: Color(0xFF19313A),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        if (isSelected)
                                          const Icon(
                                            Icons.check_circle_rounded,
                                            color: Color(0xFF0E5962),
                                            size: 21,
                                          )
                                        else
                                          const Icon(
                                            Icons.chevron_right_rounded,
                                            color: Color(0xFF9AA8AC),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
      );
    } finally {
      await categoriesRefresh;
      searchController.dispose();
    }
  }

  Widget _buildDateField() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _selectDate,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE1E8E9)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2F2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.calendar_month_outlined,
                  color: Color(0xFF0E5962),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'date'.tr,
                      style: const TextStyle(
                        color: Color(0xFF75838A),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Obx(
                      () => Text(
                        DateFormat.yMMMMd().format(
                          controller.selectedDate.value,
                        ),
                        style: const TextStyle(
                          color: Color(0xFF19313A),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.edit_calendar_outlined,
                color: Color(0xFF0E5962),
                size: 20,
              ),
            ],
          ),
        ),
      ),
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

  Future<String?> _showAddCategoryDialog() async {
    final nameController = TextEditingController();
    try {
      final newCategoryName = await Get.dialog<String>(
        AlertDialog(
          title: Text('add_category_title'.tr),
          content: TextField(
            controller: nameController,
            decoration: InputDecoration(labelText: 'category_name'.tr),
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
          ),
          actions: [
            TextButton(onPressed: Get.back, child: Text('cancel'.tr)),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) Get.back(result: name);
              },
              child: Text('save'.tr),
            ),
          ],
        ),
      );
      return newCategoryName;
    } finally {
      nameController.dispose();
    }
  }

  /// Shows a dialog to edit or delete a category.
  void _showCategoryActions(CategoryModel category) {
    final canEdit = BusinessAccessService.can('categories', 'edit');
    final canDelete = BusinessAccessService.can('categories', 'delete');
    if (!canEdit && !canDelete) return;
    Get.bottomSheet(
      SafeArea(
        child: Wrap(
          children: [
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text('Edit "${category.name}"'),
                onTap: () {
                  Get.back(); // Close the bottom sheet
                  _showEditCategoryDialog(category);
                },
              ),
            if (canDelete)
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
    if (!BusinessAccessService.can('categories', 'edit')) {
      Get.snackbar('error'.tr, 'staff_no_permission'.tr);
      return;
    }
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
    if (!BusinessAccessService.can('categories', 'delete')) {
      Get.snackbar('error'.tr, 'staff_no_permission'.tr);
      return;
    }
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
