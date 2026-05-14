import 'dart:convert';
import 'dart:html' as html;

class LocalStorageService {
  static const String _receiptsKey = 'tra_receipts';

  static Future<void> saveReceipt(Map<String, dynamic> receiptData) async {
    try {
      List<Map<String, dynamic>> receipts = getReceipts();
      receipts.add(receiptData);
      final jsonString = jsonEncode(receipts);
      html.window.localStorage[_receiptsKey] = jsonString;
    } catch (e) {
      throw Exception('Failed to save receipt: $e');
    }
  }

  static List<Map<String, dynamic>> getReceipts() {
    try {
      final jsonString = html.window.localStorage[_receiptsKey];
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (e) {
      return [];
    }
  }

  static Map<String, dynamic>? getReceiptByCode(String verificationCode) {
    try {
      final receipts = getReceipts();
      return receipts.firstWhere(
        (receipt) => receipt['verificationCode'] == verificationCode,
        orElse: () => {},
      );
    } catch (e) {
      return null;
    }
  }

  static Future<void> deleteReceipt(String verificationCode) async {
    try {
      List<Map<String, dynamic>> receipts = getReceipts();
      receipts.removeWhere(
        (receipt) => receipt['verificationCode'] == verificationCode,
      );
      final jsonString = jsonEncode(receipts);
      html.window.localStorage[_receiptsKey] = jsonString;
    } catch (e) {
      throw Exception('Failed to delete receipt: $e');
    }
  }

  static Future<void> clearAllReceipts() async {
    html.window.localStorage.remove(_receiptsKey);
  }
}
