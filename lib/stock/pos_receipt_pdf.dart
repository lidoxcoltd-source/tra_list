import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds a narrow, variable-length thermal receipt for POS sales.
Future<Uint8List> buildPosReceiptPdf(Map<String, dynamic> data) async {
  final company = _asMap(data['company']);
  final client = _asMap(data['client']);
  final invoice = _asMap(data['invoice']);
  final items = (data['items'] as List? ?? const [])
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
  final total = _number(data['total']);
  final itemHeight = items.fold<double>(0, (height, item) {
    final description = (item['description'] ?? item['name'] ?? '').toString();
    // Allow long product names to wrap on the 80 mm roll.
    final lines = (description.length / 27).ceil().clamp(1, 8).toInt();
    return height + lines * 11 + 5;
  });
  final pageHeight = (104 + itemHeight).clamp(110, 2000).toDouble();
  final pdf = pw.Document();
  final muted = PdfColors.grey700;

  String text(Object? value, [String fallback = '']) {
    final result = value?.toString().trim() ?? '';
    return result.isEmpty ? fallback : result;
  }

  String money(num value) {
    final fixed = value.toStringAsFixed(2).split('.');
    final whole = fixed.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '$whole.${fixed.last}';
  }

  pw.Widget divider() => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 4),
    child: pw.LayoutBuilder(
      builder: (context, constraints) => pw.Text(
        List.filled(((constraints?.maxWidth ?? 0) / 3).floor(), '-').join(),
        maxLines: 1,
        style: pw.TextStyle(fontSize: 7, color: muted),
      ),
    ),
  );

  pw.Widget amountRow(String label, num amount, {bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: bold ? 11 : 9,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
            pw.Text(
              money(amount),
              style: pw.TextStyle(
                fontSize: bold ? 11 : 9,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ],
        ),
      );

  final number = text(invoice['number'], text(data['number'], 'POS'));
  final date = text(invoice['issueDate']);
  final time = text(data['receiptTime']);
  final receiptId = text(data['receiptId'], text(data['id'], number));
  final receiptUrl = 'https://tra-verify-system.web.app/#/receipt/$receiptId';
  final qrCode = pw.BarcodeWidget(
    barcode: pw.Barcode.qrCode(),
    data: receiptUrl,
    width: 92,
    height: 92,
  );

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(
        80 * PdfPageFormat.mm,
        pageHeight * PdfPageFormat.mm,
      ),
      margin: const pw.EdgeInsets.fromLTRB(
        5 * PdfPageFormat.mm,
        4 * PdfPageFormat.mm,
        5 * PdfPageFormat.mm,
        4 * PdfPageFormat.mm,
      ),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text(
              'CASH RECEIPT',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
          ),
          if (text(company['name']).isNotEmpty)
            pw.Center(
              child: pw.Text(
                text(company['name']).toUpperCase(),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          if (text(company['addressLine'], text(company['address'])).isNotEmpty)
            pw.Center(
              child: pw.Text(
                text(company['addressLine'], text(company['address'])),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 8),
              ),
            ),
          if (text(company['mobile'], text(company['phone'])).isNotEmpty)
            pw.Center(
              child: pw.Text(
                'Tel: ${text(company['mobile'], text(company['phone']))}',
                style: pw.TextStyle(fontSize: 8),
              ),
            ),
          if (text(company['tin']).isNotEmpty)
            pw.Center(
              child: pw.Text(
                'TIN: ${text(company['tin'])}',
                style: pw.TextStyle(fontSize: 8),
              ),
            ),
          divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text('Date: $date', style: pw.TextStyle(fontSize: 8)),
              ),
              pw.Text(time, style: pw.TextStyle(fontSize: 8)),
            ],
          ),
          pw.Text('Receipt: $number', style: pw.TextStyle(fontSize: 8)),
          if (text(client['name']).isNotEmpty)
            pw.Text(
              'Customer: ${text(client['name'])}',
              style: pw.TextStyle(fontSize: 8),
            ),
          pw.Text(
            'Served by: ${text(data['cashierName'], 'Mhudumu')}',
            style: pw.TextStyle(fontSize: 8),
          ),
          divider(),
          for (final item in items)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      '${text(item['description'], text(item['name'], 'Item'))}  x${_quantity(item['qty'])}',
                      style: pw.TextStyle(fontSize: 9),
                    ),
                  ),
                  pw.SizedBox(width: 5),
                  pw.Text(
                    money(_number(item['amount'])),
                    style: pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),
          divider(),
          amountRow('Total', total, bold: true),
          amountRow('Sub-total', total),
          amountRow('Sales Tax', 0),
          amountRow('Balance', total, bold: true),
          pw.SizedBox(height: 10),
          pw.Center(
            child: pw.Text(
              'THANK YOU',
              style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Center(child: qrCode),
          pw.SizedBox(height: 3),
          pw.Center(
            child: pw.Text(
              number,
              style: pw.TextStyle(fontSize: 7, color: muted),
            ),
          ),
        ],
      ),
    ),
  );
  return pdf.save();
}

Map<String, dynamic> _asMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

double _number(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;

String _quantity(Object? value) {
  final quantity = _number(value);
  return quantity == quantity.roundToDouble()
      ? quantity.toInt().toString()
      : quantity.toString();
}
