// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> downloadBytes(
  Uint8List bytes,
  String fileName,
  String mime,
) async {
  final blob = html.Blob([bytes], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = fileName
    ..click();
  html.Url.revokeObjectUrl(url);
}

Future<String> savePdf(Uint8List bytes, String fileName) async {
  final safeName = fileName.replaceAll(RegExp(r'[^\w\-.]+'), '_');
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)..download = safeName;
  anchor.click();
  html.Url.revokeObjectUrl(url);
  return safeName;
}
