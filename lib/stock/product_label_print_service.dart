import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../services/pdf/pdf_saver.dart' as pdf_saver;
import 'stock_models.dart';

enum ProductCodeFormat { code128, qr }

class ProductLabelPrintService {
  static String fileNameFor(Product product) =>
      '${product.sku.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}_labels.pdf';

  static Future<bool> printLabels({
    required Product product,
    required ProductCodeFormat format,
    required int copies,
  }) async {
    final bytes = await buildLabelsPdf(
      product: product,
      format: format,
      copies: copies,
    );

    return Printing.layoutPdf(
      name: fileNameFor(product),
      format: PdfPageFormat.a4,
      onLayout: (_) async => bytes,
    );
  }

  static Future<String> saveLabels({
    required Product product,
    required ProductCodeFormat format,
    required int copies,
  }) async {
    final bytes = await buildLabelsPdf(
      product: product,
      format: format,
      copies: copies,
    );
    return pdf_saver.savePdf(bytes, fileNameFor(product));
  }

  static Future<ShareResult> shareLabels({
    required Product product,
    required ProductCodeFormat format,
    required int copies,
  }) async {
    final bytes = await buildLabelsPdf(
      product: product,
      format: format,
      copies: copies,
    );
    final fileName = fileNameFor(product);
    return SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(bytes, mimeType: 'application/pdf', name: fileName),
        ],
        fileNameOverrides: [fileName],
        title: product.name,
        subject: product.name,
      ),
    );
  }

  @visibleForTesting
  static Future<Uint8List> buildLabelsPdf({
    required Product product,
    required ProductCodeFormat format,
    required int copies,
  }) async {
    final code = product.barcode.trim().isNotEmpty
        ? product.barcode.trim()
        : product.sku.trim();
    if (code.isEmpty) {
      throw const FormatException('A barcode or SKU is required.');
    }
    if (copies < 1 || copies > 100) {
      throw RangeError.range(copies, 1, 100, 'copies');
    }
    if (format == ProductCodeFormat.code128 &&
        !RegExp(r'^[\x20-\x7E]+$').hasMatch(code)) {
      throw const FormatException(
        'Code 128 supports printable ASCII only. Use a QR code instead.',
      );
    }

    const columns = 3;
    final mm = PdfPageFormat.mm;
    final rows = (copies / columns).ceil();
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(8 * mm),
        build: (_) => [
          pw.Table(
            columnWidths: {
              for (var column = 0; column < columns; column++)
                column: const pw.FlexColumnWidth(),
            },
            children: List.generate(rows, (row) {
              return pw.TableRow(
                children: List.generate(columns, (column) {
                  final index = row * columns + column;
                  if (index >= copies) return pw.SizedBox();
                  return pw.Container(
                    height: 34 * mm,
                    margin: pw.EdgeInsets.all(1.5 * mm),
                    padding: pw.EdgeInsets.all(2 * mm),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.grey500,
                        width: .5,
                      ),
                      borderRadius: pw.BorderRadius.circular(1.5 * mm),
                    ),
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          product.name,
                          maxLines: 1,
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Center(
                            child: pw.BarcodeWidget(
                              barcode: format == ProductCodeFormat.qr
                                  ? pw.Barcode.qrCode()
                                  : pw.Barcode.code128(),
                              data: code,
                              width: format == ProductCodeFormat.qr
                                  ? 20 * mm
                                  : 54 * mm,
                              height: format == ProductCodeFormat.qr
                                  ? 20 * mm
                                  : 16 * mm,
                              drawText: false,
                            ),
                          ),
                        ),
                        pw.Text(
                          code,
                          maxLines: 1,
                          textAlign: pw.TextAlign.center,
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                        pw.Text(
                          'TZS ${formatMoney(product.sellPrice)}',
                          style: pw.TextStyle(
                            fontSize: 7,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              );
            }),
          ),
        ],
      ),
    );
    return pdf.save();
  }
}
