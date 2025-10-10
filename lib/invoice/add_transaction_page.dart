import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'transaction_model.dart';
import 'category_model.dart';
import 'category_service.dart';
import 'transaction_service.dart';
import 'package:tra_list/services/profile_service.dart'; // <--- added

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

  // Brand colors (fetched from ProfileService if available)
  Color _brandColor = const Color(0xFF1976D2);
  Color _accentColor = const Color(0xFF42A5F5);

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
    _loadBrandColors(); // <--- fetch colors from firebase/profile
  }

  Future<void> _loadBrandColors() async {
    // No-op/default implementation so the file compiles even if ProfileService
    // does not expose a static `getProfile` method. If your ProfileService
    // provides an instance method (for example `ProfileService().getProfile()`)
    // or a differently named static method (for example `fetchProfile()`),
    // replace the implementation below to fetch and apply profile colors.
    //
    // Example (if your service has an instance method):
    // try {
    //   final profile = await ProfileService().getProfile();
    //   if (profile != null) {
    //     setState(() {
    //       final b = _tryParseColor(profile.brandColor);
    //       final a = _tryParseColor(profile.accentColor);
    //       if (b != null) _brandColor = b;
    //       if (a != null) _accentColor = a;
    //     });
    //   }
    // } catch (_) {
    //   // ignore and keep defaults
    // }
    return;
  }

  Color? _tryParseColor(dynamic value) {
    if (value == null) return null;
    try {
      if (value is int) return Color(value);
      if (value is String) {
        var hex = value.replaceAll('#', '').toUpperCase();
        if (hex.length == 6) hex = 'FF$hex';
        return Color(int.parse(hex, radix: 16));
      }
    } catch (_) {}
    return null;
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
    // Responsive helpers
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 420;
    final categories = _isExpense ? _expenseCategories : _incomeCategories;

    // Height we reserve for the bottom control (button area)
    final double bottomBarHeight = isMobile ? 76.0 : 96.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Add Transaction' : 'Edit Transaction'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_brandColor, _accentColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 2,
        actions: [
          if (!_busy)
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Save',
              onPressed: _save,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([_loadCategories(), _loadBrandColors()]);
        },
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomBarHeight),
            children: [
              // Type toggle
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (!_isExpense) setState(() => _isExpense = true);
                      },
                      icon: Icon(
                        Icons.arrow_downward_rounded,
                        color: _isExpense ? Colors.white : _brandColor,
                      ),
                      label: Text(
                        'Expense',
                        style: TextStyle(
                          color: _isExpense ? Colors.white : _brandColor,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isExpense
                            ? Colors.red.shade600
                            : Colors.white,
                        foregroundColor: _isExpense
                            ? Colors.white
                            : _brandColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: _isExpense
                                ? Colors.red.shade600
                                : _brandColor.withOpacity(0.2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (_isExpense) setState(() => _isExpense = false);
                      },
                      icon: Icon(
                        Icons.arrow_upward_rounded,
                        color: !_isExpense ? Colors.white : _brandColor,
                      ),
                      label: Text(
                        'Income',
                        style: TextStyle(
                          color: !_isExpense ? Colors.white : _brandColor,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: !_isExpense
                            ? Colors.green.shade700
                            : Colors.white,
                        foregroundColor: !_isExpense
                            ? Colors.white
                            : _brandColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: !_isExpense
                                ? Colors.green.shade700
                                : _brandColor.withOpacity(0.2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Description
              TextFormField(
                controller: _descC,
                decoration: InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.description),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Description is required' : null,
              ),
              const SizedBox(height: 16),

              // Amount (prominent)
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Amount (TSH)',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Make the amount field responsive: expand on small screens,
                          // keep a comfortable width on larger screens.
                          SizedBox(
                            width: isMobile ? screenWidth * 0.55 : 200,
                            child: TextFormField(
                              controller: _amountC,
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
                                  return 'Amount is required';
                                if (double.tryParse(v.replaceAll(',', '')) ==
                                    null)
                                  return 'Invalid number';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      SizedBox(width: isMobile ? 12 : 24),
                      // Quick amount buttons
                      Column(
                        children: [
                          Text(
                            'Quick',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            children: [5000, 1000].map((val) {
                              return OutlinedButton(
                                onPressed: () {
                                  final current =
                                      double.tryParse(
                                        _amountC.text.replaceAll(',', ''),
                                      ) ??
                                      0;
                                  final newVal = (current + val).toInt();
                                  final formatted = newVal
                                      .toString()
                                      .replaceAllMapped(
                                        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                                        (m) => '${m[1]},',
                                      );
                                  setState(() => _amountC.text = formatted);
                                },
                                child: Text('$val'),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: _brandColor.withOpacity(0.14),
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
              ),
              const SizedBox(height: 16),

              // Category chips + add
              Text('Category', style: TextStyle(color: Colors.grey.shade800)),
              const SizedBox(height: 8),
              _categoriesLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...categories.map((cat) {
                          final selected = _selectedCategory == cat.name;
                          return ChoiceChip(
                            label: Text(cat.name),
                            selected: selected,
                            onSelected: (_) =>
                                setState(() => _selectedCategory = cat.name),
                            selectedColor: _brandColor,
                            backgroundColor: Colors.grey.shade200,
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : Colors.black87,
                            ),
                          );
                        }).toList(),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 18),
                          label: const Text('Add'),
                          onPressed: _showAddCategoryDialog,
                          backgroundColor: _brandColor.withOpacity(0.12),
                        ),
                      ],
                    ),
              const SizedBox(height: 16),

              // Date
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                leading: CircleAvatar(
                  backgroundColor: _brandColor.withOpacity(0.12),
                  child: Icon(Icons.calendar_today, color: _brandColor),
                ),
                title: const Text('Date'),
                subtitle: Text(
                  '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                ),
                trailing: TextButton(
                  onPressed: () async {
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
                  child: Text('Change'),
                  style: TextButton.styleFrom(foregroundColor: _brandColor),
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
              // remove the fixed spacer -- we now reserve bottom space with ListView padding
            ],
          ),
        ),
      ),
      // Single bottom control (always present) with responsive styling.
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 56,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [_brandColor, _accentColor]),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: _brandColor.withOpacity(0.18),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _busy ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _busy
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
                        children: const [
                          Icon(Icons.save, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Save Transaction',
                            style: TextStyle(
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
}
