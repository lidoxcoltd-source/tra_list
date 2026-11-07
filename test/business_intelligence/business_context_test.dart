import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/business_intelligence/business_context.dart';

void main() {
  test('purchases and tasks count valid records and exclusive end dates', () {
    final purchases = PurchaseSummary.fromRecords([
      {'status': 'received', 'total': 100, 'supplier': 'private'},
      {'status': 'received', 'total': -1},
      {'status': 'other', 'total': 10},
    ]);
    expect(purchases.total, 100);
    expect(purchases.count, 1);
    expect(purchases.invalid, 2);
    final start = DateTime(2024, 5, 1);
    final end = DateTime(2024, 5, 2);
    final tasks = TaskSummary.fromRecords([
      {'status': 'assigned', 'title': 'private'},
      {'status': 'returned'},
      {'status': 'submitted'},
      {'status': 'approved', 'approvedAt': Timestamp.fromDate(start)},
      {'status': 'approved', 'approvedAt': Timestamp.fromDate(end)},
      {'status': 'approved'},
      {'status': 'unknown'},
      {'status': 'cancelled'},
    ], ReportingPeriod(start, end));
    expect(tasks.open, 2);
    expect(tasks.awaitingReview, 1);
    expect(tasks.approvedInPeriod, 1);
    expect(tasks.invalid, 2);
  });
  test('transaction summary rejects invalid values and groups expenses', () {
    final summary = TransactionSummary.fromRecords([
      {'type': 'income', 'amount': 100},
      {'type': 'expense', 'amount': 15.5, 'category': 'Rent'},
      {'type': 'expense', 'amount': 4.5, 'category': 'Rent'},
      {'type': 'expense', 'amount': 3},
      {'type': 'other', 'amount': 50},
      {'type': 'income', 'amount': double.nan},
      {'type': 'expense', 'amount': -2},
      {'type': 'expense'},
    ]);
    expect(summary.income, 100);
    expect(summary.expenses, 23);
    expect(summary.count, 4);
    expect(summary.invalid, 4);
    expect(summary.categories, {'Rent': 20, 'Uncategorized': 3});
  });

  test('periods use local calendar days and exclusive end dates', () {
    final now = DateTime(2024, 3, 1, 15);
    final yesterday = ReportingPeriod.fromKey('yesterday', now);
    expect(yesterday.start, DateTime(2024, 2, 29));
    expect(yesterday.end, DateTime(2024, 3, 1));
    final previous = ReportingPeriod.fromKey('previous', now);
    expect(previous.start, DateTime(2024, 2, 1));
    expect(previous.end, DateTime(2024, 3, 1));
    final seven = ReportingPeriod.fromKey('seven', now);
    expect(seven.start, DateTime(2024, 2, 24));
    expect(seven.end, DateTime(2024, 3, 2));
    expect(() => ReportingPeriod.fromKey('other', now), throwsArgumentError);
  });

  test('report distinguishes cash flow and omits unavailable metrics', () {
    final context = BusinessContext(
      businessId: 'private-id',
      businessName: 'Shop',
      period: ReportingPeriod(DateTime(2024, 2, 1), DateTime(2024, 3, 1)),
      updatedAt: DateTime(2024, 3, 1),
      income: 100,
      expenses: 40,
      transactionCount: 2,
      expenseCategories: {'Rent': 40},
      lowStock: null,
      receivable: null,
      payable: null,
      limitations: ['POS data not included.'],
    );
    final report = context.report();
    expect(report, contains('2024-02-01 to 2024-02-29'));
    expect(report, contains('Recorded net cash flow (not profit): TZS 60'));
    expect(report, contains('POS data not included.'));
    expect(report, isNot(contains('private-id')));
    expect(report, isNot(contains('Current customer debts:')));
    expect(report, isNot(contains('Current low/out-of-stock products:')));
    final swahili = context.report(language: 'sw');
    expect(swahili, contains('Mapato yaliyorekodiwa: TZS 100'));
    expect(
      swahili,
      contains('Salio la fedha lililorekodiwa (si faida): TZS 60'),
    );
    expect(swahili, contains('Jibu kwa Kiswahili'));
  });

  test('POS sales are summarized separately with invalid entries counted', () {
    final summary = PosSummary.fromRecords([
      {
        'kind': 'invoice',
        'total': 100,
        'items': [
          {'description': 'Tea', 'amount': 70},
          {'description': 'Tea', 'amount': 30},
        ],
      },
      {'kind': 'quotation', 'total': 900, 'items': []},
      {'kind': 'invoice', 'total': -1},
      {
        'kind': 'invoice',
        'total': 10,
        'items': [
          {'description': 'bad'},
        ],
      },
    ]);
    expect(summary.total, 110);
    expect(summary.count, 2);
    expect(summary.products, {'Tea': 100});
    expect(summary.invalid, 2);
  });
}
