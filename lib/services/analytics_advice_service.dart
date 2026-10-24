import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AnalyticsAdviceCondition {
  const AnalyticsAdviceCondition({
    required this.metric,
    required this.operator,
    required this.value,
  });

  final String metric;
  final String operator;
  final double value;

  factory AnalyticsAdviceCondition.fromMap(Map<String, dynamic> data) {
    final metric = data['metric'];
    final operator = data['operator'];
    final value = data['value'];
    if (metric is! String ||
        !AnalyticsAdviceService.metrics.contains(metric) ||
        operator is! String ||
        !AnalyticsAdviceService.operators.contains(operator) ||
        value is! num ||
        !value.toDouble().isFinite) {
      throw const FormatException('Invalid analytics advice condition.');
    }
    return AnalyticsAdviceCondition(
      metric: metric,
      operator: operator,
      value: value.toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
    'metric': metric,
    'operator': operator,
    'value': value,
  };

  bool matches(Map<String, double> metrics) {
    final actual = metrics[metric];
    if (actual == null) return false;
    return switch (operator) {
      'gt' => actual > value,
      'gte' => actual >= value,
      'lt' => actual < value,
      'lte' => actual <= value,
      'eq' => actual == value,
      _ => false,
    };
  }
}

class AnalyticsAdvice {
  const AnalyticsAdvice({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.conditions,
    this.enabled = true,
  });

  final String id;
  final String category;
  final Map<String, String> title;
  final Map<String, String> description;
  final List<AnalyticsAdviceCondition> conditions;
  final bool enabled;

  factory AnalyticsAdvice.fromMap(Map<String, dynamic> data) {
    final conditions = data['when'];
    if (conditions is! List || conditions.isEmpty || conditions.length > 3) {
      throw const FormatException(
        'Advice needs between one and three conditions.',
      );
    }
    final category = data['category'];
    if (category is! String ||
        !AnalyticsAdviceService.categories.contains(category)) {
      throw const FormatException('Invalid analytics advice category.');
    }
    final id = data['id'];
    if (id is! String || !RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id)) {
      throw const FormatException('Advice id is required.');
    }
    return AnalyticsAdvice(
      id: id,
      category: category,
      title: _localizedText(data['title']),
      description: _localizedText(data['description']),
      conditions: conditions.map((condition) {
        if (condition is! Map) {
          throw const FormatException('Invalid analytics advice condition.');
        }
        return AnalyticsAdviceCondition.fromMap(
          Map<String, dynamic>.from(condition),
        );
      }).toList(),
      enabled: data['enabled'] != false,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'category': category,
    'title': title,
    'description': description,
    'when': conditions.map((condition) => condition.toMap()).toList(),
    'enabled': enabled,
  };

  bool matches(Map<String, double> metrics) =>
      enabled && conditions.every((condition) => condition.matches(metrics));
}

Map<String, String> _localizedText(dynamic value) {
  if (value is! Map) {
    throw const FormatException('Advice needs English and Swahili text.');
  }
  final localized = <String, String>{};
  for (final language in const ['en', 'sw']) {
    final text = value[language];
    if (text is! String || text.trim().isEmpty || text.length > 500) {
      throw FormatException('Advice needs valid "$language" text.');
    }
    localized[language] = text.trim();
  }
  return localized;
}

class AnalyticsAdviceService {
  AnalyticsAdviceService._();

  static const metrics = <String>{
    'income',
    'expenses',
    'net',
    'transactionCount',
    'incomeTransactionCount',
    'expenseTransactionCount',
    'averageIncome',
    'averageExpense',
    'topExpenseSharePercent',
    'incomeChangePercent',
    'expenseChangePercent',
    'activeTasks',
    'overdueTasks',
    'tasksForReview',
    'posSalesCount',
    'posSalesTotal',
    'staffCount',
  };
  static const operators = <String>{'gt', 'gte', 'lt', 'lte', 'eq'};
  static const categories = <String>{
    'costs',
    'growth',
    'tasks',
    'sales',
    'staff',
    'records',
  };

  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('analyticsAdvice');

  static Future<List<AnalyticsAdvice>> loadCustom() async {
    final snapshot = await _collection.get();
    final advice = <AnalyticsAdvice>[];
    for (final doc in snapshot.docs) {
      final item = AnalyticsAdvice.fromMap(doc.data());
      if (item.id != doc.id) {
        throw FormatException('Advice document id does not match ${doc.id}.');
      }
      advice.add(item);
    }
    return advice;
  }

  static Future<List<AnalyticsAdvice>> loadAllForAdmin() async {
    final snapshot = await _collection
        .orderBy('updatedAt', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => AnalyticsAdvice.fromMap(doc.data()))
        .toList();
  }

  static String encodeJson(List<AnalyticsAdvice> advice) =>
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'languageFields': ['en', 'sw'],
        'metrics': metrics.toList()..sort(),
        'operators': operators.toList()..sort(),
        'advice': advice.map((item) => item.toMap()).toList(),
      });

  static List<AnalyticsAdvice> decodeJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> ||
        decoded['schemaVersion'] != 1 ||
        decoded['advice'] is! List) {
      throw const FormatException(
        'JSON must have schemaVersion 1 and an advice list.',
      );
    }
    final rawAdvice = decoded['advice'] as List;
    if (rawAdvice.isEmpty || rawAdvice.length > 200) {
      throw const FormatException(
        'JSON must contain between 1 and 200 advice entries.',
      );
    }
    final advice = rawAdvice.map((item) {
      if (item is! Map) {
        throw const FormatException('Advice entries must be objects.');
      }
      return AnalyticsAdvice.fromMap(Map<String, dynamic>.from(item));
    }).toList();
    if (advice.map((item) => item.id).toSet().length != advice.length) {
      throw const FormatException('Advice ids must be unique.');
    }
    return advice;
  }

  static Future<void> upsertAll(List<AnalyticsAdvice> advice) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to import analytics advice.');
    if (advice.isEmpty || advice.length > 200) {
      throw ArgumentError(
        'Import must contain between 1 and 200 advice entries.',
      );
    }
    final validated = advice
        .map((item) => AnalyticsAdvice.fromMap(item.toMap()))
        .toList();
    if (validated.map((item) => item.id).toSet().length != validated.length) {
      throw const FormatException('Advice ids must be unique.');
    }
    final batch = FirebaseFirestore.instance.batch();
    for (final item in validated) {
      batch.set(_collection.doc(item.id), {
        ...item.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
      });
    }
    await batch.commit();
  }

  static Future<void> save(AnalyticsAdvice advice) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to save analytics advice.');
    final validated = AnalyticsAdvice.fromMap(advice.toMap());
    await _collection.doc(validated.id).set({
      ...validated.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
    });
  }

  static Future<void> delete(String id) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError('Sign in to delete analytics advice.');
    }
    await _collection.doc(id).delete();
  }
}
