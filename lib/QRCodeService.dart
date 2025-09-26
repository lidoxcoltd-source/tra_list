import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:get/get.dart';

class QRCodeService {
  /// Generate QR code widget for a receipt URL
  static Widget generateReceiptQR({
    required String receiptId,
    double size = 200.0,
    Color foregroundColor = Colors.black,
    Color backgroundColor = Colors.white,
  }) {
    final receiptUrl = _getReceiptUrl(receiptId);

    return QrImageView(
      data: receiptUrl,
      version: QrVersions.auto,
      size: size,
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      gapless: false,
      // embeddedImage: const AssetImage('assets/tra-logo.png'),
      embeddedImageStyle: const QrEmbeddedImageStyle(size: Size(40, 40)),
    );
  }

  /// Generate QR code for any URL
  static Widget generateQR({
    required String data,
    double size = 200.0,
    Color foregroundColor = Colors.black,
    Color backgroundColor = Colors.white,
    AssetImage? embeddedImage,
  }) {
    return QrImageView(
      data: data,
      version: QrVersions.auto,
      size: size,
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      gapless: false,
      embeddedImage: embeddedImage,
      embeddedImageStyle: embeddedImage != null
          ? const QrEmbeddedImageStyle(size: Size(40, 40))
          : null,
    );
  }

  /// Get full receipt URL with proper Flutter web hash routing
  static String _getReceiptUrl(String receiptId) {
    final baseUrl = Uri.base.toString();
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    // Flutter web uses hash routing, so we need to include the #
    return '$cleanBaseUrl/#/receipt/$receiptId';
  }

  /// Get current receipt URL from route parameters
  static String getCurrentReceiptUrl() {
    final receiptId = Get.parameters['id'];
    if (receiptId != null && receiptId.isNotEmpty) {
      return _getReceiptUrl(receiptId);
    }
    return '';
  }

  /// Show QR code in a dialog
  static void showQRDialog({
    required BuildContext context,
    required String receiptId,
    String? title,
  }) {
    final receiptUrl = _getReceiptUrl(receiptId);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title ?? 'Receipt QR Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            generateReceiptQR(receiptId: receiptId, size: 250),
            const SizedBox(height: 16),
            Text(
              'Scan to view receipt online',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            SelectableText(
              receiptUrl,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              _copyToClipboard(receiptUrl);
              Navigator.of(context).pop();
            },
            child: const Text('Copy URL'),
          ),
        ],
      ),
    );
  }

  /// Copy URL to clipboard (placeholder - in real app use clipboard package)
  static void _copyToClipboard(String text) {
    print('Copied to clipboard: $text');
    Get.snackbar(
      'URL Copied',
      'Receipt URL copied to clipboard',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.green,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
    );
  }

  /// Generate QR for PDF embedding
  static Future<QrImageView> generateForPDF({
    required String receiptId,
    double size = 100.0,
  }) async {
    final receiptUrl = _getReceiptUrl(receiptId);

    return QrImageView(
      data: receiptUrl,
      version: QrVersions.auto,
      size: size,
      foregroundColor: Colors.black,
      backgroundColor: Colors.white,
      errorCorrectionLevel:
          QrErrorCorrectLevel.H, // Higher error correction for PDF
      gapless: true,
    );
  }

  /// Validate if string is a valid receipt URL
  static bool isValidReceiptUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.pathSegments.length >= 2 &&
          uri.pathSegments[0] == 'receipt' &&
          uri.pathSegments[1].isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Extract receipt ID from URL
  static String? extractReceiptIdFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'receipt') {
        return uri.pathSegments[1];
      }
    } catch (e) {
      print('Error extracting receipt ID: $e');
    }
    return null;
  }
}
