// Web implementation using dart:html localStorage
import 'dart:html' as html;

class PlatformStorageImpl {
  static Future<void> saveData(String key, String data) async {
    html.window.localStorage[key] = data;
  }
  
  static Future<String?> loadData(String key) async {
    return html.window.localStorage[key];
  }
  
  static Future<void> removeData(String key) async {
    html.window.localStorage.remove(key);
  }
  
  static Future<Map<String, dynamic>> getStorageInfo() async {
    return {
      'platform': 'web',
      'storage': 'localStorage',
      'path': 'browser localStorage',
    };
  }
}