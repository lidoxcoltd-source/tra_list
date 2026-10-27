import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'app_version_service.dart';

/// Records when a signed-in person last used the app, for Super Admin stats.
class AppActivityService {
  static DateTime? _lastPing;
  static String? _lastUid;

  static Future<void> ping() async {
    final user = FirebaseAuth.instance.currentUser;
    final platform = AppVersionService.currentPlatform;
    if (user == null || platform == null) return;

    final now = DateTime.now();
    if (_lastUid == user.uid &&
        _lastPing != null &&
        now.difference(_lastPing!) < const Duration(minutes: 15)) {
      return;
    }
    _lastUid = user.uid;
    _lastPing = now;

    try {
      final info = await AppVersionService.installedPackageInfo();
      final ref = FirebaseFirestore.instance
          .collection('appActivity')
          .doc(user.uid);
      final version = '${info.version}+${info.buildNumber}';
      try {
        await ref.update({
          'lastActiveAt': FieldValue.serverTimestamp(),
          'platform': platform,
          'appVersion': version,
          'opens': FieldValue.increment(1),
        });
      } on FirebaseException catch (error) {
        // On a missing document the update rule cannot read the old data and
        // answers permission-denied, so fall back to create in that case too.
        if (error.code != 'not-found' && error.code != 'permission-denied') {
          rethrow;
        }
        await ref.set({
          'firstSeenAt': FieldValue.serverTimestamp(),
          'lastActiveAt': FieldValue.serverTimestamp(),
          'platform': platform,
          'appVersion': version,
          'opens': 1,
        });
      }
    } catch (error) {
      _lastPing = null;
      debugPrint('Could not record app activity: $error');
    }
  }
}
