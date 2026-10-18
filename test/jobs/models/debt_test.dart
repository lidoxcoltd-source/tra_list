import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/jobs/models/debt.dart';

void main() {
  final today = DateTime.now();
  final yesterday = DateTime(today.year, today.month, today.day - 1);

  Debt createDebt({
    required double principal,
    double amountPaid = 0,
    DateTime? dueDate,
  }) => Debt(
    id: 'test-debt',
    debtorName: 'Test person',
    phone: '',
    direction: DebtDirection.customerOwesShop,
    reason: 'advance',
    principal: principal,
    amountPaid: amountPaid,
    dueDate: dueDate,
    shopNickname: 'Test shop',
  );

  test('balance reflects partial payments', () {
    final debt = createDebt(principal: 100, amountPaid: 35);

    expect(debt.balance, 65);
    expect(debt.isSettled, isFalse);
  });

  test('settled debts do not remain overdue', () {
    final debt = createDebt(
      principal: 100,
      amountPaid: 100,
      dueDate: yesterday,
    );

    expect(debt.balance, 0);
    expect(debt.isSettled, isTrue);
    expect(debt.isOverdue, isFalse);
  });

  test('unpaid debt is overdue after its due date', () {
    final debt = createDebt(principal: 100, dueDate: yesterday);

    expect(debt.balance, 100);
    expect(debt.isOverdue, isTrue);
  });
}
