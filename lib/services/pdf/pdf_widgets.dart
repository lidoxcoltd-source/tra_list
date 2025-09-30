import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

pw.Widget dashedLine({
  double dashWidth = 8,
  double dashGap = 4,
  double thickness = 1.2,
  PdfColor color = PdfColors.grey,
}) {
  return pw.LayoutBuilder(
    builder: (context, constraints) {
      final total = constraints?.maxWidth ?? 0;
      final count = (total / (dashWidth + dashGap)).floor().clamp(1, 1000);
      return pw.Row(
        mainAxisSize: pw.MainAxisSize.max,
        children: List.generate(
          count * 2 - 1,
          (i) => i.isEven
              ? pw.Container(width: dashWidth, height: thickness, color: color)
              : pw.SizedBox(width: dashGap),
        ),
      );
    },
  );
}

pw.Widget dotLeader({
  double fontSize = 12,
  double letterSpacing = 0.2,
  PdfColor color = PdfColors.grey,
}) {
  return pw.LayoutBuilder(
    builder: (context, constraints) {
      final maxW = constraints?.maxWidth ?? 0;
      final approxDotW = fontSize * 0.5 + letterSpacing;
      final count = (maxW / approxDotW).floor().clamp(1, 2000);
      final dots = List.filled(count, '.').join();
      return pw.Text(
        dots,
        maxLines: 1,
        overflow: pw.TextOverflow.clip,
        style: pw.TextStyle(
          fontSize: fontSize,
          color: color,
          letterSpacing: letterSpacing,
        ),
      );
    },
  );
}

pw.Widget totalLine(String label, String value, pw.TextStyle style) {
  return pw.Row(
    children: [
      pw.Text(label, style: style),
      pw.Expanded(
        child: pw.Text(
          '........................................................',
          style: style,
          maxLines: 1,
          overflow: pw.TextOverflow.clip,
        ),
      ),
      pw.Text(value, style: style),
    ],
  );
}
