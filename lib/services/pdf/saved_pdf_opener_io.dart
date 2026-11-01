import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

Future<void> openSavedPdfLocation(String filePath) async {
  final path = p.normalize(filePath);
  final target = Platform.isWindows || Platform.isLinux || Platform.isMacOS
      ? p.dirname(path)
      : path;
  final result = await OpenFilex.open(
    target,
    type: target == path ? 'application/pdf' : null,
  );
  if (result.type != ResultType.done) {
    throw StateError('Could not open "$target": ${result.message}');
  }
}
