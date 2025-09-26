import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'add_receipt_controller.dart';

class AddReceiptPage extends StatelessWidget {
  const AddReceiptPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(AddReceiptController());

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Add New Receipt'),
        centerTitle: true,
        backgroundColor: const Color(0xFFFFE500),
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: controller.clearForm,
            icon: const Icon(Icons.refresh),
            tooltip: 'Clear Form',
          ),
        ],
      ),
      body: Form(
        key: controller.formKey,
        child: Scrollbar(
          controller: controller.scrollController,
          child: SingleChildScrollView(
            controller: controller.scrollController,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Company Information Section
                _buildSectionHeader('Company Information'),
                _buildCard([
                  _buildTextField(
                    controller.companyNameController,
                    'Company Name',
                    Icons.business,
                  ),
                  _buildTextField(
                    controller.companyAddressController,
                    'Address',
                    Icons.location_on,
                  ),
                  _buildTextField(
                    controller.companyMobileController,
                    'Mobile',
                    Icons.phone,
                  ),
                  _buildTextField(
                    controller.companyTinController,
                    'TIN',
                    Icons.numbers,
                  ),
                  _buildTextField(
                    controller.companyVrnController,
                    'VRN',
                    Icons.verified,
                  ),
                  _buildTextField(
                    controller.companySerialController,
                    'Serial No',
                    Icons.confirmation_number,
                  ),
                  _buildTextField(
                    controller.companyUimController,
                    'UIM',
                    Icons.qr_code,
                  ),
                  _buildTextField(
                    controller.companyTaxOfficeController,
                    'Tax Office',
                    Icons.account_balance,
                  ),
                ]),

                const SizedBox(height: 24),

                // Customer Information Section
                _buildSectionHeader('Customer Information'),
                _buildCard([
                  _buildTextField(
                    controller.customerNameController,
                    'Customer Name',
                    Icons.person,
                    required: true,
                  ),
                  _buildTextField(
                    controller.customerIdTypeController,
                    'ID Type',
                    Icons.credit_card,
                  ),
                  _buildTextField(
                    controller.customerIdNoController,
                    'ID Number',
                    Icons.numbers,
                  ),
                  _buildTextField(
                    controller.customerMobileController,
                    'Mobile',
                    Icons.phone,
                  ),
                ]),

                const SizedBox(height: 24),

                // Receipt Meta Information Section
                _buildSectionHeader('Receipt Information'),
                _buildCard([
                  _buildTextField(
                    controller.receiptNoController,
                    'Receipt No',
                    Icons.receipt,
                    readOnly: true,
                  ),
                  _buildTextField(
                    controller.zNumberController,
                    'Z Number',
                    Icons.tag,
                    required: true,
                  ),
                  _buildTextField(
                    controller.receiptDateController,
                    'Receipt Date',
                    Icons.calendar_today,
                    readOnly: true,
                  ),
                  _buildTextField(
                    controller.receiptTimeController,
                    'Receipt Time',
                    Icons.access_time,
                    readOnly: true,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller.verificationCodeController,
                          'Verification Code',
                          Icons.verified_user,
                          readOnly: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: controller.regenerateVerificationCode,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Generate New Code',
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFFFE500),
                          foregroundColor: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ]),

                const SizedBox(height: 24),

                // Items Section
                _buildSectionHeader('Item Details'),
                _buildCard([
                  _buildTextField(
                    controller.itemDescriptionController,
                    'Item Description',
                    Icons.description,
                    required: true,
                  ),
                  _buildTextField(
                    controller.itemQtyController,
                    'Quantity',
                    Icons.production_quantity_limits,
                    keyboardType: TextInputType.number,
                  ),
                  _buildTextField(
                    controller.itemAmountController,
                    'Amount (TZS)',
                    Icons.attach_money,
                    keyboardType: TextInputType.number,
                    required: true,
                  ),
                ]),

                const SizedBox(height: 24),

                // Totals Section
                _buildSectionHeader('Totals'),
                _buildCard([
                  _buildTextField(
                    controller.totalExclTaxController,
                    'Total Excl Tax',
                    Icons.calculate,
                    readOnly: true,
                  ),
                  _buildTextField(
                    controller.taxController,
                    'Tax Amount',
                    Icons.percent,
                    keyboardType: TextInputType.number,
                  ),
                  _buildTextField(
                    controller.totalInclTaxController,
                    'Total Incl Tax',
                    Icons.receipt_long,
                    readOnly: true,
                  ),
                ]),

                const SizedBox(height: 32),

                // Action Buttons
                Obx(
                  () => Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: controller.isLoading.value
                              ? null
                              : controller.previewReceipt,
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
                          onPressed: controller.isLoading.value
                              ? null
                              : controller.saveReceiptData,
                          icon: controller.isLoading.value
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black87,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: Text(
                            controller.isLoading.value
                                ? 'Saving...'
                                : 'Save Receipt',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFE500),
                            foregroundColor: Colors.black87,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: keyboardType,
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
}
