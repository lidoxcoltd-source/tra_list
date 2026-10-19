import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Registers this Android device for push notifications.
/// Web and Windows keep using the in-app notification centre.
class PushService {
  PushService._();

  static bool _listening = false;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static Future<void> register() async {
    if (!_supported) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await messaging.getToken();
      if (token != null) await _save(user.uid, token);
      if (!_listening) {
        _listening = true;
        messaging.onTokenRefresh.listen((t) {
          final u = FirebaseAuth.instance.currentUser;
          if (u != null) _save(u.uid, t);
        });
      }
    } catch (error) {
      debugPrint('Push registration skipped: $error');
    }
  }

  static Future<void> _save(String uid, String token) {
    return FirebaseFirestore.instance.collection('deviceTokens').doc(token).set(
      {
        'uid': uid,
        'platform': 'android',
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  static Future<void> unregister() async {
    if (!_supported) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      final token = await FirebaseMessaging.instance.getToken();
      if (user != null && token != null) {
        await FirebaseFirestore.instance
            .collection('deviceTokens')
            .doc(token)
            .delete();
      }
    } catch (error) {
      debugPrint('Push unregister skipped: $error');
    }
  }
}
