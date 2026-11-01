import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'business_access_service.dart';
import 'profile_service.dart';
import '../utils/image_utils.dart';

class CompanyLogoService {
  static const String _logoBytesPrefix = 'company_logo_bytes_';
  static const String _logoSourcePrefix = 'company_logo_source_';
  static String? _cachedNetworkLogoUrl;
  static Uint8List? _cachedNetworkLogoBytes;

  static Uint8List? tryDecodeInlineImageBytes(String url) {
    final trimmed = url.trim();
    if (!trimmed.startsWith('data:image/')) return null;

    try {
      return UriData.parse(trimmed).contentAsBytes();
    } catch (_) {
      return null;
    }
  }

  static bool isLocalOnlyImageUrl(String url) {
    final trimmed = url.trim();
    final lower = trimmed.toLowerCase();
    return lower.startsWith('blob:') ||
        lower.startsWith('file:') ||
        trimmed.startsWith(r'\\') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(trimmed);
  }

  static Future<SharedPreferences?> _prefsSafe() async {
    try {
      return await SharedPreferences.getInstance();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

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
    final prefs = await _prefsSafe();
    if (prefs == null) return;
    await prefs.setString(_logoSourceKey(uid), source);
  }

  static Future<String> getLogoSource({String fallback = 'firebase'}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return fallback;

    final prefs = await _prefsSafe();
    if (prefs == null) return fallback;
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

    final prefs = await _prefsSafe();
    if (prefs == null) return;
    final base64 = base64Encode(compressed.bytes);
    await prefs.setString(_logoBytesKey(uid), base64);
    await prefs.setString(_logoSourceKey(uid), 'local');
  }

  static Future<Uint8List?> loadLocalLogoBytes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final prefs = await _prefsSafe();
    if (prefs == null) return null;
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

    final prefs = await _prefsSafe();
    if (prefs == null) return;
    await prefs.remove(_logoBytesKey(user.uid));
    await prefs.remove(_logoSourceKey(user.uid));
  }

  static Future<Uint8List?> loadNetworkLogoBytes(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    final inlineBytes = tryDecodeInlineImageBytes(trimmed);
    if (inlineBytes != null) return inlineBytes;

    if (isLocalOnlyImageUrl(trimmed)) {
      return loadLocalLogoBytes();
    }

    try {
      final bundle = NetworkAssetBundle(Uri.parse(trimmed));
      final data = await bundle.load(trimmed);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> resolveLogoBytes(
    Map<String, dynamic> company,
  ) async {
    var url = (company['logoUrl'] ?? '').toString().trim();
    if (FirebaseAuth.instance.currentUser != null &&
        BusinessAccessService.canReadBusinessProfile()) {
      final profile = await ProfileService.loadOrCreate();
      url = (profile['logoUrl'] ?? '').toString().trim();
    }
    if (url.isEmpty) return null;
    if (url == _cachedNetworkLogoUrl) return _cachedNetworkLogoBytes;

    final bytes = await loadNetworkLogoBytes(url);
    if (bytes != null) {
      _cachedNetworkLogoUrl = url;
      _cachedNetworkLogoBytes = bytes;
    }
    return bytes;
  }
}
