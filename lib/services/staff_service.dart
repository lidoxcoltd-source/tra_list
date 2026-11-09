import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:tra_list/firebase_options.dart';
import 'business_access_service.dart';
import 'profile_service.dart';

class StaffMember {
  const StaffMember({
    required this.id,
    required this.data,
    this.isLegacy = false,
  });

  final String id;
  final Map<String, dynamic> data;
  final bool isLegacy;
}

class StaffService {
  static final _firestore = FirebaseFirestore.instance;
  static const _secondaryAppName = 'staff-account-creator';
  static const _staffAuthDomain = 'staff.tra-list.invalid';

  static String staffAuthEmail({
    required String businessEmail,
    required String username,
  }) {
    final identity =
        '${businessEmail.trim().toLowerCase()}|${username.trim().toLowerCase()}';
    final digest = sha256.convert(utf8.encode(identity));
    return 'staff.$digest@$_staffAuthDomain';
  }

  static String legacyStaffAuthEmail({
    required String businessEmail,
    required String username,
  }) {
    final identity =
        '${businessEmail.trim().toLowerCase()}|${username.trim().toLowerCase()}';
    final digest = sha256.convert(utf8.encode(identity));
    return 'staff.$digest@$_staffAuthDomain';
  }

  static String legacyPasswordStaffAuthEmail({
    required String businessEmail,
    required String password,
  }) {
    final identity = '${businessEmail.trim().toLowerCase()}|$password';
    final digest = sha256.convert(utf8.encode(identity));
    return 'staff.$digest@$_staffAuthDomain';
  }

  static CollectionReference<Map<String, dynamic>> get _memberships =>
      _firestore.collection('employeeMemberships');

  static Stream<List<StaffMember>> watchStaff() {
    if (!BusinessAccessService.canManageStaff) {
      throw StateError('You do not have permission to manage staff.');
    }
    final businessUid = BusinessAccessService.businessId;
    final controller = StreamController<List<StaffMember>>();
    List<StaffMember> legacyStaff = [];
    List<StaffMember> accountStaff = [];
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? legacySubscription;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
    accountSubscription;

    void emit() {
      final members = <String, StaffMember>{
        for (final member in legacyStaff) member.id: member,
        for (final member in accountStaff) member.id: member,
      };
      controller.add(members.values.toList());
    }

    legacySubscription = _memberships
        .where('businessUid', isEqualTo: businessUid)
        .snapshots()
        .listen((snapshot) {
          legacyStaff = snapshot.docs
              .map(
                (document) => StaffMember(
                  id: document.id,
                  data: document.data(),
                  isLegacy: true,
                ),
              )
              .where((member) => member.data['role'] != 'owner')
              .toList();
          emit();
        }, onError: controller.addError);
    accountSubscription = _firestore
        .collection('businessMemberships')
        .doc(businessUid)
        .collection('members')
        .snapshots()
        .listen((snapshot) {
          accountStaff = snapshot.docs
              .map(
                (document) =>
                    StaffMember(id: document.id, data: document.data()),
              )
              .where((member) => member.data['role'] != 'owner')
              .toList();
          emit();
        }, onError: controller.addError);
    controller.onCancel = () async {
      await legacySubscription?.cancel();
      await accountSubscription?.cancel();
    };
    return controller.stream;
  }

  static Future<List<StaffMember>> fetchStaff() async {
    if (!BusinessAccessService.canManageStaff) {
      throw StateError('You do not have permission to manage staff.');
    }
    final businessUid = BusinessAccessService.businessId;
    final accountFuture = _firestore
        .collection('businessMemberships')
        .doc(businessUid)
        .collection('members')
        .get();
    final legacyFuture = _memberships
        .where('businessUid', isEqualTo: businessUid)
        .get();
    final accountSnapshot = await accountFuture;
    final legacySnapshot = await legacyFuture;
    final members = <String, StaffMember>{};
    for (final document in legacySnapshot.docs ?? const []) {
      final data = document.data();
      if (data['role'] != 'owner') {
        members[document.id] = StaffMember(
          id: document.id,
          data: data,
          isLegacy: true,
        );
      }
    }
    for (final document in accountSnapshot.docs) {
      final data = document.data();
      if (data['role'] != 'owner') {
        members[document.id] = StaffMember(id: document.id, data: data);
      }
    }
    return members.values.toList();
  }

  static Future<String> createInvitation({
    required String email,
    required String name,
    required String phone,
    required String shopNickname,
    required Map<String, Map<String, bool>> permissions,
  }) async {
    if (!BusinessAccessService.isOwner.value) {
      throw StateError('Only the business owner can invite staff.');
    }
    final result = await FirebaseFunctions.instance
        .httpsCallable('createBusinessInvitation')
        .call<Map<String, dynamic>>({
          'businessUid': BusinessAccessService.businessId,
          'email': email.trim(),
          'name': name.trim(),
          'phone': phone.trim(),
          'shopNickname': shopNickname.trim(),
          'permissions': permissions,
        });
    final code = result.data['code']?.toString() ?? '';
    if (code.isEmpty) {
      throw StateError('The invitation response did not include a code.');
    }
    return code;
  }

  static Future<String> createStaff({
    required String name,
    required String email,
    required String phone,
    required String shopNickname,
    required String shopLocation,
    required String shopId,
    required String username,
    required String password,
    required Map<String, Map<String, bool>> permissions,
    required double dailyExpenseLimit,
    String barRole = 'waiter',
  }) async {
    _validateDailyExpenseLimit(dailyExpenseLimit);
    if (!const {'staff', 'waiter', 'bartender', 'manager'}.contains(barRole)) {
      throw ArgumentError.value(barRole, 'barRole', 'Unsupported bar role.');
    }
    if (barRole == 'manager' && !BusinessAccessService.isOwner.value) {
      throw StateError('Only the owner can appoint a staff manager.');
    }
    if (!BusinessAccessService.canManageStaff) {
      throw StateError('You do not have permission to add staff.');
    }
    final owner = FirebaseAuth.instance.currentUser;
    if (owner == null) {
      throw StateError('Sign in before adding staff.');
    }
    final businessProfile = await ProfileService.loadOrCreate();
    final profileEmail = businessProfile['email']?.toString().trim() ?? '';
    final fallbackEmail = BusinessAccessService.isOwner.value
        ? owner.email?.trim() ?? ''
        : '';
    final businessEmail =
        (profileEmail.isNotEmpty ? profileEmail : fallbackEmail).toLowerCase();
    if (businessEmail.isEmpty) {
      throw StateError('The business owner account does not have an email.');
    }

    final businessName = businessProfile['name']?.toString().trim() ?? '';
    final assignedShopNickname = shopNickname.trim();
    final assignedUsername = username.trim();
    if (assignedShopNickname.isEmpty) {
      throw StateError('Set a shop nickname before adding staff.');
    }
    if (assignedUsername.length < 3 || assignedUsername.length > 32) {
      throw ArgumentError('Username must contain 3 to 32 characters.');
    }
    if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(assignedUsername)) {
      throw ArgumentError('Username may contain letters, numbers, . _ and -.');
    }
    final usernameKey = assignedUsername.toLowerCase();
    final businessStaff = await _memberships
        .where('businessUid', isEqualTo: BusinessAccessService.businessId)
        .get();
    if (businessStaff.docs.any((document) {
      final data = document.data();
      final existingKey = data['usernameKey']?.toString().toLowerCase();
      final legacyKey = data['username']?.toString().toLowerCase();
      final legacyShop = data['shopNickname']?.toString().toLowerCase();
      return existingKey == usernameKey ||
          legacyKey == usernameKey ||
          (legacyKey == null && legacyShop == usernameKey);
    })) {
      throw StateError('staff_username_taken');
    }
    final existingApp = Firebase.apps.where(
      (app) => app.name == _secondaryAppName,
    );
    final secondaryApp = existingApp.isEmpty
        ? await Firebase.initializeApp(
            name: _secondaryAppName,
            options: DefaultFirebaseOptions.currentPlatform,
          )
        : existingApp.first;
    final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

    User? createdUser;
    try {
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: staffAuthEmail(
          businessEmail: businessEmail,
          username: assignedUsername,
        ),
        password: password,
      );
      createdUser = credential.user;
      if (createdUser == null) {
        throw StateError('Firebase did not return the new staff account.');
      }
      await createdUser.updateDisplayName(name.trim());

      await _memberships.doc(createdUser.uid).set({
        'employeeUid': createdUser.uid,
        'businessUid': BusinessAccessService.businessId,
        'businessEmail': businessEmail,
        'businessName': businessName,
        'shopNickname': assignedShopNickname,
        'shopLocation': shopLocation.trim(),
        'shopId': shopId.trim(),
        'username': assignedUsername,
        'usernameKey': usernameKey,
        'name': name.trim(),
        'photoUrl': '',
        'email': email.trim(),
        'phone': phone.trim(),
        'active': true,
        'permissions': permissions,
        'barRole': barRole,
        'dailyExpenseLimit': dailyExpenseLimit,
        'createdBy': FirebaseAuth.instance.currentUser!.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return createdUser.uid;
    } catch (error, stackTrace) {
      debugPrint('Failed to create staff account: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (createdUser != null) {
        try {
          await createdUser.delete();
        } catch (cleanupError, cleanupStackTrace) {
          debugPrint(
            'Could not remove incomplete staff account: $cleanupError',
          );
          debugPrintStack(stackTrace: cleanupStackTrace);
        }
      }
      rethrow;
    } finally {
      await secondaryAuth.signOut();
    }
  }

  static Future<void> updateStaff({
    required String employeeUid,
    required String name,
    required String email,
    required String phone,
    required String shopNickname,
    required String shopLocation,
    required String shopId,
    required Map<String, Map<String, bool>> permissions,
    required double dailyExpenseLimit,
    String? barRole,
  }) async {
    _validateDailyExpenseLimit(dailyExpenseLimit);
    final staffDocument = await _getManagedStaffDocument(employeeUid);
    final updates = <String, dynamic>{
      'name': name.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      'shopNickname': shopNickname.trim(),
      'shopLocation': shopLocation.trim(),
      'shopId': shopId.trim(),
      'permissions': permissions,
      'dailyExpenseLimit': dailyExpenseLimit,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (barRole != null) {
      updates['barRole'] = barRole;
    }
    await staffDocument.update(updates);
  }

  static Future<void> updateDailyExpenseLimit({
    required String employeeUid,
    required double dailyExpenseLimit,
  }) async {
    _validateDailyExpenseLimit(dailyExpenseLimit);
    final staffDocument = await _getManagedStaffDocument(employeeUid);
    await staffDocument.update({
      'dailyExpenseLimit': dailyExpenseLimit,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> setBarModeEnabled(bool enabled) async {
    if (!BusinessAccessService.isOwner.value) {
      throw StateError('Only the business owner can change Bar Mode.');
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in before changing Bar Mode.');
    await _firestore
        .collection('users')
        .doc(BusinessAccessService.businessId)
        .collection('barSettings')
        .doc('config')
        .set({
          'enabled': enabled,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': uid,
        });
    BusinessAccessService.updateBarModeEnabled(enabled);
  }

  static Future<void> setBarRole({
    required String employeeUid,
    required String role,
    bool preferLegacyMembership = false,
  }) async {
    if (!const {'staff', 'waiter', 'bartender', 'manager'}.contains(role)) {
      throw ArgumentError.value(role, 'role', 'Unsupported bar role.');
    }
    if (role == 'manager' && !BusinessAccessService.isOwner.value) {
      throw StateError('Only the owner can appoint a staff manager.');
    }
    final staffDocument = await _getManagedStaffDocument(
      employeeUid,
      preferLegacyMembership: preferLegacyMembership,
    );
    final currentMembership = await staffDocument.get();
    final currentBarRole = currentMembership.data()?['barRole'];
    await staffDocument.update({
      'barRole': role,
      if (role == 'manager' || currentBarRole == 'manager')
        'permissions.staff.manage': role == 'manager',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> updateStaffPassword({
    required String employeeUid,
    required String password,
  }) async {
    if (password.length < 6) {
      throw ArgumentError('Staff passwords must be at least 6 characters.');
    }
    await _getManagedStaffDocument(employeeUid);
    await FirebaseFunctions.instance
        .httpsCallable('updateStaffPassword')
        .call<Map<String, dynamic>>({
          'employeeUid': employeeUid,
          'newPassword': password,
        });
  }

  static Future<void> setActive(String employeeUid, bool active) async {
    final staffDocument = await _getManagedStaffDocument(employeeUid);
    await staffDocument.update({
      'active': active,
      if (active) 'removed': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> removeStaff(String employeeUid) async {
    final staffDocument = await _getManagedStaffDocument(employeeUid);
    await staffDocument.update({
      'active': false,
      'removed': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<DocumentReference<Map<String, dynamic>>>
  _getManagedStaffDocument(
    String employeeUid, {
    bool preferLegacyMembership = false,
  }) async {
    if (!BusinessAccessService.canManageStaff) {
      throw StateError('You do not have permission to manage staff access.');
    }
    if (employeeUid == FirebaseAuth.instance.currentUser?.uid) {
      throw StateError('You cannot modify your own staff membership.');
    }
    final businessUid = BusinessAccessService.businessId;
    final accountDocument = _firestore
        .collection('businessMemberships')
        .doc(businessUid)
        .collection('members')
        .doc(employeeUid);
    final legacyDocument = _memberships.doc(employeeUid);
    final documents = preferLegacyMembership
        ? [legacyDocument, accountDocument]
        : [accountDocument, legacyDocument];
    for (final document in documents) {
      final membership = await document.get();
      final targetPermissions = Map<String, dynamic>.from(
        membership.data()?['permissions'] as Map? ?? const {},
      );
      final targetStaffPermissions = Map<String, dynamic>.from(
        targetPermissions['staff'] as Map? ?? const {},
      );
      if (membership.data()?['businessUid'] == businessUid &&
          membership.data()?['role'] != 'owner' &&
          (BusinessAccessService.isOwner.value ||
              (membership.data()?['barRole'] != 'manager' &&
                  targetStaffPermissions['manage'] != true))) {
        return document;
      }
    }
    throw StateError('This staff account does not belong to this business.');
  }

  static void _validateDailyExpenseLimit(double amount) {
    if (!amount.isFinite || amount < 0 || amount > 1000000000) {
      throw ArgumentError.value(
        amount,
        'dailyExpenseLimit',
        'Must be between 0 and 1,000,000,000.',
      );
    }
  }
}
