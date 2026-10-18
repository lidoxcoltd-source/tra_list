import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as path_provider;

Future<void> downloadBytes(
  Uint8List bytes,
  String fileName,
  String mime,
) async {
  await savePdf(bytes, fileName);
}

Future<String> savePdf(Uint8List bytes, String fileName) async {
  Directory base;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    base =
        (await path_provider.getDownloadsDirectory()) ??
        await path_provider.getApplicationDocumentsDirectory();
  } else {
    base = await path_provider.getApplicationDocumentsDirectory();
  }

  final dir = Directory(p.join(base.path, 'Invoices'));
  if (!await dir.exists()) await dir.create(recursive: true);

  final safeName = fileName.replaceAll(RegExp(r'[^\w\-.]+'), '_');
  final file = File(p.join(dir.path, safeName));
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
