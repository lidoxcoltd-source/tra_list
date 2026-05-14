class LocalStorageService {
  static Future<void> saveReceipt(Map<String, dynamic> receiptData) async {}

  static List<Map<String, dynamic>> getReceipts() => [];

  static Map<String, dynamic>? getReceiptByCode(String verificationCode) =>
      null;

  static Future<void> deleteReceipt(String verificationCode) async {}

  static Future<void> clearAllReceipts() async {}
}
