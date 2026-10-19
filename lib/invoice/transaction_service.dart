import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'transaction_model.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/notification_service.dart';

class TransactionService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  static String _uidOrThrow() {
    if (_auth.currentUser == null) throw StateError('Not signed in');
    return BusinessAccessService.businessId;
  }

  static String? _shopFilter(String? requestedShopNickname) {
    if (BusinessAccessService.isOwner.value) return requestedShopNickname;

    final assignedShop = BusinessAccessService.shopNickname.value.trim();
    if (assignedShop.isEmpty) {
      throw StateError('Staff account is not assigned to a shop.');
    }
    return assignedShop;
  }

  static void _requireAssignedShop(TransactionModel transaction) {
    if (BusinessAccessService.isOwner.value) return;

    final assignedShop = BusinessAccessService.shopNickname.value.trim();
    if (assignedShop.isEmpty ||
        transaction.shopNickname.trim() != assignedShop) {
      throw StateError(
        'Staff can only save transactions for their assigned shop.',
      );
    }
  }

  static CollectionReference<TransactionModel> getCollectionRef() {
    final uid = _uidOrThrow();
    return _db
        .collection('users')
        .doc(uid)
        .collection('transactions')
        .withConverter<TransactionModel>(
          fromFirestore: (snap, _) => TransactionModel.fromFirestore(snap),
          toFirestore: (model, _) => model.toFirestore(),
        );
  }

  static Future<void> saveTransaction(TransactionModel transaction) async {
    if (!BusinessAccessService.can('transactions', 'create')) {
      throw StateError('You do not have permission to add transactions.');
    }
    _requireAssignedShop(transaction);
    await getCollectionRef().add(transaction);
    await NotificationService.notifyOwner(
      action: 'transaction',
      summary:
          'added ${transaction.type.name} TSH ${transaction.amount.toStringAsFixed(0)} — ${transaction.description}',
      amount: transaction.amount,
    );
  }

  static Future<void> updateTransaction(
    String id,
    TransactionModel transaction,
  ) async {
    if (!BusinessAccessService.can('transactions', 'edit')) {
      throw StateError('You do not have permission to edit transactions.');
    }
    _requireAssignedShop(transaction);
    await getCollectionRef().doc(id).set(transaction);
    await NotificationService.notifyOwner(
      action: 'transaction',
      summary:
          'updated ${transaction.type.name} to TSH ${transaction.amount.toStringAsFixed(0)} — ${transaction.description}',
      amount: transaction.amount,
    );
  }

  static Future<void> deleteTransaction(String id) async {
    if (!BusinessAccessService.can('transactions', 'delete')) {
      throw StateError('You do not have permission to delete transactions.');
    }
    await getCollectionRef().doc(id).delete();
    await NotificationService.notifyOwner(
      action: 'transaction',
      summary: 'deleted a transaction',
    );
  }

  static Future<QuerySnapshot<TransactionModel>> getTransactions({
    required int limit,
    DocumentSnapshot? startAfter,
    DateTime? startDate,
    DateTime? endDate,
    String? shopNickname,
    String? category,
  }) {
    final effectiveShopNickname = _shopFilter(shopNickname);
    Query<TransactionModel> query = getCollectionRef().orderBy(
      'date',
      descending: true,
    );

    if (startDate != null) {
      query = query.where('date', isGreaterThanOrEqualTo: startDate);
    }
    if (endDate != null) {
      query = query.where('date', isLessThan: endDate);
    }
    if (effectiveShopNickname != null && effectiveShopNickname.isNotEmpty) {
      query = query.where('shopNickname', isEqualTo: effectiveShopNickname);
    }
    if (category != null && category.isNotEmpty) {
      query = query.where('category', isEqualTo: category);
    }
    if (startAfter != null) query = query.startAfterDocument(startAfter);
    return query.limit(limit).get();
  }

  static Future<Map<String, double>> getTotals({
    DateTime? startDate,
    DateTime? endDate,
    String? shopNickname,
    String? category,
  }) async {
    final effectiveShopNickname = _shopFilter(shopNickname);
    Query<TransactionModel> query = getCollectionRef();

    // Apply date filters if they exist
    if (startDate != null) {
      query = query.where('date', isGreaterThanOrEqualTo: startDate);
    }
    if (endDate != null) {
      query = query.where('date', isLessThan: endDate);
    }
    if (effectiveShopNickname != null && effectiveShopNickname.isNotEmpty) {
      query = query.where('shopNickname', isEqualTo: effectiveShopNickname);
    }
    if (category != null && category.isNotEmpty) {
      query = query.where('category', isEqualTo: category);
    }

    // Run two separate aggregation queries (one for income, one for expense)
    // by applying the 'type' filter on the query before aggregation.
    final incomeAggregateSnapshot = await query
        .where('type', isEqualTo: 'income')
        .aggregate(sum('amount'))
        .get();

    final expenseAggregateSnapshot = await query
        .where('type', isEqualTo: 'expense')
        .aggregate(sum('amount'))
        .get();

    final incomeSum = incomeAggregateSnapshot.getSum('amount') ?? 0.0;
    final expenseSum = expenseAggregateSnapshot.getSum('amount') ?? 0.0;

    return {'income': incomeSum, 'expense': expenseSum};
  }

  /// Checks if a category is currently used by any transaction.
  static Future<bool> isCategoryInUse(String categoryName) async {
    try {
      final query = getCollectionRef()
          .where('category', isEqualTo: categoryName)
          .limit(1);
      final snapshot = await query.get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      // On error, assume it's in use to be safe.
      return true;
    }
  }
}
