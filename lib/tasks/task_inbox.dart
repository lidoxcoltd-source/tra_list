import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'task_detail_page.dart';
import 'task_ui.dart';

/// Per-user in-app inbox written by Cloud Functions at userNotifications/{uid}/items.
class TaskInbox {
  TaskInbox._();

  static CollectionReference<Map<String, dynamic>>? get _items {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('userNotifications')
        .doc(uid)
        .collection('items');
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watch() =>
      _items?.orderBy('createdAt', descending: true).limit(100).snapshots() ??
      const Stream.empty();

  static Future<void> markAllRead(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final unread = docs.where((d) => d.data()['read'] != true).toList();
    if (unread.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final d in unread) {
      batch.update(d.reference, {'read': true});
    }
    await batch.commit();
  }
}

/// Bell icon with an unread counter.
class TaskBell extends StatelessWidget {
  const TaskBell({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: TaskInbox.watch(),
      builder: (context, snap) {
        final unread =
            snap.data?.docs.where((d) => d.data()['read'] != true).length ?? 0;
        return IconButton(
          tooltip: 'tk_inbox'.tr,
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const TaskInboxPage())),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: const Icon(Icons.notifications_none_rounded),
          ),
        );
      },
    );
  }
}

class TaskInboxPage extends StatelessWidget {
  const TaskInboxPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TaskColors.canvas,
      appBar: AppBar(
        backgroundColor: TaskColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('tk_inbox'.tr),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: TaskInbox.watch(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('tk_error'.tr));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return Center(child: Text('tk_inbox_empty'.tr));
          }
          final hasUnread = docs.any((d) => d.data()['read'] != true);
          return Column(
            children: [
              if (hasUnread)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => TaskInbox.markAllRead(docs),
                    icon: const Icon(Icons.done_all_rounded),
                    label: Text('tk_mark_all'.tr),
                  ),
                ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: docs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _tile(context, docs[i]),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    final unread = d['read'] != true;
    final ts = d['createdAt'];
    final taskId = (d['taskId'] ?? '').toString();
    return Dismissible(
      key: ValueKey('inbox_${doc.id}'),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: TaskColors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.white),
            Icon(Icons.delete_outline_rounded, color: Colors.white),
          ],
        ),
      ),
      onDismissed: (_) => doc.reference.delete(),
      child: Material(
        color: unread ? const Color(0xFFEFF6FF) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (unread) doc.reference.update({'read': true});
            if (taskId.isNotEmpty) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TaskDetailPage(taskId: taskId),
                ),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  d['kind'] == 'overdue'
                      ? Icons.alarm_rounded
                      : Icons.task_alt_rounded,
                  color: d['kind'] == 'overdue'
                      ? const Color(0xFFDC2626)
                      : TaskColors.brand,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (d['body'] ?? '').toString(),
                        style: TextStyle(
                          fontWeight: unread
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      if (ts is Timestamp) ...[
                        const SizedBox(height: 4),
                        Text(
                          TaskUi.date(ts.toDate()),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (unread)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: CircleAvatar(
                      radius: 5,
                      backgroundColor: TaskColors.brand,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
