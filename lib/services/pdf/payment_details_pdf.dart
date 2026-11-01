import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'pdf_saver.dart' as pdf_saver;
import 'package:tra_list/services/company_logo_service.dart';
import '../profile_service.dart';

class PaymentDetailsPdf {
  static Future<void> generate(Map<String, dynamic> data) async {
    final withCompany = await _ensureCompany(data);
    final bytes = await _buildPdfBytes(withCompany);
    await Printing.layoutPdf(onLayout: (f) async => bytes);
    Get.snackbar(
      'Success',
      'Payment Details generated',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  static Future<String> generateAndSave(
    Map<String, dynamic> data, {
    required String fileName,
  }) async {
    final withCompany = await _ensureCompany(data);
    final bytes = await _buildPdfBytes(withCompany);
    return pdf_saver.savePdf(bytes, fileName);
  }

  static Future<Uint8List> generateBytes(Map<String, dynamic> data) async =>
      _buildPdfBytes(await _ensureCompany(data));

  // Ensure company data is present by loading from Firestore if missing
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
    final client = data['client'] as Map<String, dynamic>? ?? {};
    final invoice = data['invoice'] as Map<String, dynamic>? ?? {};
    final items = (data['items'] as List?)?.whereType<Map>().toList() ?? [];
    final total = (data['total'] as num?)?.toDouble() ?? 0.0;

    final colors = (company['colors'] as Map?) ?? {};
    final brandColor = colors['brand'] is int
        ? PdfColor.fromInt(colors['brand'])
        : PdfColor.fromInt(0xFFF15A24);
    final accentColor = colors['accent'] is int
        ? PdfColor.fromInt(colors['accent'])
        : PdfColor.fromInt(0xFF1976D2);
    final footerColor = colors['footer'] is int
        ? PdfColor.fromInt(colors['footer'])
        : PdfColors.grey800;
    final t = _Theme(brand: brandColor, accent: accentColor);

    final logoBytes = await CompanyLogoService.resolveLogoBytes(company);
    final pw.ImageProvider? logo = logoBytes == null
        ? null
        : pw.MemoryImage(logoBytes);

    pw.ImageProvider? socialIcons;
    try {
      final socialBytes = await rootBundle.load('assets/social-icons.png');
      socialIcons = pw.MemoryImage(socialBytes.buffer.asUint8List());
    } catch (_) {}

    String money(num v) => v
        .toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'\\B(?=(\\d{3})+(?!\\d))'), (m) => ',');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.only(top: 36, bottom: 0, left: 0, right: 0),
        footer: (ctx) => _footer(t, company, footerColor, socialIcons),
        build: (ctx) => [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 36),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // Header
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (logo != null)
                      pw.Container(
                        width: 120,
                        height: 60,
                        alignment: pw.Alignment.centerLeft,
                        child: pw.Image(logo, fit: pw.BoxFit.contain),
                      ),
                    pw.Spacer(),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('PAYMENT DETAILS', style: t.h1),
                        pw.SizedBox(height: 6),
                        pw.Text(company['name']?.toString() ?? '', style: t.h2),
                      ],
                    ),
                  ],
                ),

                pw.SizedBox(height: 36),

                // Body
                pw.Text('Dear ${client['name'] ?? 'Client'},', style: t.medium),
                pw.SizedBox(height: 12),
                pw.RichText(
                  text: pw.TextSpan(
                    style: t.medium,
                    children: [
                      const pw.TextSpan(
                        text:
                            'Please use the following details for payment of Invoice #',
                      ),
                      pw.TextSpan(
                        text: '${invoice['number'] ?? ''}',
                        style: t.mediumBold,
                      ),
                      const pw.TextSpan(text: ' for the amount of '),
                      pw.TextSpan(
                        text: 'TSH ${money(total)}',
                        style: t.mediumBold,
                      ),
                      const pw.TextSpan(text: '.'),
                    ],
                  ),
                ),
                if ((invoice['dueDate']?.toString().trim().isNotEmpty ?? false) ||
                    (invoice['paymentMethod']?.toString().trim().isNotEmpty ??
                        false)) ...[
                  pw.SizedBox(height: 10),
                  if (invoice['dueDate']?.toString().trim().isNotEmpty ?? false)
                    _detailRow(t, 'Due Date:', invoice['dueDate']),
                  if (invoice['paymentMethod']
                          ?.toString()
                          .trim()
                          .isNotEmpty ??
                      false)
                    _detailRow(t, 'Payment Method:', invoice['paymentMethod']),
                ],
                if (items.isNotEmpty) ...[
                  pw.SizedBox(height: 24),
                  pw.Text('WORK DETAILS', style: t.h3Bold),
                  pw.SizedBox(height: 8),
                  _workDetailsTable(t, items, money),
                ],
                if (_hasPaymentDetails(company)) ...[
                  pw.SizedBox(height: 24),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(16),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('PAYMENT DETAILS', style: t.h3Bold),
                        pw.Divider(height: 16),
                        if (_hasValue(company['beneficiary']))
                          _detailRow(t, 'Beneficiary:', company['beneficiary']),
                        if (_hasValue(company['bank']))
                          _detailRow(t, 'Bank Name:', company['bank']),
                        if (_hasValue(company['account']))
                          _detailRow(t, 'Account Number:', company['account']),
                        if (_hasValue(company['swift']))
                          _detailRow(t, 'SWIFT/BIC Code:', company['swift']),
                      ],
                    ),
                  ),
                ],
                pw.SizedBox(height: 24),
                pw.Text('Thank you for your business!', style: t.medium),
              ],
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static bool _hasValue(dynamic value) =>
      value != null && value.toString().trim().isNotEmpty;

  static bool _hasPaymentDetails(Map<String, dynamic> company) =>
      ['beneficiary', 'bank', 'account', 'swift'].any(
        (key) => _hasValue(company[key]),
      );

  static pw.Widget _workDetailsTable(
    _Theme t,
    List<Map> items,
    String Function(num) money,
  ) {
    pw.Widget cell(String value, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: pw.Text(
        value,
        style: bold ? t.mediumBold : t.medium,
      ),
    );

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: .5),
      columnWidths: {
        0: const pw.FlexColumnWidth(4),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: t.accent),
          children: [
            cell('Work / Item', bold: true),
            cell('Qty', bold: true),
            cell('Amount', bold: true),
          ],
        ),
        for (final item in items)
          pw.TableRow(
            children: [
              cell(
                item['description']?.toString().trim().isNotEmpty == true
                    ? item['description'].toString()
                    : 'Work item',
              ),
              cell((item['qty'] as num?)?.toString() ?? '1'),
              cell(
                'TSH ${money((item['amount'] as num?) ?? ((item['qty'] as num? ?? 1) * (item['unit'] as num? ?? 0)))}',
              ),
            ],
          ),
      ],
    );
  }

  static pw.Widget _detailRow(_Theme t, String label, dynamic value) {
    final textValue = value?.toString() ?? 'N/A';
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: t.medium),
          pw.Text(textValue, style: t.mediumBold),
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

  _Theme({required this.brand, required this.accent});

  pw.TextStyle get h1 =>
      pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: brand);
  pw.TextStyle get h2 =>
      pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold);
  pw.TextStyle get h3Bold =>
      pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold);
  pw.TextStyle get medium => pw.TextStyle(fontSize: 10, color: PdfColors.black);
  pw.TextStyle get mediumBold =>
      pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);
  pw.TextStyle get smallWhite =>
      pw.TextStyle(fontSize: 9, color: PdfColors.white);
}
