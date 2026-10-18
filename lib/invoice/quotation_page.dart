import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:tra_list/services/company_logo_service.dart';
import 'package:tra_list/services/profile_service.dart';
import 'package:tra_list/services/pdf/quotation_pdf.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/thousands_separator_formatter.dart';

class QuotationPage extends StatefulWidget {
  final DocumentSnapshot<Map<String, dynamic>>? quotation; // for editing
  const QuotationPage({super.key, this.quotation});

  @override
  State<QuotationPage> createState() => _QuotationPageState();
}

class _QuotationPageState extends State<QuotationPage> {
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  // Company profile loaded from Firestore
  Map<String, dynamic> _company = {};
  Uint8List? _companyLogoBytes;

  // Dynamic colors from profile
  Color _brandColor = const Color(0xFF1976D2);
  Color _accentColor = const Color(0xFFFFA000);

  final _clientController = TextEditingController(text: '');
  final _quotationNoController = TextEditingController(
    text:
        'QUO-${DateTime.now().toIso8601String().split("T").first}-${(DateTime.now().millisecondsSinceEpoch % 100000).toString().padLeft(5, '0')}',
  );
  final _issueDateController = TextEditingController(
    text: _fmtDate(DateTime.now()),
  );
  final _expiryDateController = TextEditingController(
    text: _fmtDate(
      DateTime.now().add(const Duration(days: 14)),
    ), // e.g. valid for 14 days
  );

  final List<Map<String, dynamic>> _items = [];

  static String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  void initState() {
    super.initState();
    _loadCompanyAndColors();

    if (widget.quotation != null) {
      final data = widget.quotation!.data();
      if (data != null) {
        final invoiceData =
            data['invoice'] as Map<String, dynamic>? ??
            {}; // It's saved as 'invoice' in firestore from InvoicePage
        final clientData = data['client'] as Map<String, dynamic>? ?? {};
        final itemsData = data['items'] as List<dynamic>? ?? [];

        _clientController.text = clientData['name'] ?? '';
        _quotationNoController.text = invoiceData['number'] ?? '';
        _issueDateController.text =
            invoiceData['issueDate'] ?? _fmtDate(DateTime.now());
        _expiryDateController.text =
            invoiceData['dueDate'] ??
            _fmtDate(
              DateTime.now().add(const Duration(days: 14)),
            ); // Using 'dueDate' field for now

        _items.clear();
        _items.addAll(
          itemsData.map((item) {
            final itemMap = item as Map<String, dynamic>;
            return {
              'desc': itemMap['description'] ?? '',
              'qty': itemMap['qty'] ?? 1,
              'unit': itemMap['unit'] ?? 0.0,
            };
          }),
        );
      }
    }
  }

  @override
  void dispose() {
    _clientController.dispose();
    _quotationNoController.dispose();
    _issueDateController.dispose();
    _expiryDateController.dispose();
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
      final profile = await ProfileService.loadOrCreate();
      final logoBytes = await CompanyLogoService.resolveLogoBytes(profile);
      if (!mounted) return;
      setState(() {
        _company = profile ?? {};
        _companyLogoBytes = logoBytes;
        if (profile.containsKey('colors')) {
          final colors = profile['colors'] as Map<String, dynamic>;
          _brandColor = Color(colors['brand'] as int? ?? 0xFF1976D2);
          _accentColor = Color(colors['accent'] as int? ?? 0xFFFFA000);
        }
      });
    } catch (e) {
      debugPrint('QuotationPage: failed to load company: $e');
      if (!mounted) return;
      Get.snackbar(
        'Profile',
        'Failed to load company details',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionHeader({required IconData icon, required String title}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: _brandColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade800,
          ),
        ),
      ],
    );
  }

  Map<String, dynamic> _prepareData() {
    return {
      'kind': 'quotation',
      'client': {'name': _clientController.text},
      'invoice': {
        'number': _quotationNoController.text,
        'issueDate': _issueDateController.text,
        'dueDate': _expiryDateController.text,
      },
      'items': _items
          .map(
            (it) => {
              'description': it['desc'],
              'qty': it['qty'],
              'unit': it['unit'],
              'total': (it['qty'] as num) * (it['unit'] as num),
            },
          )
          .toList(),
      'total': _total,
      'company': _company,
      'createdAt': widget.quotation?.data()?['createdAt'] ?? Timestamp.now(),
    };
  }

  Future<void> _previewQuotation() async {
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      Get.snackbar('Error', 'Please add at least one item');
      return;
    }
    try {
      await QuotationPdf.generate(_prepareData());
    } catch (e) {
      Get.snackbar('Error', 'Failed to preview: $e');
    }
  }

  Future<void> _saveQuotation() async {
    if (!_formKey.currentState!.validate()) return;
    final permissionAction = widget.quotation == null ? 'create' : 'edit';
    if (!BusinessAccessService.can('quotations', permissionAction)) {
      Get.snackbar('Error', 'staff_no_permission'.tr);
      return;
    }
    if (_items.isEmpty) {
      Get.snackbar('Error', 'Please add at least one item');
      return;
    }

    setState(() => _busy = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'User not logged in';

      final data = _prepareData();
      final docRef =
          widget.quotation?.reference ??
          FirebaseFirestore.instance
              .collection('users')
              .doc(BusinessAccessService.businessId)
              .collection('invoices')
              .doc();

      await docRef.set(data, SetOptions(merge: true));

      final fileName = 'quotation_${_quotationNoController.text}.pdf';
      final pathOrName = await QuotationPdf.generateAndSave(
        data,
        fileName: fileName,
      );

      Get.snackbar(
        kIsWeb ? 'PDF downloaded' : 'PDF saved',
        pathOrName,
        snackPosition: SnackPosition.BOTTOM,
      );

      if (widget.quotation == null) Navigator.pop(context);
    } catch (e) {
      Get.snackbar('Error', 'Failed to save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.quotation == null ? 'Create Quotation' : 'Edit Quotation',
        ),
        elevation: 0,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_brandColor, _accentColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
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
                onPressed: _busy ? null : _previewQuotation,
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
                onPressed: _busy ? null : _saveQuotation,
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
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              borderSide: BorderSide(color: _brandColor, width: 1.6),
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
                  _buildCompanyHeaderCard(),
                  const SizedBox(height: 16),
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
                                title: 'Quote To',
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
                                title: 'Quotation Details',
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _quotationNoController,
                                decoration: const InputDecoration(
                                  labelText: 'Quotation No',
                                  prefixIcon: Icon(
                                    Icons.confirmation_number_outlined,
                                  ),
                                ),
                                validator: (v) => (v == null || v.isEmpty)
                                    ? 'Required'
                                    : null,
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
                                      controller: _expiryDateController,
                                      readOnly: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Expiry date',
                                        prefixIcon: Icon(Icons.event_busy),
                                      ),
                                      onTap: () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: DateTime.now().add(
                                            const Duration(days: 14),
                                          ),
                                          firstDate: DateTime.now(),
                                          lastDate: DateTime(2100),
                                        );
                                        if (picked != null) {
                                          _expiryDateController.text = _fmtDate(
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
                                    initialValue:
                                        ThousandsSeparatorFormatter.format(
                                          (it['unit'] ?? 0) as num,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Unit Price',
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    inputFormatters: const [
                                      ThousandsSeparatorFormatter(),
                                    ],
                                    onChanged: (v) => setState(
                                      () => it['unit'] =
                                          ThousandsSeparatorFormatter.parse(
                                            v,
                                          ) ??
                                          0.0,
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

  Widget _buildCompanyHeaderCard() {
    final name = (_company['name'] ?? '').toString().trim();
    final phone = (_company['phone'] ?? '').toString().trim();
    final email = (_company['email'] ?? '').toString().trim();

    return _buildCard(
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: _brandColor.withOpacity(0.1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _companyLogoBytes != null
                  ? Image.memory(_companyLogoBytes!, fit: BoxFit.cover)
                  : Icon(Icons.business, color: _brandColor),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Company Profile' : name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
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
    );
  }
}
