import 'dart:typed_data';
import 'package:tra_list/services/pdf/pdf_saver.dart';
import 'package:uuid/uuid.dart';

bool invoiceHasStockLinks(Map<String, dynamic> data) {
  final lines = data['stockLines'];
  final items = data['items'];
  return (lines is List && lines.isNotEmpty) ||
      (items is List &&
          items.whereType<Map>().any((item) => item['productId'] != null));
}

Map<String, dynamic> savedInvoicePdfData(Map<String, dynamic> invoice) {
  final info = Map<String, dynamic>.from(invoice['invoice'] as Map? ?? {});
  final number = info['number']?.toString().trim() ?? '';
  final name = info['name']?.toString().trim() ?? '';
  return {
    ...invoice,
    'invoice': {...info, 'number': name.isEmpty ? number : '$number - $name'},
  };
}

Future<String> saveInvoicePdfToDevice(Uint8List bytes, String invoiceId) async {
  final safeId = invoiceId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final name = 'invoice_${safeId}_${const Uuid().v4()}.pdf';
  return savePdf(bytes, name);
}
