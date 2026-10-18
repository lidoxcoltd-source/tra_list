import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'pdf_saver.dart' as pdf_saver;
import 'package:tra_list/services/company_logo_service.dart';
import 'package:tra_list/services/document_design_service.dart';
import 'package:tra_list/services/document_terms_service.dart';
import '../profile_service.dart'; // <-- add

class InvoicePdf {
  static Future<void> generate(Map<String, dynamic> data) async {
    try {
      final preparedData = await _prepareData(data);
      final bytes = await _buildPdfBytes(preparedData);
      await Printing.layoutPdf(onLayout: (format) async => bytes);
      Get.snackbar(
        'Success',
        'Invoice PDF generated',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to generate invoice PDF: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  // Convenience: generate bytes then save to disk (or download on web).
  static Future<String> generateAndSave(
    Map<String, dynamic> data, {
    required String fileName,
  }) async {
    final preparedData = await _prepareData(data);
    final bytes = await _buildPdfBytes(preparedData);
    return pdf_saver.savePdf(bytes, fileName);
  }

  // Keep your existing generate(...) if you still need print preview.
  // Add this method to get raw PDF bytes for saving.
  static Future<Uint8List> generateBytes(Map<String, dynamic> data) async {
    final preparedData = await _prepareData(data);
    return _buildPdfBytes(preparedData);
  }

  static Future<Map<String, dynamic>> _prepareData(
    Map<String, dynamic> data,
  ) async {
    final withCompany = await _ensureCompany(data);
    final withTerms = await DocumentTermsService.applySelected(
      withCompany,
      'invoice',
    );
    return DocumentDesignService.applySelected(withTerms, 'invoice');
  }

  // Ensure company data is present by loading from Firestore if needed
  static Future<Map<String, dynamic>> _ensureCompany(
    Map<String, dynamic> data,
  ) async {
    final company = (data['company'] as Map?) ?? {};
    if (company.isNotEmpty) return data;

    final profile = await ProfileService.loadOrCreate();
    return {...data, 'company': profile ?? <String, dynamic>{}};
  }

  static Future<Uint8List> _buildPdfBytes(Map<String, dynamic> data) async {
    final pdf = pw.Document();

    final company = data['company'] as Map<String, dynamic>? ?? {};
    final documentTerms = Map<String, dynamic>.from(
      data['documentTerms'] as Map? ?? DocumentTermsService.defaultVersion(),
    );
    final client = data['client'] as Map<String, dynamic>? ?? {};
    final invoice = data['invoice'] as Map<String, dynamic>? ?? {};
    final items =
        (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final total = (data['total'] as num?)?.toDouble() ?? 0.0;

    pw.ImageProvider? logo;
    try {
      final logoBytes = await CompanyLogoService.resolveLogoBytes(company);
      if (logoBytes != null) {
        logo = pw.MemoryImage(logoBytes);
      } else {
        final bytes = await rootBundle.load('assets/lidox_logo.png');
        logo = pw.MemoryImage(bytes.buffer.asUint8List());
      }
    } catch (e) {
      print(
        'Failed to load network image for PDF, falling back to local asset: $e',
      );
      final bytes = await rootBundle.load('assets/lidox_logo.png');
      logo = pw.MemoryImage(bytes.buffer.asUint8List());
    }

    pw.ImageProvider? socialIcons;
    try {
      final socialBytes = await rootBundle.load('assets/social-icons.png');
      socialIcons = pw.MemoryImage(socialBytes.buffer.asUint8List());
    } catch (_) {}

    String money(num v) {
      final s = v.toStringAsFixed(0);
      return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    }

    final design = DocumentDesign.fromData(data, company);
    final brandColor = design.brand;
    final footerColor = design.footer;
    final t = _Theme(
      brand: design.brand,
      accent: design.accent,
      design: design,
    );

    pdf.addPage(
      pw.MultiPage(
        pageTheme: design.pageTheme(),
        footer: (_) => _footer(t, company, footerColor, socialIcons),
        build: (ctx) => [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 36),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // Header
                design.wrapHeader(
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (logo != null)
                        pw.Container(
                          width: 120,
                          height: 60,
                          alignment: pw.Alignment.centerLeft,
                          child: pw.Image(logo!, fit: pw.BoxFit.contain),
                        ),
                      pw.Spacer(),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('INVOICE', style: t.h1),
                          pw.SizedBox(height: 6),
                          pw.Text(
                            company['name']?.toString() ?? '',
                            style: t.h2,
                          ),
                          pw.Text(
                            company['address']?.toString() ?? '',
                            style: t.small,
                            textAlign: pw.TextAlign.right,
                          ),
                          if (company['taxId'] != null)
                            pw.Text(
                              'Tax Id: ${company['taxId']}',
                              style: t.small,
                            ),
                          if (company['email'] != null)
                            pw.Text(
                              company['email'].toString(),
                              style: t.small,
                            ),
                          if (company['phone'] != null)
                            pw.Text(
                              'Otc Tel: ${company['phone']}',
                              style: t.small,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 24),

                // Bill to + meta
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Row(
                            children: [
                              pw.Text('To  ', style: t.redBold),
                              pw.Container(
                                padding: const pw.EdgeInsets.only(bottom: 2),
                                decoration: const pw.BoxDecoration(
                                  border: pw.Border(
                                    bottom: pw.BorderSide(
                                      width: 1,
                                      color: PdfColors.black,
                                    ),
                                  ),
                                ),
                                child: pw.Text(
                                  client['name']?.toString() ?? '',
                                  style: t.medium,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 16),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _kv(
                          'Invoice No :',
                          invoice['number']?.toString() ?? '',
                          t.small,
                        ),
                        _kv(
                          'Issue date :',
                          invoice['issueDate']?.toString() ?? '',
                          t.smallBold,
                        ),
                        _kv(
                          'Due date:',
                          invoice['dueDate']?.toString() ?? '',
                          t.smallBold,
                        ),
                        _kv(
                          'Payment method:',
                          (invoice['paymentMethod'] ?? '').toString(),
                          t.smallBold,
                        ),
                      ],
                    ),
                  ],
                ),

                pw.SizedBox(height: 18),

                // Table header + rows
                _tableHeader(t, brandColor),
                ...items.map((it) {
                  final qty = (it['qty'] as num?)?.toDouble() ?? 0;
                  final unit = (it['unit'] as num?)?.toDouble() ?? 0;
                  final amount =
                      (it['amount'] as num?)?.toDouble() ?? qty * unit;
                  return _row(
                    t,
                    it['description']?.toString() ?? '',
                    qty,
                    unit,
                    amount,
                    dense: false,
                  );
                }),

                pw.SizedBox(height: 12),

                // Footer: note + total + payment details (content area)
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'This is computer generated document.',
                            style: t.smallGrey,
                          ),
                          pw.SizedBox(height: 10),
                          pw.Text('PAYMENT DETAILS', style: t.h3Bold),
                          if (company['beneficiary'] != null)
                            pw.Text(
                              'Beneficiary: ${company['beneficiary']}',
                              style: t.smallBold,
                            ),
                          if (company['bank'] != null)
                            pw.Text(
                              'Bank: ${company['bank']}',
                              style: t.smallBold,
                            ),
                          if (company['account'] != null)
                            pw.Text(
                              'Account Number: ${company['account']}',
                              style: t.smallBold,
                            ),
                          if (company['swift'] != null)
                            pw.Text(
                              'Swift code: ${company['swift']}',
                              style: t.smallBold,
                            ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 16),
                    pw.Container(
                      width: 240,
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'TOTAL (TSH):(TAX INCLUDED)',
                            style: t.smallBold,
                          ),
                          pw.SizedBox(width: 12),
                          pw.Text('Tsh ${money(total)}', style: t.h3Bold),
                        ],
                      ),
                    ),
                  ],
                ),
                _noteAndDelivery(t, documentTerms),
                _termsAndConditions(t, documentTerms),
              ],
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _kv(String k, String v, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(k, style: style),
          pw.SizedBox(width: 6),
          pw.Text(v, style: style),
        ],
      ),
    );
  }

  static pw.Widget _tableHeader(_Theme t, PdfColor brandColor) {
    return pw.Container(
      decoration: t.design.tableHeaderDecoration(),
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: pw.Row(
        children: [
          pw.Expanded(flex: 5, child: pw.Text('DESCRIPTION', style: t.header)),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              'QUANTITY',
              style: t.header,
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              'UNIT PRICE (TSH)',
              style: t.header,
              textAlign: pw.TextAlign.right,
            ),
          ),
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              'AMOUNT (TSH)',
              style: t.header,
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _row(
    _Theme t,
    String desc,
    double qty,
    double unit,
    double amount, {
    bool dense = false,
  }) {
    return pw.Container(
      decoration: t.design.rowDecoration(),
      padding: pw.EdgeInsets.symmetric(vertical: dense ? 4 : 6, horizontal: 6),
      child: pw.Row(
        children: [
          pw.Expanded(flex: 5, child: pw.Text(desc, style: t.medium)),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              qty.toStringAsFixed(qty.truncateToDouble() == qty ? 0 : 2),
              style: t.medium,
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              _Theme.money(unit),
              style: t.medium,
              textAlign: pw.TextAlign.right,
            ),
          ),
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              _Theme.money(amount),
              style: t.mediumBold,
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // NEW: Note + Delivery Time section shown before footer
  static pw.Widget _noteAndDelivery(
    _Theme t,
    Map<String, dynamic> documentTerms,
  ) {
    final note = documentTerms['note']?.toString().trim() ?? '';
    final delivery = documentTerms['delivery']?.toString().trim() ?? '';
    if (note.isEmpty && delivery.isEmpty) return pw.SizedBox();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (note.isNotEmpty)
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 10),
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                left: pw.BorderSide(color: PdfColors.green, width: 3),
              ),
            ),
            child: pw.Text(note, style: t.smallGrey),
          ),
        if (delivery.isNotEmpty)
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 8),
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                left: pw.BorderSide(color: PdfColors.black, width: 3),
              ),
            ),
            child: pw.Text(delivery, style: t.smallRed),
          ),
      ],
    );
  }

  static pw.Widget _termsAndConditions(
    _Theme t,
    Map<String, dynamic> documentTerms,
  ) {
    final conditions = documentTerms['conditions']?.toString().trim() ?? '';
    if (conditions.isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 16),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('TERMS AND CONDITIONS', style: t.h3Bold),
          pw.SizedBox(height: 6),
          pw.Text(conditions, style: t.small),
        ],
      ),
    );
  }

  static pw.Widget _footer(
    _Theme t,
    Map<String, dynamic> company,
    PdfColor footerColor,
    pw.ImageProvider? socialIcons,
  ) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        _footerBar(t, company, footerColor, socialIcons), // full-width dark bar
      ],
    );
  }

  // Full-width dark footer bar (no FullPage here)
  static pw.Widget _footerBar(
    _Theme t,
    Map<String, dynamic> company,
    PdfColor footerColor,
    pw.ImageProvider? socialIcons,
  ) {
    final handle = (company['handle'] ?? '').toString();
    final website = (company['website'] ?? '').toString();

    return pw.Container(
      width: double.infinity,
      color: footerColor,
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 18),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              if (socialIcons != null)
                pw.Image(socialIcons, height: 20, fit: pw.BoxFit.contain),
              if (socialIcons != null && handle.isNotEmpty)
                pw.SizedBox(width: 8),
              if (handle.isNotEmpty) pw.Text(handle, style: t.smallWhite),
            ],
          ),
          pw.Row(
            children: [
              pw.Text('Web: ', style: t.smallWhite),
              if (website.isNotEmpty) pw.Text(website, style: t.smallWhite),
            ],
          ),
        ],
      ),
    );
  }
}

class _Theme {
  final PdfColor brand;
  final PdfColor accent;
  final DocumentDesign design;

  _Theme({required this.brand, required this.accent, required this.design});

  final PdfColor grey = PdfColors.grey600;
  final PdfColor dark = PdfColors.black;
  final PdfColor light = PdfColors.grey400;

  pw.TextStyle get h1 =>
      pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: brand);
  pw.TextStyle get h2 =>
      pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold);
  pw.TextStyle get h3Bold =>
      pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold);
  pw.TextStyle get header => pw.TextStyle(
    fontSize: 10,
    fontWeight: pw.FontWeight.bold,
    color: design.lightTableHeader ? brand : PdfColors.white,
  );
  pw.TextStyle get medium => pw.TextStyle(fontSize: 10, color: PdfColors.black);
  pw.TextStyle get mediumBold => pw.TextStyle(
    fontSize: 10,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.black,
  );
  pw.TextStyle get small => pw.TextStyle(fontSize: 9, color: PdfColors.black);
  pw.TextStyle get smallBold => pw.TextStyle(
    fontSize: 9,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.black,
  );
  pw.TextStyle get smallGrey =>
      pw.TextStyle(fontSize: 9, color: PdfColors.grey700);
  pw.TextStyle get redBold =>
      pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: accent);
  pw.TextStyle get smallWhite =>
      pw.TextStyle(fontSize: 9, color: PdfColors.white);
  pw.TextStyle get smallRed =>
      pw.TextStyle(fontSize: 9, color: PdfColors.red); // NEW

  static String money(num v) {
    final s = v.toStringAsFixed(0);
    return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  }
}
