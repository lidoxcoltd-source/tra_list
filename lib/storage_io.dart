// Desktop implementation using dart:io file system
import 'dart:io';

class PlatformStorageImpl {
  static String? _receiptsFilePath;
  static const String _receiptsFileName = 'tra_receipts.json';

  // Get the file path for desktop storage
  static Future<String> _getReceiptsFilePath() async {
    if (_receiptsFilePath != null) return _receiptsFilePath!;

    try {
      final currentDir = Directory.current;
      final appDir = Directory('${currentDir.path}/TRA_Receipts');

      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }

      _receiptsFilePath = '${appDir.path}/$_receiptsFileName';
      return _receiptsFilePath!;
    } catch (e) {
      _receiptsFilePath = _receiptsFileName;
      return _receiptsFilePath!;
    }
  }
  
  static Future<void> saveData(String key, String data) async {
    final filePath = await _getReceiptsFilePath();
    final file = File(filePath);
    await file.writeAsString(data);
  }
  
  static Future<String?> loadData(String key) async {
    final filePath = await _getReceiptsFilePath();
    final file = File(filePath);
    
    if (await file.exists()) {
      return await file.readAsString();
    }
    return null;
  }
  
  static Future<void> removeData(String key) async {
    final filePath = await _getReceiptsFilePath();
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }
  
  static Future<Map<String, dynamic>> getStorageInfo() async {
    final filePath = await _getReceiptsFilePath();
    final file = File(filePath);
    final exists = await file.exists();
    final size = exists ? await file.length() : 0;

    return {
      'platform': 'desktop',
      'storage': 'file',
      'path': filePath,
      'exists': exists,
      'size': size,
    };
  }
}