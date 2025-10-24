import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'transaction_model.dart';

class TransactionService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  static String _uidOrThrow() {
    final u = _auth.currentUser;
    if (u == null) throw StateError('Not signed in');
    return u.uid;
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
    await getCollectionRef().add(transaction);
  }

  static Future<void> updateTransaction(
    String id,
    TransactionModel transaction,
  ) async {
    await getCollectionRef().doc(id).set(transaction);
  }

  static Future<void> deleteTransaction(String id) async {
    await getCollectionRef().doc(id).delete();
  }

  static Future<QuerySnapshot<TransactionModel>> getTransactions({
    required int limit,
    DocumentSnapshot? startAfter,
    DateTime? startDate,
    DateTime? endDate,
  }) {
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
    if (startAfter != null) query = query.startAfterDocument(startAfter);
    return query.limit(limit).get();
  }

  static Future<Map<String, double>> getTotals({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final uid = _uidOrThrow();
    Query<TransactionModel> query = getCollectionRef();

    // Apply date filters if they exist
    if (startDate != null) {
      query = query.where('date', isGreaterThanOrEqualTo: startDate);
    }
    if (endDate != null) {
      query = query.where('date', isLessThan: endDate);
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
