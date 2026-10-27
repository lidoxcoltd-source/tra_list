import 'dart:html' as html;
import 'dart:typed_data';

String? createVideoBlobUrl(Uint8List bytes, String mime) {
  final blob = html.Blob([bytes], mime);
  return html.Url.createObjectUrlFromBlob(blob);
}
