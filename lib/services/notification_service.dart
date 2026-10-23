import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'business_access_service.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.action,
    required this.createdAt,
    required this.read,
    required this.isAnnouncement,
    this.imageUrl,
    this.sentCount,
    this.failureCount,
    this.taskId,
    this.isInbox = false,
  });

  final String? imageUrl;
  final int? sentCount;
  final int? failureCount;
  final String? taskId;

  /// True for items from the per-user task inbox (userNotifications/{uid}/items).
  final bool isInbox;
  final String id;
  final String title;
  final String body;
  final String action;
  final DateTime? createdAt;
  final bool read;
  final bool isAnnouncement;
}

class NotificationService {
  NotificationService._();

  static final _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _ownerCollection() => _db
      .collection('users')
      .doc(BusinessAccessService.businessId)
      .collection('notifications');

  /// Tells the business owner that a staff member changed something.
  /// Never throws: a failed notification must not break the staff action.
  static Future<void> notifyOwner({
    required String action,
    required String summary,
    double? amount,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || BusinessAccessService.isOwner.value) return;
      final name = (user.displayName ?? '').trim();
      final actor = name.isNotEmpty ? name : (user.email ?? 'Staff');
      await _ownerCollection().add({
        'actorUid': user.uid,
        'actorName': actor,
        'action': action,
        'summary': summary.length > 300 ? summary.substring(0, 300) : summary,
        if (amount != null) 'amount': amount,
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
      });
    } catch (error) {
      debugPrint('Notification skipped: $error');
    }
  }

  /// Low / out-of-stock alert for the business owner. Unlike [notifyOwner]
  /// it is also delivered when the owner caused the change.
  static Future<void> stockAlert(String summary) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final name = (user.displayName ?? '').trim();
    await _ownerCollection().add({
      'actorUid': user.uid,
      'actorName': name.isNotEmpty ? name : (user.email ?? 'Stock'),
      'action': 'stock',
      'summary': summary.length > 300 ? summary.substring(0, 300) : summary,
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });
  }

  static CollectionReference<Map<String, dynamic>>? _inboxCollection() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return _db.collection('userNotifications').doc(uid).collection('items');
  }

  static Stream<List<AppNotification>> _watchOwnerActivity() {
    if (!BusinessAccessService.isOwner.value) return Stream.value(const []);
    return _ownerCollection()
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) {
            final data = doc.data();
            final actor = (data['actorName'] ?? '').toString();
            final taskId = (data['taskId'] ?? '').toString();
            return AppNotification(
              id: doc.id,
              title: actor,
              body: (data['summary'] ?? '').toString(),
              action: (data['action'] ?? '').toString(),
              createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
              read: data['read'] == true,
              isAnnouncement: false,
              taskId: taskId.isEmpty ? null : taskId,
            );
          }).toList(),
        );
  }

  static Stream<List<AppNotification>> _watchTaskInbox() {
    final col = _inboxCollection();
    if (col == null) return Stream.value(const []);
    return col
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) {
            final data = doc.data();
            final taskId = (data['taskId'] ?? '').toString();
            return AppNotification(
              id: doc.id,
              title: 'tk_all'.tr,
              body: (data['body'] ?? '').toString(),
              action: 'task',
              createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
              read: data['read'] == true,
              isAnnouncement: false,
              taskId: taskId.isEmpty ? null : taskId,
              isInbox: true,
            );
          }).toList(),
        )
        .handleError((Object e) => debugPrint('Task inbox unavailable: $e'));
  }

  /// Staff activity for the owner plus task notifications for every user.
  static Stream<List<AppNotification>> watchActivity() {
    final controller = StreamController<List<AppNotification>>();
    final subs = <StreamSubscription<List<AppNotification>>>[];
    var owner = const <AppNotification>[];
    var inbox = const <AppNotification>[];
    void emit() {
      final merged = [...owner, ...inbox]
        ..sort(
          (a, b) => (b.createdAt ?? DateTime.now()).compareTo(
            a.createdAt ?? DateTime.now(),
          ),
        );
      controller.add(merged);
    }

    controller.onListen = () {
      subs.add(
        _watchOwnerActivity().listen((v) {
          owner = v;
          emit();
        }, onError: controller.addError),
      );
      subs.add(
        _watchTaskInbox().listen((v) {
          inbox = v;
          emit();
        }),
      );
    };
    controller.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
    };
    return controller.stream;
  }

  static String get _hiddenKey =>
      'announcements_hidden_${FirebaseAuth.instance.currentUser?.uid}';

  static Future<Set<String>> hiddenAnnouncements() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_hiddenKey) ?? const <String>[]).toSet();
  }

  /// Announcements are shared by everyone, so "delete" only hides them for this user.
  static Future<void> hideAnnouncement(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_hiddenKey) ?? const <String>[]).toSet()
      ..add(id);
    await prefs.setStringList(_hiddenKey, ids.toList());
  }

  static Stream<List<AppNotification>> watchAnnouncements() {
    return _db
        .collection('announcements')
        .orderBy('createdAt', descending: true)
        .limit(15)
        .snapshots()
        .asyncMap((snap) async {
          final hidden = await hiddenAnnouncements();
          final now = DateTime.now();
          return snap.docs
              .where((doc) {
                if (hidden.contains(doc.id)) return false;
                final expires = (doc.data()['expiresAt'] as Timestamp?)
                    ?.toDate();
                return expires == null || expires.isAfter(now);
              })
              .map((doc) {
                final data = doc.data();
                return AppNotification(
                  id: doc.id,
                  title: (data['title'] ?? '').toString(),
                  body: (data['body'] ?? '').toString(),
                  action: 'announcement',
                  createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
                  read: false,
                  isAnnouncement: true,
                  imageUrl: (data['imageUrl'] as String?)?.isNotEmpty == true
                      ? data['imageUrl'] as String
                      : null,
                  sentCount: (data['sentCount'] as num?)?.toInt(),
                  failureCount: (data['failureCount'] as num?)?.toInt(),
                );
              })
              .toList();
        });
  }

  static DocumentReference<Map<String, dynamic>> _ref(String id, bool inbox) =>
      (inbox ? _inboxCollection()! : _ownerCollection()).doc(id);

  static Future<void> markRead(String id, {bool inbox = false}) =>
      _ref(id, inbox).update({'read': true});

  static Future<void> markAllRead(List<AppNotification> items) async {
    final unread = items.where((n) => !n.isAnnouncement && !n.read);
    final batch = _db.batch();
    var count = 0;
    for (final item in unread.take(400)) {
      batch.update(_ref(item.id, item.isInbox), {'read': true});
      count++;
    }
    if (count > 0) await batch.commit();
  }

  static Future<void> delete(String id, {bool inbox = false}) =>
      _ref(id, inbox).delete();

  static String get _seenKey =>
      'announcements_seen_${FirebaseAuth.instance.currentUser?.uid}';

  static Future<DateTime> lastSeenAnnouncements() async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.fromMillisecondsSinceEpoch(prefs.getInt(_seenKey) ?? 0);
  }

  static Future<void> markAnnouncementsSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seenKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> sendAnnouncement({
    required String title,
    required String body,
    DateTime? expiresAt,
    String? imageUrl,
  }) {
    return _db.collection('announcements').add({
      'title': title.trim(),
      'body': body.trim(),
      'audience': 'all',
      if (imageUrl != null) 'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
      'createdBy': FirebaseAuth.instance.currentUser?.uid,
    });
  }

  static Future<void> deleteAnnouncement(String id) =>
      _db.collection('announcements').doc(id).delete();

  /// Records (once per device) that this user opened the announcements, so the
  /// Super Admin can see how many people were reached. Never throws.
  static Future<void> recordAnnouncementReads(List<String> ids) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || ids.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final key = 'announcements_read_$uid';
      final done = (prefs.getStringList(key) ?? <String>[]).toSet();
      final pending = ids.where((id) => !done.contains(id)).toList();
      for (final id in pending) {
        await _db
            .collection('announcements')
            .doc(id)
            .collection('reads')
            .doc(uid)
            .set({'readAt': FieldValue.serverTimestamp()});
        done.add(id);
      }
      if (pending.isNotEmpty) {
        final list = done.toList();
        await prefs.setStringList(
          key,
          list.length > 200 ? list.sublist(list.length - 200) : list,
        );
      }
    } catch (error) {
      debugPrint('Announcement read skipped: $error');
    }
  }

  static Future<int> announcementReadCount(String id) async {
    final reads = _db.collection('announcements').doc(id).collection('reads');
    try {
      return (await reads.count().get()).count ?? 0;
    } catch (_) {
      return (await reads.get()).docs.length;
    }
  }

  /// Total number of users that have opened the app (analytics baseline).
  static Future<int> totalActiveUsers() async {
    final ref = _db.collection('appActivity');
    try {
      return (await ref.count().get()).count ?? 0;
    } catch (_) {
      return (await ref.get()).docs.length;
    }
  }
}
