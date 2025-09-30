import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

class FontPair {
  final pw.Font regular;
  final pw.Font bold;
  const FontPair(this.regular, this.bold);
}

class PdfAssets {
  static Future<pw.MemoryImage?> loadLogo() async {
    try {
      final data = await rootBundle.load('assets/tra-logo.png');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  static Future<FontPair> loadFonts() async {
    try {
      final regularBytes = await rootBundle.load(
        'assets/fonts/Hypermarket-Cond.ttf',
      );
      final boldBytes = await rootBundle.load(
        'assets/fonts/Hypermarket-CondBold.ttf',
      );
      return FontPair(pw.Font.ttf(regularBytes), pw.Font.ttf(boldBytes));
    } catch (_) {
      // Fallback to built-in fonts
      return FontPair(pw.Font.helvetica(), pw.Font.helveticaBold());
    }
  }
}
