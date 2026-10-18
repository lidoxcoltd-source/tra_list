import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/invoice/add_transaction_controller.dart';
import 'package:tra_list/invoice/transaction_form.dart';
import 'transaction_model.dart';

class AddTransactionPage extends StatefulWidget {
  final TransactionModel? transaction;
  final TransactionType? initialType;

  const AddTransactionPage({super.key, this.transaction, this.initialType});

  @override
  State<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends State<AddTransactionPage> {
  late final AddTransactionController controller;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Create a unique controller instance for this page.
    // It will be automatically disposed by GetX when the page is popped.
    controller = Get.put(
      AddTransactionController(
        transaction: widget.transaction,
        initialType: widget.initialType,
      ),
      // Use a unique tag to prevent conflicts if multiple forms are open.
      tag: 'transaction_form_${widget.transaction?.id ?? 'new'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.transaction == null;
    const canvas = Color(0xFFF4F7F7);

    return Scaffold(
      backgroundColor: canvas,
      appBar: AppBar(
        backgroundColor: canvas,
        foregroundColor: const Color(0xFF19313A),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: Text(
          isNew ? 'add_transaction_title'.tr : 'edit_transaction_title'.tr,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 19),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TransactionForm(
                controller: controller,
                isSaving: _isSaving,
                onSave: (saveAction) async {
                  setState(() => _isSaving = true);
                  try {
                    await saveAction();
                    if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();
                    Get.back(result: true);
                  } finally {
                    if (mounted) setState(() => _isSaving = false);
                  }
                },
                onCancel: () => Get.back(result: false),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
