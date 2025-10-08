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

  static CollectionReference<TransactionModel> _collectionRef() {
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
    await _collectionRef().add(transaction);
  }

  static Future<void> updateTransaction(
    String id,
    TransactionModel transaction,
  ) async {
    await _collectionRef().doc(id).set(transaction);
  }

  static Future<void> deleteTransaction(String id) async {
    await _collectionRef().doc(id).delete();
  }

  static Future<QuerySnapshot<TransactionModel>> getTransactions({
    required int limit,
    DocumentSnapshot? startAfter,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    Query<TransactionModel> query = _collectionRef().orderBy(
      'date',
      descending: true,
    );

    if (startDate != null) {
      query = query.where('date', isGreaterThanOrEqualTo: startDate);
    }
    if (endDate != null) {
      query = query.where('date', isLessThanOrEqualTo: endDate);
    }
    if (startAfter != null) query = query.startAfterDocument(startAfter);
    return query.limit(limit).get();
  }
}
