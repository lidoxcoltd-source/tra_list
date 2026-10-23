import 'package:cloud_firestore/cloud_firestore.dart';

class TaskStatus {
  static const assigned = 'assigned';
  static const inProgress = 'inProgress';
  static const submitted = 'submitted';
  static const approved = 'approved';
  static const returned = 'returned';
  static const cancelled = 'cancelled';
}

class TaskModel {
  TaskModel({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.priority,
    required this.assigneeUid,
    required this.assigneeName,
    required this.assigneeShop,
    required this.createdBy,
    required this.steps,
    required this.progress,
    required this.status,
    this.dueDate,
    this.expectedAmount,
    this.collectedAmount,
    this.collectedAt,
    this.paymentMethod = '',
    this.collectionNote = '',
    this.reviewNote = '',
    this.createdAt,
    this.updatedAt,
    this.submittedAt,
    this.approvedAt,
    this.transactionId,
  });

  final String id;
  final String title;
  final String description;
  final String type; // 'task' | 'collection'
  final String priority; // 'low' | 'normal' | 'high'
  final String assigneeUid;
  final String assigneeName;
  final String assigneeShop;
  final String createdBy;
  final List<String> steps;
  final Map<String, Map<String, dynamic>> progress;
  final String status;
  final DateTime? dueDate;
  final double? expectedAmount;
  final double? collectedAmount;
  final DateTime? collectedAt;
  final String paymentMethod;
  final String collectionNote;
  final String reviewNote;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? submittedAt;
  final DateTime? approvedAt;
  final String? transactionId;

  bool get isCollection => type == 'collection';
  bool get isFinal =>
      status == TaskStatus.approved || status == TaskStatus.cancelled;
  bool get staffCanWork =>
      status == TaskStatus.assigned ||
      status == TaskStatus.inProgress ||
      status == TaskStatus.returned;
  bool get isOverdue =>
      dueDate != null && staffCanWork && dueDate!.isBefore(DateTime.now());
  int get doneCount => progress.length;
  bool get allStepsDone => doneCount >= steps.length;
  double get progressFraction => steps.isEmpty
      ? (status == TaskStatus.approved || status == TaskStatus.submitted
            ? 1
            : 0)
      : (doneCount / steps.length).clamp(0, 1).toDouble();
  double? get difference => (expectedAmount != null && collectedAmount != null)
      ? collectedAmount! - expectedAmount!
      : null;

  bool isStepDone(int index) => progress.containsKey('$index');

  static DateTime? _date(dynamic value) =>
      value is Timestamp ? value.toDate() : null;

  factory TaskModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawProgress = data['progress'];
    return TaskModel(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      type: data['type'] == 'collection' ? 'collection' : 'task',
      priority: (data['priority'] ?? 'normal').toString(),
      assigneeUid: (data['assigneeUid'] ?? '').toString(),
      assigneeName: (data['assigneeName'] ?? '').toString(),
      assigneeShop: (data['assigneeShop'] ?? '').toString(),
      createdBy: (data['createdBy'] ?? '').toString(),
      steps: [
        for (final step in (data['steps'] as List? ?? const []))
          step.toString(),
      ],
      progress: rawProgress is Map
          ? {
              for (final entry in rawProgress.entries)
                entry.key.toString(): entry.value is Map
                    ? Map<String, dynamic>.from(entry.value as Map)
                    : <String, dynamic>{},
            }
          : {},
      status: (data['status'] ?? TaskStatus.assigned).toString(),
      dueDate: _date(data['dueDate']),
      expectedAmount: (data['expectedAmount'] as num?)?.toDouble(),
      collectedAmount: (data['collectedAmount'] as num?)?.toDouble(),
      collectedAt: _date(data['collectedAt']),
      paymentMethod: (data['paymentMethod'] ?? '').toString(),
      collectionNote: (data['collectionNote'] ?? '').toString(),
      reviewNote: (data['reviewNote'] ?? '').toString(),
      createdAt: _date(data['createdAt']),
      updatedAt: _date(data['updatedAt']),
      submittedAt: _date(data['submittedAt']),
      approvedAt: _date(data['approvedAt']),
      transactionId: data['transactionId']?.toString(),
    );
  }
}

class TaskHistoryEntry {
  TaskHistoryEntry({
    required this.action,
    required this.actorName,
    required this.note,
    required this.createdAt,
  });

  final String action;
  final String actorName;
  final String note;
  final DateTime? createdAt;
}
