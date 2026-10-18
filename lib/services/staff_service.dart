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

class StaffService {
  static final _firestore = FirebaseFirestore.instance;
  static const _secondaryAppName = 'staff-account-creator';
  static const _staffAuthDomain = 'staff.tra-list.invalid';

  static String staffAuthEmail({
    required String businessEmail,
    required String password,
  }) {
    final identity = '${businessEmail.trim().toLowerCase()}|$password';
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

  static CollectionReference<Map<String, dynamic>> get _memberships =>
      _firestore.collection('employeeMemberships');

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchStaff() {
    if (!BusinessAccessService.isOwner.value) {
      throw StateError('Only the business owner can manage staff.');
    }
    return _memberships
        .where('businessUid', isEqualTo: BusinessAccessService.businessId)
        .snapshots();
  }

  static Future<String> createStaff({
    required String name,
    required String email,
    required String phone,
    required String shopNickname,
    required String password,
    required Map<String, Map<String, bool>> permissions,
  }) async {
    if (!BusinessAccessService.isOwner.value) {
      throw StateError('Only the business owner can add staff.');
    }
    final owner = FirebaseAuth.instance.currentUser;
    if (owner == null) {
      throw StateError('Sign in before adding staff.');
    }
    final businessEmail = owner.email?.trim().toLowerCase() ?? '';
    if (businessEmail.isEmpty) {
      throw StateError('The business owner account does not have an email.');
    }

    final businessProfile = await ProfileService.loadOrCreate();
    final businessName = businessProfile['name']?.toString().trim() ?? '';
    final assignedShopNickname = shopNickname.trim();
    if (assignedShopNickname.isEmpty) {
      throw StateError('Set a shop nickname before adding staff.');
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
        email: staffAuthEmail(businessEmail: businessEmail, password: password),
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
        'name': name.trim(),
        'email': email.trim(),
        'phone': phone.trim(),
        'active': true,
        'permissions': permissions,
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
    required Map<String, Map<String, bool>> permissions,
  }) async {
    final staffDocument = await _getManagedStaffDocument(employeeUid);
    await staffDocument.update({
      'name': name.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      'shopNickname': shopNickname.trim(),
      'permissions': permissions,
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
  _getManagedStaffDocument(String employeeUid) async {
    if (!BusinessAccessService.isOwner.value) {
      throw StateError('Only the business owner can manage staff access.');
    }
    if (employeeUid == FirebaseAuth.instance.currentUser?.uid) {
      throw StateError('A business owner cannot modify their own membership.');
    }
    final document = _memberships.doc(employeeUid);
    final membership = await document.get();
    if (membership.data()?['businessUid'] != BusinessAccessService.businessId) {
      throw StateError('This staff account does not belong to this business.');
    }
    return document;
  }
}
