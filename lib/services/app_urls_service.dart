import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:tra_list/config/app_config.dart';

class AppUrls {
  const AppUrls({
    required this.website,
    required this.privacyPolicy,
    required this.termsOfService,
  });

  static final defaults = AppUrls(
    website: AppConfig.appBaseUrl,
    privacyPolicy: AppConfig.privacyPolicyUrl,
    termsOfService: AppConfig.termsOfServiceUrl,
  );

  final String website;
  final String privacyPolicy;
  final String termsOfService;

  factory AppUrls.fromMap(Map<String, dynamic>? data) {
    String value(String key, String fallback) {
      final candidate = data?[key];
      return candidate is String && candidate.trim().isNotEmpty
          ? candidate.trim()
          : fallback;
    }

    return AppUrls(
      website: value('websiteUrl', defaults.website),
      privacyPolicy: value('privacyPolicyUrl', defaults.privacyPolicy),
      termsOfService: value('termsOfServiceUrl', defaults.termsOfService),
    );
  }
}

class AppUrlsService {
  AppUrlsService._();

  static DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('app_config').doc('app_urls');

  static Future<AppUrls> load() async {
    try {
      final snapshot = await _ref.get().timeout(const Duration(seconds: 10));
      return AppUrls.fromMap(snapshot.data());
    } catch (error, stackTrace) {
      debugPrint('Could not load app URLs; using built-in defaults: $error');
      debugPrintStack(stackTrace: stackTrace);
      return AppUrls.defaults;
    }
  }

  static String? validationError(AppUrls urls) {
    for (final url in [
      urls.website,
      urls.privacyPolicy,
      urls.termsOfService,
    ]) {
      final uri = Uri.tryParse(url.trim());
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          url.trim().length > 500) {
        return 'Each link must be a valid HTTPS URL under 500 characters.';
      }
    }
    return null;
  }

  static Future<void> save(AppUrls urls) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to edit app URLs.');
    final error = validationError(urls);
    if (error != null) throw ArgumentError(error);

    await _ref.set({
      'websiteUrl': urls.website.trim(),
      'privacyPolicyUrl': urls.privacyPolicy.trim(),
      'termsOfServiceUrl': urls.termsOfService.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
    });
  }
}
