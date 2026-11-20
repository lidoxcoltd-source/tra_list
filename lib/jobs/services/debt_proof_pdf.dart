import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tra_list/jobs/models/debt.dart';

class DebtProofPdf {
  static Future<Uint8List> build({
    required Debt debt,
    required String proofUrl,
    required String title,
    required String referenceLabel,
    required String debtorLabel,
    required String phoneLabel,
    required String amountLabel,
    required String balanceLabel,
    required String directionLabel,
    required String directionValue,
    required String reasonLabel,
    required String reasonValue,
    required String shopLabel,
    required String dateLabel,
    required String dueDateLabel,
    required String notesLabel,
    required String evidenceLabel,
    required String qrPayloadLabel,
    required String currency,
  }) async {
    final document = pw.Document();
    final created = DateFormat('dd/MM/yyyy HH:mm').format(debt.createdAt);
    final dueDate = debt.dueDate == null
        ? '-'
        : DateFormat('dd/MM/yyyy').format(debt.dueDate!);
    final money = NumberFormat('#,##0.00');
    final qrPayload = proofUrl;
    final navy = PdfColor.fromHex('#12313A');
    final teal = PdfColor.fromHex('#0E5962');

    pw.Widget detail(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 7),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 145,
            child: pw.Text(
              label,
              style: pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value.isEmpty ? '-' : value,
              style: pw.TextStyle(
                color: navy,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(38),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                color: teal,
                borderRadius: pw.BorderRadius.circular(14),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 19,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    '$referenceLabel: ${debt.id}',
                    style: const pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            detail(debtorLabel, debt.debtorName),
            detail(phoneLabel, debt.phone),
            detail(shopLabel, debt.shopNickname),
            detail(directionLabel, directionValue),
            detail(reasonLabel, reasonValue),
            detail(amountLabel, '$currency ${money.format(debt.principal)}'),
            detail(balanceLabel, '$currency ${money.format(debt.balance)}'),
            detail(dateLabel, created),
            detail(dueDateLabel, dueDate),
            detail(notesLabel, debt.notes),
            detail(evidenceLabel, '${debt.evidenceUrls.length}'),
            pw.Spacer(),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 12),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: qrPayload,
                  width: 108,
                  height: 108,
                  drawText: false,
                ),
                pw.SizedBox(width: 18),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        qrPayloadLabel,
                        style: pw.TextStyle(
                          color: navy,
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        qrPayload,
                        style: const pw.TextStyle(
                          color: PdfColors.grey700,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return document.save();
  }
}
