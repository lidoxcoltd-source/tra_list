import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/services.dart';

class AdvanceInvoicePage extends StatefulWidget {
  const AdvanceInvoicePage({super.key});

  @override
  State<AdvanceInvoicePage> createState() => _AdvanceInvoicePageState();
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

class _AdvanceInvoicePageState extends State<AdvanceInvoicePage> {
  final _formKey = GlobalKey<FormState>();
  final _invoiceNoC = TextEditingController(
    text:
        'ADV-${DateTime.now().toIso8601String().split("T").first}-${(DateTime.now().millisecondsSinceEpoch % 100000).toString().padLeft(5, '0')}',
  );
  final _clientNameC = TextEditingController();
  final _paymentMethodC = TextEditingController();
  final _notesC = TextEditingController();
  final _subtotalC = TextEditingController();
  final _taxC = TextEditingController();
  final _advancePaidC = TextEditingController();

  DateTime _issueDate = DateTime.now();
  DateTime? _advanceDueDate = DateTime.now().add(const Duration(days: 5));

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  void dispose() {
    _invoiceNoC.dispose();
    _clientNameC.dispose();
    _paymentMethodC.dispose();
    _notesC.dispose();
    _subtotalC.dispose();
    _taxC.dispose();
    _advancePaidC.dispose();
    super.dispose();
  }

  double get _subtotal =>
      double.tryParse(_subtotalC.text.trim().replaceAll(',', '')) ?? 0;
  double get _tax =>
      double.tryParse(_taxC.text.trim().replaceAll(',', '')) ?? 0;
  double get _total => _subtotal + _tax;
  double get _advancePaid =>
      double.tryParse(_advancePaidC.text.trim().replaceAll(',', '')) ?? 0;
  double get _balance => (_subtotal + _tax) - _advancePaid;

  Future<void> _pickDate({
    required DateTime initial,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Get.snackbar(
        'Not signed in',
        'Sign in before creating documents',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    try {
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('invoices')
          .doc();

      await ref.set({
        'kind': 'advance',
        'createdAt': FieldValue.serverTimestamp(),
        'client': {'name': _clientNameC.text.trim()},
        'invoice': {
          'number': _invoiceNoC.text.trim(),
          'issueDate': _fmtDate(_issueDate),
          'advanceDueDate': _advanceDueDate != null
              ? _fmtDate(_advanceDueDate!)
              : null,
          'paymentMethod': _paymentMethodC.text.trim(),
          'notes': _notesC.text.trim(),
        },
        'items': const [],
        'subtotal': _subtotal,
        'tax': _tax,
        'total': _total,
        'advancePaid': _advancePaid,
        'balance': _balance,
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      Get.snackbar(
        'Saved',
        'Advance invoice created',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to save: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advance Invoice'),
        actions: [
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.save),
            onPressed: _save,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _invoiceNoC,
              decoration: const InputDecoration(
                labelText: 'Invoice number',
                prefixIcon: Icon(Icons.confirmation_number_outlined),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _clientNameC,
              decoration: const InputDecoration(
                labelText: 'Client name',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _paymentMethodC,
              decoration: const InputDecoration(
                labelText: 'Payment method',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesC,
              decoration: const InputDecoration(
                labelText: 'Notes',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Issue date'),
                    subtitle: Text(
                      '${_issueDate.day}/${_issueDate.month}/${_issueDate.year}',
                    ),
                    trailing: const Icon(Icons.event),
                    onTap: () => _pickDate(
                      initial: _issueDate,
                      onPicked: (d) => setState(() => _issueDate = d),
                    ),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Advance due date'),
                    subtitle: Text(
                      _advanceDueDate == null
                          ? 'Not set'
                          : '${_advanceDueDate!.day}/${_advanceDueDate!.month}/${_advanceDueDate!.year}',
                    ),
                    trailing: const Icon(Icons.event_available),
                    onTap: () => _pickDate(
                      initial: _advanceDueDate ?? DateTime.now(),
                      onPicked: (d) => setState(() => _advanceDueDate = d),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            _moneyField(
              controller: _subtotalC,
              label: 'Subtotal (TSH)',
              icon: Icons.calculate_outlined,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            _moneyField(
              controller: _taxC,
              label: 'Tax (TSH)',
              icon: Icons.percent,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            _moneyField(
              controller: _advancePaidC,
              label: 'Advance paid (TSH)',
              icon: Icons.payments,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DefaultTextStyle(
                  style: Theme.of(context).textTheme.bodyMedium!,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _summaryLine('Subtotal', _subtotal),
                      _summaryLine('Tax', _tax),
                      const Divider(),
                      _summaryLine('Total', _total, bold: true),
                      _summaryLine('Advance paid', _advancePaid),
                      const Divider(),
                      _summaryLine('Balance due', _balance, bold: true),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Save Advance Invoice'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moneyField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required ValueChanged<String> onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        ThousandsSeparatorInputFormatter(),
      ],
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixText: 'TSH',
      ),
      onChanged: onChanged,
      validator: (v) =>
          (double.tryParse(v?.trim().replaceAll(',', '') ?? '') == null)
          ? 'Enter a number'
          : null,
    );
  }

  Widget _summaryLine(String label, double value, {bool bold = false}) {
    final style = bold
        ? Theme.of(
            context,
          ).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(context).textTheme.bodyMedium!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value.toStringAsFixed(0), style: style),
        ],
      ),
    );
  }
}
