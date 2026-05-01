import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'pdf_saver.dart' as pdf_saver;
import 'package:tra_list/services/company_logo_service.dart';
import '../profile_service.dart';

class AdvancePaymentPdf {
  static Future<void> generate(Map<String, dynamic> data) async {
    try {
      final withCompany = await _ensureCompany(data);
      final bytes = await _buildPdfBytes(withCompany);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
      Get.snackbar(
        'Success',
        'Advance invoice PDF generated',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to generate advance invoice PDF: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  static Future<String> generateAndSave(
    Map<String, dynamic> data, {
    required String fileName,
  }) async {
    final withCompany = await _ensureCompany(data);
    final bytes = await _buildPdfBytes(withCompany);
    return pdf_saver.savePdf(bytes, fileName);
  }

  static Future<Uint8List> generateBytes(Map<String, dynamic> data) async {
    final withCompany = await _ensureCompany(data);
    return _buildPdfBytes(withCompany);
  }

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

    final company = (data['company'] as Map?)?.cast<String, dynamic>() ?? {};
    final client = (data['client'] as Map?)?.cast<String, dynamic>() ?? {};
    final invoice = (data['invoice'] as Map?)?.cast<String, dynamic>() ?? {};
    final items =
        (data['items'] as List?)
            ?.cast<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList() ??
        const <Map<String, dynamic>>[];

    final subtotal =
        (data['subtotal'] as num?)?.toDouble() ??
        items.fold<double>(
          0,
          (sum, it) =>
              sum +
              ((it['amount'] as num?)?.toDouble() ??
                  ((it['qty'] as num?)?.toDouble() ?? 0) *
                      ((it['unit'] as num?)?.toDouble() ?? 0)),
        );
    final tax = (data['tax'] as num?)?.toDouble() ?? 0;
    final total = (data['total'] as num?)?.toDouble() ?? (subtotal + tax);
    final advancePaid = (data['advancePaid'] as num?)?.toDouble() ?? 0;
    final balance = total - advancePaid;

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

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.only(top: 36, bottom: 0, left: 0, right: 0),
        footer: (ctx) => _footer(t, company, footerColor, socialIcons, ctx),
        build: (ctx) => [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 36),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
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
                        pw.Text('ADVANCE INVOICE', style: t.h1),
                        pw.SizedBox(height: 6),
                        pw.Text(company['name']?.toString() ?? '', style: t.h2),
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
                          pw.Text(company['email'].toString(), style: t.small),
                        if (company['phone'] != null)
                          pw.Text('Tel: ${company['phone']}', style: t.small),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 24),
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
                          if (client['address'] != null)
                            pw.Text(
                              client['address'].toString(),
                              style: t.small,
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
                          invoice['issueDate']?.toString() ??
                              invoice['date']?.toString() ??
                              '',
                          t.smallBold,
                        ),
                        _kv(
                          'Advance due:',
                          invoice['advanceDueDate']?.toString() ??
                              invoice['dueDate']?.toString() ??
                              '',
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
                _tableHeader(t, brandColor),
                ...items.map((it) {
                  final qty =
                      (it['qty'] as num?)?.toDouble() ??
                      (it['quantity'] as num?)?.toDouble() ??
                      0;
                  final unit =
                      (it['unit'] as num?)?.toDouble() ??
                      (it['unitPrice'] as num?)?.toDouble() ??
                      0;
                  final amount =
                      (it['amount'] as num?)?.toDouble() ??
                      (it['total'] as num?)?.toDouble() ??
                      (qty * unit);
                  return _row(
                    t,
                    it['description']?.toString() ?? '',
                    qty,
                    unit,
                    amount,
                  );
                }),
                pw.SizedBox(height: 12),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            invoice['notes']?.toString() ??
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
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          _totalLine(t, 'Subtotal', subtotal),
                          if (tax != 0) _totalLine(t, 'Tax', tax),
                          _totalLine(t, 'Total (TSH)', total, bold: true),
                          _totalLine(
                            t,
                            'Advance Paid',
                            advancePaid,
                            accent: true,
                          ),
                          pw.Divider(),
                          _totalLine(t, 'Balance Due', balance, bold: true),
                        ],
                      ),
                    ),
                  ],
                ),
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
      decoration: pw.BoxDecoration(
        color: brandColor,
        borderRadius: pw.BorderRadius.circular(8),
      ),
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
    double amount,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
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

  static pw.Widget _totalLine(
    _Theme t,
    String label,
    double value, {
    bool bold = false,
    bool accent = false,
  }) {
    final style = bold
        ? t.h3Bold
        : accent
        ? t.smallRedBold
        : t.smallBold;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text('Tsh ${_Theme.money(value)}', style: style),
        ],
      ),
    );
  }

  static pw.Widget _noteAndDelivery(_Theme t) {
    const note =
        'We kindly request that the remaining balance be settled upon project completion. '
        'This ensures smooth delivery and maintains our quality of service.';
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                left: pw.BorderSide(color: PdfColors.green, width: 3),
              ),
            ),
            child: pw.Text(note, style: t.smallGrey),
          ),
        ),
        pw.SizedBox(width: 18),
        pw.Container(
          width: 220,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              left: pw.BorderSide(color: PdfColors.black, width: 3),
            ),
          ),
          child: pw.RichText(
            text: pw.TextSpan(
              style: t.smallRed,
              children: [
                pw.TextSpan(text: 'Delivery Time  '),
                pw.TextSpan(text: 'Max '),
                pw.TextSpan(
                  text: '7 Days ',
                  style: t.smallRed.copyWith(fontWeight: pw.FontWeight.bold),
                ),
                pw.TextSpan(text: 'Min '),
                pw.TextSpan(
                  text: '5 Days\n',
                  style: t.smallRed.copyWith(fontWeight: pw.FontWeight.bold),
                ),
                pw.TextSpan(
                  text: 'From Payment Day',
                  style: t.smallRed.copyWith(fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _footer(
    _Theme t,
    Map<String, dynamic> company,
    PdfColor footerColor,
    pw.ImageProvider? socialIcons,
    pw.Context ctx,
  ) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        if (ctx.pageNumber == ctx.pagesCount)
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(36, 0, 36, 8),
            child: _noteAndDelivery(t),
          ),
        _footerBar(t, company, footerColor, socialIcons),
      ],
    );
  }

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

  _Theme({required this.brand, required this.accent});

  final PdfColor grey = PdfColors.grey600;

  pw.TextStyle get h1 =>
      pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: brand);
  pw.TextStyle get h2 =>
      pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold);
  pw.TextStyle get h3Bold =>
      pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold);
  pw.TextStyle get header => pw.TextStyle(
    fontSize: 10,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.white,
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
  pw.TextStyle get smallRed => pw.TextStyle(fontSize: 9, color: PdfColors.red);
  pw.TextStyle get smallRedBold => pw.TextStyle(
    fontSize: 9,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.red,
  );

  static String money(num v) {
    final s = v.toStringAsFixed(0);
    return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  }
}
