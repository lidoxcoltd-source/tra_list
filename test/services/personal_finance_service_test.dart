import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/services/personal_finance_service.dart';

void main() {
  group('PersonalFinanceService validation', () {
    test('rejects invalid transaction types and amounts', () async {
      await expectLater(
        PersonalFinanceService.addTransaction(
          type: 'business',
          description: 'Salary',
          category: 'Work',
          amount: 100,
          date: DateTime(2026),
        ),
        throwsArgumentError,
      );
      await expectLater(
        PersonalFinanceService.addTransaction(
          type: 'income',
          description: 'Salary',
          category: 'Work',
          amount: double.infinity,
          date: DateTime(2026),
        ),
        throwsArgumentError,
      );
    });

    test('rejects empty budgets and savings targets', () async {
      await expectLater(
        PersonalFinanceService.saveBudget(name: ' ', amount: 100),
        throwsArgumentError,
      );
      await expectLater(
        PersonalFinanceService.saveGoal(
          name: 'Holiday',
          targetAmount: 100,
          savedAmount: 120,
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid or incomplete personal preferences', () async {
      await expectLater(
        PersonalFinanceService.saveProfile({
          'displayName': 'Personal User',
          'photoUrl': '',
          'currency': 'GBP',
          'dateFormat': 'dd/MM/yyyy',
          'notificationsEnabled': true,
        }),
        throwsArgumentError,
      );
    });

    test('rejects non-HTTPS profile photos', () async {
      await expectLater(
        PersonalFinanceService.saveProfile({
          'displayName': 'Personal User',
          'photoUrl': 'http://example.com/photo.png',
          'currency': 'TZS',
          'dateFormat': 'dd/MM/yyyy',
          'notificationsEnabled': true,
        }),
        throwsArgumentError,
      );
    });
  });
}
