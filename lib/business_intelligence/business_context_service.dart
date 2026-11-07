import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/business_context.dart';
import 'package:tra_list/services/business_access_service.dart';

class BusinessContextService {
  BusinessContextService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  Future<BusinessContext> load(ReportingPeriod period) async {
    if (!period.end.isAfter(period.start)) {
      throw ArgumentError('The reporting period must end after it starts.');
    }
    final user = _auth.currentUser;
    if (user == null || !BusinessAccessService.hasBusinessAccess) {
      throw StateError('Business access is not available.');
    }
    if (!BusinessAccessService.can('analytics', 'view')) {
      throw StateError('Analytics permission is required.');
    }
    final businessId = BusinessAccessService.businessId;
    final name = BusinessAccessService.businessName.value.trim();
    final isOwner = BusinessAccessService.isOwner.value;
    final shop = BusinessAccessService.shopNickname.value.trim();
    final canStock = BusinessAccessService.can('stock', 'view');
    final canDebts = BusinessAccessService.can('jobs', 'view');
    final canTasks = BusinessAccessService.can('tasks', 'view');
    final canPos = isOwner && BusinessAccessService.can('invoices', 'view');
    if (!isOwner && shop.isEmpty) {
      throw StateError('A staff shop assignment is required.');
    }
    final business = _db.collection('users').doc(businessId);
    final limitations = <String>[
      'bi_limit_income'.tr,
      'bi_limit_profit'.tr,
      'bi_limit_modules'.tr,
      'bi_limit_type'.tr,
      'bi_limit_dates'.tr,
      if (!isOwner) 'bi_limit_shop'.tr,
    ];
    Query<Map<String, dynamic>> transactions = business
        .collection('transactions')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(period.start))
        .where('date', isLessThan: Timestamp.fromDate(period.end));
    if (!isOwner) {
      transactions = transactions.where('shopNickname', isEqualTo: shop);
    }
    final transactionDocs = await transactions.get(
      const GetOptions(source: Source.server),
    );
    final summary = TransactionSummary.fromRecords(
      transactionDocs.docs.map((doc) => doc.data()),
    );
    if (summary.invalid > 0) {
      limitations.add(
        'bi_limit_invalid_transactions'.trParams({
          'count': '${summary.invalid}',
        }),
      );
    }

    PosSummary? pos;
    if (canPos) {
      final sales = await business
          .collection('invoices')
          .where('source', isEqualTo: 'pos')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(period.start),
          )
          .where('createdAt', isLessThan: Timestamp.fromDate(period.end))
          .get(const GetOptions(source: Source.server));
      pos = PosSummary.fromRecords(sales.docs.map((doc) => doc.data()));
      if (pos.invalid > 0) {
        limitations.add(
          'bi_limit_invalid_pos'.trParams({'count': '${pos.invalid}'}),
        );
      }
      limitations.add('bi_limit_pos'.tr);
    } else {
      limitations.add('bi_limit_pos_unavailable'.tr);
    }

    List<String>? lowStock;
    PurchaseSummary? purchases;
    if (canStock) {
      final purchaseDocs = await business
          .collection('purchases')
          .where(
            'date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(period.start),
          )
          .where('date', isLessThan: Timestamp.fromDate(period.end))
          .get(const GetOptions(source: Source.server));
      purchases = PurchaseSummary.fromRecords(
        purchaseDocs.docs.map((doc) => doc.data()),
      );
      limitations.add('bi_limit_purchases'.tr);
      if (purchases.invalid > 0) {
        limitations.add(
          'bi_limit_invalid_purchases'.trParams({
            'count': '${purchases.invalid}',
          }),
        );
      }
      final docs = await business
          .collection('products')
          .get(const GetOptions(source: Source.server));
      lowStock = [];
      var invalidStock = 0;
      for (final doc in docs.docs) {
        final data = doc.data();
        if (data['active'] == false || data['tracked'] == false) continue;
        final quantity = data['quantity'];
        final threshold = data['lowStockThreshold'];
        if (quantity is! num ||
            !quantity.isFinite ||
            threshold is! num ||
            !threshold.isFinite) {
          invalidStock++;
          continue;
        }
        if (quantity <= threshold || quantity <= 0) {
          final productName = data['name']?.toString().trim() ?? '';
          if (productName.isEmpty) {
            invalidStock++;
            continue;
          }
          lowStock.add('$productName ($quantity ${data['unit'] ?? ''})');
        }
      }
      lowStock.sort();
      if (invalidStock > 0) {
        limitations.add(
          'bi_limit_invalid_stock'.trParams({'count': '$invalidStock'}),
        );
      }
      limitations.add('bi_limit_stock_current'.tr);
    } else {
      limitations.add('bi_limit_stock_permission'.tr);
      limitations.add('bi_limit_purchases_unavailable'.tr);
    }

    TaskSummary? tasks;
    if (canTasks) {
      final docs = await business
          .collection('tasks')
          .get(const GetOptions(source: Source.server));
      tasks = TaskSummary.fromRecords(
        docs.docs.map((doc) => doc.data()),
        period,
      );
      limitations.add('bi_limit_tasks'.tr);
      if (tasks.invalid > 0) {
        limitations.add(
          'bi_limit_invalid_tasks'.trParams({'count': '${tasks.invalid}'}),
        );
      }
    } else {
      limitations.add('bi_limit_tasks_unavailable'.tr);
    }

    double? receivable;
    double? payable;
    if (canDebts) {
      Query<Map<String, dynamic>> debts = business.collection('debts');
      if (!isOwner) debts = debts.where('shopNickname', isEqualTo: shop);
      final docs = await debts.get(const GetOptions(source: Source.server));
      var receivableTotal = 0.0;
      var payableTotal = 0.0;
      var invalidDebts = 0;
      for (final doc in docs.docs) {
        final data = doc.data();
        final principal = data['principal'];
        final paid = data['amountPaid'];
        final direction = data['direction'];
        if (principal is! num ||
            paid is! num ||
            !principal.isFinite ||
            !paid.isFinite ||
            principal < 0 ||
            paid < 0 ||
            (direction != 'customerOwesShop' && direction != 'shopOwesOther')) {
          invalidDebts++;
          continue;
        }
        final balance = (principal - paid).clamp(0, double.infinity).toDouble();
        if (direction == 'customerOwesShop') {
          receivableTotal += balance;
        } else {
          payableTotal += balance;
        }
      }
      receivable = receivableTotal;
      payable = payableTotal;
      if (invalidDebts > 0) {
        limitations.add(
          'bi_limit_invalid_debts'.trParams({'count': '$invalidDebts'}),
        );
      }
      limitations.add('bi_limit_debt_current'.tr);
    } else {
      limitations.add('bi_limit_debt_permission'.tr);
    }

    if (_auth.currentUser?.uid != user.uid ||
        !BusinessAccessService.hasBusinessAccess ||
        BusinessAccessService.businessUid.value != businessId ||
        BusinessAccessService.isOwner.value != isOwner ||
        BusinessAccessService.shopNickname.value.trim() != shop ||
        !BusinessAccessService.can('analytics', 'view') ||
        BusinessAccessService.can('stock', 'view') != canStock ||
        BusinessAccessService.can('jobs', 'view') != canDebts ||
        BusinessAccessService.can('tasks', 'view') != canTasks ||
        (BusinessAccessService.isOwner.value &&
                BusinessAccessService.can('invoices', 'view')) !=
            canPos) {
      throw StateError(
        'Business access changed while loading. Refresh and try again.',
      );
    }
    debugPrint('Business intelligence context loaded.');
    return BusinessContext(
      businessId: businessId,
      businessName: name.isEmpty ? 'Name unavailable' : name,
      period: period,
      updatedAt: DateTime.now(),
      income: summary.income,
      expenses: summary.expenses,
      transactionCount: summary.count,
      expenseCategories: summary.categories,
      lowStock: lowStock,
      receivable: receivable,
      payable: payable,
      limitations: limitations,
      pos: pos,
      incomeByDayUtc: summary.incomeByDayUtc,
      purchases: purchases,
      tasks: tasks,
    );
  }
}
