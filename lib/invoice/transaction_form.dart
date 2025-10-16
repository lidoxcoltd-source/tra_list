import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:tra_list/invoice/add_transaction_controller.dart';
import 'package:tra_list/invoice/advance_invoice_page.dart';
import 'package:tra_list/invoice/transaction_model.dart';

class TransactionForm extends StatefulWidget {
  final TransactionModel? transaction;
  final TransactionType? initialType;
  final Future<void> Function(Future<void> Function() saveAction) onSave;
  final VoidCallback onCancel;
  final bool isSaving;

  const TransactionForm({
    super.key,
    this.transaction,
    this.initialType,
    this.isSaving = false,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<TransactionForm> {
  late final AddTransactionController controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Use a unique tag to manage the controller instance for this form
    final tag = widget.transaction?.id ?? 'new_transaction';
    controller = Get.put(
      AddTransactionController(
        transaction: widget.transaction,
        initialType: widget.initialType,
      ),
      tag: tag,
    );
  }

  @override
  void dispose() {
    // Avoid deleting the controller during intermediate rebuilds (e.g., when isSaving toggles).
    // Let GetX SmartManagement clean it up when the page is actually popped.
    // final tag = widget.transaction?.id ?? 'new_transaction';
    // Get.delete<AddTransactionController>(tag: tag);
    super.dispose();
  }

  Future<void> _save() async {
    debugPrint('TransactionForm._save called');
    if (_formKey.currentState!.validate()) {
      await widget.onSave(controller.save);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.transaction == null;

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
          onPressed: widget.onCancel,
          tooltip: 'cancel'.tr,
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: widget.onCancel,
            child: Text('cancel'.tr),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: Obx(
            () => ElevatedButton.icon(
              // Obx is kept for brandColor reactivity
              onPressed: widget.isSaving ? null : _save,
              icon: widget.isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(
                widget.isSaving ? 'saving'.tr : 'save_transaction'.tr,
              ),
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
    return Obx(() {
      final categories = controller.isExpense.value
          ? controller.expenseCategories
          : controller.incomeCategories;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('category'.tr, style: Get.textTheme.titleSmall),
          const SizedBox(height: 8),
          controller.categoriesLoading.value
              ? const Center(child: CircularProgressIndicator())
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...categories.map((cat) {
                      final selected =
                          controller.selectedCategory.value == cat.name;
                      return ChoiceChip(
                        label: Text(cat.name),
                        selected: selected,
                        onSelected: (_) =>
                            controller.selectedCategory.value = cat.name,
                        selectedColor: controller.brandColor.value.withOpacity(
                          0.8,
                        ),
                        backgroundColor: Colors.grey.shade200,
                        labelStyle: TextStyle(
                          color: selected ? Colors.white : Colors.black87,
                        ),
                      );
                    }).toList(),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: Text('Add'.tr),
                      onPressed: _showAddCategoryDialog,
                    ),
                  ],
                ),
        ],
      );
    });
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
}

class AddTransactionPage extends StatefulWidget {
  const AddTransactionPage({super.key});
  @override
  State<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends State<AddTransactionPage> {
  bool isSaving = false;

  @override
  Widget build(BuildContext context) {
    return TransactionForm(
      isSaving: isSaving,
      onCancel: () => Navigator.of(context).pop(),
      onSave: (saveAction) async {
        setState(() => isSaving = true);
        try {
          await saveAction(); // IMPORTANT: actually perform the save
          Get.snackbar('Success', 'Transaction saved');
          Navigator.of(context).pop();
        } catch (e) {
          debugPrint('Save failed: $e');
          Get.snackbar('Error', 'Failed to save');
        } finally {
          if (mounted) setState(() => isSaving = false);
        }
      },
    );
  }
}
