import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'pdf_assets.dart';
import 'pdf_styles.dart';
import 'pdf_widgets.dart';

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

      // -------- Totals --------
      double totalExclTax =
          (data['totalExclTax'] as num?)?.toDouble() ??
          items.fold<double>(
            0,
            (sum, it) => sum + ((it['amount'] as num?)?.toDouble() ?? 0.0),
          );
      double tax = (data['tax'] as num?)?.toDouble() ?? 0.0;
      double totalInclTax =
          (data['totalInclTax'] as num?)?.toDouble() ?? (totalExclTax + tax);

      // -------- Assets / Theme --------
      final logoImage = await PdfAssets.loadLogo();
      final fonts = await PdfAssets.loadFonts();
      final theme = PdfTheme(regular: fonts.regular, bold: fonts.bold);

      // -------- Page --------
      const double pageWidth = 187.0;
      final pdf = pw.Document();

      pw.TextStyle t12([bool b = false]) => theme.t12(b);
      pw.TextStyle t16([bool b = false]) => theme.t16(b);

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
                pw.SizedBox(height: 10),

                if (logoImage != null)
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Container(
                      width: 50,
                      height: 35,
                      child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                    ),
                  ),
                if (logoImage != null) pw.SizedBox(height: 10),

                // Company
                pw.Text(
                  (company['name'] ?? 'LIDOX ENTERPRISES').toString(),
                  style: t12(true),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 6),
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

                pw.SizedBox(height: 15),

                // Customer
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
                  'CUSTOMER ID: ${(customer['idNo'] ?? 'N/A').toString()}',
                  style: t12(),
                  textAlign: pw.TextAlign.left,
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'CUSTOMER VRN: ${(customer['vrn'] ?? 'N/A').toString()}',
                  style: t12(),
                  textAlign: pw.TextAlign.left,
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'ADDRESS: ${(customer['mobile'] ?? 'N/A').toString()}',
                  style: t12(),
                  textAlign: pw.TextAlign.left,
                ),

                pw.SizedBox(height: 15),

                // Receipt meta
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
                pw.SizedBox(height: 5, width: 0),
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
                pw.SizedBox(height: 5),
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

                pw.SizedBox(height: 15),
                dashedLine(),
                pw.SizedBox(height: 10),

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
                pw.SizedBox(height: 15),

                ...items.map((it) {
                  final desc = (it['description'] ?? 'BRANDING').toString();
                  final qty = (it['qty'] ?? 1).toString();
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
                        pw.SizedBox(height: 5),
                        pw.Row(
                          children: [
                            pw.Text('QTY', style: t12()),
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
                        pw.SizedBox(height: 5),
                        pw.Row(
                          children: [
                            pw.Text('AMOUNT', style: t12(false)),
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

                pw.SizedBox(height: 12),
                dashedLine(),
                pw.SizedBox(height: 8),

                totalLine(
                  'TOTAL EXCL OF TAX:',
                  theme.money(totalExclTax),
                  t12(),
                ),
                totalLine('TOTAL TAX:', theme.money(tax), t12()),
                pw.SizedBox(height: 5),

                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('TOTAL', style: t12()),
                    pw.Text(theme.money(totalInclTax), style: t16(false)),
                  ],
                ),

                pw.SizedBox(height: 12),
                dashedLine(),
                pw.SizedBox(height: 20),

                pw.Center(
                  child: pw.Text(
                    'RECEIPT VERIFICATION CODE',
                    style: t12(false),
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Center(
                  child: pw.Text(
                    (data['verificationCode'] ?? '56JLBU1108').toString(),
                    style: t16(false),
                  ),
                ),
                pw.SizedBox(height: 5),

                pw.Center(
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data:
                        'https://tra-verify-system.web.app/#/receipt/${(data['verificationCode'] ?? '56JLBU1108').toString()}',
                    width: 70,
                    height: 70,
                  ),
                ),

                pw.SizedBox(height: 20),
                pw.Center(
                  child: pw.Text('*** END OF LEGAL RECEIPT ***', style: t12()),
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        name:
            'Receipt_${meta['receiptNo'] ?? DateTime.now().millisecondsSinceEpoch}',
        onLayout: (format) async => pdf.save(),
      );

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
}
