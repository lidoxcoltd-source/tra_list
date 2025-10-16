import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/job.dart';

enum _ReceiptAction { none, save, print }

class AdvancePaymentPdf {
  static Future<void> askAndHandle(
    BuildContext context, {
    required Job job,
    required NumberFormat moneyFmt,
    required DateFormat dateFmt,
    String? description,
  }) async {
    final action = await showDialog<_ReceiptAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Advance payment receipt'),
        content: const Text('Generate receipt for the advance now?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _ReceiptAction.none),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _ReceiptAction.save),
            child: const Text('Save PDF'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _ReceiptAction.print),
            child: const Text('Print'),
          ),
        ],
      ),
    );

    if (action == null || action == _ReceiptAction.none) return;

    final bytes = await build(
      job: job,
      moneyFmt: moneyFmt,
      dateFmt: dateFmt,
      description: description,
    );
    final fileName =
        'advance_receipt_${job.id ?? DateTime.now().millisecondsSinceEpoch}.pdf';

    if (action == _ReceiptAction.save) {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } else if (action == _ReceiptAction.print) {
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    }
  }

  static Future<Uint8List> build({
    required Job job,
    required NumberFormat moneyFmt,
    required DateFormat dateFmt,
    String? description,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final balance = (job.totalAmount - job.advancePaid).clamp(
      0,
      double.infinity,
    );
    final receiptNo =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${(job.id ?? now.millisecondsSinceEpoch)}';

    pw.Widget kv(String k, String v) => pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 150,
          child: pw.Text(
            k,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Expanded(child: pw.Text(v)),
      ],
    );

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(margin: const pw.EdgeInsets.all(32)),
        build: (ctx) => [
          // Header
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Advance Payment Receipt',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text('Receipt No: $receiptNo'),
                  pw.Text('Date: ${dateFmt.format(now)}'),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Divider(),
          pw.SizedBox(height: 12),

          // Customer and job info
          pw.Text(
            'Customer',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          kv('Name', job.customerName),
          if (job.jobType.isNotEmpty) kv('Job Type', job.jobType),
          if ((description ?? '').isNotEmpty) kv('Description', description!),
          if (job.phonePrimary.isNotEmpty) kv('Phone', job.phonePrimary),
          if ((job.phoneSecondary ?? '').isNotEmpty)
            kv('Alt Phone', job.phoneSecondary!),

          pw.SizedBox(height: 16),
          pw.Text(
            'Payment',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      'Item',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      'Amount',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ],
              ),
              pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('Total'),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(moneyFmt.format(job.totalAmount)),
                  ),
                ],
              ),
              pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('Advance Paid'),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(moneyFmt.format(job.advancePaid)),
                  ),
                ],
              ),
              pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      'Balance Due',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      moneyFmt.format(balance),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 24),
          pw.Text(
            'Notes',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('This receipt acknowledges the advance payment received.'),

          pw.SizedBox(height: 32),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _signatureBlock('Customer Signature'),
              _signatureBlock('Authorized Signature'),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _signatureBlock(String title) => pw.Column(
    children: [
      pw.Text(title),
      pw.SizedBox(height: 40),
      pw.Container(width: 180, height: 0.8, color: PdfColors.black),
    ],
  );
}
