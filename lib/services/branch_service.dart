import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tra_list/services/business_access_service.dart';

class BusinessBranch {
  const BusinessBranch({
    required this.id,
    required this.name,
    required this.active,
    this.barModeEnabled = false,
  });

  final String id;
  final String name;
  final bool active;
  final bool barModeEnabled;

  factory BusinessBranch.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return BusinessBranch(
      id: document.id,
      name: data['name']?.toString() ?? '',
      active: data['active'] != false,
      barModeEnabled: data['barModeEnabled'] == true,
    );
  }
}

class BranchService {
  BranchService._();

  static CollectionReference<Map<String, dynamic>> get _branches =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(BusinessAccessService.businessId)
          .collection('branches');

  static Stream<List<BusinessBranch>> watchBranches() => _branches
      .orderBy('name')
      .snapshots()
      .map((snapshot) => snapshot.docs.map(BusinessBranch.fromDoc).toList());

  static Future<List<BusinessBranch>> fetchBranches() async {
    final snapshot = await _branches.orderBy('name').get();
    return snapshot.docs.map(BusinessBranch.fromDoc).toList();
  }

  static Future<String> createBranch(String name) async {
    _requireOwner();
    final normalizedName = name.trim();
    if (normalizedName.isEmpty || normalizedName.length > 80) {
      throw ArgumentError('Branch names must contain 1 to 80 characters.');
    }

    final normalizedKey = _nameKey(normalizedName);
    final existing = await _branches
        .where('nameKey', isEqualTo: normalizedKey)
        .limit(1)
        .get();
    if (existing.docs.any((document) => document.data()['active'] != false)) {
      throw StateError('A branch with this name already exists.');
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in before creating a branch.');
    final reference = _branches.doc();
    await reference.set({
      'businessId': BusinessAccessService.businessId,
      'name': normalizedName,
      'nameKey': normalizedKey,
      'active': true,
      'barModeEnabled': false,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return reference.id;
  }

  static Future<void> updateBranch({
    required String branchId,
    required String name,
  }) async {
    _requireOwner();
    final normalizedName = name.trim();
    if (normalizedName.isEmpty || normalizedName.length > 80) {
      throw ArgumentError('Branch names must contain 1 to 80 characters.');
    }
    final normalizedKey = _nameKey(normalizedName);
    final existing = await _branches
        .where('nameKey', isEqualTo: normalizedKey)
        .limit(2)
        .get();
    if (existing.docs.any(
      (document) =>
          document.id != branchId && document.data()['active'] != false,
    )) {
      throw StateError('A branch with this name already exists.');
    }
    await _branches.doc(branchId).update({
      'name': normalizedName,
      'nameKey': normalizedKey,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> setBranchActive({
    required String branchId,
    required bool active,
  }) async {
    _requireOwner();
    await _branches.doc(branchId).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> setBranchBarMode({
    required String branchId,
    required bool enabled,
  }) async {
    _requireOwner();
    await _branches.doc(branchId).update({
      'barModeEnabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static String _nameKey(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static void _requireOwner() {
    if (!BusinessAccessService.isOwner.value) {
      throw StateError('Only the business owner can manage branches.');
    }
  }
}
