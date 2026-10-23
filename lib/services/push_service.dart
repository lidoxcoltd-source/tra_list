import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      if (token != null) await _saveIfNeeded(user.uid, token);
      if (!_listening) {
        _listening = true;
        messaging.onTokenRefresh.listen(
          (t) {
            final u = FirebaseAuth.instance.currentUser;
            if (u != null) _saveIfNeeded(u.uid, t);
          },
          onError: (Object error) {
            debugPrint('Push token refresh failed: $error');
          },
        );
      }
    } catch (error) {
      debugPrint('Push registration skipped: $error');
    }
  }

  static Future<void> _saveIfNeeded(String uid, String token) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'push_device_token_$uid';
    if (prefs.getString(key) == token) return;
    await FirebaseFirestore.instance.collection('deviceTokens').doc(token).set({
      'uid': uid,
      'platform': 'android',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await prefs.setString(key, token);
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
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('push_device_token_${user.uid}');
      }
    } catch (error) {
      debugPrint('Push unregister skipped: $error');
    }
  }
}
