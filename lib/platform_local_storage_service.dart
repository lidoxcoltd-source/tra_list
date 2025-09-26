import 'dart:convert';
import 'package:flutter/foundation.dart';

// Platform-specific storage services
import 'simple_local_storage_service.dart'
    if (kIsWeb) 'windows_local_storage_service.dart';

/// Platform-aware Local Storage Service
/// Uses file system on desktop, localStorage on web
class PlatformLocalStorageService {
  static const String _receiptsKey = 'tra_receipts';

  // Simple platform check without complex imports
  static bool get _isWebPlatform => kIsWeb;

  // Web storage operations (simplified)
  static Map<String, String> _webStorage = {};

  // Save receipt - platform aware
  static Future<void> saveReceipt(Map<String, dynamic> receiptData) async {
    try {
      if (_isWebPlatform) {
        // Web storage - get existing, add new, save back
        List<Map<String, dynamic>> receipts = await getReceipts();
        receipts.add(receiptData);
        final jsonString = jsonEncode(receipts);
        _webStorage[_receiptsKey] = jsonString;
        print('Receipt saved to web storage');
      } else {
        // Desktop - delegate to existing service
        await SimpleLocalStorageService.saveReceipt(receiptData);
      }
    } catch (e) {
      print('Error saving receipt: $e');
      throw Exception('Failed to save receipt: $e');
    }
  }

  // Get all receipts - platform aware
  static Future<List<Map<String, dynamic>>> getReceipts() async {
    try {
      if (_isWebPlatform) {
        // Web storage - use simple approach
        final jsonString = _webStorage[_receiptsKey];
        if (jsonString == null || jsonString.isEmpty) {
          return [];
        }
        final List<dynamic> jsonList = jsonDecode(jsonString);
        return jsonList.map((item) => Map<String, dynamic>.from(item)).toList();
      } else {
        // Desktop - wrap sync call in Future
        return SimpleLocalStorageService.getReceipts();
      }
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
      if (_isWebPlatform) {
        final receipts = await getReceipts();
        for (final receipt in receipts) {
          if (receipt['verificationCode'] == verificationCode) {
            return receipt;
          }
        }
        return null;
      } else {
        // Desktop - wrap sync call
        return SimpleLocalStorageService.getReceiptByCode(verificationCode);
      }
    } catch (e) {
      print('Error getting receipt by code: $e');
      return null;
    }
  }

  // Delete receipt by verification code
  static Future<void> deleteReceipt(String verificationCode) async {
    try {
      if (_isWebPlatform) {
        // Web storage - handle deletion
        List<Map<String, dynamic>> receipts = await getReceipts();
        receipts.removeWhere(
          (receipt) => receipt['verificationCode'] == verificationCode,
        );
        final jsonString = jsonEncode(receipts);
        _webStorage[_receiptsKey] = jsonString;
      } else {
        // Desktop - delegate to existing service
        await SimpleLocalStorageService.deleteReceipt(verificationCode);
      }
    } catch (e) {
      throw Exception('Failed to delete receipt: $e');
    }
  }

  // Clear all receipts
  static Future<void> clearAllReceipts() async {
    try {
      if (_isWebPlatform) {
        // Web storage - clear our storage
        _webStorage.remove(_receiptsKey);
      } else {
        // Desktop - delegate to existing service
        await SimpleLocalStorageService.clearAllReceipts();
      }
    } catch (e) {
      print('Error clearing receipts: $e');
    }
  }

  // Get storage info
  static Future<Map<String, dynamic>> getStorageInfo() async {
    if (_isWebPlatform) {
      return {
        'platform': 'web',
        'storage': 'in-memory storage',
        'path': 'memory storage (simplified)',
        'exists': _webStorage.containsKey(_receiptsKey),
        'size': _webStorage[_receiptsKey]?.length ?? 0,
      };
    } else {
      return {
        'platform': 'desktop',
        'storage': 'file',
        'path': SimpleLocalStorageService.getStoragePath(),
        'exists': SimpleLocalStorageService.storageExists(),
        'size': SimpleLocalStorageService.getStorageSize(),
      };
    }
  }
}

// Backward compatibility alias
class LocalStorageService extends PlatformLocalStorageService {}
