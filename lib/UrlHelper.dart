import 'package:flutter/material.dart';
import 'package:get/get.dart';

class UrlHelper {
  static String getReceiptUrl(String receiptId) {
    final baseUrl = Uri.base.toString();

    // Remove any trailing slash from base URL
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    return '$cleanBaseUrl/receipt/$receiptId';
  }

  static void shareReceiptUrl(String receiptId) {
    final url = getReceiptUrl(receiptId);
    Get.snackbar(
      'Share Receipt',
      'Receipt URL: $url',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 5),
    );
  }

  static void copyReceiptUrl(String receiptId) {
    final url = getReceiptUrl(receiptId);
    // In a real app, you'd use clipboard package
    print('Receipt URL copied: $url');
    Get.snackbar(
      'URL Copied',
      'Receipt URL copied to clipboard',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: const Color(0xFF4CAF50),
      colorText: const Color(0xFFFFFFFF),
      duration: const Duration(seconds: 3),
    );
  }

  static String getCurrentFullUrl() {
    final baseUrl = Uri.base.toString();
    final currentRoute = Get.currentRoute;

    if (currentRoute == '/') {
      return baseUrl;
    }

    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$cleanBaseUrl$currentRoute';
  }
}
