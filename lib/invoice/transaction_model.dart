import 'package:cloud_firestore/cloud_firestore.dart';

enum TransactionType { expense, income }

class TransactionModel {
  final String? id;
  final TransactionType type;
  final String description;
  final double amount;
  final DateTime date;
  final String category;
  final String uid;

  TransactionModel({
    this.id,
    required this.type,
    required this.description,
    required this.amount,
    required this.date,
    required this.category,
    required this.uid,
  });

  factory TransactionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TransactionModel(
      id: doc.id,
      type: (data['type'] == 'income')
          ? TransactionType.income
          : TransactionType.expense,
      description: data['description'] ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      category: data['category'] ?? 'Uncategorized',
      uid: data['uid'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'type': type == TransactionType.income ? 'income' : 'expense',
      'description': description,
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'category': category,
      'uid': uid,
    };
  }
}
