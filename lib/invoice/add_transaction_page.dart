import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'add_transaction_controller.dart';
import 'transaction_model.dart';
import 'category_model.dart';

class AddTransactionPage extends GetView<AddTransactionController> {
  final TransactionModel? transaction;
  final TransactionType? initialType;

  // Moved from _AddTransactionPageWidgets
  final _formKey = GlobalKey<FormState>();

  AddTransactionPage({super.key, this.transaction, this.initialType});
  @override
  Widget build(BuildContext context) {
    // Initialize the controller, passing constructor arguments
    Get.put(
      AddTransactionController(
        transaction: transaction,
        initialType: initialType,
      ),
    );

    final isNew = transaction == null;
    final isMobile = MediaQuery.of(context).size.width < 420;

    // Height we reserve for the bottom control (button area)
    final double bottomBarHeight = isMobile ? 76.0 : 96.0;

    return Scaffold(
      appBar: _buildAppBar(isNew),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            controller.loadCategories(),
            controller.loadBrandColors(),
          ]);
        },
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomBarHeight),
            children: [
              // Offline indicator banner
              Obx(
                () => controller.isOnline.isFalse
                    ? Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          border: Border.all(color: Colors.orange.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Working offline. Changes will sync when connection is restored.'
                                    .tr,
                                style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              // Type toggle
              _buildTypeToggle(),
              const SizedBox(height: 16),

              // Description
              _buildDescriptionField(),
              const SizedBox(height: 16),

              // Amount (prominent)
              _buildAmountField(context, isMobile),
              const SizedBox(height: 16),

              // Category chips + add
              _buildCategorySelector(),
              const SizedBox(height: 16),

              // Date
              _buildDateField(),
            ],
          ),
        ),
      ),
      // Single bottom control (always present) with responsive styling.
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Future<void> _showAddCategoryDialog() async {
    final nameController = TextEditingController();
    final newCategoryName = await Get.dialog<String>(
      AlertDialog(
        title: Row(
          children: [
            const Text('Add New Category'),
            if (controller.isOnline.isFalse) ...[
              const SizedBox(width: 8),
              Icon(Icons.wifi_off, size: 16, color: Colors.orange),
            ],
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (controller.isOnline.isFalse)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Category will be saved offline and synced when connection is restored.'
                      .tr,
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
            TextField(
              controller: nameController,
              decoration: InputDecoration(labelText: 'category_name'.tr),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text('cancel'.tr)),
          ElevatedButton(
            onPressed: () => Get.back(
              result: nameController.text.trim(), // No tr needed for logic
            ), // No tr needed for logic
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newCategoryName != null && newCategoryName.isNotEmpty) {
      await controller.addNewCategory(newCategoryName);
    }
  }

  AppBar _buildAppBar(bool isNew) {
    return AppBar(
      // Explicitly add a back button.
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Get.back(),
      ),
      title: Obx(
        () => Row(
          children: [
            Text(
              isNew ? 'add_transaction_title'.tr : 'edit_transaction_title'.tr,
            ),
            const Spacer(),
            // Connection status indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: controller.isOnline.value ? Colors.green : Colors.orange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    controller.isOnline.value ? Icons.wifi : Icons.wifi_off,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    controller.isOnline.value ? 'Online'.tr : 'Offline'.tr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      flexibleSpace: Obx(
        () => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                controller.brandColor.value,
                controller.accentColor.value,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      elevation: 2,
      actions: [
        Obx(
          () => controller.busy.isFalse
              ? IconButton(
                  icon: const Icon(Icons.check),
                  tooltip: 'save'.tr,
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      controller.save();
                    }
                  },
                )
              : const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    // Single bottom control (always present) with responsive styling.
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 56,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  controller.brandColor.value,
                  controller.accentColor.value,
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: controller.brandColor.value.withOpacity(0.18),
                  blurRadius: 8,
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  controller.save();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Obx(
                () => controller.busy.value
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            controller.isOnline.value
                                ? Icons.save
                                : Icons.save_alt,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            controller.isOnline.value
                                ? 'save_transaction'.tr
                                : 'Save Offline'.tr,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeToggle() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => controller.isExpense.value = true,
            icon: Obx(
              () => Icon(
                Icons.arrow_downward_rounded,
                color: controller.isExpense.value
                    ? Colors.white
                    : controller.brandColor.value,
              ),
            ),
            label: Obx(
              () => Text(
                'expense'.tr,
                style: TextStyle(
                  color: controller.isExpense.value
                      ? Colors.white
                      : controller.brandColor.value,
                ),
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: controller.isExpense.value
                  ? Colors.red.shade600
                  : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: controller.isExpense.value
                      ? Colors.red.shade600
                      : controller.brandColor.value.withOpacity(0.2),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => controller.isExpense.value = false,
            icon: Obx(
              () => Icon(
                Icons.arrow_upward_rounded,
                color: !controller.isExpense.value
                    ? Colors.white
                    : controller.brandColor.value,
              ),
            ),
            label: Obx(
              () => Text(
                'income'.tr,
                style: TextStyle(
                  color: !controller.isExpense.value
                      ? Colors.white
                      : controller.brandColor.value,
                ),
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: !controller.isExpense.value
                  ? Colors.green.shade700
                  : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                // No tr needed for widgets
                borderRadius: BorderRadius.circular(
                  12,
                ), // No tr needed for widgets
                side: BorderSide(
                  // No tr needed for widgets
                  color:
                      !controller
                          .isExpense
                          .value // No tr needed for widgets
                      ? Colors
                            .green
                            .shade700 // No tr needed for widgets
                      : controller.brandColor.value.withOpacity(
                          0.2,
                        ), // No tr needed for widgets
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDescriptionField() {
    return TextFormField(
      controller: controller.descC,
      decoration: InputDecoration(
        labelText: 'description'.tr,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        prefixIcon: const Icon(Icons.description),
        filled: true,
        fillColor: Colors.white,
      ),
      validator: (v) =>
          (v == null || v.isEmpty) ? 'Description is required'.tr : null,
    );
  }

  Widget _buildAmountField(BuildContext context, bool isMobile) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${'amount'.tr} (TSH)',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: isMobile ? screenWidth * 0.55 : 200,
                  child: TextFormField(
                    controller: controller.amountC,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      prefixText: 'TSH ',
                      prefixStyle: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      ThousandsSeparatorInputFormatter(),
                    ],
                    validator: (v) {
                      if (v == null || v.isEmpty)
                        return 'Amount is required'.tr;
                      if (double.tryParse(v.replaceAll(',', '')) == null)
                        return 'Invalid number'.tr;
                      return null;
                    },
                  ),
                ),
              ],
            ),
            SizedBox(width: isMobile ? 12 : 24),
            Column(
              children: [
                Text('Quick'.tr, style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [5000, 1000].map((val) {
                    return OutlinedButton(
                      onPressed: () {
                        final current =
                            double.tryParse(
                              controller.amountC.text.replaceAll(',', ''),
                            ) ??
                            0;
                        final newVal = (current + val).toInt();
                        final formatted = newVal.toString().replaceAllMapped(
                          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                          (m) => '${m[1]},',
                        );
                        controller.amountC.text = formatted;
                      },
                      child: Text('$val'),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: controller.brandColor.value.withOpacity(0.14),
                        ),
                        minimumSize: const Size(56, 36),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ],
        ),
      ),
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
          Row(
            children: [
              Text(
                'category'.tr,
                style: TextStyle(color: Colors.grey.shade800),
              ),
              if (controller.isOnline.isFalse) ...[
                const SizedBox(width: 8),
                const Icon(Icons.wifi_off, size: 14, color: Colors.orange),
              ],
            ],
          ),
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
                        selectedColor: controller.brandColor.value,
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
                      backgroundColor: controller.brandColor.value.withOpacity(
                        0.12,
                      ),
                    ),
                  ],
                ),
        ],
      );
    });
  }

  Widget _buildDateField() {
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      leading: Obx(
        () => CircleAvatar(
          backgroundColor: controller.brandColor.value.withOpacity(0.12),
          child: Icon(Icons.calendar_today, color: controller.brandColor.value),
        ),
      ),
      title: Text('date'.tr),
      subtitle: Obx(
        () => Text(
          '${controller.selectedDate.value.day}/${controller.selectedDate.value.month}/${controller.selectedDate.value.year}',
        ),
      ),
      trailing: Obx(
        () => TextButton(
          onPressed: _selectDate,
          child: Text('Change'.tr),
          style: TextButton.styleFrom(
            foregroundColor: controller.brandColor.value,
          ),
        ),
      ),
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
}

/// A custom formatter to add thousand separators to a number input.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    final number = int.tryParse(newValue.text.replaceAll(',', ''));
    if (number == null) {
      return oldValue;
    }

    final formatted = number.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );

    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
