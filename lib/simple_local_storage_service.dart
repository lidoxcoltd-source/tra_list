import 'dart:convert';
import 'dart:io';

/// Simple Windows Local Storage Service
/// Uses JSON file in application directory
class SimpleLocalStorageService {
  static const String _receiptsFileName = 'tra_receipts.json';

  // Get the receipts file
  static File _getReceiptsFile() {
    return File(_receiptsFileName);
  }

  // Save receipt to local storage
  static Future<void> saveReceipt(Map<String, dynamic> receiptData) async {
    try {
      // Get existing receipts
      List<Map<String, dynamic>> receipts = getReceipts();

      // Add new receipt
      receipts.add(receiptData);

      // Save back to file
      final file = _getReceiptsFile();
      final jsonString = jsonEncode(receipts);
      await file.writeAsString(jsonString);

      print('Receipt saved to: ${file.path}');
    } catch (e) {
      print('Error saving receipt: $e');
      throw Exception('Failed to save receipt: $e');
    }
  }

  // Get all receipts from local storage (synchronous for compatibility)
  static List<Map<String, dynamic>> getReceipts() {
    try {
      final file = _getReceiptsFile();

      if (!file.existsSync()) {
        return [];
      }

      final jsonString = file.readAsStringSync();
      if (jsonString.isEmpty) {
        return [];
      }

      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (e) {
      print('Error reading receipts: $e');
      return [];
    }
  }

  // Get receipt by verification code
  static Map<String, dynamic>? getReceiptByCode(String verificationCode) {
    try {
      final receipts = getReceipts();
      for (final receipt in receipts) {
        if (receipt['verificationCode'] == verificationCode) {
          return receipt;
        }
      }
      return null;
    } catch (e) {
      print('Error getting receipt by code: $e');
      return null;
    }
  }

  // Delete receipt by verification code
  static Future<void> deleteReceipt(String verificationCode) async {
    try {
      List<Map<String, dynamic>> receipts = getReceipts();
      receipts.removeWhere(
        (receipt) => receipt['verificationCode'] == verificationCode,
      );

      final file = _getReceiptsFile();
      final jsonString = jsonEncode(receipts);
      await file.writeAsString(jsonString);
    } catch (e) {
      throw Exception('Failed to delete receipt: $e');
    }
  }

  // Clear all receipts
  static Future<void> clearAllReceipts() async {
    try {
      final file = _getReceiptsFile();
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (e) {
      print('Error clearing receipts: $e');
    }
  }

  // Get storage file path
  static String getStoragePath() {
    return _getReceiptsFile().absolute.path;
  }

  // Check if storage file exists
  static bool storageExists() {
    return _getReceiptsFile().existsSync();
  }

  // Get storage file size
  static int getStorageSize() {
    try {
      final file = _getReceiptsFile();
      if (file.existsSync()) {
        return file.lengthSync();
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }
}

// Create an alias for existing code
class LocalStorageService extends SimpleLocalStorageService {}
