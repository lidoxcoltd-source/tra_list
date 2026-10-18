import 'dart:typed_data';

Future<void> downloadBytes(Uint8List bytes, String fileName, String mime) {
  throw UnsupportedError('Download not supported on this platform');
}

Future<String> savePdf(Uint8List bytes, String fileName) {
  throw UnsupportedError('PDF saving not supported on this platform');
}
