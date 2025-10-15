import 'package:flutter/material.dart';

enum PaymentStatus { NotPaid, AdvancePaid, FullyPaid }

enum JobStatus { Pending, InProgress, Completed }

class Job {
  final String id;
  final String customerName;
  final String jobType;
  final String customerPhone;
  final double totalCost;
  final double advancePaid;
  final DateTime startDate;
  final DateTime dueDate;
  bool isImportant;
  JobStatus status;

  Job({
    required this.id,
    required this.customerName,
    required this.jobType,
    required this.customerPhone,
    required this.totalCost,
    this.advancePaid = 0.0,
    required this.startDate,
    required this.dueDate,
    this.isImportant = false,
    this.status = JobStatus.Pending,
  });

  PaymentStatus get paymentStatus {
    if (advancePaid >= totalCost && totalCost > 0) {
      return PaymentStatus.FullyPaid;
    } else if (advancePaid > 0) {
      return PaymentStatus.AdvancePaid;
    } else {
      return PaymentStatus.NotPaid;
    }
  }

  Duration get remainingTime {
    final now = DateTime.now();
    if (dueDate.isBefore(now) && status != JobStatus.Completed) {
      return Duration.zero; // Overdue
    }
    return dueDate.difference(now);
  }

  bool get isDueSoon {
    return remainingTime.inHours < 24 &&
        remainingTime > Duration.zero &&
        status != JobStatus.Completed;
  }
}
