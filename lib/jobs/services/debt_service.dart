import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tra_list/jobs/models/debt.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/notification_service.dart';

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

  /// Fresh, shop-scoped debt records for an explicit AI debt question.
  static Future<List<Debt>> loadForAssistant() async {
    if (!BusinessAccessService.can('jobs', 'view')) {
      throw StateError('You do not have permission to view debts.');
    }
    Query<Debt> query = _collection();
    if (!BusinessAccessService.isOwner.value) {
      query = query.where('shopNickname', isEqualTo: assignedShop);
    }
    final snapshot = await query.orderBy('createdAt', descending: true)
        .limit(100).get();
    return snapshot.docs.map((doc) => doc.data()).toList(growable: false);
  }

  static Future<Debt?> loadAssistantDebt(String debtId) async {
    if (!BusinessAccessService.can('jobs', 'view')) {
      throw StateError('You do not have permission to view debts.');
    }
    final snapshot = await _collection().doc(debtId).get();
    if (!snapshot.exists) return null;
    final debt = snapshot.data()!;
    if (!BusinessAccessService.isOwner.value &&
        debt.shopNickname != assignedShop) {
      return null;
    }
    return debt;
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
      evidenceUrls: debt.evidenceUrls,
      createdAt: debt.createdAt,
    );

    final reference = _collection().doc(savedDebt.id);
    final publicProofReference = _db
        .collection('users')
        .doc(BusinessAccessService.businessId)
        .collection('publicDebtProofs')
        .doc(savedDebt.id);
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
        transaction.set(publicProofReference, _publicProofData(savedDebt));
      });
    } else {
      final batch = _db.batch();
      batch.set(reference, savedDebt);
      batch.set(publicProofReference, _publicProofData(savedDebt));
      await batch.commit();
    }
    await NotificationService.notifyOwner(
      action: 'debt',
      summary:
          '${isEditing ? 'updated' : 'added'} debt for ${savedDebt.debtorName} (TSH ${savedDebt.principal.toStringAsFixed(0)})',
      amount: savedDebt.principal,
    );
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

    // Use the converted Debt reference so transaction.get returns a Debt,
    // including its computed `balance` getter, instead of a raw map.
    final reference = _collection().doc(debtId);
    final publicProofReference = _db
        .collection('users')
        .doc(BusinessAccessService.businessId)
        .collection('publicDebtProofs')
        .doc(debtId);
    final paymentReference = reference.collection('payments').doc();
    final userId = FirebaseAuth.instance.currentUser!.uid;
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists) throw StateError('This debt no longer exists.');
      final debt = snapshot.data()!;
      if (amount > debt.balance) {
        throw ArgumentError('Payment cannot be greater than the remaining balance.');
      }
      final nextAmountPaid = debt.amountPaid + amount;
      transaction.update(reference, {
        'amountPaid': nextAmountPaid,
        'lastPaymentId': paymentReference.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(publicProofReference, _publicProofData(
        debt,
        amountPaid: nextAmountPaid,
      ));
      transaction.set(paymentReference, {
        'amount': amount,
        'paidAt': Timestamp.fromDate(paidAt),
        'method': method,
        'notes': notes.trim(),
        'recordedBy': userId,
      });
    });
    await NotificationService.notifyOwner(
      action: 'debt',
      summary: 'recorded a debt payment of TSH ${amount.toStringAsFixed(0)}',
      amount: amount,
    );
  }

  static Future<void> delete(String debtId) async {
    if (!BusinessAccessService.can('jobs', 'delete')) {
      throw StateError('You do not have permission to delete debts.');
    }

    final reference = _collection().doc(debtId);
    final paymentSnapshot = await reference.collection('payments').get();
    final batch = _db.batch();
    for (final payment in paymentSnapshot.docs) {
      batch.delete(payment.reference);
    }
    batch.delete(reference);
    batch.delete(
      _db
          .collection('users')
          .doc(BusinessAccessService.businessId)
          .collection('publicDebtProofs')
          .doc(debtId),
    );
    await batch.commit();
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

  static Map<String, dynamic> _publicProofData(
    Debt debt, {
    double? amountPaid,
  }) => {
    'id': debt.id,
    'debtorName': debt.debtorName,
    'direction': debt.direction.name,
    'principal': debt.principal,
    'amountPaid': amountPaid ?? debt.amountPaid,
    'dueDate': debt.dueDate == null ? null : Timestamp.fromDate(debt.dueDate!),
    'shopNickname': debt.shopNickname,
    'createdAt': Timestamp.fromDate(debt.createdAt),
  };
}
