import 'dart:convert';

// Platform-specific imports with conditional compilation
import 'storage_stub.dart'
    if (dart.library.html) 'storage_web.dart'
    if (dart.library.io) 'storage_io.dart';

/// Platform-aware Local Storage Service
/// Uses file system on desktop, localStorage on web
class PlatformLocalStorageService {
  static const String _receiptsKey = 'tra_receipts';

  // Save receipt - platform aware
  static Future<void> saveReceipt(Map<String, dynamic> receiptData) async {
    try {
      List<Map<String, dynamic>> receipts = await getReceipts();
      receipts.add(receiptData);

      final jsonString = jsonEncode(receipts);
      await PlatformStorageImpl.saveData(_receiptsKey, jsonString);
    } catch (e) {
      print('Error saving receipt: $e');
      throw Exception('Failed to save receipt: $e');
    }
  }

  // Get all receipts - platform aware
  static Future<List<Map<String, dynamic>>> getReceipts() async {
    try {
      final jsonString = await PlatformStorageImpl.loadData(_receiptsKey);

      if (jsonString == null || jsonString.isEmpty) {
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
  static Future<Map<String, dynamic>?> getReceiptByCode(
    String verificationCode,
  ) async {
    try {
      final receipts = await getReceipts();
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
      List<Map<String, dynamic>> receipts = await getReceipts();
      receipts.removeWhere(
        (receipt) => receipt['verificationCode'] == verificationCode,
      );

      final jsonString = jsonEncode(receipts);
      await PlatformStorageImpl.saveData(_receiptsKey, jsonString);
    } catch (e) {
      throw Exception('Failed to delete receipt: $e');
    }
  }

  // Clear all receipts
  static Future<void> clearAllReceipts() async {
    try {
      await PlatformStorageImpl.removeData(_receiptsKey);
    } catch (e) {
      print('Error clearing receipts: $e');
    }
  }

  // Get storage info (platform-aware)
  static Future<Map<String, dynamic>> getStorageInfo() async {
    return await PlatformStorageImpl.getStorageInfo();
  }
}

// Backward compatibility alias
class LocalStorageService extends PlatformLocalStorageService {
  // Synchronous methods for backward compatibility where needed
  static List<Map<String, dynamic>> getReceipts() {
    // This is a temporary bridge for existing sync code
    // In practice, this should be migrated to async
    throw UnsupportedError(
        'Synchronous getReceipts is not supported in platform-aware version. Use PlatformLocalStorageService.getReceipts() instead.');
  }

  static Map<String, dynamic>? getReceiptByCode(String verificationCode) {
    // This is a temporary bridge for existing sync code
    throw UnsupportedError(
        'Synchronous getReceiptByCode is not supported in platform-aware version. Use PlatformLocalStorageService.getReceiptByCode() instead.');
  }
}