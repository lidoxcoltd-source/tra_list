import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'transaction_model.dart';
import 'transaction_service.dart';

class DeletedTransactionsPage extends StatefulWidget {
  const DeletedTransactionsPage({super.key});

  @override
  State<DeletedTransactionsPage> createState() =>
      _DeletedTransactionsPageState();
}

class _DeletedTransactionsPageState extends State<DeletedTransactionsPage> {
  late Future<List<TransactionModel>> _transactions;

  @override
  void initState() {
    super.initState();
    _transactions = TransactionService.getDeletedTransactions();
  }

  void _refresh() => setState(() {
    _transactions = TransactionService.getDeletedTransactions();
  });

  Future<void> _restore(TransactionModel transaction) async {
    if (!BusinessAccessService.can('transactions', 'delete') ||
        transaction.id == null) {
      return;
    }
    try {
      await TransactionService.restoreTransaction(transaction.id!);
      _refresh();
      Get.snackbar('Restored', 'Transaction restored.');
    } catch (error) {
      Get.snackbar('Error', 'Could not restore transaction: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Deleted transactions')),
    body: FutureBuilder<List<TransactionModel>>(
      future: _transactions,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Could not load deleted transactions: ${snapshot.error}'));
        }
        final transactions = snapshot.data ?? const <TransactionModel>[];
        if (transactions.isEmpty) {
          return const Center(child: Text('No deleted transactions.'));
        }
        final canRestore = BusinessAccessService.can('transactions', 'delete');
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView.builder(
            itemCount: transactions.length,
            itemBuilder: (context, index) {
              final transaction = transactions[index];
              final deletedAt = transaction.deletedAt!;
              final expiresAt = deletedAt.add(const Duration(days: 30));
              final remaining = expiresAt.difference(DateTime.now()).inDays + 1;
              return ListTile(
                leading: Icon(
                  transaction.type == TransactionType.income
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                  color: transaction.type == TransactionType.income
                      ? Colors.green
                      : Colors.red,
                ),
                title: Text(transaction.description.isEmpty
                    ? transaction.category
                    : transaction.description),
                subtitle: Text(
                  '${DateFormat.yMMMd().format(transaction.date)} · Deleted ${DateFormat.yMMMd().format(deletedAt)} · Expires in $remaining day${remaining == 1 ? '' : 's'}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(NumberFormat('#,##0.##').format(transaction.amount)),
                    if (canRestore)
                      IconButton(
                        tooltip: 'Restore',
                        icon: const Icon(Icons.restore),
                        onPressed: () => _restore(transaction),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    ),
  );
}
