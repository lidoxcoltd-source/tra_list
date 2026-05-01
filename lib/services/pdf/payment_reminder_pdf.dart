import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'pdf_saver.dart' as pdf_saver;
import 'package:tra_list/services/company_logo_service.dart';
import '../profile_service.dart';

class PaymentReminderPdf {
  static Future<void> generate(Map<String, dynamic> data) async {
    final withCompany = await _ensureCompany(data);
    final bytes = await _buildPdfBytes(withCompany);
    await Printing.layoutPdf(onLayout: (f) async => bytes);
    Get.snackbar(
      'Success',
      'Payment Reminder generated',
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

    pw.ImageProvider? logo;
    try {
      final logoBytes = await CompanyLogoService.resolveLogoBytes(company);
      if (logoBytes != null) {
        logo = pw.MemoryImage(logoBytes);
      } else {
        final b = await rootBundle.load('assets/lidox_logo.png');
        logo = pw.MemoryImage(b.buffer.asUint8List());
      }
    } catch (_) {}

    pw.ImageProvider? socialIcons;
    try {
      final socialBytes = await rootBundle.load('assets/social-icons.png');
      socialIcons = pw.MemoryImage(socialBytes.buffer.asUint8List());
    } catch (_) {}

    String money(num v) => v
        .toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

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
                        child: pw.Image(logo!, fit: pw.BoxFit.contain),
                      ),
                    pw.Spacer(),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('PAYMENT REMINDER', style: t.h1),
                        pw.SizedBox(height: 6),
                        pw.Text(company['name']?.toString() ?? '', style: t.h2),
                        pw.Text(
                          company['address']?.toString() ?? '',
                          style: t.small,
                          textAlign: pw.TextAlign.right,
                        ),
                        if (company['email'] != null)
                          pw.Text(company['email'].toString(), style: t.small),
                        if (company['phone'] != null)
                          pw.Text(
                            'Otc Tel: ${company['phone']}',
                            style: t.small,
                          ),
                      ],
                    ),
                  ],
                ),

                pw.SizedBox(height: 24),

                // Recipient
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
                pw.SizedBox(height: 16),

                // Body
                pw.Text('Dear ${client['name'] ?? 'Client'},', style: t.medium),
                pw.SizedBox(height: 10),
                pw.Text(
                  'This is a friendly reminder that Invoice #${invoice['number'] ?? ''} '
                  'issued on ${invoice['issueDate'] ?? ''} was due on ${invoice['dueDate'] ?? ''}. '
                  'The outstanding balance is TSH ${money(total)}.',
                  style: t.medium,
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Kindly arrange the payment at your earliest convenience. If payment has already been made, please disregard this notice.',
                  style: t.medium,
                ),
                pw.SizedBox(height: 14),
                pw.Text('PAYMENT DETAILS', style: t.h3Bold),
                if (company['beneficiary'] != null)
                  pw.Text(
                    'Beneficiary: ${company['beneficiary']}',
                    style: t.smallBold,
                  ),
                if (company['bank'] != null)
                  pw.Text('Bank: ${company['bank']}', style: t.smallBold),
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
                pw.SizedBox(height: 18),
                pw.Text(
                  'Thank you for your prompt attention to this matter.',
                  style: t.medium,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return pdf.save();
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
      pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold);
  pw.TextStyle get medium => pw.TextStyle(fontSize: 10, color: PdfColors.black);
  pw.TextStyle get small => pw.TextStyle(fontSize: 9, color: PdfColors.black);
  pw.TextStyle get smallBold => pw.TextStyle(
    fontSize: 9,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.black,
  );
  pw.TextStyle get smallWhite =>
      pw.TextStyle(fontSize: 9, color: PdfColors.white);
  pw.TextStyle get smallGrey =>
      pw.TextStyle(fontSize: 9, color: PdfColors.grey700);
  pw.TextStyle get redBold =>
      pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: accent);
}
