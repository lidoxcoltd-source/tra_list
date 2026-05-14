import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
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
    await OpenFilex.open(file.path);
    return file.path;
  }
}
