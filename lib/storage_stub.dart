// Stub file for platform-specific storage implementations
// This file should never be imported directly

class PlatformStorageImpl {
  static Future<void> saveData(String key, String data) async {
    throw UnsupportedError('Platform not supported');
  }
  
  static Future<String?> loadData(String key) async {
    throw UnsupportedError('Platform not supported');
  }
  
  static Future<void> removeData(String key) async {
    throw UnsupportedError('Platform not supported');
  }
  
  static Future<Map<String, dynamic>> getStorageInfo() async {
    throw UnsupportedError('Platform not supported');
  }
}