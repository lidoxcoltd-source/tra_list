import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class TransactionSummary {
  const TransactionSummary({
    required this.income,
    required this.expenses,
    required this.count,
    required this.invalid,
    required this.categories,
    required this.incomeByDayUtc,
  });

  final double income;
  final double expenses;
  final int count;
  final int invalid;
  final Map<String, double> categories;
  final Map<String, double> incomeByDayUtc;

  factory TransactionSummary.fromRecords(
    Iterable<Map<String, dynamic>> records,
  ) {
    var income = 0.0;
    var expenses = 0.0;
    var count = 0;
    var invalid = 0;
    final categories = <String, double>{};
    final dailyIncome = <String, double>{};
    for (final data in records) {
      final amount = data['amount'];
      final type = data['type'];
      if (amount is! num ||
          !amount.isFinite ||
          amount < 0 ||
          (type != 'income' && type != 'expense')) {
        invalid++;
        continue;
      }
      count++;
      if (type == 'income') {
        income += amount.toDouble();
        final timestamp = data['date'];
        if (timestamp is Timestamp) {
          final day = timestamp.toDate().toUtc().toIso8601String().substring(
            0,
            10,
          );
          dailyIncome.update(
            day,
            (value) => value + amount,
            ifAbsent: () => amount.toDouble(),
          );
        }
      } else {
        expenses += amount.toDouble();
        final category = data['category']?.toString().trim() ?? '';
        final key = category.isEmpty ? 'Uncategorized' : category;
        categories.update(
          key,
          (value) => value + amount,
          ifAbsent: () => amount.toDouble(),
        );
      }
    }
    return TransactionSummary(
      income: income,
      expenses: expenses,
      count: count,
      invalid: invalid,
      categories: categories,
      incomeByDayUtc: dailyIncome,
    );
  }
}

class ReportingPeriod {
  const ReportingPeriod(this.start, this.end);

  final DateTime start;
  final DateTime end;

  static ReportingPeriod fromKey(String key, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    switch (key) {
      case 'yesterday':
        return ReportingPeriod(
          DateTime(now.year, now.month, now.day - 1),
          today,
        );
      case 'seven':
        return ReportingPeriod(
          DateTime(now.year, now.month, now.day - 6),
          tomorrow,
        );
      case 'thirty':
        return ReportingPeriod(
          DateTime(now.year, now.month, now.day - 29),
          tomorrow,
        );
      case 'month':
        return ReportingPeriod(DateTime(now.year, now.month), tomorrow);
      case 'previous':
        return ReportingPeriod(
          DateTime(now.year, now.month - 1),
          DateTime(now.year, now.month),
        );
      case 'today':
        return ReportingPeriod(today, tomorrow);
      default:
        throw ArgumentError.value(key, 'key', 'Unknown reporting period');
    }
  }
}

class PosSummary {
  const PosSummary({
    required this.total,
    required this.count,
    required this.products,
    required this.invalid,
  });
  final double total;
  final int count;
  final Map<String, double> products;
  final int invalid;

  factory PosSummary.fromRecords(Iterable<Map<String, dynamic>> records) {
    var total = 0.0;
    var count = 0;
    var invalid = 0;
    final products = <String, double>{};
    for (final record in records) {
      if (record['kind'] != 'invoice') continue;
      final amount = record['total'];
      if (amount is! num || !amount.isFinite || amount < 0) {
        invalid++;
        continue;
      }
      total += amount;
      count++;
      final items = record['items'];
      if (items is! List) {
        invalid++;
        continue;
      }
      for (final item in items) {
        if (item is! Map ||
            item['description'] is! String ||
            (item['description'] as String).trim().isEmpty ||
            item['amount'] is! num ||
            !(item['amount'] as num).isFinite ||
            (item['amount'] as num) < 0) {
          invalid++;
          continue;
        }
        final name = (item['description'] as String).trim();
        final value = (item['amount'] as num).toDouble();
        products.update(name, (old) => old + value, ifAbsent: () => value);
      }
    }
    return PosSummary(
      total: total,
      count: count,
      products: products,
      invalid: invalid,
    );
  }
}

class PurchaseSummary {
  const PurchaseSummary({
    required this.total,
    required this.count,
    required this.invalid,
  });
  final double total;
  final int count;
  final int invalid;

  factory PurchaseSummary.fromRecords(Iterable<Map<String, dynamic>> records) {
    var total = 0.0;
    var count = 0;
    var invalid = 0;
    for (final record in records) {
      final amount = record['total'];
      if (record['status'] != 'received' ||
          amount is! num ||
          !amount.isFinite ||
          amount < 0) {
        invalid++;
        continue;
      }
      total += amount;
      count++;
    }
    return PurchaseSummary(total: total, count: count, invalid: invalid);
  }
}

class TaskSummary {
  const TaskSummary({
    required this.open,
    required this.awaitingReview,
    required this.approvedInPeriod,
    required this.invalid,
  });
  final int open;
  final int awaitingReview;
  final int approvedInPeriod;
  final int invalid;

  factory TaskSummary.fromRecords(
    Iterable<Map<String, dynamic>> records,
    ReportingPeriod period,
  ) {
    var open = 0, awaitingReview = 0, approvedInPeriod = 0, invalid = 0;
    for (final record in records) {
      final status = record['status'];
      if (status == 'assigned' ||
          status == 'inProgress' ||
          status == 'returned') {
        open++;
      } else if (status == 'submitted') {
        awaitingReview++;
      } else if (status == 'approved') {
        final approvedAt = record['approvedAt'];
        if (approvedAt is! Timestamp) {
          invalid++;
          continue;
        }
        final date = approvedAt.toDate();
        if (!date.isBefore(period.start) && date.isBefore(period.end)) {
          approvedInPeriod++;
        }
      } else if (status != 'cancelled') {
        invalid++;
      }
    }
    return TaskSummary(
      open: open,
      awaitingReview: awaitingReview,
      approvedInPeriod: approvedInPeriod,
      invalid: invalid,
    );
  }
}

class BusinessContext {
  const BusinessContext({
    required this.businessId,
    required this.businessName,
    required this.period,
    required this.updatedAt,
    required this.income,
    required this.expenses,
    required this.transactionCount,
    required this.expenseCategories,
    required this.lowStock,
    required this.receivable,
    required this.payable,
    required this.limitations,
    this.pos,
    this.incomeByDayUtc = const {},
    this.purchases,
    this.tasks,
  });

  final String businessId;
  final String businessName;
  final ReportingPeriod period;
  final DateTime updatedAt;
  final double? income;
  final double? expenses;
  final int? transactionCount;
  final Map<String, double> expenseCategories;
  final List<String>? lowStock;
  final double? receivable;
  final double? payable;
  final List<String> limitations;
  final PosSummary? pos;
  final Map<String, double> incomeByDayUtc;
  final PurchaseSummary? purchases;
  final TaskSummary? tasks;

  BusinessContext withPeriod(ReportingPeriod value) => BusinessContext(
    businessId: businessId,
    businessName: businessName,
    period: value,
    updatedAt: updatedAt,
    income: income,
    expenses: expenses,
    transactionCount: transactionCount,
    expenseCategories: expenseCategories,
    lowStock: lowStock,
    receivable: receivable,
    payable: payable,
    limitations: limitations,
    pos: pos,
    incomeByDayUtc: incomeByDayUtc,
    purchases: purchases,
    tasks: tasks,
  );

  String report({String language = 'en'}) {
    final sw = language == 'sw';
    String text(String en, String swahili) => sw ? swahili : en;
    final date = DateFormat('yyyy-MM-dd');
    final money = NumberFormat('#,##0.##', 'en_US');
    final lines = <String>[
      text(
        'MJASI business intelligence report',
        'Ripoti ya uchambuzi wa biashara ya MJASI',
      ),
      '${text('Business', 'Biashara')}: $businessName',
      text('Business type: not available', 'Aina ya biashara: haipatikani'),
      '${text('Period', 'Kipindi')}: ${date.format(period.start)} ${text('to', 'hadi')} ${date.format(DateTime(period.end.year, period.end.month, period.end.day - 1))} ${text('(inclusive)', '(pamoja)')}',
      '${text('Updated', 'Imesasishwa')}: ${updatedAt.toIso8601String()}',
      if (income != null)
        '${text('Recorded income', 'Mapato yaliyorekodiwa')}: TZS ${money.format(income)}',
      if (expenses != null)
        '${text('Recorded expenses', 'Matumizi yaliyorekodiwa')}: TZS ${money.format(expenses)}',
      if (income != null && expenses != null)
        '${text('Recorded net cash flow (not profit)', 'Salio la fedha lililorekodiwa (si faida)')}: TZS ${money.format(income! - expenses!)}',
      if (transactionCount != null)
        '${text('Recorded transactions', 'Miamala iliyorekodiwa')}: $transactionCount',
      if (incomeByDayUtc.isNotEmpty) ...[
        '${text('Recorded income by day (UTC)', 'Mapato yaliyorekodiwa kwa siku (UTC)')}:',
        for (final entry
            in (incomeByDayUtc.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key))))
          '- ${entry.key}: TZS ${money.format(entry.value)}',
      ],
      if (pos != null) ...[
        '${text('POS sales', 'Mauzo ya POS')}: TZS ${money.format(pos!.total)} (${pos!.count})',
        '${text('POS products by recorded sales value', 'Bidhaa za POS kwa thamani ya mauzo iliyorekodiwa')}:',
        for (final entry
            in (pos!.products.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .take(10))
          '- ${entry.key}: TZS ${money.format(entry.value)}',
      ],
      if (expenseCategories.isNotEmpty) ...[
        '${text('Expense categories', 'Makundi ya matumizi')}:',
        for (final entry in expenseCategories.entries)
          '- ${entry.key}: TZS ${money.format(entry.value)}',
      ],
      if (lowStock != null)
        '${text('Current low/out-of-stock products', 'Bidhaa zenye akiba ndogo au zilizoisha sasa')}: ${lowStock!.isEmpty ? text("none", "hakuna") : lowStock!.join(", ")}',
      if (receivable != null)
        '${text('Current customer debts', 'Madeni ya wateja yaliyobaki sasa')}: TZS ${money.format(receivable)}',
      if (payable != null)
        '${text('Current debts owed by business', 'Madeni ya biashara yaliyobaki sasa')}: TZS ${money.format(payable)}',
      if (purchases != null)
        '${text('Received stock purchases in period', 'Manunuzi ya bidhaa yaliyopokelewa katika kipindi')}: TZS ${money.format(purchases!.total)} (${purchases!.count})',
      if (tasks != null) ...[
        '${text('Current open tasks', 'Kazi zilizo wazi sasa')}: ${tasks!.open}',
        '${text('Tasks awaiting review now', 'Kazi zinazosubiri ukaguzi sasa')}: ${tasks!.awaitingReview}',
        '${text('Tasks approved in period', 'Kazi zilizoidhinishwa katika kipindi')}: ${tasks!.approvedInPeriod}',
      ],
      '${text('Data limitations', 'Mipaka ya taarifa')}:',
      for (final limitation in limitations) '- $limitation',
      text(
        'Use only the supplied data. State uncertainty and do not infer missing facts. Provide practical business insights and ask for any information needed.',
        'Tumia taarifa zilizotolewa pekee. Eleza kutokuwa na uhakika na usibuni taarifa zinazokosekana. Toa ushauri wa biashara unaotekelezeka na uliza taarifa zinazohitajika. Jibu kwa Kiswahili.',
      ),
    ];
    return lines.join('\n');
  }
}
