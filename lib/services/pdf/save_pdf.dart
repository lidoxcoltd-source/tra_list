import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:open_file_plus/open_file_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

Future<String> saveAndLaunchFile(List<int> bytes, String fileName) async {
  if (kIsWeb) {
    await Printing.sharePdf(
      bytes: Uint8List.fromList(bytes),
      filename: fileName,
    );
    return fileName;
  } else {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes);
    await OpenFile.open(file.path);
    return file.path;
  }
}
