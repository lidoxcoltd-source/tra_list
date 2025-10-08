import 'dart:typed_data';
import 'package:image/image.dart' as img;

class CompressedImage {
  final Uint8List bytes;
  final String ext; // 'png' or 'jpg'
  final String contentType; // 'image/png' or 'image/jpeg'
  CompressedImage(this.bytes, this.ext, this.contentType);
}

Future<CompressedImage> compressLogoBytes(
  Uint8List original, {
  int maxSide = 640,
  int jpegQuality = 92,
}) async {
  final decoded = img.decodeImage(original);
  if (decoded == null) throw ArgumentError('Unable to decode image');

  final w = decoded.width, h = decoded.height;
  final scale = (w > h ? maxSide / w : maxSide / h);
  final resized = (scale < 1.0)
      ? img.copyResize(
          decoded,
          width: (w * scale).round(),
          height: (h * scale).round(),
          interpolation: img.Interpolation.cubic,
        )
      : decoded;

  final hasAlpha = resized.hasAlpha;
  if (hasAlpha) {
    final out = Uint8List.fromList(img.encodePng(resized, level: 4));
    return CompressedImage(out, 'png', 'image/png');
  } else {
    final out = Uint8List.fromList(
      img.encodeJpg(resized, quality: jpegQuality),
    );
    return CompressedImage(out, 'jpg', 'image/jpeg');
  }
}
