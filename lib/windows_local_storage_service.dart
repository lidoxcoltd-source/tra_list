import 'dart:convert';
import 'dart:io';

/// Windows-compatible Local Storage Service
/// Uses file system instead of web localStorage
class WindowsLocalStorageService {
  static const String _receiptsFileName = 'tra_receipts.json';
  static String? _receiptsFilePath;

  // Get the file path for storing receipts
  static Future<String> _getReceiptsFilePath() async {
    if (_receiptsFilePath != null) return _receiptsFilePath!;

    try {
      // Use current directory for simplicity
      final currentDir = Directory.current;
      final appDir = Directory('${currentDir.path}/TRA_Receipts');

      // Create directory if it doesn't exist
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }

      _receiptsFilePath = '${appDir.path}/$_receiptsFileName';
      return _receiptsFilePath!;
    } catch (e) {
      // Fallback to current directory
      _receiptsFilePath = _receiptsFileName;
      return _receiptsFilePath!;
    }
  }

  // Save receipt to local file
  static Future<void> saveReceipt(Map<String, dynamic> receiptData) async {
    try {
      // Get existing receipts
      List<Map<String, dynamic>> receipts = await getReceipts();

      // Add new receipt
      receipts.add(receiptData);

      // Save back to file
      final filePath = await _getReceiptsFilePath();
      final file = File(filePath);
      final jsonString = jsonEncode(receipts);
      await file.writeAsString(jsonString);

      print('Receipt saved to: $filePath');
    } catch (e) {
      print('Error saving receipt: $e');
      throw Exception('Failed to save receipt: $e');
    }
  }

  // Get all receipts from local file
  static Future<List<Map<String, dynamic>>> getReceipts() async {
    try {
      final filePath = await _getReceiptsFilePath();
      final file = File(filePath);

      if (!await file.exists()) {
        return [];
      }

      final jsonString = await file.readAsString();
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

      final filePath = await _getReceiptsFilePath();
      final file = File(filePath);
      final jsonString = jsonEncode(receipts);
      await file.writeAsString(jsonString);
    } catch (e) {
      throw Exception('Failed to delete receipt: $e');
    }
  }

  // Clear all receipts
  static Future<void> clearAllReceipts() async {
    try {
      final filePath = await _getReceiptsFilePath();
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('Error clearing receipts: $e');
    }
  }

  // Get storage file path (for debugging)
  static Future<String> getStoragePath() async {
    return await _getReceiptsFilePath();
  }

  // Check if storage file exists
  static Future<bool> storageExists() async {
    try {
      final filePath = await _getReceiptsFilePath();
      final file = File(filePath);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  // Get storage file size
  static Future<int> getStorageSize() async {
    try {
      final filePath = await _getReceiptsFilePath();
      final file = File(filePath);
      if (await file.exists()) {
        return await file.length();
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }
}
