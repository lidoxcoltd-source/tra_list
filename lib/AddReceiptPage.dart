import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'ReceiptPage.dart';
import 'LocalStorageService.dart';
import 'UrlHelper.dart';
import 'services/profile_service.dart';
import 'utils/url_launcher_platform.dart';

class AddReceiptPage extends StatefulWidget {
  final ReceiptData? receiptData;
  const AddReceiptPage({super.key, this.receiptData});

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
  final _customerVrnController = TextEditingController();

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

  late final FocusNode _itemAmountFocusNode;
  late final FocusNode _taxFocusNode;

  // Dynamic colors from profile
  Color _brandColor = const Color(0xFF1976D2);
  Color _accentColor = const Color(0xFFFFA000);

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProfileColors();

    _itemAmountFocusNode = FocusNode();
    _taxFocusNode = FocusNode();
    _itemAmountFocusNode.addListener(_onItemAmountFocusChange);
    _taxFocusNode.addListener(_onTaxFocusChange);

    if (widget.receiptData != null) {
      _loadDataFromReceipt(widget.receiptData!);
    } else {
      _setCurrentDateTime();
      _generateReceiptNumber();
      _generateVerificationCode();
      _generateZNumber();
    }
  }

  void _onItemAmountFocusChange() {
    if (_itemAmountFocusNode.hasFocus) {
      _itemAmountController.text = _itemAmountController.text.replaceAll(
        ',',
        '',
      );
    } else {
      final value = double.tryParse(_itemAmountController.text) ?? 0.0;
      _itemAmountController.text = _formatNumberValue(value);
    }
  }

  void _onTaxFocusChange() {
    if (_taxFocusNode.hasFocus) {
      _taxController.text = _taxController.text.replaceAll(',', '');
    } else {
      final value = double.tryParse(_taxController.text) ?? 0.0;
      _taxController.text = _formatNumberValue(value);
    }
  }

  void _loadDataFromReceipt(ReceiptData data) {
    // Company
    _companyNameController.text = data.company.name;
    _companyAddressController.text = data.company.addressLine;
    _companyMobileController.text = data.company.mobile;
    _companyTinController.text = data.company.tin;
    _companyVrnController.text = data.company.vrn;
    _companySerialController.text = data.company.serialNo;
    _companyUimController.text = data.company.uim;
    _companyTaxOfficeController.text = data.company.taxOffice;

    // Customer
    _customerNameController.text = data.customer.name;
    _customerIdTypeController.text = data.customer.idType;
    _customerIdNoController.text = data.customer.idNo;
    _customerMobileController.text = data.customer.mobile;
    _customerVrnController.text = data.customer.vrn;

    // Meta
    _receiptNoController.text = data.meta.receiptNo;
    _zNumberController.text = data.meta.zNumber;
    _receiptDateController.text = data.meta.receiptDate;
    _receiptTimeController.text = data.meta.receiptTime;
    _verificationCodeController.text = data.verificationCode;

    // Items (assuming one item for now as the form is simple)
    if (data.items.isNotEmpty) {
      final item = data.items.first;
      _itemDescriptionController.text = item.description;
      _itemQtyController.text = item.qty.toString();
      _itemAmountController.text = _formatNumberValue(item.amount);
    }

    // Totals
    _totalExclTaxController.text = _formatNumberValue(data.totalExclTax);
    _taxController.text = _formatNumberValue(data.tax);
    _totalInclTaxController.text = _formatNumberValue(data.totalInclTax);
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

  Future<void> _loadProfileColors() async {
    try {
      final profile = await ProfileService.loadOrCreate();
      if (mounted && profile.containsKey('colors')) {
        final colors = profile['colors'] as Map<String, dynamic>;
        setState(() {
          _brandColor = Color(colors['brand'] as int? ?? 0xFF1976D2);
          _accentColor = Color(colors['accent'] as int? ?? 0xFFFFA000);
        });
      }
    } catch (e) {
      debugPrint('Failed to load profile colors: $e');
    }
  }

  void _generateVerificationCode() {
    final numbers = '0123456789';
    final letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final random = Random();

    String code = '';

    // Generate 6-7 numbers first
    for (int i = 0; i < 6 + random.nextInt(2); i++) {
      code += numbers[random.nextInt(numbers.length)];
    }

    // Add 2-3 letters
    final letterCount = 2 + random.nextInt(2); // 2 or 3 letters
    for (int i = 0; i < letterCount; i++) {
      code += letters[random.nextInt(letters.length)];
    }

    // Shuffle the code to mix numbers and letters
    List<String> codeList = code.split('');
    codeList.shuffle(random);

    _verificationCodeController.text = codeList.join();
  }

  void _generateZNumber() {
    final random = Random();
    final part1 = (random.nextInt(99) + 1).toString().padLeft(3, '0');
    final part2 = random.nextInt(1000).toString().padLeft(3, '0');
    _zNumberController.text = '$part1/$part2';
  }

  String _formatNumberValue(double value) {
    final parts = value.toStringAsFixed(2).split('.');
    final wholePart = parts[0];
    final decimalPart = parts[1];

    final formattedWholePart = wholePart.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );

    return '$formattedWholePart.$decimalPart';
  }

  void _calculateTotals() {
    final amount =
        double.tryParse(_itemAmountController.text.replaceAll(',', '')) ?? 0.0;
    final tax = double.tryParse(_taxController.text.replaceAll(',', '')) ?? 0.0;

    _totalExclTaxController.text = _formatNumberValue(amount);
    _totalInclTaxController.text = _formatNumberValue(amount + tax);
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
          'vrn': _customerVrnController.text,
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
            'amount':
                double.tryParse(
                  _itemAmountController.text.replaceAll(',', ''),
                ) ??
                0.0,
          },
        ],
        'totalExclTax':
            double.tryParse(_totalExclTaxController.text.replaceAll(',', '')) ??
            0.0,
        'tax': double.tryParse(_taxController.text.replaceAll(',', '')) ?? 0.0,
        'totalInclTax':
            double.tryParse(_totalInclTaxController.text.replaceAll(',', '')) ??
            0.0,
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
        await LocalStorageService.saveReceipt(receiptData);
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
        vrn: _customerVrnController.text,
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
          amount:
              double.tryParse(_itemAmountController.text.replaceAll(',', '')) ??
              0.0,
        ),
      ],
      totalExclTax:
          double.tryParse(_totalExclTaxController.text.replaceAll(',', '')) ??
          0.0,
      tax: double.tryParse(_taxController.text.replaceAll(',', '')) ?? 0.0,
      totalInclTax:
          double.tryParse(_totalInclTaxController.text.replaceAll(',', '')) ??
          0.0,
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
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text(
          'New Receipt',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: Scrollbar(
          controller: _scrollController,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Company Information Section
                _buildSectionHeader(
                  'Company Information',
                  Icons.business_rounded,
                ),
                _buildCard([
                  _buildTextField(
                    _companyNameController,
                    'Company Name',
                    Icons.business_rounded,
                  ),
                  _buildTextField(
                    _companyAddressController,
                    'Address',
                    Icons.location_on_rounded,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          _companyMobileController,
                          'Mobile',
                          Icons.phone_rounded,
                          bottomPad: 0,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          _companyTinController,
                          'TIN',
                          Icons.tag_rounded,
                          bottomPad: 0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          _companyVrnController,
                          'VRN',
                          Icons.verified_rounded,
                          bottomPad: 0,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          _companySerialController,
                          'Serial No',
                          Icons.confirmation_number_rounded,
                          bottomPad: 0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    _companyUimController,
                    'UIM',
                    Icons.qr_code_rounded,
                  ),
                  _buildTextField(
                    _companyTaxOfficeController,
                    'Tax Office',
                    Icons.account_balance_rounded,
                    bottomPad: 0,
                  ),
                ]),

                const SizedBox(height: 20),

                // Customer Information Section
                _buildSectionHeader(
                  'Customer Information',
                  Icons.person_rounded,
                ),
                _buildCard([
                  _buildTextField(
                    _customerNameController,
                    'Customer Name',
                    Icons.person_rounded,
                    required: true,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          _customerIdTypeController,
                          'ID Type',
                          Icons.credit_card_rounded,
                          bottomPad: 0,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          _customerIdNoController,
                          'ID Number',
                          Icons.numbers_rounded,
                          bottomPad: 0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          _customerMobileController,
                          'Mobile',
                          Icons.phone_rounded,
                          bottomPad: 0,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          _customerVrnController,
                          'VRN',
                          Icons.confirmation_number_rounded,
                          bottomPad: 0,
                        ),
                      ),
                    ],
                  ),
                ]),

                const SizedBox(height: 20),

                // Receipt Meta Information Section
                _buildSectionHeader(
                  'Receipt Information',
                  Icons.receipt_long_rounded,
                ),
                _buildCard([
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          _receiptNoController,
                          'Receipt No',
                          Icons.receipt_rounded,
                          bottomPad: 0,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          _zNumberController,
                          'Z Number',
                          Icons.tag_rounded,
                          required: true,
                          bottomPad: 0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 0),
                          child: TextFormField(
                            controller: _receiptDateController,
                            readOnly: true,
                            onTap: () async {
                              DateTime initialDate = DateTime.now();
                              try {
                                final parts = _receiptDateController.text.split(
                                  '-',
                                );
                                if (parts.length == 3) {
                                  initialDate = DateTime(
                                    int.parse(parts[2]),
                                    int.parse(parts[1]),
                                    int.parse(parts[0]),
                                  );
                                }
                              } catch (_) {}
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: initialDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setState(() {
                                  _receiptDateController.text =
                                      '${picked.day.toString().padLeft(2, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.year}';
                                });
                              }
                            },
                            decoration: _fieldDecoration(
                              'Date',
                              Icons.calendar_today_rounded,
                              readOnly: true,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _receiptTimeController,
                          readOnly: true,
                          onTap: () async {
                            final now = DateTime.now();
                            int initHour = now.hour,
                                initMinute = now.minute,
                                seconds = now.second;
                            try {
                              final parts = _receiptTimeController.text.split(
                                ':',
                              );
                              if (parts.length >= 2) {
                                initHour = int.parse(parts[0]);
                                initMinute = int.parse(parts[1]);
                                if (parts.length >= 3)
                                  seconds = int.parse(parts[2]);
                              }
                            } catch (_) {}
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay(
                                hour: initHour,
                                minute: initMinute,
                              ),
                            );
                            if (picked != null) {
                              setState(() {
                                _receiptTimeController.text =
                                    '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
                              });
                            }
                          },
                          decoration: _fieldDecoration(
                            'Time',
                            Icons.access_time_rounded,
                            readOnly: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    _verificationCodeController,
                    'Verification Code',
                    Icons.verified_user_rounded,
                    readOnly: true,
                    bottomPad: 0,
                  ),
                ]),

                const SizedBox(height: 20),

                // Items Section
                _buildSectionHeader('Item Details', Icons.inventory_2_rounded),
                _buildCard([
                  _buildTextField(
                    _itemDescriptionController,
                    'Item Description',
                    Icons.description_rounded,
                    required: true,
                  ),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildTextField(
                          _itemAmountController,
                          'Amount (TZS)',
                          Icons.payments_rounded,
                          focusNode: _itemAmountFocusNode,
                          keyboardType: TextInputType.number,
                          required: true,
                          onChanged: (_) => _calculateTotals(),
                          bottomPad: 0,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          _itemQtyController,
                          'Qty',
                          Icons.production_quantity_limits_rounded,
                          keyboardType: TextInputType.number,
                          bottomPad: 0,
                        ),
                      ),
                    ],
                  ),
                ]),

                const SizedBox(height: 20),

                // Totals Section
                _buildSectionHeader('Totals', Icons.calculate_rounded),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildTotalRow(
                        'Total Excl. Tax',
                        _totalExclTaxController.text,
                        isHighlighted: false,
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: _buildTextField(
                          _taxController,
                          'Tax Amount',
                          Icons.percent_rounded,
                          focusNode: _taxFocusNode,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _calculateTotals(),
                          bottomPad: 0,
                        ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _buildTotalRow(
                        'Total Incl. Tax',
                        _totalInclTaxController.text,
                        isHighlighted: true,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _previewReceipt,
                        icon: const Icon(Icons.visibility_rounded),
                        label: const Text('Preview'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A1A2E),
                          side: const BorderSide(
                            color: Color(0xFF1A1A2E),
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _saveReceiptData,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(_isLoading ? 'Saving…' : 'Save Receipt'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A1A2E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTotalRow(
    String label,
    String value, {
    required bool isHighlighted,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w500,
              color: isHighlighted
                  ? const Color(0xFF1A1A2E)
                  : Colors.grey.shade600,
            ),
          ),
          Text(
            'TZS $value',
            style: TextStyle(
              fontSize: isHighlighted ? 16 : 14,
              fontWeight: FontWeight.bold,
              color: isHighlighted
                  ? const Color(0xFF2E7D32)
                  : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: const Color(0xFFFFE500), size: 16),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  InputDecoration _fieldDecoration(
    String label,
    IconData icon, {
    bool readOnly = false,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
      prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF1A1A2E), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
      filled: true,
      fillColor: readOnly ? const Color(0xFFF0F0F5) : Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
    FocusNode? focusNode,
    double bottomPad = 16,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        readOnly: readOnly,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A2E)),
        decoration: _fieldDecoration(label, icon, readOnly: readOnly),
        validator: required
            ? (value) {
                if (value == null || value.isEmpty) return 'Required';
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
    _customerVrnController.dispose();
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
    _itemAmountFocusNode.removeListener(_onItemAmountFocusChange);
    _taxFocusNode.removeListener(_onTaxFocusChange);
    _itemAmountFocusNode.dispose();
    _taxFocusNode.dispose();
    super.dispose();
  }

  void _showSuccessDialog(bool savedToFirestore, String receiptId) {
    final receiptUrl = UrlHelper.getReceiptUrl(receiptId);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF2E7D32),
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Receipt Saved!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                savedToFirestore
                    ? 'Saved to Firebase successfully.'
                    : 'Saved locally — Firebase unavailable.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              // URL box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F6FA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Receipt URL',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      receiptUrl,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => UrlHelper.copyReceiptUrl(receiptId),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1A1A2E),
                        side: const BorderSide(color: Color(0xFF1A1A2E)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        try {
                          if (kIsWeb) {
                            openUrlInNewTab(receiptUrl);
                          } else {
                            Clipboard.setData(ClipboardData(text: receiptUrl));
                            Get.snackbar(
                              'URL Copied',
                              'Open in browser to view receipt.',
                              backgroundColor: Colors.green,
                              colorText: Colors.white,
                              snackPosition: SnackPosition.BOTTOM,
                              duration: const Duration(seconds: 4),
                            );
                          }
                        } catch (e) {
                          Get.snackbar(
                            'Error',
                            'Failed to open receipt: $e',
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                            snackPosition: SnackPosition.BOTTOM,
                          );
                        }
                      },
                      icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                      label: const Text('View'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A1A2E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
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
}
