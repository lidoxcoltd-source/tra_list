import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfTheme {
  final pw.Font regular;
  final pw.Font bold;
  final double fontScale;
  final PdfColor textColor;
  final PdfColor textColorBold;
  final double letterSpacing;

  PdfTheme({
    required this.regular,
    required this.bold,
    this.fontScale = 0.8, // was 1.1
    PdfColor? textColor,
    PdfColor? textColorBold,
    this.letterSpacing = 0.0, // was 0.1
  }) : textColor = textColor ?? PdfColor(0.50, 0.50, 0.50), // was 0.36
       textColorBold = textColorBold ?? PdfColor(0.44, 0.44, 0.44); // was 0.32

  pw.TextStyle t12([bool isBold = false]) => pw.TextStyle(
    font: isBold ? bold : regular,
    fontSize: 12 * fontScale,
    color: isBold ? textColorBold : textColor,
    letterSpacing: letterSpacing,
  );

  pw.TextStyle t14([bool isBold = false]) => pw.TextStyle(
    font: isBold ? bold : regular,
    fontSize: 14 * fontScale,
    color: isBold ? textColorBold : textColor,
    letterSpacing: letterSpacing,
  );

  pw.TextStyle t16([bool isBold = false]) => pw.TextStyle(
    font: isBold ? bold : regular,
    fontSize: 16 * fontScale,
    color: isBold ? textColorBold : textColor,
    letterSpacing: letterSpacing,
  );

  String money(num? v) {
    final amount = (v ?? 0).toDouble();
    final regex = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final fixed = amount.toStringAsFixed(2);
    return fixed.replaceAllMapped(regex, (m) => '${m[1]},');
  }
}
