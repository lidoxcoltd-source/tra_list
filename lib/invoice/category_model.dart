import 'package:cloud_firestore/cloud_firestore.dart';
import 'transaction_model.dart'; // Reusing TransactionType enum

class CategoryModel {
  final String? id;
  final String name;
  final TransactionType type;

  CategoryModel({this.id, required this.name, required this.type});

  factory CategoryModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CategoryModel(
      id: doc.id,
      name: data['name'] ?? '',
      type: (data['type'] == 'income')
          ? TransactionType.income
          : TransactionType.expense,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'type': type == TransactionType.income ? 'income' : 'expense',
    };
  }

  @override
  String toString() => name;

  @override
  int get hashCode => id.hashCode;
}
