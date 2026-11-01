import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:tra_list/services/pdf/pdf_saver.dart' as pdf_saver;
import 'package:tra_list/services/company_logo_service.dart';
import 'package:tra_list/services/profile_service.dart';
import 'transaction_model.dart';

class TransactionReportPdf {
  static Future<void> generate({
    required List<TransactionModel> transactions,
    required double totalIncome,
    required double totalExpense,
    required double netProfit,
    required String filterTitle,
  }) async {
    final bytes = await _buildPdfBytes(
      transactions,
      totalIncome,
      totalExpense,
      netProfit,
      filterTitle,
    );
    await Printing.layoutPdf(onLayout: (f) async => bytes);
    Get.snackbar(
      'Success',
      'Transaction Report generated',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  static Future<String> generateAndSave({
    required List<TransactionModel> transactions,
    required double totalIncome,
    required double totalExpense,
    required double netProfit,
    required String filterTitle,
  }) async {
    final bytes = await _buildPdfBytes(
      transactions,
      totalIncome,
      totalExpense,
      netProfit,
      filterTitle,
    );
    final fileName =
        'Transaction_Report_${DateTime.now().toIso8601String()}.pdf';
    return pdf_saver.savePdf(bytes, fileName);
  }

  static Future<Uint8List> _buildPdfBytes(
    List<TransactionModel> transactions,
    double totalIncome,
    double totalExpense,
    double netProfit,
    String filterTitle,
  ) async {
    final pdf = pw.Document();
    final company = await ProfileService.loadOrCreate();

    final colors = (company['colors'] as Map?) ?? {};
    final brandColor = colors['brand'] is int
        ? PdfColor.fromInt(colors['brand'])
        : PdfColor.fromInt(0xFF1976D2);
    final accentColor = colors['accent'] is int
        ? PdfColor.fromInt(colors['accent'])
        : PdfColor.fromInt(0xFF42A5F5);
    final footerColor = colors['footer'] is int
        ? PdfColor.fromInt(colors['footer'])
        : PdfColors.grey800;
    final t = _Theme(brand: brandColor, accent: accentColor);

    final logoBytes = await CompanyLogoService.resolveLogoBytes(company);
    final pw.ImageProvider? logo = logoBytes == null
        ? null
        : pw.MemoryImage(logoBytes);

    pw.ImageProvider? socialIcons;
    try {
      final socialBytes = await rootBundle.load('assets/social-icons.png');
      socialIcons = pw.MemoryImage(socialBytes.buffer.asUint8List());
    } catch (_) {}

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (ctx) => _buildHeader(t, company, logo, filterTitle),
        footer: (ctx) => _buildFooter(t, company, footerColor, socialIcons),
        build: (ctx) => [
          _buildSummary(t, totalIncome, totalExpense, netProfit),
          pw.SizedBox(height: 24),
          _buildTable(t, brandColor, transactions),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildHeader(
    _Theme t,
    Map<String, dynamic> company,
    pw.ImageProvider? logo,
    String filterTitle,
  ) {
    return pw.Column(
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logo != null)
              pw.Container(
                width: 80,
                height: 80,
                child: pw.Image(logo, fit: pw.BoxFit.contain),
              ),
            if (logo != null) pw.SizedBox(width: 20),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(company['name'] ?? '', style: t.h2),
                  pw.Text(company['address'] ?? '', style: t.small),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Transaction Report', style: t.h1),
                pw.Text(filterTitle, style: t.smallGrey),
              ],
            ),
          ],
        ),
        pw.Divider(height: 24),
      ],
    );
  }

  static pw.Widget _buildSummary(
    _Theme t,
    double income,
    double expense,
    double net,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
      children: [
        _summaryItem(t, 'Total Income', income, PdfColors.green),
        _summaryItem(t, 'Total Expenses', expense, PdfColors.red),
        _summaryItem(
          t,
          'Net Profit',
          net,
          net >= 0 ? PdfColors.blue : PdfColors.orange,
        ),
      ],
    );
  }

  static pw.Widget _summaryItem(
    _Theme t,
    String label,
    double value,
    PdfColor color,
  ) {
    return pw.Column(
      children: [
        pw.Text(label, style: t.smallGrey),
        pw.SizedBox(height: 4),
        pw.Text(
          'TSH ${_Theme.money(value)}',
          style: t.h3Bold.copyWith(color: color),
        ),
      ],
    );
  }

  static pw.Widget _buildTable(
    _Theme t,
    PdfColor brandColor,
    List<TransactionModel> transactions,
  ) {
    final headers = ['Date', 'Description', 'Category', 'Income', 'Expense'];

    final data = transactions.map((trans) {
      final date = '${trans.date.day}/${trans.date.month}/${trans.date.year}';
      final isIncome = trans.type == TransactionType.income;
      return [
        date,
        trans.description,
        trans.category,
        isIncome ? _Theme.money(trans.amount) : '-',
        !isIncome ? _Theme.money(trans.amount) : '-',
      ];
    }).toList();

    return pw.Table.fromTextArray(
      headers: headers,
      data: data,
      border: null,
      headerStyle: t.header,
      headerDecoration: pw.BoxDecoration(
        color: brandColor,
        borderRadius: pw.BorderRadius.circular(2),
      ),
      cellHeight: 30,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
      },
      cellStyle: t.small,
    );
  }

  static pw.Widget _buildFooter(
    _Theme t,
    Map<String, dynamic> company,
    PdfColor footerColor,
    pw.ImageProvider? socialIcons,
  ) {
    final handle = (company['handle'] ?? '').toString();
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
          pw.Text(
            'Generated on ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
            style: t.smallWhite,
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
      pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: brand);
  pw.TextStyle get h2 =>
      pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold);
  pw.TextStyle get h3Bold =>
      pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold);
  pw.TextStyle get header => pw.TextStyle(
    fontSize: 10,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.white,
  );
  pw.TextStyle get small => pw.TextStyle(fontSize: 9, color: PdfColors.black);
  pw.TextStyle get smallGrey =>
      pw.TextStyle(fontSize: 9, color: PdfColors.grey700);
  pw.TextStyle get smallWhite =>
      pw.TextStyle(fontSize: 9, color: PdfColors.white);

  static String money(num v) => v
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
}
