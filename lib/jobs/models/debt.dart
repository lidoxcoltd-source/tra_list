import 'package:cloud_firestore/cloud_firestore.dart';

enum DebtDirection { customerOwesShop, shopOwesOther }

class Debt {
  final String id;
  final String debtorName;
  final String phone;
  final DebtDirection direction;
  final String reason;
  final String notes;
  final double principal;
  final double amountPaid;
  final DateTime? dueDate;
  final String shopNickname;
  final DateTime createdAt;
  final DateTime updatedAt;

  Debt({
    String? id,
    required this.debtorName,
    required this.phone,
    required this.direction,
    required this.reason,
    this.notes = '',
    required this.principal,
    this.amountPaid = 0,
    this.dueDate,
    required this.shopNickname,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  double get balance => (principal - amountPaid).clamp(0, double.infinity);
  bool get isSettled => balance <= 0;
  bool get isOverdue =>
      !isSettled &&
      dueDate != null &&
      DateTime(
        dueDate!.year,
        dueDate!.month,
        dueDate!.day,
      ).isBefore(DateTime.now().dateOnly);

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'debtorName': debtorName,
    'phone': phone,
    'direction': direction.name,
    'reason': reason,
    'notes': notes,
    'principal': principal,
    'amountPaid': amountPaid,
    'dueDate': dueDate == null ? null : Timestamp.fromDate(dueDate!),
    'shopNickname': shopNickname,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  factory Debt.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data()!;
    final direction = DebtDirection.values.firstWhere(
      (value) => value.name == data['direction'],
      orElse: () => DebtDirection.customerOwesShop,
    );
    return Debt(
      id: snapshot.id,
      debtorName: data['debtorName']?.toString() ?? '',
      phone: data['phone']?.toString() ?? '',
      direction: direction,
      reason: data['reason']?.toString() ?? 'other',
      notes: data['notes']?.toString() ?? '',
      principal: (data['principal'] as num?)?.toDouble() ?? 0,
      amountPaid: (data['amountPaid'] as num?)?.toDouble() ?? 0,
      dueDate: (data['dueDate'] as Timestamp?)?.toDate(),
      shopNickname: data['shopNickname']?.toString() ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

extension on DateTime {
  DateTime get dateOnly => DateTime(year, month, day);
}

class DebtPayment {
  final String id;
  final double amount;
  final DateTime paidAt;
  final String method;
  final String notes;
  final String recordedBy;

  const DebtPayment({
    required this.id,
    required this.amount,
    required this.paidAt,
    required this.method,
    required this.notes,
    required this.recordedBy,
  });

  factory DebtPayment.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data()!;
    return DebtPayment(
      id: snapshot.id,
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      paidAt: (data['paidAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      method: data['method']?.toString() ?? 'other',
      notes: data['notes']?.toString() ?? '',
      recordedBy: data['recordedBy']?.toString() ?? '',
    );
  }
}
