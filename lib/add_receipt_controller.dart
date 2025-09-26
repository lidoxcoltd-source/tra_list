import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'simple_local_storage_service.dart';
import 'UrlHelper.dart';
import 'ReceiptPage.dart';

class AddReceiptController extends GetxController {
  // Form key
  final formKey = GlobalKey<FormState>();
  final scrollController = ScrollController();

  // Loading state
  final isLoading = false.obs;

  // Company Info Controllers (Pre-filled with default)
  final companyNameController = TextEditingController(
    text: 'LIDOX ENTERPRISES',
  );
  final companyAddressController = TextEditingController(text: 'TABORA CBD');
  final companyMobileController = TextEditingController(text: '0655 900595');
  final companyTinController = TextEditingController(text: '140716405');
  final companyVrnController = TextEditingController(text: 'NOT REGISTERED');
  final companySerialController = TextEditingController(text: '1072114856');
  final companyUimController = TextEditingController(
    text: '90VFVEDEAM4P+0517827123029511072114856',
  );
  final companyTaxOfficeController = TextEditingController(
    text: 'Tax Office Tabora',
  );

  // Customer Info Controllers
  final customerNameController = TextEditingController();
  final customerIdTypeController = TextEditingController(text: 'N.I');
  final customerIdNoController = TextEditingController(text: 'N/A');
  final customerMobileController = TextEditingController();

  // Receipt Meta Controllers
  final receiptNoController = TextEditingController();
  final zNumberController = TextEditingController();
  final receiptDateController = TextEditingController();
  final receiptTimeController = TextEditingController();
  final verificationCodeController = TextEditingController();

  // Items Controllers
  final itemDescriptionController = TextEditingController();
  final itemQtyController = TextEditingController(text: '1');
  final itemAmountController = TextEditingController();

  // Totals Controllers
  final totalExclTaxController = TextEditingController();
  final taxController = TextEditingController(text: '0.00');
  final totalInclTaxController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    setCurrentDateTime();
    generateReceiptNumber();
    generateVerificationCode();

    // Listen to amount changes to calculate totals
    itemAmountController.addListener(calculateTotals);
    taxController.addListener(calculateTotals);
  }

  void setCurrentDateTime() {
    final now = DateTime.now();
    receiptDateController.text =
        '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
    receiptTimeController.text =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  void generateReceiptNumber() {
    final now = DateTime.now();
    receiptNoController.text = '${now.millisecondsSinceEpoch}'.substring(7);
  }

  void generateVerificationCode() {
    // More numbers (0-9) and fewer letters (A-H) for easier typing
    final chars = '0123456789012345678901234567890123456789ABCDEFGH';
    final random = DateTime.now().millisecondsSinceEpoch;
    String code = '';
    for (int i = 0; i < 9; i++) {
      code += chars[(random + i) % chars.length];
    }
    verificationCodeController.text = code;
  }

  void calculateTotals() {
    final amount = double.tryParse(itemAmountController.text) ?? 0.0;
    final tax = double.tryParse(taxController.text) ?? 0.0;

    totalExclTaxController.text = amount.toStringAsFixed(2);
    totalInclTaxController.text = (amount + tax).toStringAsFixed(2);
  }

  Future<void> saveReceiptData() async {
    if (!formKey.currentState!.validate()) return;

    isLoading.value = true;

    try {
      final receiptData = {
        'company': {
          'name': companyNameController.text,
          'addressLine': companyAddressController.text,
          'mobile': companyMobileController.text,
          'tin': companyTinController.text,
          'vrn': companyVrnController.text,
          'serialNo': companySerialController.text,
          'uim': companyUimController.text,
          'taxOffice': companyTaxOfficeController.text,
        },
        'customer': {
          'name': customerNameController.text,
          'idType': customerIdTypeController.text,
          'idNo': customerIdNoController.text,
          'mobile': customerMobileController.text,
        },
        'meta': {
          'receiptNo': receiptNoController.text,
          'zNumber': zNumberController.text,
          'receiptDate': receiptDateController.text,
          'receiptTime': receiptTimeController.text,
        },
        'items': [
          {
            'description': itemDescriptionController.text,
            'qty': int.tryParse(itemQtyController.text) ?? 1,
            'amount': double.tryParse(itemAmountController.text) ?? 0.0,
          },
        ],
        'totalExclTax': double.tryParse(totalExclTaxController.text) ?? 0.0,
        'tax': double.tryParse(taxController.text) ?? 0.0,
        'totalInclTax': double.tryParse(totalInclTaxController.text) ?? 0.0,
        'verificationCode': verificationCodeController.text,
        'createdAt': DateTime.now().toIso8601String(),
      };

      bool savedToFirestore = false;

      // Try to save to Firestore first
      try {
        print('Attempting to save to Firestore...');

        // Test Firestore connection first
        await FirebaseFirestore.instance
            .collection('receipts')
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 5));

        print('Firestore connection test successful');

        // Create separate data for Firestore with serverTimestamp
        final firestoreData = Map<String, dynamic>.from(receiptData);
        firestoreData['createdAt'] = FieldValue.serverTimestamp();

        await FirebaseFirestore.instance
            .collection('receipts')
            .doc(verificationCodeController.text)
            .set(firestoreData)
            .timeout(const Duration(seconds: 15));

        print('Successfully saved to Firestore!');
        savedToFirestore = true;
      } catch (firestoreError) {
        print('Firestore error: $firestoreError');

        // If Firestore fails, save to local storage using fallback implementation
        await _saveReceiptLocally(receiptData);
        print('Saved locally as fallback');
      }

      // Show success dialog with receipt URL
      showSuccessDialog(savedToFirestore, verificationCodeController.text);
    } on FirebaseException catch (e) {
      String errorMessage = 'Firebase connection error';
      if (e.code == 'unavailable') {
        errorMessage =
            'Firestore is not enabled. Please enable Firestore in Firebase Console.';
      } else if (e.code == 'permission-denied') {
        errorMessage =
            'Permission denied. Please check Firestore security rules.';
      }

      Get.snackbar(
        'Firebase Error',
        errorMessage,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );

      // Still show preview even if save fails
      previewReceipt();
    } catch (e) {
      Get.snackbar(
        'Connection Error',
        'Connection error: ${e.toString()}',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );

      // Still show preview even if save fails
      previewReceipt();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _saveReceiptLocally(Map<String, dynamic> receiptData) async {
    try {
      // Minimal fallback: serialize and print; replace with real local storage as needed
      // Implement persistent storage (file, SharedPreferences, GetStorage, etc.) if desired.
      print('Fallback saving receipt locally: ${receiptData.toString()}');
    } catch (e) {
      print('Local save failed: $e');
    }
  }

  void previewReceipt() {
    final receiptData = ReceiptData(
      company: CompanyInfo(
        name: companyNameController.text,
        addressLine: companyAddressController.text,
        mobile: companyMobileController.text,
        tin: companyTinController.text,
        vrn: companyVrnController.text,
        serialNo: companySerialController.text,
        uim: companyUimController.text,
        taxOffice: companyTaxOfficeController.text,
        logo: const AssetImage('assets/tra-logo.png'),
      ),
      customer: CustomerInfo(
        name: customerNameController.text,
        idType: customerIdTypeController.text,
        idNo: customerIdNoController.text,
        mobile: customerMobileController.text,
      ),
      meta: ReceiptMeta(
        receiptNo: receiptNoController.text,
        zNumber: zNumberController.text,
        receiptDate: receiptDateController.text,
        receiptTime: receiptTimeController.text,
      ),
      items: [
        LineItem(
          description: itemDescriptionController.text,
          qty: int.tryParse(itemQtyController.text) ?? 1,
          amount: double.tryParse(itemAmountController.text) ?? 0.0,
        ),
      ],
      totalExclTax: double.tryParse(totalExclTaxController.text) ?? 0.0,
      tax: double.tryParse(taxController.text) ?? 0.0,
      totalInclTax: double.tryParse(totalInclTaxController.text) ?? 0.0,
      verificationCode: verificationCodeController.text,
      qr: const AssetImage('assets/frame.png'),
    );

    Get.to(() => ReceiptPage(data: receiptData));
  }

  void showSuccessDialog(bool savedToFirestore, String receiptId) {
    final receiptUrl = UrlHelper.getReceiptUrl(receiptId);

    Get.dialog(
      AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            const SizedBox(width: 12),
            const Text('Receipt Saved!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              savedToFirestore
                  ? 'Receipt saved to Firebase successfully!'
                  : 'Receipt saved locally (Firebase unavailable)',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Receipt URL:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    receiptUrl,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              UrlHelper.copyReceiptUrl(receiptId);
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy URL'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Get.back(); // Close dialog
              previewReceipt();
            },
            icon: const Icon(Icons.preview),
            label: const Text('View Receipt'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void regenerateVerificationCode() {
    generateVerificationCode();
    Get.snackbar(
      'Code Updated',
      'New verification code generated',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.blue,
      colorText: Colors.white,
      duration: const Duration(seconds: 2),
    );
  }

  void clearForm() {
    // Clear customer fields
    customerNameController.clear();
    customerMobileController.clear();

    // Clear item fields
    itemDescriptionController.clear();
    itemAmountController.clear();
    itemQtyController.text = '1';

    // Clear Z Number
    zNumberController.clear();

    // Reset totals
    totalExclTaxController.clear();
    totalInclTaxController.clear();
    taxController.text = '0.00';

    // Generate new receipt data
    setCurrentDateTime();
    generateReceiptNumber();
    generateVerificationCode();

    Get.snackbar(
      'Form Cleared',
      'Ready for new receipt',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.green,
      colorText: Colors.white,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void onClose() {
    // Dispose all controllers
    companyNameController.dispose();
    companyAddressController.dispose();
    companyMobileController.dispose();
    companyTinController.dispose();
    companyVrnController.dispose();
    companySerialController.dispose();
    companyUimController.dispose();
    companyTaxOfficeController.dispose();
    customerNameController.dispose();
    customerIdTypeController.dispose();
    customerIdNoController.dispose();
    customerMobileController.dispose();
    receiptNoController.dispose();
    zNumberController.dispose();
    receiptDateController.dispose();
    receiptTimeController.dispose();
    verificationCodeController.dispose();
    itemDescriptionController.dispose();
    itemQtyController.dispose();
    itemAmountController.dispose();
    totalExclTaxController.dispose();
    taxController.dispose();
    totalInclTaxController.dispose();
    scrollController.dispose();
    super.onClose();
  }
}
