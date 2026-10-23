import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tra_list/services/business_access_service.dart';

import 'task_model.dart';

class TaskService {
  TaskService._();

  static final _db = FirebaseFirestore.instance;

  static String get _uid => FirebaseAuth.instance.currentUser!.uid;

  static String get currentUid => _uid;

  static String get actorName {
    final user = FirebaseAuth.instance.currentUser;
    final name = (user?.displayName ?? '').trim();
    return name.isNotEmpty ? name : (user?.email ?? 'User');
  }

  static DocumentReference<Map<String, dynamic>> get _business =>
      _db.collection('users').doc(BusinessAccessService.businessId);

  static CollectionReference<Map<String, dynamic>> get _tasks =>
      _business.collection('tasks');

  // Assigning is owner-only because only the owner can list staff accounts.
  static bool get canAssign => BusinessAccessService.isOwner.value;
  static bool get canViewAll => BusinessAccessService.can('tasks', 'view');
  static bool get canReview => BusinessAccessService.can('tasks', 'edit');
  static bool get canDelete => BusinessAccessService.can('tasks', 'delete');

  static bool isAssignee(TaskModel task) => task.assigneeUid == _uid;

  static Stream<List<TaskModel>> watchTasks() {
    final Query<Map<String, dynamic>> query = canViewAll
        ? _tasks.orderBy('createdAt', descending: true).limit(300)
        : _tasks.where('assigneeUid', isEqualTo: _uid).limit(300);
    return query.snapshots().map((snap) {
      final list = snap.docs.map(TaskModel.fromDoc).toList();
      list.sort(
        (a, b) => (b.createdAt ?? DateTime.now()).compareTo(
          a.createdAt ?? DateTime.now(),
        ),
      );
      return list;
    });
  }

  static Future<int> activeCount() async {
    final list = await watchTasks().first;
    return list.where((t) => !t.isFinal).length;
  }

  static Stream<TaskModel?> watchTask(String id) => _tasks
      .doc(id)
      .snapshots()
      .map((doc) => doc.exists ? TaskModel.fromDoc(doc) : null);

  static Stream<List<TaskHistoryEntry>> watchHistory(String id) => _tasks
      .doc(id)
      .collection('history')
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map(
        (snap) => snap.docs.map((doc) {
          final data = doc.data();
          return TaskHistoryEntry(
            action: (data['action'] ?? '').toString(),
            actorName: (data['actorName'] ?? '').toString(),
            note: (data['note'] ?? '').toString(),
            createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
          );
        }).toList(),
      );

  static Future<void> _log(
    String taskId,
    String action, [
    String note = '',
  ]) async {
    try {
      await _tasks.doc(taskId).collection('history').add({
        'actorUid': _uid,
        'actorName': actorName,
        'action': action,
        'note': note.length > 300 ? note.substring(0, 300) : note,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // History is an audit aid; it must never block the task action.
    }
  }

  static Future<void> create({
    required String title,
    required String description,
    required String type,
    required String priority,
    required String assigneeUid,
    required String assigneeName,
    required String assigneeShop,
    required List<String> steps,
    DateTime? dueDate,
    double? expectedAmount,
  }) async {
    if (!canAssign) throw StateError('Only the owner can assign tasks.');
    final ref = _tasks.doc();
    await ref.set({
      'title': title,
      'description': description,
      'type': type,
      'priority': priority,
      'assigneeUid': assigneeUid,
      'assigneeName': assigneeName,
      'assigneeShop': assigneeShop,
      'createdBy': _uid,
      'steps': steps,
      'progress': <String, dynamic>{},
      'status': TaskStatus.assigned,
      if (dueDate != null) 'dueDate': Timestamp.fromDate(dueDate),
      if (type == 'collection' && expectedAmount != null)
        'expectedAmount': expectedAmount,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _log(ref.id, 'created');
  }

  static Future<void> updateDetails(
    TaskModel task, {
    required String title,
    required String description,
    required String type,
    required String priority,
    required List<String> steps,
    DateTime? dueDate,
    double? expectedAmount,
  }) async {
    if (!canAssign) throw StateError('Only the owner can edit tasks.');
    await _tasks.doc(task.id).update({
      'title': title,
      'description': description,
      'type': type,
      'priority': priority,
      if (task.progress.isEmpty) 'steps': steps,
      'dueDate': dueDate == null
          ? FieldValue.delete()
          : Timestamp.fromDate(dueDate),
      'expectedAmount': type == 'collection' && expectedAmount != null
          ? expectedAmount
          : FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _log(task.id, 'edited');
  }

  static Future<void> setStep(TaskModel task, int index, bool done) async {
    if (!isAssignee(task) || !task.staffCanWork) {
      throw StateError('You cannot change this task.');
    }
    await _tasks.doc(task.id).update({
      'progress.$index': done
          ? {
              'doneAt': FieldValue.serverTimestamp(),
              'doneBy': _uid,
              'doneByName': actorName,
            }
          : FieldValue.delete(),
      'status': TaskStatus.inProgress,
      if (task.status == TaskStatus.assigned)
        'startedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _log(task.id, done ? 'step_done' : 'step_undone', task.steps[index]);
  }

  static Future<void> submit(
    TaskModel task, {
    double? collectedAmount,
    String paymentMethod = '',
    String note = '',
    DateTime? collectedAt,
  }) async {
    if (!isAssignee(task) || !task.staffCanWork) {
      throw StateError('You cannot submit this task.');
    }
    if (!task.allStepsDone) throw StateError('Complete all steps first.');
    if (task.isCollection && collectedAmount == null) {
      throw ArgumentError('Enter the amount collected.');
    }
    await _tasks.doc(task.id).update({
      'status': TaskStatus.submitted,
      'submittedAt': FieldValue.serverTimestamp(),
      if (task.isCollection) ...{
        'collectedAmount': collectedAmount,
        'collectedAt': Timestamp.fromDate(collectedAt ?? DateTime.now()),
        'paymentMethod': paymentMethod,
        'collectionNote': note.trim(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _log(
      task.id,
      'submitted',
      task.isCollection ? 'collected: $collectedAmount' : '',
    );
  }

  static Future<void> approve(TaskModel task, {String note = ''}) async {
    _requireReviewer(task);
    await _tasks.doc(task.id).update({
      'status': TaskStatus.approved,
      'reviewNote': note.trim(),
      'reviewedBy': _uid,
      'approvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _log(task.id, 'approved', note);
  }

  static Future<void> returnForCorrection(
    TaskModel task, {
    required String note,
  }) async {
    _requireReviewer(task);
    await _tasks.doc(task.id).update({
      'status': TaskStatus.returned,
      'reviewNote': note.trim(),
      'reviewedBy': _uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _log(task.id, 'returned', note);
  }

  static Future<void> cancel(TaskModel task) async {
    _requireReviewer(task);
    await _tasks.doc(task.id).update({
      'status': TaskStatus.cancelled,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _log(task.id, 'cancelled');
  }

  static Future<void> delete(TaskModel task) async {
    if (!canDelete) throw StateError('You cannot delete tasks.');
    await _tasks.doc(task.id).delete();
  }

  static void _requireReviewer(TaskModel task) {
    if (!canReview) throw StateError('You cannot review tasks.');
    if (isAssignee(task)) {
      throw StateError('You cannot review your own task.');
    }
  }

  /// Records the approved collection as income exactly once. The transaction
  /// id is derived from the task id, so retries can never create a duplicate.
  static Future<bool> recordAsIncome(TaskModel task) async {
    if (!BusinessAccessService.isOwner.value) {
      throw StateError('Only the owner can record income.');
    }
    final taskRef = _tasks.doc(task.id);
    final txRef = _business.collection('transactions').doc('task_${task.id}');
    final created = await _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(taskRef);
      final data = snap.data();
      if (data == null) throw StateError('Task not found.');
      if (data['status'] != TaskStatus.approved) {
        throw StateError('Approve the task first.');
      }
      if ((data['transactionId'] ?? '').toString().isNotEmpty) return false;
      final amount = (data['collectedAmount'] as num?)?.toDouble() ?? 0;
      if (amount <= 0) throw StateError('Nothing was collected.');
      final existing = await tx.get(txRef);
      if (!existing.exists) {
        tx.set(txRef, {
          'type': 'income',
          'description': 'Task: ${data['title']}',
          'amount': amount,
          'date': data['collectedAt'] ?? Timestamp.now(),
          'category': 'Task collection',
          'uid': data['assigneeUid'],
          'shopNickname': data['assigneeShop'] ?? '',
          'taskId': task.id,
        });
      }
      tx.update(taskRef, {
        'transactionId': txRef.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (created) await _log(task.id, 'income_recorded');
    return created;
  }
}
