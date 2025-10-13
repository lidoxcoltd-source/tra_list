import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;
import 'transaction_model.dart';

class TransactionExcelExport {
  static Future<String> generateAndSave({
    required List<TransactionModel> transactions,
    required double totalIncome,
    required double totalExpense,
    required double netProfit,
    required String filterTitle,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Transactions'];

    // Remove default sheet if it exists
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // Header styling
    final headerStyle = CellStyle(
      fontFamily: getFontFamily(FontFamily.Calibri),
      fontSize: 12,
      bold: true,
      backgroundColorHex: ExcelColor.blue,
      fontColorHex: ExcelColor.white,
    );

    final summaryStyle = CellStyle(
      fontFamily: getFontFamily(FontFamily.Calibri),
      fontSize: 11,
      bold: true,
      backgroundColorHex: ExcelColor.grey400,
    );

    // Title and summary section
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue(
      'Transaction Report - $filterTitle',
    );
    sheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
      fontFamily: getFontFamily(FontFamily.Calibri),
      fontSize: 14,
      bold: true,
    );

    sheet.cell(CellIndex.indexByString('A3')).value = TextCellValue('Summary');
    sheet.cell(CellIndex.indexByString('A3')).cellStyle = summaryStyle;

    sheet.cell(CellIndex.indexByString('A4')).value = TextCellValue(
      'Total Income:',
    );
    sheet.cell(CellIndex.indexByString('B4')).value = DoubleCellValue(
      totalIncome,
    );
    sheet.cell(CellIndex.indexByString('A4')).cellStyle = summaryStyle;

    sheet.cell(CellIndex.indexByString('A5')).value = TextCellValue(
      'Total Expense:',
    );
    sheet.cell(CellIndex.indexByString('B5')).value = DoubleCellValue(
      totalExpense,
    );
    sheet.cell(CellIndex.indexByString('A5')).cellStyle = summaryStyle;

    sheet.cell(CellIndex.indexByString('A6')).value = TextCellValue(
      'Net Profit/Loss:',
    );
    sheet.cell(CellIndex.indexByString('B6')).value = DoubleCellValue(
      netProfit,
    );
    sheet.cell(CellIndex.indexByString('A6')).cellStyle = summaryStyle;

    // Transaction headers (starting from row 8)
    final headers = ['Date', 'Description', 'Category', 'Type', 'Amount (TSH)'];
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 7),
      );
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    // Add transaction data
    for (int i = 0; i < transactions.length; i++) {
      final transaction = transactions[i];
      final rowIndex = i + 8; // Starting from row 9 (0-indexed)

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex))
          .value = TextCellValue(
        DateFormat('yyyy-MM-dd').format(transaction.date),
      );

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex))
          .value = TextCellValue(
        transaction.description,
      );

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex))
          .value = TextCellValue(
        transaction.category,
      );

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex))
          .value = TextCellValue(
        transaction.type == TransactionType.income ? 'Income' : 'Expense',
      );

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex))
          .value = DoubleCellValue(
        transaction.amount,
      );
    }

    // Auto-fit columns
    for (int i = 0; i < headers.length; i++) {
      sheet.setColumnWidth(i, 20);
    }

    // Generate file
    final bytes = excel.encode()!;
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'transactions_$timestamp.xlsx';

    if (kIsWeb) {
      // Web download
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.document.createElement('a') as html.AnchorElement
        ..href = url
        ..style.display = 'none'
        ..download = fileName;
      html.document.body?.children.add(anchor);
      anchor.click();
      html.document.body?.children.remove(anchor);
      html.Url.revokeObjectUrl(url);
      return fileName;
    } else {
      // Mobile/Desktop save
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(bytes);
      return file.path;
    }
  }
}
