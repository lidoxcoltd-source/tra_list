import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/image_utils.dart';

class CompanyLogoService {
  static const String _logoBytesPrefix = 'company_logo_bytes_';
  static const String _logoSourcePrefix = 'company_logo_source_';

  static String _uidOrThrow() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }
    return user.uid;
  }

  static String _logoBytesKey(String uid) => '$_logoBytesPrefix$uid';
  static String _logoSourceKey(String uid) => '$_logoSourcePrefix$uid';

  static Future<void> setLogoSource(String source) async {
    final uid = _uidOrThrow();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_logoSourceKey(uid), source);
  }

  static Future<String> getLogoSource({String fallback = 'firebase'}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return fallback;

    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_logoSourceKey(user.uid));
    if (source == null || source.isEmpty) return fallback;
    return source;
  }

  static Future<void> saveLocalLogo(Uint8List original) async {
    final uid = _uidOrThrow();
    final compressed = await compressLogoBytes(
      original,
      maxSide: 640,
      jpegQuality: 86,
    );

    final prefs = await SharedPreferences.getInstance();
    final base64 = base64Encode(compressed.bytes);
    await prefs.setString(_logoBytesKey(uid), base64);
    await prefs.setString(_logoSourceKey(uid), 'local');
  }

  static Future<Uint8List?> loadLocalLogoBytes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_logoBytesKey(user.uid));
    if (encoded == null || encoded.isEmpty) return null;

    try {
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearLocalLogo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_logoBytesKey(user.uid));
  }

  static Future<Uint8List?> loadNetworkLogoBytes(String url) async {
    if (url.trim().isEmpty) return null;

    try {
      final bundle = NetworkAssetBundle(Uri.parse(url));
      final data = await bundle.load(url);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> resolveLogoBytes(
    Map<String, dynamic> company,
  ) async {
    final sourceFromCompany = (company['logoSource'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final sourceFromApp = (await getLogoSource()).trim().toLowerCase();
    final preferredSource = sourceFromCompany.isNotEmpty
        ? sourceFromCompany
        : sourceFromApp;

    final url = (company['logoUrl'] ?? '').toString().trim();
    final local = await loadLocalLogoBytes();

    if (preferredSource == 'local') {
      if (local != null) return local;
      if (url.isNotEmpty) return loadNetworkLogoBytes(url);
      return null;
    }

    if (url.isNotEmpty) {
      final network = await loadNetworkLogoBytes(url);
      if (network != null) return network;
    }

    return local;
  }
}
