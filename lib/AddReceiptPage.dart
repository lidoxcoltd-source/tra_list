import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'ReceiptPage.dart';
import 'platform_local_storage_service.dart';
import 'UrlHelper.dart';

class AddReceiptPage extends StatefulWidget {
  const AddReceiptPage({super.key});

  @override
  State<AddReceiptPage> createState() => _AddReceiptPageState();
}

class _AddReceiptPageState extends State<AddReceiptPage> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  // Company Info Controllers (Pre-filled with default)
  final _companyNameController = TextEditingController(
    text: 'LIDOX ENTERPRISES',
  );
  final _companyAddressController = TextEditingController(text: 'TABORA CBD');
  final _companyMobileController = TextEditingController(text: '0655 900595');
  final _companyTinController = TextEditingController(text: '140716405');
  final _companyVrnController = TextEditingController(text: 'NOT REGISTERED');
  final _companySerialController = TextEditingController(text: '1072114856');
  final _companyUimController = TextEditingController(
    text: '90VFVEDEAM4P+0517827123029511072114856',
  );
  final _companyTaxOfficeController = TextEditingController(
    text: 'Tax Office Tabora',
  );

  // Customer Info Controllers
  final _customerNameController = TextEditingController();
  final _customerIdTypeController = TextEditingController(text: 'N.I');
  final _customerIdNoController = TextEditingController(text: 'N/A');
  final _customerMobileController = TextEditingController();

  // Receipt Meta Controllers
  final _receiptNoController = TextEditingController();
  final _zNumberController = TextEditingController();
  final _receiptDateController = TextEditingController();
  final _receiptTimeController = TextEditingController();
  final _verificationCodeController = TextEditingController();

  // Items Controllers
  final _itemDescriptionController = TextEditingController();
  final _itemQtyController = TextEditingController(text: '1');
  final _itemAmountController = TextEditingController();

  // Totals Controllers
  final _totalExclTaxController = TextEditingController();
  final _taxController = TextEditingController(text: '0.00');
  final _totalInclTaxController = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _setCurrentDateTime();
    _generateReceiptNumber();
    _generateVerificationCode();
  }

  void _setCurrentDateTime() {
    final now = DateTime.now();
    _receiptDateController.text =
        '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
    _receiptTimeController.text =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  void _generateReceiptNumber() {
    final now = DateTime.now();
    _receiptNoController.text = '${now.millisecondsSinceEpoch}'.substring(7);
  }

  void _generateVerificationCode() {
    final chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    String code = '';
    for (int i = 0; i < 9; i++) {
      code += chars[(random + i) % chars.length];
    }
    _verificationCodeController.text = code;
  }

  void _calculateTotals() {
    final amount = double.tryParse(_itemAmountController.text) ?? 0.0;
    final tax = double.tryParse(_taxController.text) ?? 0.0;

    _totalExclTaxController.text = amount.toStringAsFixed(2);
    _totalInclTaxController.text = (amount + tax).toStringAsFixed(2);
  }

  Future<void> _saveReceiptData() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final receiptData = {
        'company': {
          'name': _companyNameController.text,
          'addressLine': _companyAddressController.text,
          'mobile': _companyMobileController.text,
          'tin': _companyTinController.text,
          'vrn': _companyVrnController.text,
          'serialNo': _companySerialController.text,
          'uim': _companyUimController.text,
          'taxOffice': _companyTaxOfficeController.text,
        },
        'customer': {
          'name': _customerNameController.text,
          'idType': _customerIdTypeController.text,
          'idNo': _customerIdNoController.text,
          'mobile': _customerMobileController.text,
        },
        'meta': {
          'receiptNo': _receiptNoController.text,
          'zNumber': _zNumberController.text,
          'receiptDate': _receiptDateController.text,
          'receiptTime': _receiptTimeController.text,
        },
        'items': [
          {
            'description': _itemDescriptionController.text,
            'qty': int.tryParse(_itemQtyController.text) ?? 1,
            'amount': double.tryParse(_itemAmountController.text) ?? 0.0,
          },
        ],
        'totalExclTax': double.tryParse(_totalExclTaxController.text) ?? 0.0,
        'tax': double.tryParse(_taxController.text) ?? 0.0,
        'totalInclTax': double.tryParse(_totalInclTaxController.text) ?? 0.0,
        'verificationCode': _verificationCodeController.text,
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
            .doc(_verificationCodeController.text)
            .set(firestoreData)
            .timeout(const Duration(seconds: 15));

        print('Successfully saved to Firestore!');
        savedToFirestore = true;
      } catch (firestoreError) {
        print('Firestore error: $firestoreError');

        // If Firestore fails, save to local storage using original receiptData
        // (which still has the ISO string timestamp)
        await PlatformLocalStorageService.saveReceipt(receiptData);
        print('Saved to local storage as fallback');
      }

      if (mounted) {
        // Show success dialog with receipt URL
        _showSuccessDialog(savedToFirestore, _verificationCodeController.text);
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        String errorMessage = 'Firebase connection error';
        if (e.code == 'unavailable') {
          errorMessage =
              'Firestore is not enabled. Please enable Firestore in Firebase Console.';
        } else if (e.code == 'permission-denied') {
          errorMessage =
              'Permission denied. Please check Firestore security rules.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(errorMessage),
                const SizedBox(height: 4),
                const Text(
                  'Receipt preview will still work!',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w300),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );

        // Still show preview even if save fails
        _previewReceipt();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Connection error: ${e.toString()}'),
                const SizedBox(height: 4),
                const Text(
                  'Receipt preview will still work!',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w300),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );

        // Still show preview even if save fails
        _previewReceipt();
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _previewReceipt() {
    final receiptData = ReceiptData(
      company: CompanyInfo(
        name: _companyNameController.text,
        addressLine: _companyAddressController.text,
        mobile: _companyMobileController.text,
        tin: _companyTinController.text,
        vrn: _companyVrnController.text,
        serialNo: _companySerialController.text,
        uim: _companyUimController.text,
        taxOffice: _companyTaxOfficeController.text,
        logo: const AssetImage('assets/tra-logo.png'),
      ),
      customer: CustomerInfo(
        name: _customerNameController.text,
        idType: _customerIdTypeController.text,
        idNo: _customerIdNoController.text,
        mobile: _customerMobileController.text,
      ),
      meta: ReceiptMeta(
        receiptNo: _receiptNoController.text,
        zNumber: _zNumberController.text,
        receiptDate: _receiptDateController.text,
        receiptTime: _receiptTimeController.text,
      ),
      items: [
        LineItem(
          description: _itemDescriptionController.text,
          qty: int.tryParse(_itemQtyController.text) ?? 1,
          amount: double.tryParse(_itemAmountController.text) ?? 0.0,
        ),
      ],
      totalExclTax: double.tryParse(_totalExclTaxController.text) ?? 0.0,
      tax: double.tryParse(_taxController.text) ?? 0.0,
      totalInclTax: double.tryParse(_totalInclTaxController.text) ?? 0.0,
      verificationCode: _verificationCodeController.text,
      qr: const AssetImage('assets/frame.png'),
    );

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ReceiptPage(data: receiptData)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Add New Receipt'),
        centerTitle: true,
        backgroundColor: const Color(0xFFFFE500),
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: Scrollbar(
          controller: _scrollController,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Company Information Section
                _buildSectionHeader('Company Information'),
                _buildCard([
                  _buildTextField(
                    _companyNameController,
                    'Company Name',
                    Icons.business,
                  ),
                  _buildTextField(
                    _companyAddressController,
                    'Address',
                    Icons.location_on,
                  ),
                  _buildTextField(
                    _companyMobileController,
                    'Mobile',
                    Icons.phone,
                  ),
                  _buildTextField(_companyTinController, 'TIN', Icons.numbers),
                  _buildTextField(_companyVrnController, 'VRN', Icons.verified),
                  _buildTextField(
                    _companySerialController,
                    'Serial No',
                    Icons.confirmation_number,
                  ),
                  _buildTextField(_companyUimController, 'UIM', Icons.qr_code),
                  _buildTextField(
                    _companyTaxOfficeController,
                    'Tax Office',
                    Icons.account_balance,
                  ),
                ]),

                const SizedBox(height: 24),

                // Customer Information Section
                _buildSectionHeader('Customer Information'),
                _buildCard([
                  _buildTextField(
                    _customerNameController,
                    'Customer Name',
                    Icons.person,
                    required: true,
                  ),
                  _buildTextField(
                    _customerIdTypeController,
                    'ID Type',
                    Icons.credit_card,
                  ),
                  _buildTextField(
                    _customerIdNoController,
                    'ID Number',
                    Icons.numbers,
                  ),
                  _buildTextField(
                    _customerMobileController,
                    'Mobile',
                    Icons.phone,
                  ),
                ]),

                const SizedBox(height: 24),

                // Receipt Meta Information Section
                _buildSectionHeader('Receipt Information'),
                _buildCard([
                  _buildTextField(
                    _receiptNoController,
                    'Receipt No',
                    Icons.receipt,
                    readOnly: true,
                  ),
                  _buildTextField(
                    _zNumberController,
                    'Z Number',
                    Icons.tag,
                    required: true,
                  ),
                  _buildTextField(
                    _receiptDateController,
                    'Receipt Date',
                    Icons.calendar_today,
                    readOnly: true,
                  ),
                  _buildTextField(
                    _receiptTimeController,
                    'Receipt Time',
                    Icons.access_time,
                    readOnly: true,
                  ),
                  _buildTextField(
                    _verificationCodeController,
                    'Verification Code',
                    Icons.verified_user,
                    readOnly: true,
                  ),
                ]),

                const SizedBox(height: 24),

                // Items Section
                _buildSectionHeader('Item Details'),
                _buildCard([
                  _buildTextField(
                    _itemDescriptionController,
                    'Item Description',
                    Icons.description,
                    required: true,
                  ),
                  _buildTextField(
                    _itemQtyController,
                    'Quantity',
                    Icons.production_quantity_limits,
                    keyboardType: TextInputType.number,
                  ),
                  _buildTextField(
                    _itemAmountController,
                    'Amount (TZS)',
                    Icons.attach_money,
                    keyboardType: TextInputType.number,
                    required: true,
                    onChanged: (value) => _calculateTotals(),
                  ),
                ]),

                const SizedBox(height: 24),

                // Totals Section
                _buildSectionHeader('Totals'),
                _buildCard([
                  _buildTextField(
                    _totalExclTaxController,
                    'Total Excl Tax',
                    Icons.calculate,
                    readOnly: true,
                  ),
                  _buildTextField(
                    _taxController,
                    'Tax Amount',
                    Icons.percent,
                    keyboardType: TextInputType.number,
                    onChanged: (value) => _calculateTotals(),
                  ),
                  _buildTextField(
                    _totalInclTaxController,
                    'Total Incl Tax',
                    Icons.receipt_long,
                    readOnly: true,
                  ),
                ]),

                const SizedBox(height: 32),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _previewReceipt,
                        icon: const Icon(Icons.preview),
                        label: const Text('Preview Receipt'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _saveReceiptData,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black87,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(_isLoading ? 'Saving...' : 'Save Receipt'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFE500),
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Card(
      elevation: 2,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: children),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool required = false,
    bool readOnly = false,
    TextInputType? keyboardType,
    Function(String)? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: keyboardType,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.grey.shade600),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFFFE500), width: 2),
          ),
          filled: readOnly,
          fillColor: readOnly ? Colors.grey.shade100 : null,
        ),
        validator: required
            ? (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter $label';
                }
                return null;
              }
            : null,
      ),
    );
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _companyAddressController.dispose();
    _companyMobileController.dispose();
    _companyTinController.dispose();
    _companyVrnController.dispose();
    _companySerialController.dispose();
    _companyUimController.dispose();
    _companyTaxOfficeController.dispose();
    _customerNameController.dispose();
    _customerIdTypeController.dispose();
    _customerIdNoController.dispose();
    _customerMobileController.dispose();
    _receiptNoController.dispose();
    _zNumberController.dispose();
    _receiptDateController.dispose();
    _receiptTimeController.dispose();
    _verificationCodeController.dispose();
    _itemDescriptionController.dispose();
    _itemQtyController.dispose();
    _itemAmountController.dispose();
    _totalExclTaxController.dispose();
    _taxController.dispose();
    _totalInclTaxController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _showSuccessDialog(bool savedToFirestore, String receiptId) {
    final receiptUrl = UrlHelper.getReceiptUrl(receiptId);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
              Navigator.of(context).pop();
              _previewReceipt();
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
}
