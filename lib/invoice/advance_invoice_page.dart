import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/services/profile_service.dart';
import 'package:tra_list/services/company_logo_service.dart';
import 'package:tra_list/services/business_access_service.dart';
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
  Map<String, dynamic> _company = {};
  Uint8List? _companyLogoBytes;

  // Dynamic colors from profile
  Color _brandColor = const Color(0xFF1976D2);
  Color _accentColor = const Color(0xFFFFA000);

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

  @override
  void initState() {
    super.initState();
    _loadProfileAndBranding();
  }

  Future<void> _loadProfileAndBranding() async {
    try {
      final profile = await ProfileService.loadOrCreate();
      final logoBytes = await CompanyLogoService.resolveLogoBytes(profile);
      if (mounted && profile.containsKey('colors')) {
        final colors = profile['colors'] as Map<String, dynamic>;
        setState(() {
          _company = profile;
          _companyLogoBytes = logoBytes;
          _brandColor = Color(colors['brand'] as int? ?? 0xFF1976D2);
          _accentColor = Color(colors['accent'] as int? ?? 0xFFFFA000);
        });
      } else if (mounted) {
        setState(() {
          _company = profile;
          _companyLogoBytes = logoBytes;
        });
      }
    } catch (e) {
      debugPrint('Failed to load profile colors: $e');
    }
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
    if (!BusinessAccessService.can('invoices', 'create')) {
      Get.snackbar('error'.tr, 'staff_no_permission'.tr);
      return;
    }

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
          .doc(BusinessAccessService.businessId)
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
        foregroundColor: Colors.white,
        title: const Text('Advance Invoice'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_brandColor, _accentColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.save),
            onPressed: _save, // Keep save action
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildCompanyHeaderCard(),
            const SizedBox(height: 12),
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
              color: _brandColor.withOpacity(0.1),
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
            SizedBox(
              height: 50,
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('Save Advance Invoice'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
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

  Widget _buildCompanyHeaderCard() {
    final name = (_company['name'] ?? '').toString().trim();
    final phone = (_company['phone'] ?? '').toString().trim();
    final email = (_company['email'] ?? '').toString().trim();

    return Card(
      elevation: 0,
      color: _brandColor.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Colors.white,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _companyLogoBytes != null
                    ? Image.memory(_companyLogoBytes!, fit: BoxFit.cover)
                    : Icon(Icons.business, color: _brandColor),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Company Profile' : name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  if (phone.isNotEmpty || email.isNotEmpty)
                    Text(
                      [phone, email].where((e) => e.isNotEmpty).join('  •  '),
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
