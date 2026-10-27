import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SupportFaq {
  const SupportFaq({required this.question, required this.answer});

  final String question;
  final String answer;

  factory SupportFaq.fromMap(Map<String, dynamic> data) => SupportFaq(
    question: data['question']?.toString().trim() ?? '',
    answer: data['answer']?.toString().trim() ?? '',
  );

  Map<String, String> toMap() => {
    'question': question.trim(),
    'answer': answer.trim(),
  };
}

class SupportCenterConfig {
  const SupportCenterConfig({this.whatsappNumber = '', this.faqs = const []});

  final String whatsappNumber;
  final List<SupportFaq> faqs;

  factory SupportCenterConfig.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const SupportCenterConfig();
    final rawFaqs = data['faqs'];
    final faqs = rawFaqs is List
        ? rawFaqs
              .whereType<Map>()
              .map((faq) => SupportFaq.fromMap(Map<String, dynamic>.from(faq)))
              .where((faq) => faq.question.isNotEmpty && faq.answer.isNotEmpty)
              .toList()
        : <SupportFaq>[];
    return SupportCenterConfig(
      whatsappNumber: data['whatsappNumber']?.toString() ?? '',
      faqs: faqs,
    );
  }
}

class SupportCenterService {
  SupportCenterService._();

  static const _cacheKey = 'support_center.public_config';

  static final _document = FirebaseFirestore.instance
      .collection('app_config')
      .doc('support_center');

  static Future<SupportCenterConfig> load() async {
    try {
      final snapshot = await _document
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      final config = SupportCenterConfig.fromMap(snapshot.data());
      try {
        await _cache(config);
      } catch (error, stackTrace) {
        debugPrint('Could not cache support center content: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      return config;
    } on FirebaseException catch (error, stackTrace) {
      debugPrint(
        'Could not load support center from Firestore '
        '(${error.code}): ${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);
      final cached = await _readCache();
      if (cached != null) return cached;
      rethrow;
    } on TimeoutException catch (error, stackTrace) {
      debugPrint('Support center request timed out: $error');
      debugPrintStack(stackTrace: stackTrace);
      final cached = await _readCache();
      if (cached != null) return cached;
      rethrow;
    }
  }

  static Future<void> _cache(SupportCenterConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey,
      jsonEncode({
        'whatsappNumber': config.whatsappNumber,
        'faqs': config.faqs.map((faq) => faq.toMap()).toList(),
      }),
    );
  }

  static Future<SupportCenterConfig?> _readCache() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_cacheKey);
    if (value == null) return null;
    try {
      final data = jsonDecode(value);
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid support center cache.');
      }
      debugPrint('Showing cached support center content.');
      return SupportCenterConfig.fromMap(data);
    } on FormatException catch (error, stackTrace) {
      debugPrint('Could not read support center cache: $error');
      debugPrintStack(stackTrace: stackTrace);
      await prefs.remove(_cacheKey);
      return null;
    }
  }

  static Future<void> save(SupportCenterConfig config) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null)
      throw StateError('You must sign in to save support settings.');
    if (config.faqs.length > 50) {
      throw ArgumentError('A maximum of 50 FAQ entries is allowed.');
    }
    await _document.set({
      'whatsappNumber': config.whatsappNumber.replaceAll(RegExp(r'\D'), ''),
      'faqs': config.faqs.map((faq) => faq.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
    });
  }
}
