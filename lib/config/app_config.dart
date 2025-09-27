class AppConfig {
  static const String appName = 'TRA Receipt Verification Portal';
  static const String version = '1.0.0';

  // Production URL - update this with your actual domain
  static const String baseUrl = 'https://your-domain.com';

  // API endpoints
  static const String apiBaseUrl = '$baseUrl/api';

  // QR Code configuration
  static String getReceiptUrl(String receiptId) {
    return '$baseUrl/#/receipt/$receiptId';
  }
}
