import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tra_list/jobs/models/debt.dart';
import 'package:tra_list/services/business_access_service.dart';

class DebtService {
  static final _db = FirebaseFirestore.instance;

  static CollectionReference<Debt> _collection() {
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError('Not signed in');
    }
    if (!BusinessAccessService.isOwner.value &&
        BusinessAccessService.shopNickname.value.trim().isEmpty) {
      throw StateError('The staff account has no assigned shop.');
    }
    return _db
        .collection('users')
        .doc(BusinessAccessService.businessId)
        .collection('debts')
        .withConverter<Debt>(
          fromFirestore: (snapshot, _) => Debt.fromFirestore(snapshot),
          toFirestore: (debt, _) => debt.toFirestore(),
        );
  }

  static String get assignedShop => BusinessAccessService.isOwner.value
      ? ''
      : BusinessAccessService.shopNickname.value.trim();

  static Stream<QuerySnapshot<Debt>> watchDebts() {
    if (!BusinessAccessService.can('jobs', 'view')) {
      throw StateError('You do not have permission to view debts.');
    }
    Query<Debt> query = _collection();
    if (!BusinessAccessService.isOwner.value) {
      query = query.where('shopNickname', isEqualTo: assignedShop);
    }
    return query.orderBy('createdAt', descending: true).snapshots();
  }

  static Future<void> save(Debt debt, {required bool isEditing}) async {
    final action = isEditing ? 'edit' : 'create';
    if (!BusinessAccessService.can('jobs', action)) {
      throw StateError('You do not have permission to $action debts.');
    }
    final shopNickname = BusinessAccessService.isOwner.value
        ? debt.shopNickname.trim()
        : assignedShop;
    if (shopNickname.isEmpty) {
      throw StateError('Choose a shop before saving this debt.');
    }

    final savedDebt = Debt(
      id: debt.id,
      debtorName: debt.debtorName.trim(),
      phone: debt.phone.trim(),
      direction: debt.direction,
      reason: debt.reason,
      notes: debt.notes.trim(),
      principal: debt.principal,
      amountPaid: debt.amountPaid,
      dueDate: debt.dueDate,
      shopNickname: shopNickname,
      createdAt: debt.createdAt,
    );

    final reference = _collection().doc(savedDebt.id);
    if (isEditing) {
      await _db.runTransaction((transaction) async {
        final snapshot = await transaction.get(reference);
        if (!snapshot.exists) throw StateError('This debt no longer exists.');
        final existing = snapshot.data()!;
        if (savedDebt.principal < existing.amountPaid) {
          throw StateError(
            'The debt amount cannot be less than payments made.',
          );
        }
        if (savedDebt.shopNickname != existing.shopNickname) {
          throw StateError('A debt cannot be moved to another shop.');
        }
        transaction.update(reference, {
          ...savedDebt.toFirestore(),
          'amountPaid': existing.amountPaid,
          'createdAt': Timestamp.fromDate(existing.createdAt),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } else {
      await reference.set(savedDebt);
    }
  }

  static Future<void> recordPayment({
    required String debtId,
    required double amount,
    required DateTime paidAt,
    required String method,
    required String notes,
  }) async {
    if (!BusinessAccessService.can('jobs', 'edit')) {
      throw StateError('You do not have permission to record debt payments.');
    }
    if (amount <= 0) throw ArgumentError('Payment must be greater than zero.');

    final reference = _collection().doc(debtId);
    final paymentReference = reference.collection('payments').doc();
    final userId = FirebaseAuth.instance.currentUser!.uid;
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists) throw StateError('This debt no longer exists.');
      final debt = snapshot.data()!;
      if (!BusinessAccessService.isOwner.value &&
          debt.shopNickname != assignedShop) {
        throw StateError('This debt belongs to another shop.');
      }
      if (amount > debt.balance) {
        throw ArgumentError('Payment cannot exceed the remaining balance.');
      }
      transaction.update(reference, {
        'amountPaid': debt.amountPaid + amount,
        'lastPaymentId': paymentReference.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(paymentReference, {
        'amount': amount,
        'paidAt': Timestamp.fromDate(paidAt),
        'method': method,
        'notes': notes.trim(),
        'recordedBy': userId,
      });
    });
  }

  static Stream<QuerySnapshot<DebtPayment>> watchPayments(String debtId) {
    final reference = _collection().doc(debtId);
    return reference
        .collection('payments')
        .withConverter<DebtPayment>(
          fromFirestore: (snapshot, _) => DebtPayment.fromFirestore(snapshot),
          toFirestore: (_, _) =>
              throw UnsupportedError('Debt payment history is read-only.'),
        )
        .orderBy('paidAt', descending: true)
        .snapshots();
  }
}
