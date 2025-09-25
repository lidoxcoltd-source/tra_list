import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/ReceiptViewPage.dart';

class VerifyRoutes {
  static const String viewReceipt = '/receipt/:id';
  static const String home = '/';

  // Helper method to generate receipt URL
  static String getReceiptRoute(String receiptId) => '/receipt/$receiptId';

  static List<GetPage> routes = [
    // Redirect home to a default receipt or show instructions
    GetPage(
      name: home,
      page: () => const VerificationHomePage(),
      transition: Transition.fadeIn,
    ),
    // Main verification route
    GetPage(
      name: viewReceipt,
      page: () => ReceiptViewPage(),
      transition: Transition.fadeIn,
    ),
  ];
}

// Simple home page for verification-only app
class VerificationHomePage extends StatelessWidget {
  const VerificationHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('TRA Receipt Verification'),
        backgroundColor: const Color(0xFFFFE500),
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // TRA Logo
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/logo.png',
                  height: 100,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.receipt_long,
                      size: 100,
                      color: Colors.blue,
                    );
                  },
                ),
              ),

              const SizedBox(height: 32),

              const Text(
                'Receipt Verification System',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              const Text(
                'To verify a receipt, scan the QR code or enter the receipt URL',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // URL format example
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Receipt URL Format:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${Uri.base.origin}/#/receipt/VERIFICATION_CODE',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.blue,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Test with sample receipt
              ElevatedButton.icon(
                onPressed: () {
                  Get.toNamed('/receipt/SAMPLE123');
                },
                icon: const Icon(Icons.preview),
                label: const Text('View Sample Receipt'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
