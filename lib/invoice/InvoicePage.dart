import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/services/pdf/invoice_pdf.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// // ignore: avoid_web_libraries_in_flutter
// import 'dart:html' as html; // NEW: for web download

class InvoicePage extends StatefulWidget {
  const InvoicePage({super.key});

  @override
  State<InvoicePage> createState() => _InvoicePageState();
}

class _InvoicePageState extends State<InvoicePage> {
  final _formKey = GlobalKey<FormState>();
  bool _busy = false; // track saving/generating state

  final _company = {
    // Branding for the left header block
    'name': 'Lidox Enterprises',
    'brand': 'Lidox Signs',
    'tagline': 'Where Ideas Turn to Innovation',
    // Social/footer
    'handle': '@lidoxinc',
    'website': 'www.lidoxcoltd.com',
    // Address & legal
    'address': 'TABORA - TOWN\nP O BOX 1807\nTABORA , TANZANIA',
    'taxId': '1:53-540-657',
    'email': 'lidoxctd@gmail.com',
    'phone': '0655 900 595',
    'paymentMethod': 'CASH',
    'beneficiary': 'EDGAR JOSEPH NYAMBO',
    'bank': 'CRDB Bank, Tabora Branch',
    'account': '0152955448900',
    'swift': 'CORUTZTZ',
  };

  final _clientController = TextEditingController(text: 'RAZIA AUTO WORKS');
  final _invoiceNoController = TextEditingController(text: '234');
  final _issueDateController = TextEditingController(
    text: _fmtDate(DateTime.now()),
  );
  final _dueDateController = TextEditingController(
    text: _fmtDate(DateTime.now().add(const Duration(days: 0))),
  );

  final List<Map<String, dynamic>> _items = [
    {'desc': 'Profoma', 'qty': 3, 'unit': 15000.0},
    {'desc': 'Invoice', 'qty': 3, 'unit': 15000.0},
    {'desc': 'Delivery Note', 'qty': 3, 'unit': 15000.0},
    {'desc': 'Service Card', 'qty': 50, 'unit': 400.0},
    {'desc': 'Business Card', 'qty': 100, 'unit': 400.0},
    {'desc': 'Sticker', 'qty': 50, 'unit': 400.0},
  ];

  static String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  void dispose() {
    _clientController.dispose();
    _invoiceNoController.dispose();
    _issueDateController.dispose();
    _dueDateController.dispose();
    super.dispose();
  }

  double get _total => _items.fold<double>(
    0,
    (s, it) => s + (it['qty'] as num) * (it['unit'] as num),
  );

  String _money(num v) => v
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

  @override
  Widget build(BuildContext context) {
    final primary = const Color(0xFF1976D2);
    final accent = const Color(0xFF42A5F5);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        foregroundColor: Colors.white,
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
      // Replaces FAB with a sticky bottom action bar
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Total (TSH)',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      _money(_total),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: primary,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _busy ? null : _generate,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.picture_as_pdf),
                label: Text(_busy ? 'Please wait...' : 'Generate PDF'),
              ),
            ],
          ),
        ),
      ),
      body: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: primary, width: 1.6),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Top info section (responsive two columns)
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      SizedBox(
                        width: isWide
                            ? (constraints.maxWidth - 16) / 2
                            : constraints.maxWidth,
                        child: _buildCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionHeader(
                                icon: Icons.person_outline,
                                title: 'Bill To',
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _clientController,
                                decoration: const InputDecoration(
                                  labelText: 'Client name',
                                ),
                                validator: (v) => (v == null || v.isEmpty)
                                    ? 'Required'
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isWide
                            ? (constraints.maxWidth - 16) / 2
                            : constraints.maxWidth,
                        child: _buildCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionHeader(
                                icon: Icons.description_outlined,
                                title: 'Invoice Details',
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _invoiceNoController,
                                      decoration: const InputDecoration(
                                        labelText: 'Invoice No',
                                        prefixIcon: Icon(
                                          Icons.confirmation_number_outlined,
                                        ),
                                      ),
                                      validator: (v) => (v == null || v.isEmpty)
                                          ? 'Required'
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _issueDateController,
                                      readOnly: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Issue date',
                                        prefixIcon: Icon(Icons.event),
                                      ),
                                      onTap: () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: DateTime.now(),
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime(2100),
                                        );
                                        if (picked != null) {
                                          _issueDateController.text = _fmtDate(
                                            picked,
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _dueDateController,
                                      readOnly: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Due date',
                                        prefixIcon: Icon(Icons.event_available),
                                      ),
                                      onTap: () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: DateTime.now(),
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime(2100),
                                        );
                                        if (picked != null) {
                                          _dueDateController.text = _fmtDate(
                                            picked,
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Items section (styled table)
                  _buildCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _sectionHeader(
                              icon: Icons.list_alt,
                              title: 'Items',
                            ),
                            const Spacer(),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: primary,
                                side: BorderSide(color: primary),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () {
                                setState(() {
                                  _items.add({
                                    'desc': 'New Item',
                                    'qty': 1,
                                    'unit': 0.0,
                                  });
                                });
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Add Item'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 12,
                          ),
                          child: Row(
                            children: const [
                              Expanded(
                                flex: 5,
                                child: Text(
                                  'DESCRIPTION',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  'QTY',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  'UNIT PRICE',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              SizedBox(width: 44),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        ..._items.asMap().entries.map((e) {
                          final i = e.key;
                          final it = e.value;
                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: TextFormField(
                                    initialValue: it['desc']?.toString() ?? '',
                                    decoration: const InputDecoration(
                                      labelText: 'Description',
                                    ),
                                    onChanged: (v) => it['desc'] = v,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    initialValue: (it['qty'] ?? 1).toString(),
                                    decoration: const InputDecoration(
                                      labelText: 'Qty',
                                    ),
                                    keyboardType: TextInputType.number,
                                    onChanged: (v) => setState(
                                      () => it['qty'] = int.tryParse(v) ?? 1,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    initialValue: (it['unit'] ?? 0).toString(),
                                    decoration: const InputDecoration(
                                      labelText: 'Unit Price',
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    onChanged: (v) => setState(
                                      () => it['unit'] =
                                          double.tryParse(v) ?? 0.0,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  tooltip: 'Remove',
                                  onPressed: () {
                                    setState(() {
                                      _items.removeAt(i);
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const Divider(height: 24),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Total: TSH ${_money(_total)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }

  Widget _sectionHeader({required IconData icon, required String title}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF1976D2).withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFF1976D2), size: 20),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ],
    );
  }

  // Try saving to Firestore; return docRef or null if permission denied.
  Future<DocumentReference<Map<String, dynamic>>?> _trySaveToFirestore(
    Map<String, dynamic> data,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Get.snackbar('Sign in required', 'Please sign in to save to cloud');
        return null;
      }

      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('invoices');

      final docRef = col.doc();
      debugPrint('Saving to ${docRef.path}');
      await docRef.set({
        ...data,
        'id': docRef.id,
        'uid': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return docRef;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        Get.snackbar(
          'Info',
          'Cloud save skipped (permission denied). Generating PDF only.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return null;
      }
      rethrow;
    }
  }

  Future<void> _generate() async {
    if (!_formKey.currentState!.validate()) return;

    final data = {
      'company': _company,
      'client': {'name': _clientController.text.trim()},
      'invoice': {
        'number': _invoiceNoController.text.trim(),
        'issueDate': _issueDateController.text.trim(),
        'dueDate': _dueDateController.text.trim(),
        'paymentMethod': _company['paymentMethod'],
      },
      'items': _items
          .map(
            (e) => {
              'description': e['desc'],
              'qty': e['qty'],
              'unit': e['unit'],
              'amount': (e['qty'] as num) * (e['unit'] as num),
            },
          )
          .toList(),
      'total': _total,
    };

    setState(() => _busy = true);
    try {
      final docRef = await _trySaveToFirestore(data);
      final savedData = {
        ...data,
        if (docRef != null) 'id': docRef.id,
        'createdAt': DateTime.now().toIso8601String(),
      };
      if (docRef != null) {
        Get.snackbar(
          'Saved',
          'Invoice saved to cloud',
          snackPosition: SnackPosition.BOTTOM,
        );
      }

      // Generate and save via invoice_pdf.dart
      final pathOrName = await InvoicePdf.generateAndSave(
        savedData,
        fileName:
            'invoice_${_invoiceNoController.text.trim().isEmpty ? DateTime.now().millisecondsSinceEpoch : _invoiceNoController.text.trim()}.pdf',
      );

      Get.snackbar(
        kIsWeb ? 'PDF downloaded' : 'PDF saved',
        pathOrName,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
    } on FirebaseException catch (e) {
      Get.snackbar(
        'Error',
        'Cloud error: ${e.message}',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to save/generate: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
