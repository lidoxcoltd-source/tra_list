import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/services/pdf/invoice_pdf.dart';
import 'package:tra_list/services/pdf/proforma_pdf.dart';
import 'package:tra_list/services/pdf/delivery_note_pdf.dart';
import 'package:tra_list/services/pdf/payment_reminder_pdf.dart';
import 'package:tra_list/services/pdf/payment_details_pdf.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:tra_list/services/profile_service.dart';

class InvoicePage extends StatefulWidget {
  final DocumentSnapshot<Map<String, dynamic>>? invoice;
  const InvoicePage({super.key, this.invoice});

  @override
  State<InvoicePage> createState() => _InvoicePageState();
}

class _InvoicePageState extends State<InvoicePage> {
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  // Company profile loaded from Firestore
  Map<String, dynamic> _company = {};

  // Dynamic colors from profile
  Color _brandColor = const Color(0xFF1976D2);
  Color _accentColor = const Color(0xFFFFA000);

  final _clientController = TextEditingController(text: '');
  final _invoiceNoController = TextEditingController(
    text:
        'INV-${DateTime.now().toIso8601String().split("T").first}-${(DateTime.now().millisecondsSinceEpoch % 100000).toString().padLeft(5, '0')}',
  );
  final _issueDateController = TextEditingController(
    text: _fmtDate(DateTime.now()),
  );
  final _dueDateController = TextEditingController(
    text: _fmtDate(DateTime.now().add(const Duration(days: 0))),
  );

  final List<Map<String, dynamic>> _items = [];

  static String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  void initState() {
    super.initState();
    // fetch profile from Firestore and load colors
    _loadCompanyAndColors();

    if (widget.invoice != null) {
      final data = widget.invoice!.data();
      if (data != null) {
        final invoiceData = data['invoice'] as Map<String, dynamic>? ?? {};
        final clientData = data['client'] as Map<String, dynamic>? ?? {};
        final itemsData = data['items'] as List<dynamic>? ?? [];

        _clientController.text = clientData['name'] ?? '';
        _invoiceNoController.text = invoiceData['number'] ?? '';
        _issueDateController.text = invoiceData['issueDate'] ?? _fmtDate(DateTime.now());
        _dueDateController.text = invoiceData['dueDate'] ?? _fmtDate(DateTime.now());

        _items.clear();
        _items.addAll(itemsData.map((item) {
          final itemMap = item as Map<String, dynamic>;
          return {
            'desc': itemMap['description'] ?? '',
            'qty': itemMap['qty'] ?? 1,
            'unit': itemMap['unit'] ?? 0.0,
          };
        }));
      }
    }
  }

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

  Future<void> _loadCompanyAndColors() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        debugPrint('InvoicePage: no signed-in user; skip company load');
        Get.snackbar(
          'Not signed in',
          'Sign in to load company profile',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }
      final profile = await ProfileService.loadOrCreate();
      if (!mounted) return;
      setState(() {
        _company = profile ?? {};
        if (profile.containsKey('colors')) {
          final colors = profile['colors'] as Map<String, dynamic>;
          _brandColor = Color(colors['brand'] as int? ?? 0xFF1976D2);
          _accentColor = Color(colors['accent'] as int? ?? 0xFFFFA000);
        }
      });
      debugPrint(
        'InvoicePage: loaded company: ${_company['name'] ?? '(none)'}',
      );
    } catch (e) {
      debugPrint('InvoicePage: failed to load company: $e');
      if (!mounted) return;
      Get.snackbar(
        'Profile',
        'Failed to load company details',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          // Apply consistent gradient
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_brandColor, _accentColor],
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
                        color: _brandColor,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _brandColor,
                  side: BorderSide(color: _brandColor),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _busy ? null : _chooseDocTypeAndPreview,
                icon: const Icon(Icons.preview_outlined),
                label: const Text('Preview'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _busy ? null : _chooseDocTypeAndSave,
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
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              borderSide: BorderSide(
                color: Color(0xFF1976D2),
                width: 1.6,
              ), // Kept for consistency
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
                                foregroundColor: _brandColor,
                                side: BorderSide(color: _brandColor),
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
                            color: _brandColor.withOpacity(0.08),
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
                              color: _brandColor,
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
            // Use brand color
            color: _brandColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: _brandColor, size: 20),
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
  Future<void> _trySaveToFirestore(
    Map<String, dynamic> data,
    String kind,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Get.snackbar('Sign in required', 'Please sign in to save to cloud');
        return;
      }

      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('invoices');

      if (widget.invoice != null) {
        // Update existing document
        debugPrint('Updating ${widget.invoice!.id}');
        await col.doc(widget.invoice!.id).update({
          ...data,
          'kind': kind,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Create new document
        final docRef = col.doc();
        debugPrint('Saving to ${docRef.path}');
        await docRef.set({
          ...data,
          'kind': kind,
          'id': docRef.id,
          'uid': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        Get.snackbar(
          'Info',
          'Cloud save skipped (permission denied). Generating PDF only.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      }
      rethrow;
    }
  }

  Map<String, dynamic> _buildData() {
    return {
      // Include loaded company; PDFs also auto-fetch if empty
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
  }

  Future<void> _chooseDocTypeAndSave() async {
    if (!_formKey.currentState!.validate()) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('Invoice'),
              onTap: () => _saveDoc('invoice'),
            ),
            ListTile(
              leading: const Icon(Icons.request_quote_outlined),
              title: const Text('Proforma'),
              onTap: () => _saveDoc('proforma'),
            ),
            ListTile(
              leading: const Icon(Icons.local_shipping_outlined),
              title: const Text('Delivery Note'),
              onTap: () => _saveDoc('delivery'),
            ),
            ListTile(
              leading: const Icon(Icons.alarm_on_outlined),
              title: const Text('Payment Reminder'),
              onTap: () => _saveDoc('reminder'),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Payment Details'),
              onTap: () => _saveDoc('payment_details'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseDocTypeAndPreview() async {
    if (!_formKey.currentState!.validate()) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('Invoice'),
              onTap: () => _previewDoc('invoice'),
            ),
            ListTile(
              leading: const Icon(Icons.request_quote_outlined),
              title: const Text('Proforma'),
              onTap: () => _previewDoc('proforma'),
            ),
            ListTile(
              leading: const Icon(Icons.local_shipping_outlined),
              title: const Text('Delivery Note'),
              onTap: () => _previewDoc('delivery'),
            ),
            ListTile(
              leading: const Icon(Icons.alarm_on_outlined),
              title: const Text('Payment Reminder'),
              onTap: () => _previewDoc('reminder'),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Payment Details'),
              onTap: () => _previewDoc('payment_details'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _previewDoc(String kind) async {
    Navigator.pop(context);
    setState(() => _busy = true);
    try {
      final data = _buildData();

      await ({
        'invoice': () => InvoicePdf.generate(data),
        'proforma': () => ProformaPdf.generate(data),
        'delivery': () => DeliveryNotePdf.generate(data),
        'reminder': () => PaymentReminderPdf.generate(data),
        'payment_details': () => PaymentDetailsPdf.generate(data),
      }[kind]!).call();
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to generate preview: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveDoc(String kind) async {
    Navigator.pop(context);
    setState(() => _busy = true);
    try {
      final data = _buildData();

      // Save a record to Firestore before generating the PDF
      await _trySaveToFirestore(data, kind);

      final invNo = (_invoiceNoController.text.trim().isEmpty)
          ? DateTime.now().millisecondsSinceEpoch.toString()
          : _invoiceNoController.text.trim();

      final fileNameBase = kind == 'invoice'
          ? 'invoice_$invNo'
          : kind == 'proforma'
          ? 'proforma_$invNo'
          : kind == 'delivery'
          ? 'delivery_note_$invNo'
          : kind == 'reminder'
          ? 'payment_reminder_$invNo'
          : 'payment_details_$invNo';
      final fileName = '$fileNameBase.pdf';

      final pathOrName = await ({
        'invoice': () => InvoicePdf.generateAndSave(data, fileName: fileName),
        'proforma': () => ProformaPdf.generateAndSave(data, fileName: fileName),
        'delivery': () =>
            DeliveryNotePdf.generateAndSave(data, fileName: fileName),
        'reminder': () =>
            PaymentReminderPdf.generateAndSave(data, fileName: fileName),
        'payment_details': () =>
            PaymentDetailsPdf.generateAndSave(data, fileName: fileName),
      }[kind]!).call();

      Get.snackbar(
        kIsWeb ? 'PDF downloaded' : 'PDF saved',
        pathOrName,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to save PDF: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
