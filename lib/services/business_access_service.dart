import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

class DisabledAccountException implements Exception {
  const DisabledAccountException();
}

class BusinessAccessOption {
  const BusinessAccessOption({
    required this.businessId,
    required this.businessName,
    required this.isOwner,
    required this.isActive,
    required this.isMembership,
    required this.isLegacyMembership,
    required this.permissions,
    required this.shopNickname,
    this.barRole = '',
    this.dailyExpenseLimit = 0,
  });

  final String businessId;
  final String businessName;
  final bool isOwner;
  final bool isActive;
  final bool isMembership;
  final bool isLegacyMembership;
  final Map<String, dynamic> permissions;
  final String shopNickname;
  final String barRole;
  final double dailyExpenseLimit;
}

class BusinessAccessService {
  BusinessAccessService._();

  static const modules = <String, String>{
    'transactions': 'staff_module_transactions',
    'invoices': 'staff_module_invoices',
    'receipts': 'staff_module_receipts',
    'quotations': 'staff_module_quotations',
    'jobs': 'staff_module_jobs',
    'tasks': 'staff_module_tasks',
    'analytics': 'staff_module_analytics',
    'categories': 'staff_module_categories',
    'stock': 'staff_module_stock',
    'profile': 'staff_module_profile',
  };

  static const actions = <String, String>{
    'view': 'staff_action_view',
    'create': 'staff_action_create',
    'edit': 'staff_action_edit',
    'delete': 'staff_action_delete',
  };

  static final businessUid = ''.obs;
  static final isOwner = false.obs;
  static final hasMembership = false.obs;
  static final isLegacyMembership = false.obs;
  static final isActive = false.obs;
  static final isReady = false.obs;
  static final permissions = <String, dynamic>{}.obs;
  static final businessName = ''.obs;
  static final shopNickname = ''.obs;
  static final dailyExpenseLimit = 0.0.obs;
  static final barModeEnabled = false.obs;
  static final barRole = ''.obs;
  static final availableBusinesses = <BusinessAccessOption>[].obs;
  static final _storage = GetStorage();
  static String? initializationError;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _barSettingsSubscription;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _membershipSubscription;
  static int _accessGeneration = 0;

  static CollectionReference<Map<String, dynamic>> get _memberships =>
      FirebaseFirestore.instance.collection('employeeMemberships');

  static String get businessId {
    final id = businessUid.value;
    if (id.isEmpty) {
      throw StateError('Business access has not been initialized.');
    }
    return id;
  }

  static bool get hasBusinessAccess =>
      isReady.value && isActive.value && businessUid.value.isNotEmpty;

  static Future<void> initializeForCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      clear();
      return;
    }

    clear();
    await ensureCurrentAccountEnabled();

    final businesses = <BusinessAccessOption>[];
    final ownBusinessProfile = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('profile')
        .doc('company')
        .get();
    if (ownBusinessProfile.exists) {
      final data = ownBusinessProfile.data() ?? const <String, dynamic>{};
      businesses.add(
        BusinessAccessOption(
          businessId: user.uid,
          businessName: data['name']?.toString().trim() ?? '',
          isOwner: true,
          isActive: true,
          isMembership: false,
          isLegacyMembership: false,
          permissions: <String, dynamic>{},
          shopNickname: data['shopNickname']?.toString().trim() ?? '',
        ),
      );
    }

    final legacyMembership = await _memberships.doc(user.uid).get();
    if (legacyMembership.exists) {
      businesses.add(
        _optionFromMembership(
          legacyMembership.data()!,
          isLegacyMembership: true,
        ),
      );
    }

    try {
      final modernMemberships = await FirebaseFirestore.instance
          .collectionGroup('members')
          .where('employeeUid', isEqualTo: user.uid)
          .get();
      for (final membership in modernMemberships.docs) {
        final data = membership.data();
        final businessId = data['businessUid']?.toString() ?? '';
        if (businessId.isEmpty) continue;
        final existingIndex = businesses.indexWhere(
          (option) => option.businessId == businessId,
        );
        if (existingIndex < 0) {
          businesses.add(_optionFromMembership(data));
        } else if (businesses[existingIndex].isLegacyMembership) {
          businesses[existingIndex] = _optionFromMembership(data);
        }
      }
    } on FirebaseException catch (error) {
      // Owners and legacy staff must still be able to open Business mode.
      if (error.code != 'permission-denied' &&
          error.code != 'failed-precondition') {
        rethrow;
      }
    }

    availableBusinesses.assignAll(businesses);
    final savedBusinessId = _storage.read<String>(
      'business_selection_${user.uid}',
    );
    BusinessAccessOption? selected;
    for (final option in businesses) {
      if (option.businessId == savedBusinessId && option.isActive) {
        selected = option;
        break;
      }
    }
    selected ??= businesses.where((option) => option.isActive).firstOrNull;
    selected ??= businesses.isEmpty ? null : businesses.first;

    if (selected == null) {
      clear();
      isReady.value = true;
      return;
    }
    _applySelection(selected);
    await _loadBarMode(selected);
    isReady.value = true;
  }

  static BusinessAccessOption _optionFromMembership(
    Map<String, dynamic> data, {
    bool isLegacyMembership = false,
  }) => BusinessAccessOption(
    businessId: data['businessUid']?.toString() ?? '',
    businessName: data['businessName']?.toString().trim() ?? '',
    isOwner: data['role'] == 'owner',
    isActive: data['active'] == true,
    isMembership: true,
    isLegacyMembership: isLegacyMembership,
    permissions: Map<String, dynamic>.from(
      data['permissions'] as Map? ?? const {},
    ),
    shopNickname: data['shopNickname']?.toString().trim() ?? '',
    barRole: data['barRole']?.toString() ?? '',
    dailyExpenseLimit: (data['dailyExpenseLimit'] as num?)?.toDouble() ?? 0,
  );

  static Future<void> selectBusiness(String id) async {
    BusinessAccessOption? selected;
    for (final option in availableBusinesses) {
      if (option.businessId == id && option.isActive) {
        selected = option;
        break;
      }
    }
    if (selected == null) {
      throw StateError('This business is not available to your account.');
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to choose a business.');
    await _storage.write('business_selection_$uid', id);
    _applySelection(selected);
    await _loadBarMode(selected);
  }

  static bool get isBartender => barRole.value == 'bartender';
  static bool get isBarBartender => barModeEnabled.value && isBartender;
  static bool get isBarWaiter =>
      barModeEnabled.value &&
      hasMembership.value &&
      isActive.value &&
      !isOwner.value &&
      !isBartender;
  static bool get canUseBarPos =>
      isOwner.value || isBarWaiter || can('invoices', 'create');

  static Future<void> _loadBarMode(BusinessAccessOption option) async {
    _cancelAccessSubscriptions();
    final generation = _accessGeneration;
    final id = businessUid.value;
    if (id.isEmpty) return;
    final firestore = FirebaseFirestore.instance;
    final settingsRef = firestore
        .collection('users')
        .doc(id)
        .collection('barSettings')
        .doc('config');
    final settings = await settingsRef.get();
    if (generation != _accessGeneration) return;
    barModeEnabled.value = settings.data()?['enabled'] == true;
    _barSettingsSubscription = settingsRef.snapshots().listen(
      (snapshot) {
        if (generation != _accessGeneration) return;
        barModeEnabled.value = snapshot.data()?['enabled'] == true;
      },
      onError: (Object error, StackTrace stackTrace) {
        if (generation != _accessGeneration) return;
        debugPrint('Could not load Bar Mode settings: $error');
        debugPrintStack(stackTrace: stackTrace);
        initializationError = 'Could not load Bar Mode settings: $error';
        barModeEnabled.value = true;
      },
    );

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (!option.isMembership || uid == null) return;
    final membershipRef = option.isLegacyMembership
        ? _memberships.doc(uid)
        : firestore
              .collection('businessMemberships')
              .doc(id)
              .collection('members')
              .doc(uid);
    final membership = await membershipRef.get();
    if (generation != _accessGeneration) return;
    if (!membership.exists) {
      throw StateError('The selected business membership no longer exists.');
    }
    _applyLiveMembership(membership.data()!);
    _membershipSubscription = membershipRef.snapshots().listen(
      (snapshot) {
        if (generation != _accessGeneration) return;
        final data = snapshot.data();
        if (data == null || data['active'] != true) {
          isActive.value = false;
          permissions.clear();
          barRole.value = '';
          return;
        }
        _applyLiveMembership(data);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (generation != _accessGeneration) return;
        debugPrint('Could not load staff access updates: $error');
        debugPrintStack(stackTrace: stackTrace);
        initializationError = 'Could not load staff access updates: $error';
        isActive.value = false;
        permissions.clear();
        barRole.value = '';
      },
    );
  }

  static void _applyLiveMembership(Map<String, dynamic> data) {
    isActive.value = data['active'] == true;
    permissions.assignAll(
      Map<String, dynamic>.from(data['permissions'] as Map? ?? const {}),
    );
    barRole.value = data['barRole']?.toString() ?? '';
  }

  static void _cancelAccessSubscriptions() {
    _accessGeneration++;
    final settingsSubscription = _barSettingsSubscription;
    final membershipSubscription = _membershipSubscription;
    _barSettingsSubscription = null;
    _membershipSubscription = null;
    if (settingsSubscription != null) unawaited(settingsSubscription.cancel());
    if (membershipSubscription != null) {
      unawaited(membershipSubscription.cancel());
    }
  }

  static void updateBarModeEnabled(bool enabled) {
    barModeEnabled.value = enabled;
  }

  static void _applySelection(BusinessAccessOption option) {
    businessUid.value = option.businessId;
    isOwner.value = option.isOwner;
    hasMembership.value = option.isMembership;
    isLegacyMembership.value = option.isLegacyMembership;
    isActive.value = option.isActive;
    permissions.assignAll(option.permissions);
    businessName.value = option.businessName;
    shopNickname.value = option.shopNickname;
    dailyExpenseLimit.value = option.dailyExpenseLimit;
    barRole.value = option.barRole;
  }

  static Future<void> ensureCurrentAccountEnabled() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null)
      throw StateError('Sign in before checking account access.');
    final accountAccess = await FirebaseFirestore.instance
        .collection('accountAccess')
        .doc(user.uid)
        .get();
    if (accountAccess.data()?['disabled'] == true) {
      clear();
      throw const DisabledAccountException();
    }
  }

  static bool can(String module, String action) {
    if (!isReady.value || !isActive.value) return false;
    if (isOwner.value) return true;
    if (isBarBartender) {
      if (module == 'transactions' || module == 'stock') return false;
      if (module == 'invoices') return action == 'create';
      return false;
    }
    final modulePermissions = Map<String, dynamic>.from(
      permissions[module] as Map? ?? const {},
    );
    if (modulePermissions[action] == true) return true;

    if (module == 'categories' && action == 'view') {
      return _hasPermission('transactions', 'create') ||
          _hasPermission('invoices', 'create') ||
          _hasPermission('quotations', 'create');
    }
    return false;
  }

  static bool canReadBusinessProfile() {
    return isBarWaiter ||
        can('profile', 'view') ||
        can('invoices', 'create') ||
        can('quotations', 'create') ||
        can('receipts', 'create') ||
        can('jobs', 'create');
  }

  static bool _hasPermission(String module, String action) {
    final modulePermissions = Map<String, dynamic>.from(
      permissions[module] as Map? ?? const {},
    );
    return modulePermissions[action] == true;
  }

  static bool canAccessRoute(String route) {
    if (isOwner.value) return true;
    if (isBarBartender) {
      if (route == '/tasks') return isActive.value;
      return route == '/pos' && can('invoices', 'create');
    }
    if (route == '/pos') return canUseBarPos;
    // Every active staff member can open their own assigned tasks.
    if (route == '/tasks') return isActive.value;
    if (route == '/invoices' || route == '/document-shares') {
      return can('invoices', 'view') || can('quotations', 'view');
    }
    final permission = switch (route) {
      '/transactions' => ('transactions', 'view'),
      '/AddTransactionPage' => ('transactions', 'create'),
      '/invoice' => ('invoices', 'create'),
      '/add-receipt' => ('receipts', 'create'),
      '/receipts' => ('receipts', 'view'),
      '/quotation' => ('quotations', 'create'),
      '/jobs' => ('jobs', 'view'),
      '/jobs-archive' => ('jobs', 'view'),
      '/analytics' => ('analytics', 'view'),
      '/categories' => ('categories', 'view'),
      '/stock' => ('stock', 'view'),
      '/pos' => ('invoices', 'create'),
      _ => null,
    };
    return permission != null && can(permission.$1, permission.$2);
  }

  static Map<String, Map<String, bool>> emptyPermissions() => {
    for (final module in modules.keys)
      module: {for (final action in actions.keys) action: false},
  };

  static void clear() {
    _cancelAccessSubscriptions();
    initializationError = null;
    businessUid.value = '';
    isOwner.value = false;
    hasMembership.value = false;
    isLegacyMembership.value = false;
    isActive.value = false;
    isReady.value = false;
    permissions.clear();
    businessName.value = '';
    shopNickname.value = '';
    dailyExpenseLimit.value = 0;
    barModeEnabled.value = false;
    barRole.value = '';
    availableBusinesses.clear();
  }
}
