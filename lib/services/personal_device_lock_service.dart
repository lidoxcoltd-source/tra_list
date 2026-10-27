import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:uuid/uuid.dart';

import '../routes.dart';
import 'business_access_service.dart';

/// Keeps a Personal account active on one device at a time. The most recent
/// device to claim the account wins; the previous device is signed out.
class PersonalDeviceLockService {
  PersonalDeviceLockService._();

  static const _storageKey = 'personal_device_id';
  static final _storage = GetStorage();
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _watch;
  static StreamSubscription<User?>? _authWatch;
  static String? _watchedUid;

  static String get deviceId {
    var id = _storage.read<String>(_storageKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      unawaited(_storage.write(_storageKey, id));
    }
    return id;
  }

  static DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      FirebaseFirestore.instance
          .collection('personalUsers')
          .doc(uid)
          .collection('device')
          .doc('session');

  static Future<int> _authTime(User user) async {
    final token = await user.getIdTokenResult();
    final value = token.claims?['auth_time'];
    if (value is num) return value.toInt();
    throw StateError('Missing auth_time in the ID token.');
  }

  /// Takes over the account for this device and signs out any other device.
  /// Throws when the claim cannot be saved, so callers never continue unlocked.
  static Future<void> claim() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _doc(user.uid).set({
      'deviceId': deviceId,
      'platform': defaultTargetPlatform.name,
      'authTime': await _authTime(user),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _watchFor(user.uid);
  }

  /// Used on app start: claims when unclaimed, signs out when another device
  /// owns the account, and otherwise just starts watching.
  static Future<void> ensure() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snapshot = await _doc(user.uid).get();
      final data = snapshot.data();
      final owner = data?['deviceId'];
      if (!snapshot.exists || owner == null) {
        await claim();
      } else if (owner != deviceId) {
        await _kick();
      } else if (data?['authTime'] != await _authTime(user)) {
        await claim();
      } else {
        _watchFor(user.uid);
      }
    } on FirebaseException catch (error) {
      // The server rejects this session's data access once another device
      // has claimed the account, so treat a denial as being signed out.
      if (error.code == 'permission-denied') {
        await _kick();
      } else {
        debugPrint('Personal device check failed: ${error.code}');
      }
    }
  }

  static void stop() {
    unawaited(_watch?.cancel());
    _watch = null;
    _watchedUid = null;
  }

  static void _watchFor(String uid) {
    if (_watchedUid == uid && _watch != null) return;
    stop();
    _watchedUid = uid;
    _authWatch ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) stop();
    });
    _watch = _doc(uid).snapshots().listen(
      (snapshot) {
        final owner = snapshot.data()?['deviceId'];
        if (snapshot.exists &&
            !snapshot.metadata.hasPendingWrites &&
            owner != null &&
            owner != deviceId) {
          unawaited(_kick());
        }
      },
      onError: (Object error) {
        debugPrint('Device watch error: $error');
        if (error is FirebaseException && error.code == 'permission-denied') {
          unawaited(_kick());
        }
      },
    );
  }

  static Future<void> _kick() async {
    stop();
    await FirebaseAuth.instance.signOut();
    BusinessAccessService.clear();
    Get.offAllNamed(AppRoutes.login);
    Get.snackbar(
      'personal_device_title'.tr,
      'personal_device_signed_out'.tr,
      backgroundColor: Colors.orange.shade800,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 8),
    );
  }
}
