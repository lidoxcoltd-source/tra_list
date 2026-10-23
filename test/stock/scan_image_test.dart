import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tra_list/stock/stock_media.dart';
import 'package:zxing_lib/zxing.dart';

List<int> render(String text, BarcodeFormat format, int w, int h) {
  final m = MultiFormatWriter().encode(text, format, w, h);
  const quiet = 20;
  final image = img.Image(width: m.width + quiet * 2, height: m.height + quiet * 2);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  for (var y = 0; y < m.height; y++) {
    for (var x = 0; x < m.width; x++) {
      if (m.get(x, y)) {
        image.setPixelRgb(x + quiet, y + quiet, 0, 0, 0);
      }
    }
  }
  return img.encodePng(image);
}

void main() {
  test('reads a QR code from a picture', () async {
    final png = render('MJASI-12345', BarcodeFormat.qrCode, 300, 300);
    expect(await decodeCodeFromImage(Uint8List.fromList(png)), 'MJASI-12345');
  });

  test('reads an EAN-13 product barcode from a picture', () async {
    final png = render('5901234123457', BarcodeFormat.ean13, 400, 150);
    expect(await decodeCodeFromImage(Uint8List.fromList(png)), '5901234123457');
  });

  test('returns null when the picture has no code', () async {
    final blank = img.Image(width: 200, height: 200);
    img.fill(blank, color: img.ColorRgb8(255, 255, 255));
    expect(await decodeCodeFromImage(Uint8List.fromList(img.encodePng(blank))), isNull);
  });
}
