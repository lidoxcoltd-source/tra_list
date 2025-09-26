import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tra_list/ReceiptPage.dart';
import 'simple_local_storage_service.dart';
import 'package:tra_list/QRCodeService.dart';

class ReceiptViewController extends GetxController {
  final isLoading = true.obs;
  final errorMessage = ''.obs;
  final receiptData = Rxn<ReceiptData>();

  @override
  void onInit() {
    super.onInit();
    loadReceipt();
  }

  void loadReceipt() async {
    try {
      isLoading.value = true;
      errorMessage.value = '';

      final receiptId = Get.parameters['id'];
      if (receiptId == null || receiptId.isEmpty) {
        errorMessage.value = 'Receipt ID not provided';
        return;
      }

      print('Loading receipt with ID: $receiptId');

      // Try to load from Firestore first
      ReceiptData? receipt = await _loadFromFirestore(receiptId);

      // If not found in Firestore, try local storage
      if (receipt == null) {
        receipt = await _loadFromLocalStorage(receiptId);
      }

      if (receipt != null) {
        receiptData.value = receipt;
      } else {
        errorMessage.value = 'Receipt not found';
      }
    } catch (e) {
      print('Error loading receipt: $e');
      errorMessage.value = 'Error loading receipt: $e';
    } finally {
      isLoading.value = false;
    }
  }

  Future<ReceiptData?> _loadFromFirestore(String receiptId) async {
    try {
      print('Trying to load from Firestore...');

      final doc = await FirebaseFirestore.instance
          .collection('receipts')
          .doc(receiptId)
          .get()
          .timeout(const Duration(seconds: 5));

      if (doc.exists) {
        print('Found receipt in Firestore');
        final data = doc.data() as Map<String, dynamic>;
        return _mapToReceiptData(data);
      }
    } catch (e) {
      print('Failed to load from Firestore: $e');
    }
    return null;
  }

  Future<ReceiptData?> _loadFromLocalStorage(String receiptId) async {
    try {
      print('Trying to load from local storage...');

      // Support both instance and static implementations and both sync/async returns.
      final data = await (() async {
        try {
          // Try instance method first (works if SimpleLocalStorageService defines an instance API)
          final svc = SimpleLocalStorageService();
          final result = (svc as dynamic).getReceiptByCode(receiptId);
          if (result is Future) return await result;
          return result;
        } catch (_) {
          try {
            // Fall back to a static method if available
            final result = SimpleLocalStorageService.getReceiptByCode(
              receiptId,
            );
            if (result is Future) return await result;
            return result;
          } catch (_) {
            return null;
          }
        }
      })();

      if (data != null && data is Map && data.isNotEmpty) {
        print('Found receipt in local storage');
        return _mapToReceiptData(Map<String, dynamic>.from(data));
      }
    } catch (e) {
      print('Failed to load from local storage: $e');
    }
    return null;
  }

  ReceiptData _mapToReceiptData(Map<String, dynamic> data) {
    final company = data['company'] as Map<String, dynamic>? ?? {};
    final customer = data['customer'] as Map<String, dynamic>? ?? {};
    final meta = data['meta'] as Map<String, dynamic>? ?? {};
    final items = data['items'] as List<dynamic>? ?? [];

    return ReceiptData(
      company: CompanyInfo(
        name: company['name'] ?? '',
        addressLine: company['addressLine'] ?? '',
        mobile: company['mobile'] ?? '',
        tin: company['tin'] ?? '',
        vrn: company['vrn'] ?? '',
        serialNo: company['serialNo'] ?? '',
        uim: company['uim'] ?? '',
        taxOffice: company['taxOffice'] ?? '',
        logo: const AssetImage('assets/tra-logo.png'),
      ),
      customer: CustomerInfo(
        name: customer['name'] ?? '',
        idType: customer['idType'] ?? '',
        idNo: customer['idNo'] ?? '',
        mobile: customer['mobile'] ?? '',
      ),
      meta: ReceiptMeta(
        receiptNo: meta['receiptNo'] ?? '',
        zNumber: meta['zNumber'] ?? '',
        receiptDate: meta['receiptDate'] ?? '',
        receiptTime: meta['receiptTime'] ?? '',
      ),
      items: items.map((item) {
        final itemMap = item as Map<String, dynamic>;
        return LineItem(
          description: itemMap['description'] ?? '',
          qty: itemMap['qty'] ?? 1,
          amount: (itemMap['amount'] as num?)?.toDouble() ?? 0.0,
        );
      }).toList(),
      totalExclTax: (data['totalExclTax'] as num?)?.toDouble() ?? 0.0,
      tax: (data['tax'] as num?)?.toDouble() ?? 0.0,
      totalInclTax: (data['totalInclTax'] as num?)?.toDouble() ?? 0.0,
      verificationCode: data['verificationCode'] ?? '',
      qr: const AssetImage('assets/frame.png'),
    );
  }

  void shareReceiptUrl() {
    final receiptId = Get.parameters['id'];
    if (receiptId != null) {
      final url = '${Get.currentRoute}';
      Get.snackbar(
        'Share Receipt',
        'Receipt URL: $url',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
      );
    }
  }

  void copyReceiptUrl() {
    final receiptId = Get.parameters['id'];
    if (receiptId != null) {
      final url =
          '${Uri.base.scheme}://${Uri.base.host}:${Uri.base.port}${Get.currentRoute}';
      print('Receipt URL: $url'); // In a real app, you'd use clipboard package
      Get.snackbar(
        'URL Copied',
        'Receipt URL: $url',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
    }
  }
}

class ReceiptViewPage extends StatelessWidget {
  ReceiptViewPage({super.key});

  final controller = Get.put(ReceiptViewController());

  void _showQRDialog(BuildContext context, String receiptId) {
    final receiptUrl = 'http://localhost:8080/receipt/$receiptId';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Receipt QR Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QRCodeService.generateReceiptQR(receiptId: receiptId, size: 250),
            const SizedBox(height: 16),
            const Text(
              'Scan to view receipt online',
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
              controller.copyReceiptUrl();
              Navigator.of(context).pop();
            },
            child: const Text('Copy URL'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text('Receipt ${Get.parameters['id'] ?? ''}'),
        backgroundColor: const Color(0xFFFFE500),
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          // QR Code button
          IconButton(
            onPressed: () {
              final receiptId = Get.parameters['id'];
              if (receiptId != null && receiptId.isNotEmpty) {
                _showQRDialog(context, receiptId);
              }
            },
            icon: const Icon(Icons.qr_code),
            tooltip: 'Show QR Code',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'share':
                  controller.shareReceiptUrl();
                  break;
                case 'copy':
                  controller.copyReceiptUrl();
                  break;
                case 'qr':
                  final receiptId = Get.parameters['id'];
                  if (receiptId != null && receiptId.isNotEmpty) {
                    _showQRDialog(context, receiptId);
                  }
                  break;
                case 'reload':
                  controller.loadReceipt();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'qr',
                child: Row(
                  children: [
                    Icon(Icons.qr_code),
                    SizedBox(width: 8),
                    Text('Show QR Code'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share),
                    SizedBox(width: 8),
                    Text('Share URL'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Icons.copy),
                    SizedBox(width: 8),
                    Text('Copy URL'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'reload',
                child: Row(
                  children: [
                    Icon(Icons.refresh),
                    SizedBox(width: 8),
                    Text('Reload'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading receipt...'),
              ],
            ),
          );
        }

        if (controller.errorMessage.value.isNotEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Receipt Not Found',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.red.shade600,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    controller.errorMessage.value,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: controller.loadReceipt,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try Again'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        onPressed: () => Get.offAllNamed('/'),
                        icon: const Icon(Icons.home),
                        label: const Text('Go Home'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        if (controller.receiptData.value != null) {
          return ReceiptPage(data: controller.receiptData.value!);
        }

        return const Center(child: Text('No receipt data available'));
      }),
    );
  }
}
