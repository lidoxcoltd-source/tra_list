import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

// PDF/Print
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// QR Code Service
import 'QRCodeService.dart';

/// ───────────────────────────────── DATA MODELS ─────────────────────────────────

class CompanyInfo {
  final String name;
  final String addressLine;
  final String mobile;
  final String tin;
  final String vrn;
  final String serialNo;
  final String uim;
  final String taxOffice;
  final ImageProvider? logo;

  const CompanyInfo({
    required this.name,
    required this.addressLine,
    required this.mobile,
    required this.tin,
    required this.vrn,
    required this.serialNo,
    required this.uim,
    required this.taxOffice,
    this.logo,
  });

  CompanyInfo copyWith({ImageProvider? logo}) => CompanyInfo(
    name: name,
    addressLine: addressLine,
    mobile: mobile,
    tin: tin,
    vrn: vrn,
    serialNo: serialNo,
    uim: uim,
    taxOffice: taxOffice,
    logo: logo ?? this.logo,
  );
}

class CustomerInfo {
  final String name;
  final String idType;
  final String idNo;
  final String mobile;
  const CustomerInfo({
    required this.name,
    required this.idType,
    required this.idNo,
    required this.mobile,
  });
}

class ReceiptMeta {
  final String receiptNo;
  final String zNumber;
  final String receiptDate;
  final String receiptTime;

  const ReceiptMeta({
    required this.receiptNo,
    required this.zNumber,
    required this.receiptDate,
    required this.receiptTime,
  });
}

class LineItem {
  final String description;
  final int qty;
  final double amount; // extended amount for the line
  const LineItem({
    required this.description,
    required this.qty,
    required this.amount,
  });
}

class ReceiptData {
  final CompanyInfo company;
  final CustomerInfo customer;
  final ReceiptMeta meta;
  final List<LineItem> items;
  final double totalExclTax;
  final double tax;
  final double totalInclTax;
  final String verificationCode;
  final ImageProvider? qr;

  const ReceiptData({
    required this.company,
    required this.customer,
    required this.meta,
    required this.items,
    required this.totalExclTax,
    required this.tax,
    required this.totalInclTax,
    required this.verificationCode,
    this.qr,
  });

  ReceiptData copyWith({CompanyInfo? company, ImageProvider? qr}) =>
      ReceiptData(
        company: (company ?? this.company),
        customer: customer,
        meta: meta,
        items: items,
        totalExclTax: totalExclTax,
        tax: tax,
        totalInclTax: totalInclTax,
        verificationCode: verificationCode,
        qr: qr ?? this.qr,
      );
}

/// ───────────────────────────────── RECEIPT PAGE (UI) ─────────────────────────────────

class ReceiptPage extends StatelessWidget {
  const ReceiptPage({super.key, this.data});

  final ReceiptData? data;

  String _fmtTZS(num v) {
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final whole = parts[0];
    final buf = StringBuffer();
    for (int i = 0; i < whole.length; i++) {
      final fromEnd = whole.length - i;
      buf.write(whole[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
    }
    return '${buf.toString()}.${parts[1]}';
  }

  static String _tzs(String money) => 'TZS $money';

  Widget _dottedDivider() => LayoutBuilder(
    builder: (context, c) {
      final dots = (c.maxWidth / 6).floor();
      return Text(
        List.filled(dots, '·').join(' '),
        style: TextStyle(color: Colors.grey.shade400, letterSpacing: 1),
        textAlign: TextAlign.center,
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final d = data ?? _sampleData();

    final textMuted = TextStyle(color: Colors.grey.shade600, fontSize: 12);
    final textSmall = const TextStyle(fontSize: 12);
    final labelStyle = textSmall.copyWith(color: Colors.grey.shade700);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Legal Receipt'), centerTitle: true),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Text(
                    '*** START OF LEGAL RECEIPT ***',
                    style: textMuted,
                  ),
                ),
                const SizedBox(height: 8),

                // Header with logo/info
                Column(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: d.company.logo,
                      child: d.company.logo == null
                          ? const Icon(Icons.approval, size: 28)
                          : null,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      d.company.name.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    _companyRow(
                      'ADDRESS:',
                      d.company.addressLine,
                      labelStyle,
                      textSmall,
                    ),
                    _companyRow(
                      'MOBILE:',
                      d.company.mobile,
                      labelStyle,
                      textSmall,
                    ),
                    _companyRow('TIN:', d.company.tin, labelStyle, textSmall),
                    _companyRow('VRN:', d.company.vrn, labelStyle, textSmall),
                    _companyRow(
                      'SERIAL NO:',
                      d.company.serialNo,
                      labelStyle,
                      textSmall,
                    ),
                    _companyRow('UIM:', d.company.uim, labelStyle, textSmall),
                    _companyRow(
                      'TAX OFFICE:',
                      d.company.taxOffice,
                      labelStyle,
                      textSmall,
                    ),
                  ],
                ),

                const SizedBox(height: 10),
                _dottedDivider(),
                const SizedBox(height: 6),

                // Customer
                _twoColRow(
                  'CUSTOMER NAME:',
                  d.customer.name,
                  labelStyle,
                  textSmall,
                ),
                _twoColRow(
                  'CUSTOMER ID TYPE:',
                  d.customer.idType,
                  labelStyle,
                  textSmall,
                ),
                _twoColRow(
                  'CUSTOMER ID NO:',
                  d.customer.idNo,
                  labelStyle,
                  textSmall,
                ),
                _twoColRow(
                  'CUSTOMER MOBILE:',
                  d.customer.mobile,
                  labelStyle,
                  textSmall,
                ),

                const SizedBox(height: 6),
                _dottedDivider(),
                const SizedBox(height: 6),

                // Meta
                _twoColRow(
                  'RECEIPT NO:',
                  d.meta.receiptNo,
                  labelStyle,
                  textSmall,
                ),
                _twoColRow('Z NUMBER:', d.meta.zNumber, labelStyle, textSmall),
                _twoColRow(
                  'RECEIPT DATE:',
                  d.meta.receiptDate,
                  labelStyle,
                  textSmall,
                ),
                _twoColRow(
                  'RECEIPT TIME:',
                  d.meta.receiptTime,
                  labelStyle,
                  textSmall,
                ),

                const SizedBox(height: 10),
                _dottedDivider(),
                const SizedBox(height: 12),

                // Items table
                Text(
                  'Purchased Items',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),

                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(6),
                      1: FlexColumnWidth(2),
                      2: FlexColumnWidth(3),
                    },
                    border: TableBorder(
                      horizontalInside: BorderSide(color: Colors.grey.shade300),
                    ),
                    children: [
                      TableRow(
                        decoration: BoxDecoration(color: Colors.grey.shade100),
                        children: const [
                          _Cell('Description', bold: true),
                          _Cell('Qty', bold: true, align: TextAlign.center),
                          _Cell('Amount', bold: true, align: TextAlign.right),
                        ],
                      ),
                      ...d.items.map(
                        (it) => TableRow(
                          children: [
                            _Cell(it.description),
                            _Cell('${it.qty}', align: TextAlign.center),
                            _Cell(
                              _tzs(_fmtTZS(it.amount)),
                              align: TextAlign.right,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Totals
                _totalRow('TOTAL EXCL OF TAX:', _tzs(_fmtTZS(d.totalExclTax))),
                _totalRow('TOTAL TAX:', _tzs(_fmtTZS(d.tax))),
                _totalRow(
                  'TOTAL INCL OF TAX:',
                  _tzs(_fmtTZS(d.totalInclTax)),
                  bold: true,
                ),

                const SizedBox(height: 14),
                _dottedDivider(),
                const SizedBox(height: 12),

                // Verification section
                Center(
                  child: Column(
                    children: [
                      Text(
                        'RECEIPT VERIFICATION CODE',
                        style: textSmall.copyWith(color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        d.verificationCode,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: () {
                          if (d.verificationCode.isNotEmpty) {
                            QRCodeService.showQRDialog(
                              context: context,
                              receiptId: d.verificationCode,
                              title: 'Receipt QR Code',
                            );
                          }
                        },
                        child: Container(
                          width: 120,
                          height: 120,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.white,
                          ),
                          child: d.verificationCode.isNotEmpty
                              ? QRCodeService.generateReceiptQR(
                                  receiptId: d.verificationCode,
                                  size: 120,
                                )
                              : d.qr != null
                              ? Image(image: d.qr!, fit: BoxFit.cover)
                              : const Center(
                                  child: Icon(Icons.qr_code, size: 72),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                Center(
                  child: Text('*** END OF LEGAL RECEIPT ***', style: textMuted),
                ),

                const SizedBox(height: 20),

                // Print / Save as PDF
                Center(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final bytes = await buildReceiptPdf(d);
                      await Printing.layoutPdf(
                        onLayout: (format) async => bytes,
                      );
                    },
                    icon: const Icon(Icons.print),
                    label: const Text('Print Receipt'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFE500),
                      foregroundColor: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      fontSize: 13,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: style.copyWith(color: Colors.grey.shade800),
            ),
          ),
          Text(value, style: style),
        ],
      ),
    );
  }

  static Widget _companyRow(
    String label,
    String value,
    TextStyle labelStyle,
    TextStyle valueStyle,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(
          style: valueStyle.copyWith(color: Colors.black87),
          children: [
            TextSpan(text: '$label ', style: labelStyle),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  static Widget _twoColRow(
    String label,
    String value,
    TextStyle labelStyle,
    TextStyle valueStyle,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 170, child: Text(label, style: labelStyle)),
          Expanded(child: Text(value, style: valueStyle)),
        ],
      ),
    );
  }

  /// Sample data so the page shows immediately.
  ReceiptData _sampleData() => const ReceiptData(
    company: CompanyInfo(
      name: 'LIDOX ENTERPRISES',
      addressLine: 'TABORA CBD',
      mobile: '0655 900595',
      tin: '140716405',
      vrn: 'NOT REGISTERED',
      serialNo: '1072114856',
      uim: '90VFVEDEAM4P+0517827123029511072114856',
      taxOffice: 'Tax Office Tabora',
      logo: AssetImage('assets/tra-logo.png'),
    ),
    customer: CustomerInfo(
      name: 'MKURUGENZI TABORA MC',
      idType: 'N.I',
      idNo: 'N/A',
      mobile: 'N/A',
    ),
    meta: ReceiptMeta(
      receiptNo: '1157',
      zNumber: '12420711',
      receiptDate: '08-20-2025',
      receiptTime: '15:56 :58',
    ),
    items: [LineItem(description: 'PRINTING', qty: 1, amount: 300000.00)],
    totalExclTax: 300000.00,
    tax: 0.00,
    totalInclTax: 300000.00,
    verificationCode: '56BE8A245',
    qr: AssetImage('assets/frame.png'),
  );
}

/// ───────────────────────────────── SMALL TABLE CELL ─────────────────────────────────
class _Cell extends StatelessWidget {
  final String text;
  final bool bold;
  final TextAlign align;
  const _Cell(this.text, {this.bold = false, this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: 13,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }
}

/// ───────────────────────────────── HELPER FUNCTIONS ─────────────────────────────────

/// Get receipt URL for QR code generation
String _getReceiptUrl(String receiptId) {
  // Get the current base URL dynamically
  final baseUrl = Uri.base.toString();
  String cleanBaseUrl = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  // Remove any existing hash fragments to avoid duplication
  if (cleanBaseUrl.contains('#')) {
    cleanBaseUrl = cleanBaseUrl.split('#')[0];
  }

  // Flutter web uses hash routing, so include the #
  return '$cleanBaseUrl/#/receipt/$receiptId';
}

/// ───────────────────────────────── PDF BUILDER ─────────────────────────────────

Future<Uint8List> buildReceiptPdf(ReceiptData d) async {
  final pdf = pw.Document();

  String fmtTZS(num v) {
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final whole = parts[0];
    final buf = StringBuffer();
    for (int i = 0; i < whole.length; i++) {
      final fromEnd = whole.length - i;
      buf.write(whole[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
    }
    return 'TZS ${buf.toString()}.${parts[1]}';
  }

  pw.Widget dotted() => pw.Center(
    child: pw.Text(
      List.filled(120, '·').join(' '),
      style: pw.TextStyle(color: PdfColors.grey500, fontSize: 8),
    ),
  );

  // Generate QR code for receipt URL
  pw.Widget qr;
  if (d.verificationCode.isNotEmpty) {
    // Generate QR code with receipt URL
    final receiptUrl = _getReceiptUrl(d.verificationCode);
    qr = pw.BarcodeWidget(
      barcode: pw.Barcode.qrCode(),
      data: receiptUrl,
      width: 120,
      height: 120,
    );
  } else {
    // Fallback to asset image
    try {
      final qrImageBytes = await rootBundle.load('assets/frame.png');
      final qrImage = pw.MemoryImage(qrImageBytes.buffer.asUint8List());
      qr = pw.Container(
        width: 120,
        height: 120,
        child: pw.Image(qrImage, fit: pw.BoxFit.contain),
      );
    } catch (e) {
      // If asset loading fails, create a placeholder
      qr = pw.Container(
        width: 120,
        height: 120,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey),
        ),
        child: pw.Center(
          child: pw.Text('QR Code', style: pw.TextStyle(color: PdfColors.grey)),
        ),
      );
    }
  }

  pw.Widget kv(String k, String v) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 130,
          child: pw.Text(
            k,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ),
        pw.Expanded(child: pw.Text(v, style: const pw.TextStyle(fontSize: 10))),
      ],
    ),
  );

  pdf.addPage(
    pw.MultiPage(
      pageTheme: const pw.PageTheme(
        margin: pw.EdgeInsets.fromLTRB(24, 24, 24, 36),
      ),
      build: (ctx) => [
        pw.Center(
          child: pw.Text(
            '*** START OF LEGAL RECEIPT ***',
            style: pw.TextStyle(color: PdfColors.grey600, fontSize: 9),
          ),
        ),
        pw.SizedBox(height: 6),

        // Header
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // If you want a real logo, load it as pw.MemoryImage and put it here.
            pw.Container(
              width: 48,
              height: 48,
              decoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
                shape: pw.BoxShape.circle,
              ),
              alignment: pw.Alignment.center,
              child: pw.Icon(pw.IconData(0xe5ca), size: 20),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              d.company.name.toUpperCase(),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
            ),
            pw.SizedBox(height: 4),
            kv('ADDRESS:', d.company.addressLine),
            kv('MOBILE:', d.company.mobile),
            kv('TIN:', d.company.tin),
            kv('VRN:', d.company.vrn),
            kv('SERIAL NO:', d.company.serialNo),
            kv('UIM:', d.company.uim),
            kv('TAX OFFICE:', d.company.taxOffice),
          ],
        ),

        pw.SizedBox(height: 6),
        dotted(),
        pw.SizedBox(height: 4),

        // Customer
        kv('CUSTOMER NAME:', d.customer.name),
        kv('CUSTOMER ID TYPE:', d.customer.idType),
        kv('CUSTOMER ID NO:', d.customer.idNo),
        kv('CUSTOMER MOBILE:', d.customer.mobile),

        pw.SizedBox(height: 4),
        dotted(),
        pw.SizedBox(height: 4),

        // Meta
        kv('RECEIPT NO:', d.meta.receiptNo),
        kv('Z NUMBER:', d.meta.zNumber),
        kv('RECEIPT DATE:', d.meta.receiptDate),
        kv('RECEIPT TIME:', d.meta.receiptTime),

        pw.SizedBox(height: 8),
        dotted(),
        pw.SizedBox(height: 10),

        // Items
        pw.Text(
          'Purchased Items',
          style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
          columnWidths: {
            0: const pw.FlexColumnWidth(6),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(3),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _pd('Description', bold: true),
                _pd('Qty', bold: true, align: pw.Alignment.center),
                _pd('Amount', bold: true, align: pw.Alignment.centerRight),
              ],
            ),
            ...d.items.map(
              (it) => pw.TableRow(
                children: [
                  _pd(it.description),
                  _pd('${it.qty}', align: pw.Alignment.center),
                  _pd(fmtTZS(it.amount), align: pw.Alignment.centerRight),
                ],
              ),
            ),
          ],
        ),

        pw.SizedBox(height: 12),
        _totalRowPdf('TOTAL EXCL OF TAX:', fmtTZS(d.totalExclTax)),
        _totalRowPdf('TOTAL TAX:', fmtTZS(d.tax)),
        _totalRowPdf('TOTAL INCL OF TAX:', fmtTZS(d.totalInclTax), bold: true),

        pw.SizedBox(height: 10),
        dotted(),
        pw.SizedBox(height: 10),

        pw.Center(
          child: pw.Column(
            children: [
              pw.Text(
                'RECEIPT VERIFICATION CODE',
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                d.verificationCode,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),
              qr,
            ],
          ),
        ),

        pw.SizedBox(height: 10),
        pw.Center(
          child: pw.Text(
            '*** END OF LEGAL RECEIPT ***',
            style: pw.TextStyle(color: PdfColors.grey600, fontSize: 9),
          ),
        ),
      ],
    ),
  );

  return pdf.save();
}

pw.Widget _pd(
  String t, {
  bool bold = false,
  pw.Alignment align = pw.Alignment.centerLeft,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(8),
    child: pw.Align(
      alignment: align,
      child: pw.Text(
        t,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    ),
  );
}

pw.Widget _totalRowPdf(String label, String value, {bool bold = false}) {
  final st = pw.TextStyle(
    fontSize: 11,
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
  );
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 4),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(label, style: st.copyWith(color: PdfColors.grey800)),
        ),
        pw.Text(value, style: st),
      ],
    ),
  );
}
