import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlatformVersionPolicy {
  const PlatformVersionPolicy({
    this.enabled = false,
    this.minimumVersion = '0.0.0',
    this.minimumBuild = 0,
    this.updateUrl = '',
  });

  final bool enabled;
  final String minimumVersion;
  final int minimumBuild;
  final String updateUrl;

  factory PlatformVersionPolicy.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const PlatformVersionPolicy();
    final enabled = data['enabled'];
    final minimumVersion = data['minimumVersion'];
    final minimumBuild = data['minimumBuild'];
    final updateUrl = data['updateUrl'];
    if (enabled is! bool ||
        minimumVersion is! String ||
        minimumBuild is! int ||
        updateUrl is! String) {
      throw const FormatException('Invalid platform version policy.');
    }
    return PlatformVersionPolicy(
      enabled: enabled,
      minimumVersion: minimumVersion,
      minimumBuild: minimumBuild,
      updateUrl: updateUrl,
    );
  }

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'minimumVersion': minimumVersion,
    'minimumBuild': minimumBuild,
    'updateUrl': updateUrl,
  };
}

class AppVersionPolicy {
  const AppVersionPolicy({
    required this.android,
    required this.windows,
    required this.web,
    this.message = 'Please install the latest app version to continue.',
  });

  static const defaults = AppVersionPolicy(
    android: PlatformVersionPolicy(),
    windows: PlatformVersionPolicy(),
    web: PlatformVersionPolicy(),
  );

  final PlatformVersionPolicy android;
  final PlatformVersionPolicy windows;
  final PlatformVersionPolicy web;
  final String message;

  PlatformVersionPolicy forPlatform(String platform) => switch (platform) {
    'android' => android,
    'windows' => windows,
    'web' => web,
    _ => const PlatformVersionPolicy(),
  };

  factory AppVersionPolicy.fromMap(Map<String, dynamic>? data) {
    if (data == null) return defaults;
    final platforms = data['platforms'];
    final message = data['message'];
    if (platforms is! Map || message is! String) {
      throw const FormatException('Invalid app version policy.');
    }
    Map<String, dynamic> platformMap(String name) {
      final value = platforms[name];
      if (value is! Map) {
        throw FormatException('Missing $name app version policy.');
      }
      return Map<String, dynamic>.from(value);
    }

    final policy = AppVersionPolicy(
      android: PlatformVersionPolicy.fromMap(platformMap('android')),
      windows: PlatformVersionPolicy.fromMap(platformMap('windows')),
      web: PlatformVersionPolicy.fromMap(platformMap('web')),
      message: message,
    );
    AppVersionService._validatePolicy(policy);
    return policy;
  }

  Map<String, dynamic> toMap() => {
    'message': message,
    'platforms': {
      'android': android.toMap(),
      'windows': windows.toMap(),
      'web': web.toMap(),
    },
  };
}

class AppVersionService {
  AppVersionService._();

  static final _firestore = FirebaseFirestore.instance;
  static const _cacheKey = 'app_version_policy_v1';
  static DocumentReference<Map<String, dynamic>> get _policyRef =>
      _firestore.collection('app_config').doc('version_policy');

  static String? get currentPlatform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.windows => 'windows',
      _ => null,
    };
  }

  static Future<PackageInfo> installedPackageInfo() =>
      PackageInfo.fromPlatform();

  static bool isUpdateRequired({
    required String installedVersion,
    required int installedBuild,
    required PlatformVersionPolicy policy,
  }) {
    if (!policy.enabled) return false;
    final versionOrder = compareVersions(
      installedVersion,
      policy.minimumVersion,
    );
    return versionOrder < 0 ||
        (versionOrder == 0 && installedBuild < policy.minimumBuild);
  }

  static int compareVersions(String left, String right) {
    final leftParts = _versionParts(left);
    final rightParts = _versionParts(right);
    final length = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var index = 0; index < length; index++) {
      final leftPart = index < leftParts.length ? leftParts[index] : 0;
      final rightPart = index < rightParts.length ? rightParts[index] : 0;
      if (leftPart != rightPart) return leftPart.compareTo(rightPart);
    }
    return 0;
  }

  static List<int> _versionParts(String version) {
    final parts = version.split('.');
    if (parts.isEmpty || parts.any((part) => int.tryParse(part) == null)) {
      throw FormatException('Invalid version number: $version');
    }
    return parts.map(int.parse).toList(growable: false);
  }

  static Future<AppVersionPolicy?> loadCachedPolicy() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final cached = preferences.getString(_cacheKey);
      if (cached == null) return null;
      try {
        return _decodePolicy(cached);
      } catch (error, stackTrace) {
        debugPrint('Ignoring invalid cached app version policy: $error');
        debugPrintStack(stackTrace: stackTrace);
        await preferences.remove(_cacheKey);
        return null;
      }
    } catch (error, stackTrace) {
      debugPrint('Could not load cached app version policy: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  static Future<AppVersionPolicy> loadRemotePolicy() async {
    final snapshot = await _policyRef.get(
      const GetOptions(source: Source.server),
    );
    final policy = AppVersionPolicy.fromMap(snapshot.data());
    await _writeCache(policy);
    return policy;
  }

  static Future<AppVersionPolicy> loadManagedPolicy() async {
    await _requireSuperAdmin();
    final snapshot = await _policyRef.get(
      const GetOptions(source: Source.serverAndCache),
    );
    return AppVersionPolicy.fromMap(snapshot.data());
  }

  static Future<void> savePolicy(AppVersionPolicy policy) async {
    await _requireSuperAdmin();
    _validatePolicy(policy);
    final user = FirebaseAuth.instance.currentUser!;
    await _policyRef.set({
      ...policy.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
    });
    await _writeCache(policy);
  }

  static void _validatePolicy(AppVersionPolicy policy) {
    if (policy.message.trim().isEmpty || policy.message.length > 500) {
      throw ArgumentError.value(
        policy.message,
        'message',
        'Enter a message with 1 to 500 characters.',
      );
    }
    for (final entry in {
      'Android': policy.android,
      'Windows': policy.windows,
      'Web': policy.web,
    }.entries) {
      final platform = entry.value;
      if (!RegExp(r'^\d+(\.\d+){1,3}$').hasMatch(platform.minimumVersion)) {
        throw ArgumentError.value(
          platform.minimumVersion,
          '${entry.key} minimum version',
          'Use a numeric version such as 1.2.3.',
        );
      }
      if (platform.minimumBuild < 0) {
        throw ArgumentError.value(
          platform.minimumBuild,
          '${entry.key} minimum build',
          'Build number cannot be negative.',
        );
      }
      final uri = Uri.tryParse(platform.updateUrl);
      if (platform.enabled &&
          (uri == null || uri.scheme != 'https' || uri.host.isEmpty)) {
        throw ArgumentError.value(
          platform.updateUrl,
          '${entry.key} update URL',
          'An enabled platform needs a valid HTTPS update URL.',
        );
      }
    }
  }

  static Future<void> _requireSuperAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in as a super admin.');
    final profile = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('profile')
        .doc('company')
        .get();
    final role = profile.data()?['role']?.toString() ?? '';
    if (_normalizeRole(role) != 'superadmin') {
      throw StateError('Only a super admin can manage app versions.');
    }
  }

  static String _normalizeRole(String role) =>
      role.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static Future<void> _writeCache(AppVersionPolicy policy) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_cacheKey, _encodePolicy(policy));
    } catch (error, stackTrace) {
      debugPrint('Could not cache app version policy: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static String _encodePolicy(AppVersionPolicy policy) =>
      jsonEncode(policy.toMap());

  static AppVersionPolicy _decodePolicy(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FormatException('Invalid policy cache.');
    }
    return AppVersionPolicy.fromMap(Map<String, dynamic>.from(decoded));
  }
}
