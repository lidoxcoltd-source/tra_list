import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tra_list/services/business_access_service.dart';

class BusinessBranch {
  const BusinessBranch({
    required this.id,
    required this.name,
    this.location = '',
    required this.active,
    this.barModeEnabled = false,
  });

  final String id;
  final String name;
  final String location;
  final bool active;
  final bool barModeEnabled;

  factory BusinessBranch.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return BusinessBranch(
      id: document.id,
      name: data['name']?.toString() ?? '',
      location: data['location']?.toString() ?? '',
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

  static Future<String> createBranch({
    required String name,
    required String location,
  }) async {
    _requireOwner();
    final normalizedName = name.trim();
    final normalizedLocation = location.trim();
    if (normalizedName.isEmpty || normalizedName.length > 80) {
      throw ArgumentError('Branch names must contain 1 to 80 characters.');
    }
    if (normalizedLocation.isEmpty || normalizedLocation.length > 120) {
      throw ArgumentError('Branch locations must contain 1 to 120 characters.');
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
      'location': normalizedLocation,
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
    required String location,
  }) async {
    _requireOwner();
    final businessId = BusinessAccessService.businessId;
    final legacyStaff = await FirebaseFirestore.instance
        .collection('employeeMemberships')
        .where('businessUid', isEqualTo: businessId)
        .get();
    final assignedAccountStaff = await FirebaseFirestore.instance
        .collection('businessMemberships')
        .doc(businessId)
        .collection('members')
        .where('shopId', isEqualTo: branchId)
        .limit(1)
        .get();
    if (legacyStaff.docs.any(
          (document) => document.data()['shopId'] == branchId,
        ) ||
        assignedAccountStaff.docs.isNotEmpty) {
      throw StateError('staff_shop_location_assigned');
    }
    final normalizedName = name.trim();
    final normalizedLocation = location.trim();
    if (normalizedName.isEmpty || normalizedName.length > 80) {
      throw ArgumentError('Branch names must contain 1 to 80 characters.');
    }
    if (normalizedLocation.isEmpty || normalizedLocation.length > 120) {
      throw ArgumentError('Branch locations must contain 1 to 120 characters.');
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
      'location': normalizedLocation,
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
