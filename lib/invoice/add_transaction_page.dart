import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final isNew = widget.transaction == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isNew ? 'add_transaction_title'.tr : 'edit_transaction_title'.tr,
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: TransactionForm(
          transaction: widget.transaction,
          initialType: widget.initialType,
          isSaving: _isSaving, // Pass saving state to the form
          onSave: (saveAction) async {
            setState(() => _isSaving = true);
            try {
              await saveAction(); // Execute the save logic from the form
              // The controller now handles the snackbar and navigation.
              // The onSave in the form will trigger the controller's save, which then closes the page.
              // For mobile, we need to explicitly close.
              if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();
              Get.back(result: true); // This was missing.
            } finally {
              if (mounted) setState(() => _isSaving = false);
            }
          },
          onCancel: () => Get.back(result: false),
        ),
      ),
    );
  }
}
