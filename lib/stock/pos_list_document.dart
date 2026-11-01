import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PosListDocument {
  static Future<Uint8List> generateBytes(Map<String, dynamic> data) async {
    final pdf = pw.Document();
    final items = (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final total = (data['total'] as num?)?.toDouble() ?? 0;
    final number = data['listNumber']?.toString() ?? '';
    final customer = data['customerName']?.toString().trim() ?? '';
    final dateText = data['dateText']?.toString() ?? '';
    final title = data['documentTitle']?.toString() ?? 'PRODUCT LIST';
    final customerLabel = data['customerLabel']?.toString() ?? 'Customer';
    final totalLabel = data['totalLabel']?.toString() ?? 'TOTAL';
    final footerNote =
        data['footerNote']?.toString() ?? 'List only - no sale completed';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat(
          80 * PdfPageFormat.mm,
          180 * PdfPageFormat.mm,
        ),
        pageTheme: const pw.PageTheme(
          margin: pw.EdgeInsets.fromLTRB(8, 10, 8, 10),
        ),
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Center(
            child: pw.Text(
              '${context.pageNumber}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ),
        ),
        build: (context) => [
          pw.Center(
            child: pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blueGrey900,
              ),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(number, style: const pw.TextStyle(fontSize: 9)),
          ),
          if (dateText.isNotEmpty)
            pw.Center(
              child: pw.Text(dateText, style: const pw.TextStyle(fontSize: 8)),
            ),
          if (customer.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: pw.Text(
                '$customerLabel: $customer',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          pw.Divider(),
          for (final item in items) _itemRow(item),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                totalLabel,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'TZS ${_money(total)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(
              footerNote,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _itemRow(Map<String, dynamic> item) {
    final name = item['name']?.toString() ?? '';
    final unit = item['unit']?.toString() ?? '';
    final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
    final unitPrice = (item['unitPrice'] as num?)?.toDouble() ?? 0;
    final amount = (item['amount'] as num?)?.toDouble() ?? 0;

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Text(
                  name,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.Text('TZS ${_money(amount)}'),
            ],
          ),
          pw.Text(
            '${_quantity(quantity)} $unit x TZS ${_money(unitPrice)}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  static String _quantity(num value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();

  static String _money(num value) => value.round().toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => ',',
  );
}
