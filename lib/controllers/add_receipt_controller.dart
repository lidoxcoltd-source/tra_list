import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../LocalStorageService.dart';
import '../UrlHelper.dart';
import '../ReceiptPage.dart';

class AddReceiptController extends GetxController {
  final formKey = GlobalKey<FormState>();
  final scrollController = ScrollController();

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

  // Reactive variables
  var isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    _setCurrentDateTime();
    _generateReceiptNumber();
    _generateVerificationCode();
  }

  void _setCurrentDateTime() {
    final now = DateTime.now();
    receiptDateController.text =
        '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
    receiptTimeController.text =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  void _generateReceiptNumber() {
    final now = DateTime.now();
    receiptNoController.text = '${now.millisecondsSinceEpoch}'.substring(7);
  }

  void _generateVerificationCode() {
    final chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
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
      final receiptData = _buildReceiptData();
      bool savedToFirestore = false;

      // Try to save to Firestore first
      try {
        print('Attempting to save to Firestore...');
        await _testFirestoreConnection();
        print('Firestore connection test successful');

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
        await LocalStorageService.saveReceipt(receiptData);
        print('Saved to local storage as fallback');
      }

      _showSuccessDialog(savedToFirestore, verificationCodeController.text);
    } on FirebaseException catch (e) {
      _handleFirebaseException(e);
    } catch (e) {
      _handleGenericException(e);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _testFirestoreConnection() async {
    await FirebaseFirestore.instance
        .collection('receipts')
        .limit(1)
        .get()
        .timeout(const Duration(seconds: 5));
  }

  Map<String, dynamic> _buildReceiptData() {
    return {
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
  }

  void _handleFirebaseException(FirebaseException e) {
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
      messageText: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(errorMessage, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 4),
          const Text(
            'Receipt preview will still work!',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w300,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );

    previewReceipt();
  }

  void _handleGenericException(dynamic e) {
    Get.snackbar(
      'Connection Error',
      'Connection error: ${e.toString()}',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.orange,
      colorText: Colors.white,
      duration: const Duration(seconds: 5),
      messageText: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connection error: ${e.toString()}',
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 4),
          const Text(
            'Receipt preview will still work!',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w300,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );

    previewReceipt();
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

  void _showSuccessDialog(bool savedToFirestore, String receiptId) {
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
              Get.back();
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
