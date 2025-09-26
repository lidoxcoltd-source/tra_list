import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:get/get.dart';

/// Windows-optimized QR Code Service
/// Optimized for desktop performance and Windows-specific features
class WindowsQRCodeService {
  /// Generate QR code widget optimized for Windows desktop
  static Widget generateReceiptQR({
    required String receiptId,
    double size = 200.0,
    Color foregroundColor = Colors.black,
    Color backgroundColor = Colors.white,
  }) {
    final receiptUrl = _getReceiptUrl(receiptId);

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: QrImageView(
          data: receiptUrl,
          version: QrVersions.auto,
          size: size,
          foregroundColor: foregroundColor,
          backgroundColor: backgroundColor,
          errorCorrectionLevel: QrErrorCorrectLevel.M,
          gapless: false,
          embeddedImageStyle: const QrEmbeddedImageStyle(size: Size(40, 40)),
        ),
      ),
    );
  }

  /// Generate QR code for Windows desktop with enhanced features
  static Widget generateDesktopQR({
    required String data,
    double size = 200.0,
    Color foregroundColor = Colors.black,
    Color backgroundColor = Colors.white,
    bool showUrl = true,
  }) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: data,
              version: QrVersions.auto,
              size: size,
              foregroundColor: foregroundColor,
              backgroundColor: backgroundColor,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
              gapless: false,
            ),
            if (showUrl) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        data,
                        style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _copyToClipboard(data),
                      icon: const Icon(Icons.copy, size: 16),
                      tooltip: 'Copy URL',
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Get receipt URL for Windows desktop app
  static String _getReceiptUrl(String receiptId) {
    // For Windows desktop, we can use the web version URL
    return 'https://tra-verify-system.web.app/#/receipt/$receiptId';
  }

  /// Show QR code in Windows-optimized dialog
  static void showWindowsQRDialog({
    required BuildContext context,
    required String receiptId,
    String? title,
  }) {
    final receiptUrl = _getReceiptUrl(receiptId);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.qr_code, color: Colors.blue.shade600),
                  const SizedBox(width: 12),
                  Text(
                    title ?? 'Receipt QR Code',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              generateDesktopQR(data: receiptUrl, size: 250),
              const SizedBox(height: 20),
              Text(
                'Scan with mobile device to view receipt online',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      label: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _copyToClipboard(receiptUrl);
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy URL'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Windows-optimized clipboard functionality
  static void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    Get.snackbar(
      'URL Copied',
      'Receipt URL copied to clipboard',
      snackPosition: SnackPosition.TOP,
      backgroundColor: Colors.green.shade600,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
      margin: const EdgeInsets.all(16),
      borderRadius: 8,
      icon: const Icon(Icons.check_circle, color: Colors.white),
    );
  }

  /// Open URL in default Windows browser
  static Future<void> openInBrowser(String receiptId) async {
    final url = _getReceiptUrl(receiptId);
    // This would require url_launcher package for Windows
    // For now, just copy to clipboard
    _copyToClipboard(url);
    Get.snackbar(
      'URL Ready',
      'Receipt URL copied. Paste in browser to open.',
      snackPosition: SnackPosition.TOP,
      backgroundColor: Colors.blue.shade600,
      colorText: Colors.white,
      duration: const Duration(seconds: 4),
      margin: const EdgeInsets.all(16),
      borderRadius: 8,
    );
  }

  /// Generate QR for printing on Windows
  static Widget generatePrintableQR({
    required String receiptId,
    double size = 150.0,
    bool includeText = true,
  }) {
    final receiptUrl = _getReceiptUrl(receiptId);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(
            data: receiptUrl,
            version: QrVersions.auto,
            size: size,
            foregroundColor: Colors.black,
            backgroundColor: Colors.white,
            errorCorrectionLevel: QrErrorCorrectLevel.H,
            gapless: true,
          ),
          if (includeText) ...[
            const SizedBox(height: 12),
            Text(
              'Receipt: $receiptId',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Scan to verify online',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }
}
