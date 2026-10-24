import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/services/analytics_advice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnalyticsAdvice', () {
    test('loads every bundled advice rule', () async {
      final source = await rootBundle.loadString(
        'assets/analytics_advice.json',
      );

      expect(AnalyticsAdviceService.decodeJson(source), isNotEmpty);
    });

    test('matches all metric conditions', () {
      final advice = AnalyticsAdvice.fromMap({
        'id': 'high-expenses',
        'category': 'costs',
        'title': {'en': 'Review costs', 'sw': 'Kagua gharama'},
        'description': {
          'en': 'Expenses are high.',
          'sw': 'Matumizi ni makubwa.',
        },
        'when': [
          {'metric': 'expenses', 'operator': 'gte', 'value': 100000},
          {'metric': 'net', 'operator': 'lt', 'value': 0},
        ],
      });

      expect(advice.matches({'expenses': 120000, 'net': -1}), isTrue);
      expect(advice.matches({'expenses': 120000, 'net': 10}), isFalse);
      expect(advice.matches({'net': -1}), isFalse);
    });

    test('round-trips rule data for Firestore storage', () {
      final advice = AnalyticsAdvice.fromMap({
        'id': 'task-reminder',
        'category': 'tasks',
        'title': {'en': 'Review tasks', 'sw': 'Kagua kazi'},
        'description': {
          'en': 'There are {activeTasks} active tasks.',
          'sw': 'Kuna kazi {activeTasks} zinazoendelea.',
        },
        'when': [
          {'metric': 'activeTasks', 'operator': 'gt', 'value': 2},
        ],
        'enabled': true,
      });

      expect(AnalyticsAdvice.fromMap(advice.toMap()).toMap(), advice.toMap());
    });

    test('exports and imports a bilingual catalogue', () {
      final advice = AnalyticsAdvice.fromMap({
        'id': 'monthly-review',
        'category': 'records',
        'title': {'en': 'Review month', 'sw': 'Kagua mwezi'},
        'description': {
          'en': 'Review {transactionCount} entries.',
          'sw': 'Kagua miamala {transactionCount}.',
        },
        'when': [
          {'metric': 'transactionCount', 'operator': 'gte', 'value': 10},
        ],
      });
      final json = AnalyticsAdviceService.encodeJson([advice]);
      final imported = AnalyticsAdviceService.decodeJson(json);

      expect(imported, hasLength(1));
      expect(imported.single.id, advice.id);
      expect(imported.single.title['sw'], 'Kagua mwezi');
      expect(imported.single.conditions.single.value, 10);
    });

    test('rejects unknown metrics and incomplete translations', () {
      expect(
        () => AnalyticsAdvice.fromMap({
          'id': 'invalid-metric',
          'category': 'costs',
          'title': {'en': 'Title', 'sw': 'Kichwa'},
          'description': {'en': 'Text', 'sw': 'Maelezo'},
          'when': [
            {'metric': 'unknownMetric', 'operator': 'gt', 'value': 1},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => AnalyticsAdvice.fromMap({
          'id': 'missing-language',
          'category': 'costs',
          'title': {'en': 'Title'},
          'description': {'en': 'Text', 'sw': 'Maelezo'},
          'when': [
            {'metric': 'expenses', 'operator': 'gt', 'value': 1},
          ],
        }),
        throwsFormatException,
      );
    });
  });
}
