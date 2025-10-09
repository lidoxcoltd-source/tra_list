import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'transaction_model.dart';
import 'category_model.dart';
import 'category_service.dart';
import 'transaction_service.dart';

class AddTransactionPage extends StatefulWidget {
  final TransactionModel? transaction;
  final TransactionType? initialType;

  const AddTransactionPage({super.key, this.transaction, this.initialType});
  @override
  State<AddTransactionPage> createState() => _AddTransactionPageState();
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

class _AddTransactionPageState extends State<AddTransactionPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isExpense = true;
  final _descC = TextEditingController();
  final _amountC = TextEditingController();
  String? _selectedCategory;
  DateTime _selectedDate = DateTime.now();
  bool _busy = false;

  // State for categories dropdown
  List<CategoryModel> _incomeCategories = [];
  List<CategoryModel> _expenseCategories = [];
  bool _categoriesLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.transaction != null) {
      final t = widget.transaction!;
      _isExpense = t.type == TransactionType.expense;
      _descC.text = t.description;
      _amountC.text = t.amount.toString();
      _selectedCategory = t.category;
      _selectedDate = t.date;
    } else if (widget.initialType != null) {
      _isExpense = widget.initialType == TransactionType.expense;
    }
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _categoriesLoading = true);
    try {
      final snapshot = await CategoryService.getCategoriesStream().first;
      final allCategories = snapshot.docs.map((doc) => doc.data()).toList();
      if (mounted) {
        setState(() {
          _incomeCategories = allCategories
              .where((c) => c.type == TransactionType.income)
              .toList();
          _expenseCategories = allCategories
              .where((c) => c.type == TransactionType.expense)
              .toList();
        });
      }
    } finally {
      if (mounted) setState(() => _categoriesLoading = false);
    }
  }

  @override
  void dispose() {
    _descC.dispose();
    _amountC.dispose();
    super.dispose();
  }

  Future<void> _showAddCategoryDialog() async {
    final nameController = TextEditingController();
    final newCategoryName = await Get.dialog<String>(
      AlertDialog(
        title: const Text('Add New Category'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Category Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Get.back(result: nameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newCategoryName != null && newCategoryName.isNotEmpty) {
      final newCategory = CategoryModel(
        name: newCategoryName,
        type: _isExpense ? TransactionType.expense : TransactionType.income,
      );
      await CategoryService.addCategory(newCategory);
      await _loadCategories(); // Refresh the list
      setState(() {
        _selectedCategory = newCategoryName; // Auto-select the new category
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('User not signed in');

      final model = TransactionModel(
        id: widget.transaction?.id,
        type: _isExpense ? TransactionType.expense : TransactionType.income,
        description: _descC.text.trim(),
        amount: double.tryParse(_amountC.text.replaceAll(',', '')) ?? 0.0,
        date: _selectedDate,
        category: _selectedCategory == null || _selectedCategory!.isEmpty
            ? 'Uncategorized'
            : _selectedCategory!,
        uid: uid,
      );

      if (widget.transaction == null) {
        await TransactionService.saveTransaction(model);
      } else {
        await TransactionService.updateTransaction(model.id!, model);
      }

      Get.back(result: true); // Return true on success
      Get.snackbar(
        'Success',
        'Transaction saved successfully',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to save transaction: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.transaction == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Add Transaction' : 'Edit Transaction'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadCategories,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        if (!_isExpense) setState(() => _isExpense = true);
                      },
                      icon: Icon(
                        Icons.arrow_downward_rounded,
                        color: _isExpense ? Colors.red.shade700 : Colors.grey,
                      ),
                      label: Text(
                        'Expense',
                        style: TextStyle(
                          color: _isExpense
                              ? Colors.red.shade700
                              : Colors.black87,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        backgroundColor: _isExpense
                            ? Colors.red.shade50
                            : Colors.transparent,
                        side: BorderSide(
                          color: _isExpense
                              ? Colors.red.shade300
                              : Colors.grey.shade300,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        if (_isExpense) setState(() => _isExpense = false);
                      },
                      icon: Icon(
                        Icons.arrow_upward_rounded,
                        color: !_isExpense
                            ? Colors.green.shade700
                            : Colors.grey,
                      ),
                      label: Text(
                        'Income',
                        style: TextStyle(
                          color: !_isExpense
                              ? Colors.green.shade700
                              : Colors.black87,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        backgroundColor: !_isExpense
                            ? Colors.green.shade50
                            : Colors.transparent,
                        side: BorderSide(
                          color: !_isExpense
                              ? Colors.green.shade300
                              : Colors.grey.shade300,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descC,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Description is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountC,
                decoration: const InputDecoration(
                  labelText: 'Amount (TSH)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                ),
                keyboardType: TextInputType.number,
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
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      items:
                          (_isExpense ? _expenseCategories : _incomeCategories)
                              .map(
                                (cat) => DropdownMenuItem(
                                  value: cat.name,
                                  child: Text(cat.name),
                                ),
                              )
                              .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedCategory = value;
                        });
                      },
                      decoration: InputDecoration(
                        labelText: 'Category',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.category),
                        suffixIcon: _categoriesLoading
                            ? const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      hint: const Text('Select a category'),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please select a category';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _showAddCategoryDialog,
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Add new category',
                    padding: const EdgeInsets.only(top: 8),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                  side: BorderSide(color: Colors.grey.shade400),
                ),
                leading: const Icon(Icons.calendar_today),
                title: const Text('Date'),
                subtitle: Text(
                  '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null && picked != _selectedDate) {
                    setState(() => _selectedDate = picked);
                  }
                },
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: Text(_busy ? 'Saving...' : 'Save Transaction'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }
}
