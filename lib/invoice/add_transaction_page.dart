import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'transaction_model.dart';
import 'transaction_service.dart';

class AddTransactionPage extends StatefulWidget {
  final TransactionModel? transaction;
  const AddTransactionPage({super.key, this.transaction});

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
  final _categoryC = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.transaction != null) {
      final t = widget.transaction!;
      _isExpense = t.type == TransactionType.expense;
      _descC.text = t.description;
      _amountC.text = t.amount.toString();
      _categoryC.text = t.category;
      _selectedDate = t.date;
    }
  }

  @override
  void dispose() {
    _descC.dispose();
    _amountC.dispose();
    _categoryC.dispose();
    super.dispose();
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
        category: _categoryC.text.trim().isEmpty
            ? 'Uncategorized'
            : _categoryC.text.trim(),
        uid: uid,
      );

      if (widget.transaction == null) {
        await TransactionService.saveTransaction(model);
      } else {
        await TransactionService.updateTransaction(model.id!, model);
      }

      Get.back();
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
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ToggleButtons(
              isSelected: [_isExpense, !_isExpense],
              onPressed: (i) => setState(() => _isExpense = i == 0),
              borderRadius: BorderRadius.circular(8),
              selectedColor: Colors.white,
              fillColor: _isExpense
                  ? Colors.red.shade400
                  : Colors.green.shade400,
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Expense'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Income'),
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
            TextFormField(
              controller: _categoryC,
              decoration: const InputDecoration(
                labelText: 'Category (e.g., Rent, Sales)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category),
              ),
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
