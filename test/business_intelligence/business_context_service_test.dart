import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/business_context.dart';
import 'package:tra_list/business_intelligence/business_context_service.dart';
import 'package:tra_list/services/business_access_service.dart';

class TestUser extends Fake implements User {
  @override
  String get uid => 'staff';
}

class TestAuth extends Fake implements FirebaseAuth {
  @override
  User? get currentUser => TestUser();
}

void main() {
  test(
    'selected business and staff shop scope constrain aggregated data',
    () async {
      final db = FakeFirebaseFirestore();
      final day = DateTime(2024, 5, 1);
      final first = db.collection('users').doc('business-a');
      final second = db.collection('users').doc('business-b');
      Future<void> transaction(
        DocumentReference<Map<String, dynamic>> business,
        String id,
        String shop,
        int amount,
      ) => business.collection('transactions').doc(id).set({
        'date': Timestamp.fromDate(day),
        'shopNickname': shop,
        'type': 'income',
        'amount': amount,
      });
      await transaction(first, 'a', 'shop-a', 100);
      await transaction(first, 'b', 'shop-b', 200);
      await transaction(second, 'c', 'shop-a', 300);
      await transaction(first, 'outside', 'shop-a', 400);
      await first.collection('transactions').doc('outside').update({
        'date': Timestamp.fromDate(DateTime(2024, 5, 2)),
      });
      await first.collection('products').doc('low').set({
        'name': 'Item',
        'quantity': 1,
        'lowStockThreshold': 2,
        'unit': 'piece',
        'tracked': true,
      });
      await first.collection('products').doc('service').set({
        'name': 'Service',
        'tracked': false,
      });
      await first.collection('purchases').doc('purchase').set({
        'date': Timestamp.fromDate(day),
        'status': 'received',
        'total': 45,
        'supplier': 'Private supplier',
      });
      await second.collection('purchases').doc('other').set({
        'date': Timestamp.fromDate(day),
        'status': 'received',
        'total': 900,
      });
      await first.collection('tasks').doc('task').set({
        'status': 'approved',
        'approvedAt': Timestamp.fromDate(day),
        'title': 'Private task',
        'assigneeName': 'Private employee',
      });
      await first.collection('tasks').doc('open').set({'status': 'assigned'});
      await first.collection('debts').doc('a').set({
        'shopNickname': 'shop-a',
        'direction': 'customerOwesShop',
        'principal': 80,
        'amountPaid': 30,
        'debtorName': 'Private name',
        'phone': 'Private number',
      });
      await first.collection('debts').doc('b').set({
        'shopNickname': 'shop-b',
        'direction': 'customerOwesShop',
        'principal': 200,
        'amountPaid': 0,
      });
      BusinessAccessService.businessUid.value = 'business-a';
      BusinessAccessService.businessName.value = 'Business A';
      BusinessAccessService.isOwner.value = false;
      BusinessAccessService.isReady.value = true;
      BusinessAccessService.isActive.value = true;
      BusinessAccessService.shopNickname.value = 'shop-a';
      BusinessAccessService.permissions.assignAll({
        'analytics': {'view': true},
      });
      addTearDown(BusinessAccessService.clear);

      final service = BusinessContextService(firestore: db, auth: TestAuth());
      final report = await service.load(
        ReportingPeriod(day, DateTime(2024, 5, 2)),
      );
      expect(report.income, 100);
      expect(report.transactionCount, 1);
      expect(report.lowStock, isNull);
      expect(report.receivable, isNull);
      expect(report.tasks, isNull);
      expect(report.purchases, isNull);

      BusinessAccessService.permissions.assignAll({
        'analytics': {'view': true},
        'stock': {'view': true},
        'jobs': {'view': true},
        'tasks': {'view': true},
      });
      final expanded = await service.load(
        ReportingPeriod(day, DateTime(2024, 5, 2)),
      );
      expect(expanded.lowStock, ['Item (1 piece)']);
      expect(expanded.receivable, 50);
      expect(expanded.purchases?.total, 45);
      expect(expanded.tasks?.open, 1);
      expect(expanded.tasks?.approvedInPeriod, 1);
      expect(expanded.report(), isNot(contains('Private name')));
      expect(expanded.report(), isNot(contains('Private number')));
      expect(expanded.report(), isNot(contains('Private supplier')));
      expect(expanded.report(), isNot(contains('Private task')));
      expect(expanded.report(), isNot(contains('Private employee')));

      await first.collection('invoices').doc('pos').set({
        'source': 'pos',
        'kind': 'invoice',
        'createdAt': Timestamp.fromDate(day),
        'total': 70,
        'items': [
          {'description': 'Item', 'amount': 70},
        ],
        'client': {'name': 'Customer private name'},
      });
      await first.collection('invoices').doc('bar').set({
        'source': 'bar_order',
        'kind': 'invoice',
        'createdAt': Timestamp.fromDate(day),
        'total': 900,
        'items': [],
      });
      BusinessAccessService.isOwner.value = true;
      final ownerReport = await service.load(
        ReportingPeriod(day, DateTime(2024, 5, 2)),
      );
      expect(ownerReport.income, 300);
      expect(ownerReport.pos?.total, 70);
      expect(ownerReport.pos?.products, {'Item': 70});
      expect(ownerReport.report(), isNot(contains('Customer private name')));
      expect(ownerReport.incomeByDayUtc, {
        day.toUtc().toIso8601String().substring(0, 10): 300,
      });

      BusinessAccessService.isOwner.value = false;
      BusinessAccessService.businessUid.value = 'business-b';
      final otherReport = await service.load(
        ReportingPeriod(day, DateTime(2024, 5, 2)),
      );
      expect(otherReport.income, 300);

      BusinessAccessService.permissions.clear();
      await expectLater(
        service.load(ReportingPeriod(day, DateTime(2024, 5, 2))),
        throwsStateError,
      );
    },
  );
}
