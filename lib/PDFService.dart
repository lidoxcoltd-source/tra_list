export 'services/pdf/pdf_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/foundation.dart';

class PDFService {
  static Future<void> generatePDF(Map<String, dynamic> data) async {
    try {
      // -------- Input normalization --------
      final customer = (data['customer'] as Map<String, dynamic>?) ?? {};
      final company = (data['company'] as Map<String, dynamic>?) ?? {};
      final meta = (data['meta'] as Map<String, dynamic>?) ?? {};
      final itemsRaw = (data['items'] as List?) ?? const [];
      final items = itemsRaw
          .cast<Map>()
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // Optional: auto compute totals if not provided
      double totalExclTax =
          (data['totalExclTax'] as num?)?.toDouble() ??
          items.fold<double>(
            0,
            (sum, it) => sum + ((it['amount'] as num?)?.toDouble() ?? 0.0),
          );
      double tax = (data['tax'] as num?)?.toDouble() ?? 0.0;
      double totalInclTax =
          (data['totalInclTax'] as num?)?.toDouble() ?? (totalExclTax + tax);

      // -------- Assets (logo + fonts) with graceful fallbacks --------
      pw.MemoryImage? logoImage;
      try {
        final logoData = await rootBundle.load(
          'assets/tra-logo.png',
        ); // ensure pubspec has this!
        logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
      } catch (_) {
        // no logo available — keep null
      }

      pw.Font? fontRegular;
      pw.Font? fontBold;
      try {
        final f = await rootBundle.load('assets/fonts/Hypermarket-Cond.ttf');
        final fb = await rootBundle.load(
          'assets/fonts/Hypermarket-CondBold.ttf',
        );
        fontRegular = pw.Font.ttf(f);
        fontBold = pw.Font.ttf(fb);
      } catch (_) {
        // Fallback to built-in fonts
        fontRegular = pw.Font.helvetica();
        fontBold = pw.Font.helveticaBold();
      }

      // -------- Helpers --------
      const double fontScale = 1.2; // was 1.3
      // Slightly lighter text colors
      final PdfColor textColor = PdfColor(0.28, 0.28, 0.28); // was 0.28
      final PdfColor textColorBold = PdfColor(0.22, 0.22, 0.22); // was 0.22
      const double kLetterSpacing = 0.2; // was 0.2

      String money(num? v) {
        final amount = (v ?? 0).toDouble();
        final isNegative = amount < 0;
        final abs = amount.abs();
        final parts = abs.toStringAsFixed(2).split('.');
        String intPart = parts[0];
        final fracPart = parts[1];
        final reg = RegExp(r'\B(?=(\d{3})+(?!\d))');
        intPart = intPart.replaceAllMapped(reg, (m) => "'");
        final formatted = '$intPart.$fracPart';
        return isNegative ? '-$formatted' : formatted;
      }

      pw.TextStyle t12([bool bold = false]) => pw.TextStyle(
        font: fontRegular, // force regular to reduce weight
        fontSize: 12 * fontScale,
        color: bold ? textColorBold : textColor,
        letterSpacing: kLetterSpacing,
      );
      pw.TextStyle t14([bool bold = false]) => pw.TextStyle(
        font: fontRegular, // force regular
        fontSize: 14 * fontScale,
        color: bold ? textColorBold : textColor,
        letterSpacing: kLetterSpacing,
      );
      pw.TextStyle t16([bool bold = false]) => pw.TextStyle(
        font: fontRegular, // force regular
        fontSize: 16 * fontScale,
        color: bold ? textColorBold : textColor,
        letterSpacing: kLetterSpacing,
      );

      pw.Widget kv(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(flex: 3, child: pw.Text(k, style: t12())),
            pw.SizedBox(width: 6),
            pw.Expanded(flex: 5, child: pw.Text(v, style: t12())),
          ],
        ),
      );

      // -------- Page with moderate increases --------
      const double pageWidth = 187.0; // Increased from 180 to 190

      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(pageWidth, double.infinity, marginAll: 8),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Center(
                  child: pw.Text(
                    '***START OF LEGAL RECEIPT***',
                    style: t12(),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 10), // Increased from 8

                if (logoImage != null)
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Container(
                      width: 50,
                      height: 35,
                      child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                    ),
                  ),
                if (logoImage != null)
                  pw.SizedBox(height: 10), // Increased from 8
                // Company
                pw.Text(
                  (company['name'] ?? 'LIDOX ENTERPRISES').toString(),
                  style: t14(true),
                  textAlign: pw.TextAlign.center,
                ),

                pw.Text(
                  'ADDRESS: ${company['addressLine'] ?? 'TABORA CBD'}',
                  style: t12(),
                  textAlign: pw.TextAlign.center,
                ),
                pw.Text(
                  'MOBILE: ${company['mobile'] ?? '0655 000095'}',
                  style: t12(),
                  textAlign: pw.TextAlign.center,
                ),
                pw.Text(
                  'TIN: ${company['tin'] ?? '140710405'}',
                  style: t16(false),
                  textAlign: pw.TextAlign.center,
                ),
                pw.Text(
                  'VRN: ${company['vrn'] ?? 'NOT REGISTERED'}',
                  style: t12(),
                  textAlign: pw.TextAlign.center,
                ),
                pw.Text(
                  'SERIAL NO: ${company['serialNo'] ?? '1072114856'}',
                  style: t12(),
                  textAlign: pw.TextAlign.center,
                ),
                pw.Text(
                  'UIM: ${company['uim'] ?? '90VFVEDEA4P4055778277123029511072114856'}',
                  style: t12(),
                  textAlign: pw.TextAlign.center,
                ),
                pw.Text(
                  'TAX OFFICE: ${company['taxOffice'] ?? 'Tax Office Tabora'}',
                  style: t12(),
                  textAlign: pw.TextAlign.center,
                ),

                pw.SizedBox(height: 13), // Increased from 15
                // Customer (arranged)
                pw.Text(
                  'CUSTOMER NAME: ${((customer['name'] ?? '') as String).toUpperCase()}',
                  style: t12(false),
                  textAlign: pw.TextAlign.left,
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'CUSTOMER ID TYPE: ${(customer['idType'] ?? 'N/A').toString()}',
                  style: t12(),
                  textAlign: pw.TextAlign.left,
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'CUSTOMER ID: ${(customer['idNo'] ?? 'N/A').toString()}', // was: ID YA MNUNUZI
                  style: t12(),
                  textAlign: pw.TextAlign.left,
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'CUSTOMER VRN: ${(customer['vrn'] ?? 'N/A').toString()}', // was: VRN YA MNUNUZI
                  style: t12(),
                  textAlign: pw.TextAlign.left,
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'ADDRESS: ${(customer['mobile'] ?? 'N/A').toString()}', // was: ANWANI
                  style: t12(),
                  textAlign: pw.TextAlign.left,
                ),

                pw.SizedBox(height: 13), // Increased from 15
                // Receipt meta (arranged)
                pw.Row(
                  children: [
                    pw.Text('RECEIPT NUMBER', style: t12()),
                    pw.Expanded(
                      child: pw.Text(
                        '........................................................',
                        style: t12(),
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                      ),
                    ),
                    pw.Text((meta['receiptNo'] ?? '').toString(), style: t12()),
                  ],
                ),
                pw.SizedBox(height: 5),
                pw.Row(
                  children: [
                    pw.Text('ZNo', style: t12()),
                    pw.Expanded(
                      child: pw.Text(
                        '........................................................',
                        style: t12(),
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                      ),
                    ),
                    pw.Text((meta['zNumber'] ?? '').toString(), style: t12()),
                  ],
                ),

                // ECR: 01                             01
                pw.SizedBox(height: 5), // Increased from 15
                // DATE ...   TIME ...
                pw.Row(
                  children: [
                    pw.Text(
                      'DATE ${(meta['receiptDate'] ?? '').toString()}',
                      style: t12(),
                    ),
                    pw.Spacer(),
                    pw.Text(
                      '  TIME ${(meta['receiptTime'] ?? '').toString()}',
                      style: t12(),
                    ),
                  ],
                ),
                pw.SizedBox(height: 13), // Increased from 15
                dashedLine(),
                pw.SizedBox(height: 10), // Increased from 15
                pw.Row(
                  children: [
                    pw.Text('ECR:', style: t12()),
                    pw.SizedBox(width: 4),
                    pw.Text((meta['ecrNo'] ?? '01').toString(), style: t12()),
                    pw.Spacer(),
                    pw.Text(
                      (meta['counterNo'] ?? '01').toString(),
                      style: t12(),
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                dashedLine(),
                pw.SizedBox(height: 13), // Increased from 15
                // 1) All item descriptions first
                ...items.map((it) {
                  final desc = (it['description'] ?? 'BRANDING').toString();
                  final amt = (it['amount'] as num?)?.toDouble() ?? 60000.0;
                  final formattedAmt = (() {
                    final parts = amt.toStringAsFixed(2).split('.');
                    var intPart = parts[0];
                    final reg = RegExp(r'\B(?=(\d{3})+(?!\d))');
                    intPart = intPart.replaceAllMapped(reg, (m) => "'");
                    return '$intPart.${parts.length > 1 ? parts[1] : '00'}';
                  })();

                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 5),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              desc,
                              style: t12(),
                              maxLines: 1,
                              overflow: pw.TextOverflow.clip,
                            ),
                            pw.SizedBox(height: 5),
                            pw.Expanded(
                              child: pw.Text(
                                '........................................................',
                                style: t12(),
                                maxLines: 1,
                                overflow: pw.TextOverflow.clip,
                              ),
                            ),
                            pw.Text(formattedAmt, style: t12(), maxLines: 1),
                          ],
                        ),
                      ],
                    ),
                  );
                }),

                pw.SizedBox(height: 5),
                // dashed separator before totals
                dashedLine(),
                pw.SizedBox(height: 5),

                // 2) Totals: EXCL -> VAT
                _totalLine('TOTAL EXCL OF TAX:', money(totalExclTax), t12()),

                pw.SizedBox(height: 5),

                _totalLine('TOTAL TAX:', money(tax), t12()),
                pw.SizedBox(height: 5),
                dashedLine(),
                pw.SizedBox(height: 5),

                // 3) All AMOUNT rows per item
                // REMOVED: per-item "CASH" amount rows to avoid duplication
                pw.SizedBox(height: 5),

                // 4) TOTAL (overall)
                pw.Container(
                  height: 44,
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Text('TOTAL INCLUSIVE OF TAX', style: t12()),
                      pw.SizedBox(height: 4),
                      pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(money(totalInclTax), style: t16(false)),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 5),
                dashedLine(),
                pw.SizedBox(height: 5),

                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 5),
                  child: pw.Row(
                    children: [
                      pw.Text('CASH', style: t12()),
                      pw.Expanded(
                        child: pw.Text(
                          '........................................................',
                          style: t12(),
                          maxLines: 1,
                          overflow: pw.TextOverflow.clip,
                        ),
                      ),
                      pw.Text(money(totalInclTax), style: t12()),
                    ],
                  ),
                ),

                // 5) All QTY rows per item
                ...items.map((it) {
                  final qty = (it['qty'] ?? 1).toString();
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 5),
                    child: pw.Row(
                      children: [
                        pw.Text('ITEMS NUMBER', style: t12()),
                        pw.Expanded(
                          child: pw.Text(
                            '........................................................',
                            style: t12(),
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip,
                          ),
                        ),
                        pw.Text(qty, style: t12()),
                      ],
                    ),
                  );
                }),

                // CASH row showing total inclusive of tax
                pw.SizedBox(height: 5),
                // dashed separator before verification
                dashedLine(),
                pw.SizedBox(height: 5), // Increased from 15
                // Verification
                pw.Center(
                  child: pw.Text(
                    'RECEIPT VERIFICATION CODE',
                    style: t12(false),
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Center(
                  child: pw.Text(
                    (data['verificationCode'] ?? '56JLBU1108').toString(),
                    style: t16(false), // was t14(false)
                  ),
                ),
                pw.SizedBox(height: 5), // Increased from 12
                // QR code
                pw.Center(
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data:
                        'https://tra-verify-system.web.app/#/receipt/${(data['verificationCode'] ?? '56JLBU1108').toString()}',
                    width: 70,
                    height: 70,
                  ),
                ),

                pw.SizedBox(height: 20), // Increased from 15
                pw.Center(
                  child: pw.Text('*** END OF LEGAL RECEIPT ***', style: t12()),
                ),
              ],
            );
          },
        ),
      );

      // -------- Print/Save --------
      final fileName =
          'Receipt_${meta['receiptNo'] ?? DateTime.now().millisecondsSinceEpoch}.pdf';
      final bytes = await pdf.save();

      if (kIsWeb) {
        // Safari/iOS friendly: triggers download/share from user gesture
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      } else {
        await Printing.layoutPdf(
          name: fileName,
          onLayout: (format) async => bytes,
        );
      }

      // Feedback
      Get.snackbar(
        'Success',
        'PDF generated successfully',
        backgroundColor: Colors.green,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to generate PDF: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  // helper for aligned total rows
  static pw.Widget _totalLine(String label, String value, pw.TextStyle style) {
    final baseSize = style.fontSize ?? 12;
    final labelStyle = style.copyWith(
      fontSize: baseSize * 0.95, // slightly smaller to help fit
      letterSpacing: 0, // tighter tracking
    );
    final leaderSize = baseSize * 0.7; // smaller dots to save width

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        // Label stays full, truncated only if absolutely necessary
        pw.Text(
          label,
          style: labelStyle,
          maxLines: 1,
          overflow: pw.TextOverflow.clip,
        ),
        pw.SizedBox(width: 2),
        // Dynamic dotted leader consumes remaining space
        pw.Expanded(
          child: dotLeader(
            fontSize: leaderSize,
            letterSpacing: 0,
            color: PdfColors.grey,
          ),
        ),
        pw.SizedBox(width: 2),
        // Amount on the far right
        pw.Text(value, style: style),
      ],
    );
  }

  // dashed horizontal line
  static pw.Widget dashedLine({
    double dashWidth = 8, // was 4
    double dashGap = 4, // was 3
    double thickness = 1.2, // was 0.7
    PdfColor color = PdfColors.grey,
  }) {
    return pw.LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints?.maxWidth;
        final count = (total! / (dashWidth + dashGap)).floor().clamp(1, 1000);
        return pw.Row(
          mainAxisSize: pw.MainAxisSize.max,
          children: List.generate(
            count * 2 - 1,
            (i) => i.isEven
                ? pw.Container(
                    width: dashWidth,
                    height: thickness,
                    color: color,
                  )
                : pw.SizedBox(width: dashGap),
          ),
        );
      },
    );
  }

  // dotted leader using '.' characters so it aligns with the text baseline
  static pw.Widget dotLeader({
    double fontSize = 12,
    double letterSpacing = 0.2,
    PdfColor color = PdfColors.grey,
  }) {
    return pw.LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints?.maxWidth;
        final approxDotW = fontSize * 0.5 + letterSpacing;
        final count = (maxW! / approxDotW).floor().clamp(1, 2000);
        final dots = List.filled(count, '.').join();
        return pw.Text(
          dots,
          maxLines: 1,
          overflow: pw.TextOverflow.clip,
          style: pw.TextStyle(
            fontSize: fontSize,
            color: color,
            letterSpacing: letterSpacing,
          ),
        );
      },
    );
  }
}
