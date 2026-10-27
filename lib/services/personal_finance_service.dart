import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PersonalFinanceService {
  PersonalFinanceService._();

  static final _firestore = FirebaseFirestore.instance;

  static String get _uid {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to access personal finance.');
    return user.uid;
  }

  static DocumentReference<Map<String, dynamic>> get _profile =>
      _firestore.collection('personalUsers').doc(_uid);

  static CollectionReference<Map<String, dynamic>> get _transactions =>
      _firestore
          .collection('personalUsers')
          .doc(_uid)
          .collection('transactions');

  static CollectionReference<Map<String, dynamic>> get _budgets =>
      _firestore.collection('personalUsers').doc(_uid).collection('budgets');

  static CollectionReference<Map<String, dynamic>> get _goals => _firestore
      .collection('personalUsers')
      .doc(_uid)
      .collection('savingsGoals');

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchTransactions() =>
      _transactions.orderBy('date', descending: true).snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchBudgets() =>
      _budgets.orderBy('name').snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchGoals() =>
      _goals.orderBy('name').snapshots();

  static Future<void> addTransaction({
    required String type,
    required String description,
    required String category,
    required double amount,
    required DateTime date,
  }) async {
    final normalizedType = type.trim().toLowerCase();
    if (!{'income', 'expense'}.contains(normalizedType) ||
        description.trim().isEmpty ||
        description.trim().length > 160 ||
        category.trim().isEmpty ||
        category.trim().length > 80 ||
        !amount.isFinite ||
        amount <= 0) {
      throw ArgumentError('Enter a valid personal transaction.');
    }
    await _transactions.add({
      'type': normalizedType,
      'description': description.trim(),
      'category': category.trim(),
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteTransaction(String id) =>
      _transactions.doc(id).delete();

  static Future<void> saveBudget({
    required String name,
    required double amount,
  }) async {
    _validatePlan(name, amount);
    await _budgets.add({
      'name': name.trim(),
      'amount': amount,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteBudget(String id) => _budgets.doc(id).delete();

  static Future<void> saveGoal({
    required String name,
    required double targetAmount,
    required double savedAmount,
  }) async {
    _validatePlan(name, targetAmount);
    if (!savedAmount.isFinite ||
        savedAmount < 0 ||
        savedAmount > targetAmount) {
      throw ArgumentError('Enter a valid savings amount.');
    }
    await _goals.add({
      'name': name.trim(),
      'targetAmount': targetAmount,
      'savedAmount': savedAmount,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> updateGoalSavedAmount({
    required String id,
    required double targetAmount,
    required double savedAmount,
  }) async {
    if (!targetAmount.isFinite ||
        targetAmount <= 0 ||
        !savedAmount.isFinite ||
        savedAmount < 0 ||
        savedAmount > targetAmount) {
      throw ArgumentError('Enter a valid savings amount.');
    }
    await _goals.doc(id).update({
      'savedAmount': savedAmount,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteGoal(String id) => _goals.doc(id).delete();

  static Future<Map<String, dynamic>> loadProfile() async {
    final snapshot = await _profile.get();
    final data = snapshot.data() ?? const <String, dynamic>{};
    return {
      'displayName':
          data['displayName']?.toString() ??
          FirebaseAuth.instance.currentUser?.displayName ??
          '',
      'photoUrl': data['photoUrl']?.toString() ?? '',
      'currency': data['currency']?.toString() ?? 'TZS',
      'dateFormat': data['dateFormat']?.toString() ?? 'dd/MM/yyyy',
      'notificationsEnabled': data['notificationsEnabled'] != false,
    };
  }

  static Future<void> saveProfile(Map<String, dynamic> data) async {
    final allowedCurrencies = {'TZS', 'KES', 'USD'};
    final allowedDateFormats = {'dd/MM/yyyy', 'MM/dd/yyyy', 'yyyy-MM-dd'};
    final currency = data['currency'];
    final dateFormat = data['dateFormat'];
    final displayName = data['displayName'];
    final photoUrl = data['photoUrl'];
    final photoUri = photoUrl is String && photoUrl.trim().isNotEmpty
        ? Uri.tryParse(photoUrl.trim())
        : null;
    if (currency is! String ||
        !allowedCurrencies.contains(currency) ||
        dateFormat is! String ||
        !allowedDateFormats.contains(dateFormat) ||
        displayName is! String ||
        displayName.trim().length > 100 ||
        photoUrl is! String ||
        photoUrl.length > 2048 ||
        (photoUrl.trim().isNotEmpty &&
            (photoUri == null ||
                photoUri.scheme != 'https' ||
                photoUri.host.isEmpty)) ||
        data['notificationsEnabled'] is! bool) {
      throw ArgumentError('Invalid personal profile preferences.');
    }
    await _profile.set({
      'displayName': displayName.trim(),
      'photoUrl': photoUrl.trim(),
      'currency': currency,
      'dateFormat': dateFormat,
      'notificationsEnabled': data['notificationsEnabled'],
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static void _validatePlan(String name, double amount) {
    if (name.trim().isEmpty ||
        name.trim().length > 80 ||
        !amount.isFinite ||
        amount <= 0) {
      throw ArgumentError('Enter a valid name and amount.');
    }
  }
}
