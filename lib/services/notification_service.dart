import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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
  });

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

  static Stream<List<AppNotification>> watchActivity() {
    if (!BusinessAccessService.isOwner.value) return Stream.value(const []);
    return _ownerCollection()
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) {
            final data = doc.data();
            final actor = (data['actorName'] ?? '').toString();
            return AppNotification(
              id: doc.id,
              title: actor,
              body: (data['summary'] ?? '').toString(),
              action: (data['action'] ?? '').toString(),
              createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
              read: data['read'] == true,
              isAnnouncement: false,
            );
          }).toList(),
        );
  }

  static Stream<List<AppNotification>> watchAnnouncements() {
    return _db
        .collection('announcements')
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots()
        .map((snap) {
          final now = DateTime.now();
          return snap.docs
              .where((doc) {
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
                );
              })
              .toList();
        });
  }

  static Future<void> markRead(String id) =>
      _ownerCollection().doc(id).update({'read': true});

  static Future<void> markAllRead(List<AppNotification> items) async {
    final unread = items.where((n) => !n.isAnnouncement && !n.read);
    final batch = _db.batch();
    var count = 0;
    for (final item in unread.take(400)) {
      batch.update(_ownerCollection().doc(item.id), {'read': true});
      count++;
    }
    if (count > 0) await batch.commit();
  }

  static Future<void> delete(String id) => _ownerCollection().doc(id).delete();

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
  }) {
    return _db.collection('announcements').add({
      'title': title.trim(),
      'body': body.trim(),
      'audience': 'all',
      'createdAt': FieldValue.serverTimestamp(),
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
      'createdBy': FirebaseAuth.instance.currentUser?.uid,
    });
  }

  static Future<void> deleteAnnouncement(String id) =>
      _db.collection('announcements').doc(id).delete();
}
