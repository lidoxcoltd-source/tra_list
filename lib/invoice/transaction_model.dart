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
  final String shopNickname;
  final String recordedByName;
  final DateTime? deletedAt;

  TransactionModel({
    this.id,
    required this.type,
    required this.description,
    required this.amount,
    required this.date,
    required this.category,
    required this.uid,
    this.shopNickname = '',
    this.recordedByName = '',
    this.deletedAt,
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
      shopNickname: data['shopNickname']?.toString() ?? '',
      recordedByName: data['recordedByName']?.toString() ?? '',
      deletedAt: (data['deletedAt'] as Timestamp?)?.toDate(),
    );
  }

  // NEW: Factory to create from a map (for JSON decoding)
  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'],
      type: (json['type'] == 'income')
          ? TransactionType.income
          : TransactionType.expense,
      description: json['description'] ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      // Handle both Timestamp and ISO8601 string for date
      date: json['date'] is String
          ? DateTime.parse(json['date'])
          : (json['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      category: json['category'] ?? 'Uncategorized',
      uid: json['uid'] ?? '',
      shopNickname: json['shopNickname']?.toString() ?? '',
      recordedByName: json['recordedByName']?.toString() ?? '',
      deletedAt: json['deletedAt'] is String
          ? DateTime.tryParse(json['deletedAt'] as String)
          : (json['deletedAt'] as Timestamp?)?.toDate(),
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
      'shopNickname': shopNickname,
      'recordedByName': recordedByName,
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
    };
  }

  // NEW: Method to convert to a map (for JSON encoding)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type == TransactionType.income ? 'income' : 'expense',
      'description': description,
      'amount': amount,
      'date': date.toIso8601String(), // Use ISO8601 for JSON compatibility
      'category': category,
      'uid': uid,
      'shopNickname': shopNickname,
      'recordedByName': recordedByName,
      'deletedAt': deletedAt?.toIso8601String(),
    };
  }
}
