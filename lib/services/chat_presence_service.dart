import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:tra_list/services/business_access_service.dart';

class ChatPresenceService {
  ChatPresenceService._();

  static final _firestore = FirebaseFirestore.instance;
  static Timer? _heartbeat;
  static DocumentReference<Map<String, dynamic>>? _presenceRef;
  static bool _isForeground = true;

  static void setForeground(bool value) {
    _isForeground = value;
    refresh();
  }

  static void refresh() {
    final user = FirebaseAuth.instance.currentUser;
    final businessId = BusinessAccessService.hasBusinessAccess
        ? BusinessAccessService.businessUid.value
        : '';
    if (!_isForeground || user == null || businessId.isEmpty) {
      _stopPresence();
      return;
    }

    final ref = _firestore
        .collection('chatPresence')
        .doc(businessId)
        .collection('members')
        .doc(user.uid);
    if (_presenceRef?.path == ref.path) return;

    _stopPresence();
    _presenceRef = ref;
    _updatePresence(ref, true);
    _heartbeat = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _updatePresence(ref, true),
    );
  }

  static void _stopPresence() {
    _heartbeat?.cancel();
    _heartbeat = null;
    final ref = _presenceRef;
    _presenceRef = null;
    if (ref != null) _updatePresence(ref, false);
  }

  static Future<void> _updatePresence(
    DocumentReference<Map<String, dynamic>> ref,
    bool isOnline,
  ) async {
    try {
      await ref.set({
        'isOnline': isOnline,
        'lastActiveAt': FieldValue.serverTimestamp(),
      });
    } catch (error, stackTrace) {
      debugPrint('Could not update chat presence: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
