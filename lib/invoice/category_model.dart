import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tra_list/invoice/transaction_model.dart';

class CategoryModel {
  final String? id;
  final String name;
  final TransactionType type;

  CategoryModel({this.id, required this.name, required this.type});

  factory CategoryModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CategoryModel(
      id: doc.id,
      name: data['name'] ?? 'Unnamed',
      type: data['type'] == 'income'
          ? TransactionType.income
          : TransactionType.expense,
    );
  }

  // NEW: Factory to create from a map (for JSON decoding)
  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'],
      name: json['name'] ?? 'Unnamed',
      type: json['type'] == 'income'
          ? TransactionType.income
          : TransactionType.expense,
    );
  }

  // NEW: Method to convert to a map (for JSON encoding)
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type == TransactionType.income ? 'income' : 'expense',
  };
}
