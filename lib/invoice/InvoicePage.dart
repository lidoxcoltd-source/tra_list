import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/services/pdf/invoice_pdf.dart';
import 'package:tra_list/services/pdf/proforma_pdf.dart';
import 'package:tra_list/services/pdf/quotation_pdf.dart';
import 'package:tra_list/services/pdf/advance_payment_pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tra_list/services/pdf/pdf_saver.dart';
import 'package:tra_list/services/pdf/delivery_note_pdf.dart';
import 'package:tra_list/services/pdf/payment_reminder_pdf.dart';
import 'package:tra_list/services/pdf/payment_details_pdf.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:tra_list/services/profile_service.dart';
import 'package:tra_list/services/company_logo_service.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/notification_service.dart';
import 'package:tra_list/services/document_terms_service.dart';
import 'package:tra_list/invoice/document_share_sheet.dart';
import 'package:tra_list/services/thousands_separator_formatter.dart';
import 'package:tra_list/stock/stock_models.dart';
import 'package:tra_list/stock/stock_service.dart';
import 'package:tra_list/stock/stock_ui.dart';

class InvoicePage extends StatefulWidget {
  final DocumentSnapshot<Map<String, dynamic>>? invoice;
  const InvoicePage({super.key, this.invoice});

  @override
  State<InvoicePage> createState() => _InvoicePageState();
}

class _InvoicePageState extends State<InvoicePage> {
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  bool _includeTerms = false;

  // Company profile loaded from Firestore
  Map<String, dynamic> _company = {};
  Uint8List? _companyLogoBytes;

  // Dynamic colors from profile
  Color _brandColor = const Color(0xFF1976D2);
  Color _accentColor = const Color(0xFFFFA000);

  final _clientController = TextEditingController(text: '');
  final _invoiceNameController = TextEditingController();
  final _termsController = TextEditingController();
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
  Map<String, dynamic> _baseDocumentTerms = {};
  String? _savedDocId;

  static String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
  static String get _defaultConditions => Get.locale?.languageCode == 'sw'
      ? 'Malipo yanapaswa kufanyika baada ya kupokea hati hii. Tafadhali wasiliana nasi ikiwa una maswali.'
      : 'Payment is due upon receipt. Please contact us if you have any questions.';

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
        _invoiceNameController.text = invoiceData['name'] ?? '';
        final savedTerms = data['documentTerms'] as Map<String, dynamic>? ?? {};
        _includeTerms = savedTerms['includeConditions'] == true;
        _termsController.text = savedTerms['conditions']?.toString() ?? '';
        _invoiceNoController.text =
            invoiceData['numberCode'] ?? invoiceData['number'] ?? '';
        _issueDateController.text =
            invoiceData['issueDate'] ?? _fmtDate(DateTime.now());
        _dueDateController.text =
            invoiceData['dueDate'] ?? _fmtDate(DateTime.now());

        _items.clear();
        _items.addAll(
          itemsData.map((item) {
            final itemMap = item as Map<String, dynamic>;
            return {
              'desc': itemMap['description'] ?? '',
              'qty': itemMap['qty'] ?? 1,
              'unit': itemMap['unit'] ?? 0.0,
              if (itemMap['productId'] != null)
                'productId': itemMap['productId'],
            };
          }),
        );
      }
    }
  }

  @override
  void dispose() {
    _clientController.dispose();
    _invoiceNameController.dispose();
    _termsController.dispose();
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

  num _parseQty(String v) {
    final d = double.tryParse(v.trim());
    if (d == null || d <= 0) return 1;
    return d == d.roundToDouble() ? d.toInt() : d;
  }

  Future<void> _addFromStock() async {
    try {
      final products = await StockService.current().watchProducts().first;
      if (!mounted) return;
      final p = await pickProduct(context, products);
      if (p == null) return;
      setState(() {
        _items.add({
          'desc': p.name,
          'qty': 1,
          'unit': p.sellPrice,
          'productId': p.id,
        });
      });
    } catch (e) {
      Get.snackbar('error'.tr, stockErrorText(e));
    }
  }

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
      final logoBytes = await CompanyLogoService.resolveLogoBytes(profile);
      final selectedTerms = DocumentTermsService.selectedFor(
        profile,
        'invoice',
      );
      final savedData = widget.invoice?.data();
      final savedTerms = savedData?['documentTerms'] as Map? ?? const {};
      final savedConditions = savedTerms['conditions']?.toString().trim() ?? '';
      final selectedConditions =
          selectedTerms['conditions']?.toString().trim() ?? '';
      final fallbackConditions = selectedConditions.isNotEmpty
          ? selectedConditions
          : _defaultConditions;
      if (!mounted) return;
      setState(() {
        _company = profile ?? {};
        _companyLogoBytes = logoBytes;
        _baseDocumentTerms = {
          ...selectedTerms,
          if (savedTerms.isNotEmpty) ...Map<String, dynamic>.from(savedTerms),
          'conditions': savedConditions.isNotEmpty
              ? savedConditions
              : fallbackConditions,
        };
        if (_termsController.text.trim().isEmpty) {
          _termsController.text = savedConditions.isNotEmpty
              ? savedConditions
              : fallbackConditions;
        }
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
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          'Create document',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
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
      bottomNavigationBar: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          return Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 20,
              vertical: compact ? 10 : 12,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: compact
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.receipt_long_rounded,
                              size: 18,
                              color: Colors.black54,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Total (TSH)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  _money(_total),
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    color: _brandColor,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _brandColor,
                                  side: BorderSide(
                                    color: _brandColor.withValues(alpha: .35),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                ),
                                onPressed: _busy
                                    ? null
                                    : _chooseDocTypeAndPreview,
                                icon: const Icon(
                                  Icons.preview_outlined,
                                  size: 18,
                                ),
                                label: const Text('Preview'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.outlined(
                              tooltip: 'Share as image',
                              style: IconButton.styleFrom(
                                foregroundColor: _brandColor,
                                side: BorderSide(
                                  color: _brandColor.withValues(alpha: .35),
                                ),
                                minimumSize: const Size(46, 46),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(11),
                                ),
                              ),
                              onPressed: _busy ? null : _chooseDocTypeAndShare,
                              icon: const Icon(Icons.share_outlined, size: 19),
                            ),
                            const SizedBox(width: 6),
                            IconButton.outlined(
                              tooltip: 'Send link on WhatsApp',
                              style: IconButton.styleFrom(
                                foregroundColor: const Color(0xFF168A62),
                                side: const BorderSide(
                                  color: Color(0x33168A62),
                                ),
                                minimumSize: const Size(42, 42),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(11),
                                ),
                              ),
                              onPressed: _busy
                                  ? null
                                  : _chooseDocTypeAndWhatsApp,
                              icon: const Icon(Icons.chat_outlined, size: 19),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _brandColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                ),
                                onPressed: _busy ? null : _chooseDocTypeAndSave,
                                icon: _busy
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.picture_as_pdf_outlined,
                                        size: 18,
                                      ),
                                label: Text(_busy ? 'Wait...' : 'Save PDF'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Total (TSH)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
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
                        IconButton.outlined(
                          tooltip: 'Share as image',
                          style: IconButton.styleFrom(
                            foregroundColor: _brandColor,
                            side: BorderSide(color: _brandColor),
                            padding: const EdgeInsets.all(14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _busy ? null : _chooseDocTypeAndShare,
                          icon: const Icon(Icons.share_outlined),
                        ),
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          tooltip: 'Send link on WhatsApp',
                          style: IconButton.styleFrom(
                            foregroundColor: const Color(0xFF168A62),
                            side: const BorderSide(color: Color(0x33168A62)),
                            padding: const EdgeInsets.all(14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _busy ? null : _chooseDocTypeAndWhatsApp,
                          icon: const Icon(Icons.chat_outlined),
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
                          label: Text(
                            _busy ? 'Please wait...' : 'Generate PDF',
                          ),
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Theme(
            data: Theme.of(context).copyWith(
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _brandColor, width: 1.6),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 13,
                ),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;
                final isCompact = constraints.maxWidth < 600;
                final horizontalPadding = isCompact ? 12.0 : 20.0;
                final contentWidth =
                    constraints.maxWidth - horizontalPadding * 2;
                return Form(
                  key: _formKey,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      isCompact ? 12 : 20,
                      horizontalPadding,
                      24,
                    ),
                    children: [
                      _buildCompanyHeaderCard(),
                      const SizedBox(height: 16),
                      // Top info section (responsive two columns)
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          SizedBox(
                            width: isWide
                                ? (contentWidth - 16) / 2
                                : contentWidth,
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
                                ? (contentWidth - 16) / 2
                                : contentWidth,
                            child: _buildCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _sectionHeader(
                                    icon: Icons.description_outlined,
                                    title: 'Invoice Details',
                                  ),
                                  const SizedBox(height: 12),
                                  if (isCompact) ...[
                                    Row(
                                      children: [
                                        Expanded(child: _invoiceNameField()),
                                        const SizedBox(width: 8),
                                        Expanded(child: _invoiceNumberField()),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _dateField(
                                            _issueDateController,
                                            'Issue date',
                                            Icons.event_outlined,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _dateField(
                                            _dueDateController,
                                            'Due date',
                                            Icons.event_available_outlined,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ] else
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: _invoiceNameField(),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 3,
                                          child: _invoiceNumberField(),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 2,
                                          child: _dateField(
                                            _issueDateController,
                                            'Issue date',
                                            Icons.event_outlined,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 2,
                                          child: _dateField(
                                            _dueDateController,
                                            'Due date',
                                            Icons.event_available_outlined,
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
                            _sectionHeader(
                              icon: Icons.gavel_outlined,
                              title: 'Terms & Conditions',
                            ),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Include terms on document'),
                              value: _includeTerms,
                              activeColor: _brandColor,
                              onChanged: (value) {
                                setState(() => _includeTerms = value);
                              },
                            ),
                            if (_includeTerms) ...[
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _termsController,
                                minLines: 3,
                                maxLines: 6,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  hintText:
                                      'Add terms for this document. Leave empty to use the default terms.',
                                  alignLabelWithHint: true,
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: _brandColor,
                                      width: 1.6,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'These terms will appear on the generated document.',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
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
                                if (widget.invoice == null)
                                  if (isCompact)
                                    IconButton.outlined(
                                      tooltip: 'stk_from_stock'.tr,
                                      color: _brandColor,
                                      onPressed: _addFromStock,
                                      icon: const Icon(
                                        Icons.inventory_2_outlined,
                                      ),
                                    )
                                  else
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: IconButton.outlined(
                                        tooltip: 'stk_from_stock'.tr,
                                        color: _brandColor,
                                        onPressed: _addFromStock,
                                        icon: const Icon(
                                          Icons.inventory_2_outlined,
                                        ),
                                      ),
                                    ),
                                if (isCompact)
                                  IconButton.filled(
                                    tooltip: 'Add Item',
                                    style: IconButton.styleFrom(
                                      backgroundColor: _brandColor,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: _addEmptyItem,
                                    icon: const Icon(Icons.add_rounded),
                                  )
                                else
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _brandColor,
                                      side: BorderSide(color: _brandColor),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: _addEmptyItem,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add Item'),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (!isCompact)
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
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        'QTY',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        'UNIT PRICE',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 44),
                                  ],
                                ),
                              ),
                            if (!isCompact) const SizedBox(height: 6),
                            ..._items.asMap().entries.map((e) {
                              final i = e.key;
                              final it = e.value;
                              return _buildItemEditor(
                                i,
                                it,
                                compact: isCompact,
                              );
                            }),
                            if (!isCompact) ...[
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
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _addEmptyItem() {
    setState(() {
      _items.add({'desc': 'New Item', 'qty': 1, 'unit': 0.0});
    });
  }

  Widget _dateField(
    TextEditingController controller,
    String label,
    IconData icon,
  ) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked != null) controller.text = _fmtDate(picked);
      },
    );
  }

  Widget _invoiceNameField() {
    return TextFormField(
      controller: _invoiceNameController,
      textCapitalization: TextCapitalization.words,
      maxLength: 32,
      decoration: const InputDecoration(
        labelText: 'Name (optional)',
        hintText: 'Short name, e.g. Office chairs',
        prefixIcon: Icon(Icons.label_outline_rounded),
        counterText: '',
      ),
    );
  }

  Widget _invoiceNumberField() {
    return TextFormField(
      controller: _invoiceNoController,
      decoration: const InputDecoration(
        labelText: 'Invoice No',
        prefixIcon: Icon(Icons.confirmation_number_outlined),
      ),
      validator: (value) =>
          value == null || value.trim().isEmpty ? 'Required' : null,
    );
  }

  String get _displayInvoiceNumber {
    final number = _invoiceNoController.text.trim();
    final name = _invoiceNameController.text.trim();
    if (name.isEmpty) return number;
    return '$number - $name';
  }

  Map<String, dynamic> _dataForStorage(Map<String, dynamic> data) {
    final invoice = Map<String, dynamic>.from(
      data['invoice'] as Map<String, dynamic>,
    );
    invoice['number'] = invoice.remove('numberCode');
    return {...data, 'invoice': invoice};
  }

  Widget _buildItemEditor(
    int index,
    Map<String, dynamic> item, {
    required bool compact,
  }) {
    final description = TextFormField(
      initialValue: item['desc']?.toString() ?? '',
      decoration: const InputDecoration(
        labelText: 'Description',
        prefixIcon: Icon(Icons.inventory_2_outlined),
      ),
      onChanged: (value) => item['desc'] = value,
    );
    final quantity = TextFormField(
      initialValue: (item['qty'] ?? 1).toString(),
      decoration: const InputDecoration(labelText: 'Qty'),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (value) => setState(() => item['qty'] = _parseQty(value)),
    );
    final unitPrice = TextFormField(
      initialValue: ThousandsSeparatorFormatter.format(
        (item['unit'] as num?) ?? 0,
      ),
      decoration: const InputDecoration(labelText: 'Unit Price'),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: const [ThousandsSeparatorFormatter()],
      onChanged: (value) => setState(
        () => item['unit'] = ThousandsSeparatorFormatter.parse(value) ?? 0.0,
      ),
    );
    final removeButton = IconButton(
      tooltip: 'Remove',
      onPressed: () => setState(() => _items.removeAt(index)),
      style: IconButton.styleFrom(
        foregroundColor: Colors.red.shade700,
        backgroundColor: Colors.red.shade50,
      ),
      icon: const Icon(Icons.delete_outline_rounded),
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: EdgeInsets.all(compact ? 10 : 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: compact
          ? Column(
              children: [
                description,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(flex: 2, child: quantity),
                    const SizedBox(width: 8),
                    Expanded(flex: 3, child: unitPrice),
                    const SizedBox(width: 4),
                    removeButton,
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(flex: 5, child: description),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: quantity),
                const SizedBox(width: 8),
                Expanded(flex: 3, child: unitPrice),
                const SizedBox(width: 6),
                removeButton,
              ],
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EAF0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
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
      final storageData = _dataForStorage(data);
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Get.snackbar('Sign in required', 'Please sign in to save to cloud');
        return;
      }
      final existingId = widget.invoice?.id ?? _savedDocId;
      if (!BusinessAccessService.can(
        'invoices',
        existingId == null ? 'create' : 'edit',
      )) {
        if (_savedDocId != null) return; // already saved by this session
        Get.snackbar('error'.tr, 'staff_no_permission'.tr);
        return;
      }

      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(BusinessAccessService.businessId)
          .collection('invoices');

      if (existingId != null) {
        // Update existing document
        debugPrint('Updating $existingId');
        await col.doc(existingId).update({
          ...storageData,
          'kind': kind,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await NotificationService.notifyOwner(
          action: kind == 'quotation' ? 'quotation' : 'invoice',
          summary:
              'edited $kind $_displayInvoiceNumber (TSH ${_total.toStringAsFixed(0)})',
          amount: _total,
        );
      } else {
        // Create new document
        final docRef = col.doc();
        debugPrint('Saving to ${docRef.path}');
        final saleData = {
          ...storageData,
          'kind': kind,
          'id': docRef.id,
          'uid': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        };
        final stockLines = kind == 'invoice'
            ? _items
                  .where((e) => e['productId'] != null)
                  .map(
                    (e) => SaleLine(
                      productId: e['productId'].toString(),
                      quantity: (e['qty'] as num).toDouble(),
                    ),
                  )
                  .toList()
            : <SaleLine>[];
        if (stockLines.isEmpty) {
          await docRef.set(saleData);
        } else {
          // Sale record and stock deduction commit together or not at all.
          try {
            await StockService.current().finalizeSale(
              saleRef: docRef,
              saleData: saleData,
              lines: stockLines,
            );
          } on FirebaseException catch (e) {
            if (e.code == 'permission-denied') {
              throw StockException('stk_err_permission');
            }
            rethrow;
          }
        }
        _savedDocId = docRef.id;
        await NotificationService.notifyOwner(
          action: kind == 'quotation' ? 'quotation' : 'invoice',
          summary:
              'created $kind $_displayInvoiceNumber (TSH ${_total.toStringAsFixed(0)})',
          amount: _total,
        );
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
    final conditions = _includeTerms ? _termsController.text.trim() : '';
    final documentTerms = {
      ..._baseDocumentTerms,
      'includeConditions': _includeTerms,
      'conditions': !_includeTerms
          ? ''
          : conditions.isNotEmpty
          ? conditions
          : (_baseDocumentTerms['conditions']?.toString().trim().isNotEmpty ??
                false)
          ? _baseDocumentTerms['conditions']
          : _defaultConditions,
    };
    return {
      // Include loaded company; PDFs also auto-fetch if empty
      'company': _company,
      'client': {'name': _clientController.text.trim()},
      'documentTerms': documentTerms,
      'invoice': {
        'number': _displayInvoiceNumber,
        'numberCode': _invoiceNoController.text.trim(),
        'name': _invoiceNameController.text.trim(),
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
              if (e['productId'] != null) 'productId': e['productId'],
              'amount': (e['qty'] as num) * (e['unit'] as num),
            },
          )
          .toList(),
      'total': _total,
    };
  }

  static const _docKinds = <(String, String, IconData)>[
    ('invoice', 'Invoice', Icons.receipt_long),
    ('quotation', 'Quotation', Icons.format_quote_outlined),
    ('proforma', 'Proforma', Icons.request_quote_outlined),
    ('delivery', 'Delivery Note', Icons.local_shipping_outlined),
    ('advance_payment', 'Advance Payment', Icons.payments_outlined),
    ('reminder', 'Payment Reminder', Icons.alarm_on_outlined),
    (
      'payment_details',
      'Payment Details',
      Icons.account_balance_wallet_outlined,
    ),
  ];

  void _chooseDocType(String title, Future<void> Function(String kind) onPick) {
    if (!_formKey.currentState!.validate()) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final k in _docKinds)
                ListTile(
                  leading: Icon(k.$3),
                  title: Text(k.$2),
                  subtitle: k.$1 == 'payment_details'
                      ? Text(
                          Get.locale?.languageCode == 'sw'
                              ? 'Maelezo ya malipo na kazi'
                              : 'Payment and work details',
                        )
                      : null,
                  onTap: () => onPick(k.$1),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseDocTypeAndSave() =>
      Future.sync(() => _chooseDocType('Generate PDF', _saveDoc));

  Future<void> _chooseDocTypeAndPreview() =>
      Future.sync(() => _chooseDocType('Preview', _previewDoc));

  Future<void> _chooseDocTypeAndShare() =>
      Future.sync(() => _chooseDocType('Share as image', _shareDoc));

  Future<void> _chooseDocTypeAndWhatsApp() => Future.sync(
    () => _chooseDocType('Send document link on WhatsApp', _sendOnWhatsApp),
  );

  Future<void> _sendOnWhatsApp(String kind) async {
    Navigator.pop(context);
    final data = _buildData();
    if (!await _applyAdvance(kind, data)) return;
    setState(() => _busy = true);
    try {
      await _trySaveToFirestore(data, kind);
      final documentId = widget.invoice?.id ?? _savedDocId;
      if (documentId == null) {
        throw StateError(
          'Save this document to your account before sharing it on WhatsApp.',
        );
      }
      final module = kind == 'quotation' ? 'quotations' : 'invoices';
      if (!BusinessAccessService.can(module, 'create') &&
          !BusinessAccessService.can(module, 'edit')) {
        throw StateError('You do not have permission to share this document.');
      }
      await showDocumentShareSheet(
        context: context,
        businessUid: BusinessAccessService.businessId,
        documentId: documentId,
        document: {...data, 'kind': kind},
      );
    } catch (error) {
      if (mounted) {
        Get.snackbar(
          'Could not share document',
          error.toString().replaceFirst('Bad state: ', ''),
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Asks for the advance amount and adds it to the data. Returns false if cancelled.
  Future<bool> _applyAdvance(String kind, Map<String, dynamic> data) async {
    if (kind != 'advance_payment') return true;
    final total = (data['total'] as num?)?.toDouble() ?? 0;
    final c = TextEditingController();
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Advance payment'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [ThousandsSeparatorFormatter()],
          decoration: InputDecoration(
            labelText: 'Advance paid',
            helperText: 'Total: ${ThousandsSeparatorFormatter.format(total)}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(ctx, ThousandsSeparatorFormatter.parse(c.text)),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    c.dispose();
    if (value == null) return false;
    data['subtotal'] = total;
    data['tax'] = 0.0;
    data['advancePaid'] = value;
    data['balance'] = total - value;
    return true;
  }

  Future<Uint8List> _bytesFor(String kind, Map<String, dynamic> data) {
    switch (kind) {
      case 'quotation':
        return QuotationPdf.generateBytes(data);
      case 'proforma':
        return ProformaPdf.generateBytes(data);
      case 'delivery':
        return DeliveryNotePdf.generateBytes(data);
      case 'advance_payment':
        return AdvancePaymentPdf.generateBytes(data);
      case 'reminder':
        return PaymentReminderPdf.generateBytes(data);
      case 'payment_details':
        return PaymentDetailsPdf.generateBytes(data);
      default:
        return InvoicePdf.generateBytes(data);
    }
  }

  Future<void> _shareDoc(String kind) async {
    Navigator.pop(context);
    final data = _buildData();
    if (!await _applyAdvance(kind, data)) return;
    setState(() => _busy = true);
    try {
      final bytes = await _bytesFor(kind, data);
      final invNo = _displayInvoiceNumber;
      final base = '${kind}_${invNo.isEmpty ? 'document' : invNo}'.replaceAll(
        RegExp(r'[\\/:*?"<>|]'),
        '-',
      );
      final files = <XFile>[];
      final names = <String>[];
      var i = 0;
      await for (final page in Printing.raster(bytes, dpi: 144)) {
        i++;
        final png = await page.toPng();
        names.add('${base}_$i.png');
        if (kIsWeb) {
          // Browsers rarely support file sharing, so download the images.
          await downloadBytes(png, names.last, 'image/png');
        } else {
          files.add(XFile.fromData(png, mimeType: 'image/png'));
        }
      }
      if (kIsWeb) {
        Get.snackbar(
          'Image downloaded',
          '${names.length} file(s): ${names.join(', ')}',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }
      await SharePlus.instance.share(
        ShareParams(files: files, fileNameOverrides: names, subject: base),
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to share image: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _previewDoc(String kind) async {
    Navigator.pop(context);
    final data = _buildData();
    if (!await _applyAdvance(kind, data)) return;
    setState(() => _busy = true);
    try {
      await ({
        'invoice': () => InvoicePdf.generate(data),
        'quotation': () => QuotationPdf.generate(data),
        'proforma': () => ProformaPdf.generate(data),
        'delivery': () => DeliveryNotePdf.generate(data),
        'advance_payment': () => AdvancePaymentPdf.generate(data),
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
    final data = _buildData();
    if (!await _applyAdvance(kind, data)) return;
    setState(() => _busy = true);
    try {
      // Save a record to Firestore before generating the PDF
      await _trySaveToFirestore(data, kind);

      final invNo = (_displayInvoiceNumber.trim().isEmpty)
          ? DateTime.now().millisecondsSinceEpoch.toString()
          : _displayInvoiceNumber;

      final fileNameBase = switch (kind) {
        'delivery' => 'delivery_note_$invNo',
        'reminder' => 'payment_reminder_$invNo',
        _ => '${kind}_$invNo',
      };
      final safeFileNameBase = fileNameBase.replaceAll(
        RegExp(r'[\\/:*?"<>|]'),
        '-',
      );
      final fileName = '$safeFileNameBase.pdf';

      final pathOrName = await ({
        'invoice': () => InvoicePdf.generateAndSave(data, fileName: fileName),
        'quotation': () =>
            QuotationPdf.generateAndSave(data, fileName: fileName),
        'advance_payment': () =>
            AdvancePaymentPdf.generateAndSave(data, fileName: fileName),
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
      if (!mounted) return;
      final viewDocument = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Document saved'),
          content: Text(
            kIsWeb
                ? 'Your PDF has been downloaded. Would you like to view it now?'
                : 'Your PDF has been saved. Would you like to view it now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Done'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('View document'),
            ),
          ],
        ),
      );
      if (viewDocument == true && mounted) {
        await _openDocumentPreview(data, kind, fileName);
      }
    } catch (e) {
      Get.snackbar(
        'Error',
        e is StockException ? stockErrorText(e) : 'Failed to save PDF: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDocumentPreview(
    Map<String, dynamic> data,
    String kind,
    String fileName,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(fileName)),
          body: PdfPreview(
            build: (_) => _bytesFor(kind, data),
            canChangeOrientation: false,
            canChangePageFormat: false,
            allowPrinting: true,
            allowSharing: true,
            pdfFileName: fileName,
          ),
        ),
      ),
    );
  }
}
