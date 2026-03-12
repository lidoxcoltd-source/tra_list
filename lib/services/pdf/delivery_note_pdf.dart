import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'pdf_saver.dart' as pdf_saver;
import '../profile_service.dart';

class DeliveryNotePdf {
  static Future<void> generate(Map<String, dynamic> data) async {
    final withCompany = await _ensureCompany(data);
    final bytes = await _buildPdfBytes(withCompany);
    await Printing.layoutPdf(onLayout: (f) async => bytes);
    Get.snackbar(
      'Success',
      'Delivery Note generated',
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
    final existing = (data['company'] as Map?)?.cast<String, dynamic>() ?? {};
    if (existing.isNotEmpty) return data;

    try {
      // Use loadOrCreate to guarantee a doc exists
      final profile = await ProfileService.loadOrCreate();
      if (profile == null || profile.isEmpty) {
        print('DeliveryNotePdf: profile missing or empty.');
        return data;
      }
      print('DeliveryNotePdf: loaded company => ${profile['name']}');
      return {...data, 'company': profile};
    } catch (e) {
      print('DeliveryNotePdf: failed to load profile: $e');
      Get.snackbar(
        'Profile',
        'Failed to load company details',
        snackPosition: SnackPosition.BOTTOM,
      );
      return data;
    }
  }

  static Future<Uint8List> _buildPdfBytes(Map<String, dynamic> data) async {
    final pdf = pw.Document();

    final company = data['company'] as Map<String, dynamic>? ?? {};
    final client = data['client'] as Map<String, dynamic>? ?? {};
    final invoice = data['invoice'] as Map<String, dynamic>? ?? {};
    final items =
        (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    // Load logo from profile logoUrl; fallback to asset.
    pw.ImageProvider? logo;
    try {
      final url = (company['logoUrl'] ?? '').toString();
      if (url.isNotEmpty) {
        final bundle = NetworkAssetBundle(Uri.parse(url));
        final bytes = (await bundle.load(url)).buffer.asUint8List();
        logo = pw.MemoryImage(bytes);
      } else {
        final b = await rootBundle.load('assets/lidox_logo.png');
        logo = pw.MemoryImage(b.buffer.asUint8List());
      }
    } catch (e) {
      print(
        'Failed to load network image for PDF, falling back to local asset: $e',
      );
      final b = await rootBundle.load('assets/lidox_logo.png');
      logo = pw.MemoryImage(b.buffer.asUint8List());
    }

    pw.ImageProvider? socialIcons;
    try {
      final socialBytes = await rootBundle.load('assets/social-icons.png');
      socialIcons = pw.MemoryImage(socialBytes.buffer.asUint8List());
    } catch (_) {}

    // Read brand color from profile; fallback default.
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
                        pw.Text('DELIVERY NOTE', style: t.h1),
                        pw.SizedBox(height: 6),
                        pw.Text(company['name']?.toString() ?? '', style: t.h2),
                        pw.Text(
                          company['address']?.toString() ?? '',
                          style: t.small,
                          textAlign: pw.TextAlign.right,
                        ),
                        if ((company['email'] ?? '').toString().isNotEmpty)
                          pw.Text(company['email'].toString(), style: t.small),
                        if ((company['phone'] ?? '').toString().isNotEmpty)
                          pw.Text('Tel: ${company['phone']}', style: t.small),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 24),

                // Bill to + meta
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Row(
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
                    ),
                    pw.SizedBox(width: 16),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _kv(
                          'Ref No :',
                          invoice['number']?.toString() ?? '',
                          t.small,
                        ),
                        _kv(
                          'Date :',
                          invoice['issueDate']?.toString() ?? '',
                          t.smallBold,
                        ),
                      ],
                    ),
                  ],
                ),

                pw.SizedBox(height: 18),

                // Table header with brand color
                _tableHeader(t, brandColor),
                ...items.map((it) {
                  final qty = (it['qty'] as num?)?.toDouble() ?? 0;
                  return _row(t, it['description']?.toString() ?? '', qty);
                }),

                pw.SizedBox(height: 18),

                // Signatures
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Delivered by:', style: t.smallBold),
                          pw.SizedBox(height: 28),
                          pw.Container(height: 1, color: PdfColors.black),
                          pw.SizedBox(height: 4),
                          pw.Text('Name & Signature', style: t.smallGrey),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 24),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Received by:', style: t.smallBold),
                          pw.SizedBox(height: 28),
                          pw.Container(height: 1, color: PdfColors.black),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Name, Signature & Stamp',
                            style: t.smallGrey,
                          ),
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

  static pw.Widget _kv(String k, String v, pw.TextStyle style) => pw.Padding(
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

  // pass brandColor from profile
  static pw.Widget _tableHeader(_Theme t, PdfColor brandColor) => pw.Container(
    decoration: pw.BoxDecoration(
      color: brandColor,
      borderRadius: pw.BorderRadius.circular(8),
    ),
    padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
    child: pw.Row(
      children: [
        pw.Expanded(flex: 7, child: pw.Text('DESCRIPTION', style: t.header)),
        pw.Expanded(
          flex: 3,
          child: pw.Text(
            'QUANTITY',
            style: t.header,
            textAlign: pw.TextAlign.center,
          ),
        ),
      ],
    ),
  );

  static pw.Widget _row(_Theme t, String desc, double qty) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
    child: pw.Row(
      children: [
        pw.Expanded(flex: 7, child: pw.Text(desc, style: t.medium)),
        pw.Expanded(
          flex: 3,
          child: pw.Text(
            qty.toStringAsFixed(qty.truncateToDouble() == qty ? 0 : 2),
            style: t.medium,
            textAlign: pw.TextAlign.center,
          ),
        ),
      ],
    ),
  );

  static pw.Widget _noteAndDelivery(_Theme t) =>
      pw.Container(); // not needed here

  static pw.Widget _footer(
    _Theme t,
    Map<String, dynamic> company,
    PdfColor footerColor,
    pw.ImageProvider? socialIcons,
    pw.Context ctx,
  ) => _footerBar(t, company, footerColor, socialIcons);

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

  pw.TextStyle get h1 =>
      pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: brand);
  pw.TextStyle get h2 =>
      pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold);
  pw.TextStyle get header => pw.TextStyle(
    fontSize: 10,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.white,
  );
  pw.TextStyle get medium => pw.TextStyle(fontSize: 10, color: PdfColors.black);
  pw.TextStyle get small => pw.TextStyle(fontSize: 9, color: PdfColors.black);
  pw.TextStyle get smallBold => pw.TextStyle(
    fontSize: 9,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.black,
  );
  pw.TextStyle get smallGrey =>
      pw.TextStyle(fontSize: 9, color: PdfColors.grey700);
  pw.TextStyle get smallWhite =>
      pw.TextStyle(fontSize: 9, color: PdfColors.white);
  pw.TextStyle get redBold =>
      pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: accent);
}
