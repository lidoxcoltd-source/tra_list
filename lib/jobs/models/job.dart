import 'package:cloud_firestore/cloud_firestore.dart';

class Job {
  final String id;
  String customerName; // Changed from clientName to customerName
  String jobType;
  String phonePrimary;
  String? phoneSecondary;
  double totalAmount;
  double advancePaid;
  DateTime startDate;
  DateTime dueDate;
  bool isImportant;
  bool isCompleted;
  bool paymentRecorded;
  DateTime createdAt;
  DateTime updatedAt;

  Job({
    String? id,
    required this.customerName,
    required this.jobType,
    required this.phonePrimary,
    this.phoneSecondary,
    required this.totalAmount,
    required this.advancePaid,
    required this.startDate,
    required this.dueDate,
    this.isImportant = false,
    this.isCompleted = false,
    this.paymentRecorded = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  double get paid => advancePaid.clamp(0, totalAmount);
  double get balance => (totalAmount - paid).clamp(0, double.infinity);
  bool get paidInFull => balance == 0;

  int get remainingDays {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return due.difference(today).inDays;
  }

  bool get isOverdue => !isCompleted && remainingDays < 0;
  bool get dueToday => !isCompleted && remainingDays == 0;
  bool get dueDanger => !isCompleted && remainingDays == 1;
  bool get dueWarning =>
      !isCompleted && remainingDays >= 2 && remainingDays <= 3;

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'customerName': customerName,
    'jobType': jobType,
    'phonePrimary': phonePrimary,
    'phoneSecondary': phoneSecondary,
    'totalAmount': totalAmount,
    'advancePaid': advancePaid,
    'startDate': Timestamp.fromDate(startDate),
    'dueDate': Timestamp.fromDate(dueDate),
    'isImportant': isImportant,
    'isCompleted': isCompleted,
    'paymentRecorded': paymentRecorded,
    'createdAt': createdAt, // Keep original value
    'updatedAt': updatedAt, // Keep original value
  };

  factory Job.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final map = snapshot.data()!;
    return Job(
      id: snapshot.id,
      customerName: map['customerName'] ?? '',
      jobType: map['jobType'] ?? '',
      phonePrimary: map['phonePrimary'] ?? '',
      phoneSecondary: map['phoneSecondary'],
      totalAmount: (map['totalAmount'] as num?)?.toDouble() ?? 0.0,
      advancePaid: (map['advancePaid'] as num?)?.toDouble() ?? 0.0,
      startDate: (map['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      dueDate: (map['dueDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isImportant: map['isImportant'] ?? false,
      isCompleted: map['isCompleted'] ?? false,
      paymentRecorded: map['paymentRecorded'] ?? false,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  // Kept for potential local use if needed, but not for Firestore.
  Map<String, dynamic> toMap() => {
    ...toFirestore(),
    'startDate': startDate.toIso8601String(),
    'dueDate': dueDate.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}
