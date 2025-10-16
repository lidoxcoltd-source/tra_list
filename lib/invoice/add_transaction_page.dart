import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/invoice/transaction_form.dart';
import 'transaction_model.dart';

class AddTransactionPage extends StatelessWidget {
  final TransactionModel? transaction;
  final TransactionType? initialType;

  const AddTransactionPage({super.key, this.transaction, this.initialType});
  @override
  Widget build(BuildContext context) {
    final isNew = transaction == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isNew ? 'add_transaction_title'.tr : 'edit_transaction_title'.tr,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: TransactionForm(
          transaction: transaction,
          initialType: initialType,
          onSave: () => Get.back(result: true),
          onCancel: () => Get.back(result: false),
        ),
      ),
    );
  }
}
