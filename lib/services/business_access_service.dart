import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

class DisabledAccountException implements Exception {
  const DisabledAccountException();
}

class BusinessAccessService {
  BusinessAccessService._();

  static const modules = <String, String>{
    'transactions': 'staff_module_transactions',
    'invoices': 'staff_module_invoices',
    'receipts': 'staff_module_receipts',
    'quotations': 'staff_module_quotations',
    'jobs': 'staff_module_jobs',
    'analytics': 'staff_module_analytics',
    'categories': 'staff_module_categories',
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
  static final isActive = false.obs;
  static final isReady = false.obs;
  static final permissions = <String, dynamic>{}.obs;
  static final businessName = ''.obs;
  static final shopNickname = ''.obs;

  static CollectionReference<Map<String, dynamic>> get _memberships =>
      FirebaseFirestore.instance.collection('employeeMemberships');

  static String get businessId {
    final id = businessUid.value;
    if (id.isEmpty) {
      throw StateError('Business access has not been initialized.');
    }
    return id;
  }

  static Future<void> initializeForCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      clear();
      return;
    }

    isReady.value = false;
    final accountAccess = await FirebaseFirestore.instance
        .collection('accountAccess')
        .doc(user.uid)
        .get();
    if (accountAccess.data()?['disabled'] == true) {
      clear();
      throw const DisabledAccountException();
    }

    final membership = await _memberships.doc(user.uid).get();
    if (!membership.exists) {
      businessUid.value = user.uid;
      isOwner.value = true;
      isActive.value = true;
      permissions.clear();
      businessName.value = '';
      shopNickname.value = '';
    } else {
      final data = membership.data()!;
      businessUid.value = data['businessUid']?.toString() ?? '';
      isOwner.value = false;
      isActive.value = data['active'] == true;
      businessName.value = data['businessName']?.toString().trim() ?? '';
      shopNickname.value = data['shopNickname']?.toString().trim() ?? '';
      permissions.assignAll(
        Map<String, dynamic>.from(data['permissions'] as Map? ?? const {}),
      );
    }
    isReady.value = true;
  }

  static bool can(String module, String action) {
    if (!isReady.value || !isActive.value) return false;
    if (isOwner.value) return true;
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
    return can('profile', 'view') ||
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
    if (route == '/invoices') {
      return can('invoices', 'view') || can('quotations', 'view');
    }
    final permission = switch (route) {
      '/transactions' => ('transactions', 'view'),
      '/invoice' => ('invoices', 'create'),
      '/add-receipt' => ('receipts', 'create'),
      '/receipts' => ('receipts', 'view'),
      '/quotation' => ('quotations', 'create'),
      '/jobs' => ('jobs', 'view'),
      '/jobs-archive' => ('jobs', 'view'),
      '/analytics' => ('analytics', 'view'),
      '/categories' => ('categories', 'view'),
      _ => null,
    };
    return permission != null && can(permission.$1, permission.$2);
  }

  static Map<String, Map<String, bool>> emptyPermissions() => {
    for (final module in modules.keys)
      module: {for (final action in actions.keys) action: false},
  };

  static void clear() {
    businessUid.value = '';
    isOwner.value = false;
    isActive.value = false;
    isReady.value = false;
    permissions.clear();
    businessName.value = '';
    shopNickname.value = '';
  }
}
