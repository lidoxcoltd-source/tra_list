import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tra_list/invoice/category_model.dart';
import 'package:tra_list/invoice/transaction_service.dart';
import 'package:tra_list/invoice/category_service.dart';
import 'package:tra_list/invoice/add_transaction_controller.dart';
import 'package:tra_list/invoice/advance_invoice_page.dart';
import 'package:tra_list/invoice/transaction_model.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/theme/app_theme.dart';

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
                  Obx(() {
                    if (!controller.isExpense.value ||
                        BusinessAccessService.isOwner.value ||
                        BusinessAccessService.dailyExpenseLimit.value <= 0) {
                      return const SizedBox.shrink();
                    }
                    final date = controller.selectedDate.value;
                    return _DailyExpenseLimitWarning(
                      key: ValueKey('${date.year}-${date.month}-${date.day}'),
                      controller: controller,
                      date: date,
                      limit: BusinessAccessService.dailyExpenseLimit.value,
                    );
                  }),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE1E8E9)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildAmountField(context),
                        const SizedBox(height: 16),
                        _buildDescriptionField(),
                        const SizedBox(height: 16),
                        _buildCategorySelector(context),
                        const SizedBox(height: 12),
                        _buildDateField(),
                        const SizedBox(height: 12),
                        _buildTransactionInsightsButton(context),
                      ],
                    ),
                  ),
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

  Widget _buildCategorySelector(BuildContext context) {
    return Obx(
      () => TextFormField(
        key: ValueKey(controller.selectedCategory.value), // Rebuild on change
        initialValue: controller.selectedCategory.value.isEmpty
            ? null
            : controller.selectedCategory.value,
        readOnly: true,
        onTap: () => _showSearchableCategoryPicker(context),
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

  Future<void> _showSearchableCategoryPicker(BuildContext context) async {
    final searchController = TextEditingController();
    final searchQuery = ''.obs;
    final favoriteCategories = <String>[].obs;
    final mostUsedCategories = <String>[].obs;
    final quickCategoriesLoading = true.obs;
    final categoryType = controller.isExpense.value
        ? TransactionType.expense
        : TransactionType.income;
    final favoritesKey =
        'favorite_categories_${BusinessAccessService.businessId}_${categoryType.name}';

    Future<void> loadQuickCategories() async {
      try {
        final preferences = await SharedPreferences.getInstance();
        favoriteCategories.assignAll(
          preferences.getStringList(favoritesKey) ?? const <String>[],
        );
        final start = DateTime.now().subtract(const Duration(days: 90));
        final snapshot = await TransactionService.getTransactions(
          limit: 500,
          startDate: start,
        );
        final usage = <String, int>{};
        for (final transaction in snapshot.docs.map((doc) => doc.data())) {
          if (transaction.type != categoryType ||
              transaction.category.trim().isEmpty) {
            continue;
          }
          usage.update(
            transaction.category.trim(),
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
        final ranked = usage.keys.toList()
          ..sort((a, b) {
            final countOrder = usage[b]!.compareTo(usage[a]!);
            return countOrder != 0 ? countOrder : a.compareTo(b);
          });
        mostUsedCategories.assignAll(ranked.take(3));
      } catch (error, stackTrace) {
        debugPrint('Could not load favorite and popular categories: $error');
        debugPrintStack(stackTrace: stackTrace);
        Get.snackbar(
          'error'.tr,
          Get.locale?.languageCode == 'sw'
              ? 'Imeshindwa kupakia kategoria unazotumia mara nyingi.'
              : 'Could not load frequently used categories.',
          snackPosition: SnackPosition.BOTTOM,
        );
      } finally {
        quickCategoriesLoading.value = false;
      }
    }

    Future<void> toggleFavorite(String name) async {
      final next = favoriteCategories.toList();
      if (next.contains(name)) {
        next.remove(name);
      } else {
        next.insert(0, name);
      }
      try {
        final preferences = await SharedPreferences.getInstance();
        final saved = await preferences.setStringList(favoritesKey, next);
        if (!saved) throw StateError('Could not save favorite categories.');
        favoriteCategories.assignAll(next);
      } catch (error, stackTrace) {
        debugPrint('Could not save favorite category "$name": $error');
        debugPrintStack(stackTrace: stackTrace);
        Get.snackbar(
          'error'.tr,
          Get.locale?.languageCode == 'sw'
              ? 'Imeshindwa kuhifadhi kategoria pendwa.'
              : 'Could not save favorite category.',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }

    unawaited(loadQuickCategories());
    final categoriesRefresh = controller.loadCategories();
    try {
      await Get.bottomSheet(
        DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.82,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (sheetContext, sheetScrollController) => SafeArea(
            top: false,
            child: Container(
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
                      onPressed:
                          BusinessAccessService.can('categories', 'create')
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
                      final availableNames = categories
                          .map((category) => category.name)
                          .toSet();
                      final pinned = favoriteCategories
                          .where(
                            (name) =>
                                availableNames.contains(name) &&
                                name.toLowerCase().contains(query),
                          )
                          .toList();
                      final popular = mostUsedCategories
                          .where(
                            (name) =>
                                availableNames.contains(name) &&
                                name.toLowerCase().contains(query),
                          )
                          .take(3)
                          .toList();

                      Widget quickPicks(
                        String title,
                        List<String> names,
                        IconData icon,
                      ) {
                        if (query.isNotEmpty || names.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Color(0xFF52656A),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                height: 38,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: names.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (context, index) {
                                    final name = names[index];
                                    return ActionChip(
                                      avatar: Icon(icon, size: 16),
                                      label: Text(name),
                                      onPressed: () {
                                        controller.selectedCategory.value =
                                            name;
                                        Get.back();
                                      },
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: Colors.white,
                                      side: const BorderSide(
                                        color: Color(0xFFE1E8E9),
                                      ),
                                      labelStyle: const TextStyle(
                                        color: Color(0xFF19313A),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      }

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
                              border: Border.all(
                                color: const Color(0xFFE7ECEE),
                              ),
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

                      final sortedCategories = [...filteredCategories]
                        ..sort((a, b) {
                          final aPinned = favoriteCategories.contains(a.name);
                          final bPinned = favoriteCategories.contains(b.name);
                          if (aPinned == bPinned) {
                            return a.name.compareTo(b.name);
                          }
                          return aPinned ? -1 : 1;
                        });

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (controller.categoriesError.value.isNotEmpty)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: controller.loadCategories,
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 17,
                                ),
                                label: Text('categories_retry'.tr),
                              ),
                            ),
                          if (quickCategoriesLoading.value && query.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: LinearProgressIndicator(minHeight: 2),
                            ),
                          quickPicks(
                            Get.locale?.languageCode == 'sw'
                                ? 'Kategoria pendwa'
                                : 'Favorites',
                            pinned,
                            Icons.push_pin_outlined,
                          ),
                          quickPicks(
                            Get.locale?.languageCode == 'sw'
                                ? 'Zinazotumika zaidi'
                                : 'Most used',
                            popular,
                            Icons.local_fire_department_outlined,
                          ),
                          Expanded(
                            child: ListView.separated(
                              controller: sheetScrollController,
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              itemCount: sortedCategories.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final category = sortedCategories[index];
                                final isSelected =
                                    controller.selectedCategory.value ==
                                    category.name;
                                final isFavorite = favoriteCategories.contains(
                                  category.name,
                                );

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
                                              borderRadius:
                                                  BorderRadius.circular(13),
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
                                          IconButton(
                                            tooltip: isFavorite
                                                ? (Get.locale?.languageCode ==
                                                          'sw'
                                                      ? 'Ondoa kwenye pendwa'
                                                      : 'Remove from favorites')
                                                : (Get.locale?.languageCode ==
                                                          'sw'
                                                      ? 'Bandika kwenye pendwa'
                                                      : 'Pin to favorites'),
                                            visualDensity:
                                                VisualDensity.compact,
                                            constraints: const BoxConstraints(
                                              minWidth: 40,
                                              minHeight: 40,
                                            ),
                                            onPressed: () {
                                              unawaited(
                                                toggleFavorite(category.name),
                                              );
                                            },
                                            icon: Icon(
                                              isFavorite
                                                  ? Icons.push_pin_rounded
                                                  : Icons.push_pin_outlined,
                                              color: isFavorite
                                                  ? const Color(0xFF1565C0)
                                                  : const Color(0xFF9AA8AC),
                                              size: 19,
                                            ),
                                          ),
                                          Icon(
                                            isSelected
                                                ? Icons.check_circle_rounded
                                                : Icons.chevron_right_rounded,
                                            color: isSelected
                                                ? const Color(0xFF0E5962)
                                                : const Color(0xFF9AA8AC),
                                            size: 21,
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

  Widget _buildTransactionInsightsButton(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _showTransactionInsights(context),
      icon: const Icon(Icons.auto_awesome_rounded),
      label: Text(
        Get.locale?.languageCode == 'sw'
            ? 'Uchambuzi wa muamala'
            : 'Transaction insights',
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: MjasiColors.primaryBlue,
        side: const BorderSide(color: MjasiColors.primaryBlue),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _showTransactionInsights(BuildContext context) async {
    final selectedDate = controller.selectedDate.value;
    final end = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day + 1,
    );
    final start = end.subtract(const Duration(days: 30));
    final category = controller.selectedCategory.value.trim();
    final type = controller.isExpense.value
        ? TransactionType.expense
        : TransactionType.income;
    final amount = double.tryParse(controller.amountC.text.replaceAll(',', ''));
    final transactionsFuture =
        TransactionService.getTransactions(
          limit: 500,
          startDate: start,
          endDate: end,
          category: category.isEmpty ? null : category,
        ).then(
          (snapshot) => snapshot.docs
              .map((doc) => doc.data())
              .where((transaction) => transaction.type == type)
              .toList(),
        );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          decoration: const BoxDecoration(
            color: MjasiColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MjasiColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: MjasiColors.primaryBlue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      Get.locale?.languageCode == 'sw'
                          ? 'Kinachoendelea'
                          : 'What is happening',
                      style: const TextStyle(
                        color: MjasiColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'close'.tr,
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: FutureBuilder<List<TransactionModel>>(
                  future: transactionsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          Get.locale?.languageCode == 'sw'
                              ? 'Imeshindwa kupata miamala ya kulinganisha. Tafadhali jaribu tena.'
                              : 'Could not load comparison transactions. Please try again.',
                          style: const TextStyle(color: MjasiColors.error),
                        ),
                      );
                    }

                    final recent = snapshot.data ?? const <TransactionModel>[];
                    final total = recent.fold<double>(
                      0,
                      (sum, transaction) => sum + transaction.amount,
                    );
                    final average = recent.isEmpty
                        ? 0.0
                        : total / recent.length;
                    final largest = recent.isEmpty
                        ? null
                        : recent.reduce((a, b) => a.amount >= b.amount ? a : b);
                    final money = NumberFormat('#,##0.##');
                    final sw = Get.locale?.languageCode == 'sw';
                    final isExpense = type == TransactionType.expense;
                    final typeLabel = (isExpense ? 'expense' : 'income').tr;

                    final insights = <String>[];
                    if (category.isEmpty) {
                      insights.add(
                        sw
                            ? 'Chagua kategoria ili ulinganishe muamala huu na rekodi za kategoria maalum.'
                            : 'Choose a category to compare this entry with records for a specific category.',
                      );
                    }
                    if (recent.isEmpty) {
                      insights.add(
                        sw
                            ? 'Hakuna ${isExpense ? 'matumizi' : 'mapato'} yaliyorekodiwa katika siku 30 zilizopita kwa chaguo hili. Rekodi hii itaanza kuweka historia ya kulinganisha.'
                            : 'No ${isExpense ? 'expenses' : 'income'} were recorded in the last 30 days for this selection. This entry will start a comparison history.',
                      );
                    } else {
                      insights.add(
                        sw
                            ? 'Katika siku 30 zilizopita, rekodi ${recent.length} za $typeLabel ${category.isEmpty ? '' : 'kwenye "$category" '}zilikuwa na jumla ya TSH ${money.format(total)} na wastani wa TSH ${money.format(average)} kwa muamala.'
                            : 'In the last 30 days, ${recent.length} $typeLabel entries${category.isEmpty ? '' : ' in "$category"'} totalled TSH ${money.format(total)}, averaging TSH ${money.format(average)} per entry.',
                      );
                      if (amount != null && amount > 0 && average > 0) {
                        final difference = ((amount - average) / average * 100)
                            .round();
                        if (difference.abs() < 15) {
                          insights.add(
                            sw
                                ? 'Kiasi hiki kiko karibu na wastani wa rekodi zako za hivi karibuni.'
                                : 'This amount is close to your recent average.',
                          );
                        } else {
                          insights.add(
                            sw
                                ? 'Kiasi hiki kiko ${difference.abs()}% ${difference > 0 ? 'juu' : 'chini'} ya wastani wa hivi karibuni.'
                                : 'This amount is ${difference.abs()}% ${difference > 0 ? 'above' : 'below'} your recent average.',
                          );
                        }
                      }
                      if (largest != null) {
                        insights.add(
                          sw
                              ? 'Rekodi kubwa zaidi katika kipindi hicho ilikuwa TSH ${money.format(largest.amount)} (${largest.description}).'
                              : 'The largest entry in that period was TSH ${money.format(largest.amount)} (${largest.description}).',
                        );
                      }
                    }
                    if (selectedDate.year != DateTime.now().year ||
                        selectedDate.month != DateTime.now().month ||
                        selectedDate.day != DateTime.now().day) {
                      insights.add(
                        sw
                            ? 'Tarehe iliyochaguliwa ni ${DateFormat.yMMMMd().format(selectedDate)}; muamala huu utaonekana kwenye ripoti ya tarehe hiyo, si ya leo.'
                            : 'The selected date is ${DateFormat.yMMMMd().format(selectedDate)}; this entry will appear in that date’s reports, not today’s.',
                      );
                    }

                    return ListView(
                      shrinkWrap: true,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: MjasiColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: MjasiColors.border),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isExpense
                                    ? Icons.trending_down_rounded
                                    : Icons.trending_up_rounded,
                                color: isExpense
                                    ? MjasiColors.error
                                    : MjasiColors.success,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${controller.descC.text.trim().isEmpty ? typeLabel : controller.descC.text.trim()}${category.isEmpty ? '' : ' · $category'}',
                                  style: const TextStyle(
                                    color: MjasiColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (amount != null)
                                Text(
                                  'TSH ${money.format(amount)}',
                                  style: TextStyle(
                                    color: isExpense
                                        ? MjasiColors.error
                                        : MjasiColors.success,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final insight in insights)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: MjasiColors.surface,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.lightbulb_outline_rounded,
                                    size: 19,
                                    color: MjasiColors.primaryBlue,
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      insight,
                                      style: const TextStyle(
                                        height: 1.4,
                                        color: MjasiColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Text(
                          sw
                              ? 'Uchambuzi huu umetokana na miamala iliyorekodiwa katika siku 30 zilizopita.'
                              : 'This insight is based on transactions recorded in the last 30 days.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: MjasiColors.textSecondary,
                          ),
                        ),
                      ],
                    );
                  },
                ),
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

class _DailyExpenseLimitWarning extends StatefulWidget {
  const _DailyExpenseLimitWarning({
    super.key,
    required this.controller,
    required this.date,
    required this.limit,
  });

  final AddTransactionController controller;
  final DateTime date;
  final double limit;

  @override
  State<_DailyExpenseLimitWarning> createState() =>
      _DailyExpenseLimitWarningState();
}

class _DailyExpenseLimitWarningState extends State<_DailyExpenseLimitWarning>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;
  double _spent = 0;
  bool _loading = true;
  bool _checkFailed = false;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    widget.controller.amountC.addListener(_syncBlink);
    _loadDailyTotal();
  }

  @override
  void didUpdateWidget(covariant _DailyExpenseLimitWarning oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.date.year != widget.date.year ||
        oldWidget.date.month != widget.date.month ||
        oldWidget.date.day != widget.date.day) {
      _loadDailyTotal();
    } else if (oldWidget.limit != widget.limit) {
      _syncBlink();
    }
  }

  Future<void> _loadDailyTotal() async {
    setState(() {
      _loading = true;
      _checkFailed = false;
    });
    _syncBlink();
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Sign in to check daily expenses.');
      final total = await TransactionService.getStaffDailyExpenseTotal(
        employeeUid: uid,
        date: widget.date,
        excludeTransactionId: widget.controller.editingTransactionId,
      );
      if (!mounted) return;
      setState(() {
        _spent = total;
        _loading = false;
      });
      _syncBlink();
    } catch (error, stackTrace) {
      debugPrint('Could not check the staff daily expense limit: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _checkFailed = true;
        _loading = false;
      });
      _syncBlink();
    }
  }

  void _syncBlink() {
    final entered =
        double.tryParse(
          widget.controller.amountC.text.replaceAll(',', '').trim(),
        ) ??
        0;
    final exceeded =
        !_loading && !_checkFailed && _spent + entered > widget.limit;
    if (exceeded && !_blink.isAnimating) {
      _blink.repeat(reverse: true);
    } else if (!exceeded && _blink.isAnimating) {
      _blink.stop();
      _blink.reset();
    }
  }

  @override
  void dispose() {
    widget.controller.amountC.removeListener(_syncBlink);
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller.amountC, _blink]),
      builder: (context, _) {
        final entered =
            double.tryParse(
              widget.controller.amountC.text.replaceAll(',', '').trim(),
            ) ??
            0;
        final projected = _spent + entered;
        final exceeded = !_loading && !_checkFailed && projected > widget.limit;

        final baseColor = _checkFailed || exceeded
            ? const Color(0xFFFFF0ED)
            : const Color(0xFFEAF5EF);
        final backgroundColor = exceeded
            ? Color.lerp(baseColor, const Color(0xFFFFD6CE), _blink.value)!
            : baseColor;
        final foregroundColor = exceeded || _checkFailed
            ? const Color(0xFF9B3025)
            : const Color(0xFF236344);
        final formatter = NumberFormat('#,##0.##');
        final remaining = (widget.limit - projected).clamp(0, widget.limit);

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: exceeded || _checkFailed
                    ? const Color(0xFFE8AAA1)
                    : const Color(0xFFC9E1D2),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _checkFailed
                      ? Icons.sync_problem_rounded
                      : exceeded
                      ? Icons.warning_amber_rounded
                      : Icons.shield_outlined,
                  color: foregroundColor,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'staff_expense_limit_title'.tr,
                        style: TextStyle(
                          color: foregroundColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      if (_loading)
                        const LinearProgressIndicator(minHeight: 3)
                      else if (_checkFailed)
                        Text(
                          'staff_expense_limit_check_failed'.tr,
                          style: TextStyle(
                            color: foregroundColor,
                            fontSize: 12,
                          ),
                        )
                      else ...[
                        Text(
                          exceeded
                              ? 'staff_expense_limit_exceeded'.tr
                              : 'staff_expense_limit_remaining'.trParams({
                                  'amount': formatter.format(remaining),
                                }),
                          style: TextStyle(
                            color: foregroundColor,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'staff_expense_limit_spent'.trParams({
                            'spent': formatter.format(projected),
                            'limit': formatter.format(widget.limit),
                          }),
                          style: TextStyle(
                            color: foregroundColor,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 7),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (projected / widget.limit)
                                .clamp(0.0, 1.0)
                                .toDouble(),
                            minHeight: 5,
                            backgroundColor: Colors.white,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              exceeded
                                  ? const Color(0xFFB63D31)
                                  : const Color(0xFF3B8A62),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
