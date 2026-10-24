import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:tra_list/invoice/transaction_model.dart';
import 'package:tra_list/invoice/category_model.dart';
import 'package:tra_list/invoice/transaction_service.dart';
import 'package:tra_list/invoice/category_service.dart';
import 'package:tra_list/services/business_access_service.dart';

/// A result object for the sync operation.
class SyncResult {
  final int successCount;
  final int failureCount;
  final List<String> errors;

  SyncResult({
    this.successCount = 0,
    this.failureCount = 0,
    this.errors = const [],
  });
}

class PendingTransaction {
  const PendingTransaction({required this.transaction, required this.isCreate});

  final TransactionModel transaction;
  final bool isCreate;

  Map<String, dynamic> toJson() => {
    'operation': isCreate ? 'create' : 'update',
    'transaction': transaction.toJson(),
  };

  factory PendingTransaction.fromJson(Map<String, dynamic> json) {
    final raw = json['transaction'];
    if (raw is Map) {
      return PendingTransaction(
        transaction: TransactionModel.fromJson(Map<String, dynamic>.from(raw)),
        isCreate: json['operation'] == 'create',
      );
    }
    final transaction = TransactionModel.fromJson(json);
    return PendingTransaction(
      transaction: transaction,
      isCreate: transaction.id?.startsWith('offline_') ?? false,
    );
  }
}

class OfflineService {
  static const _uuid = Uuid();
  static Future<SyncResult>? _syncInFlight;

  static String get _userScope {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');
    return '${BusinessAccessService.businessId}.${user.uid}';
  }

  static String get _pendingTransactionsKey =>
      'pending_transactions.$_userScope';
  static String get _pendingCategoriesKey =>
      'pending_categories.${BusinessAccessService.businessId}';
  static String get _cachedCategoriesKey =>
      'cached_categories.${BusinessAccessService.businessId}';
  static String get _pendingDeletionsKey => 'pending_deletions.$_userScope';

  static String newLocalId() => 'offline_${_uuid.v4()}';

  // Save transaction offline
  static Future<TransactionModel> saveTransactionOffline(
    TransactionModel transaction, {
    required bool isCreate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingTransactions = await _getPendingTransactionRecords();
    final savedTransaction = transaction.id == null
        ? TransactionModel.fromJson({
            ...transaction.toJson(),
            'id': newLocalId(),
          })
        : transaction;
    final existingIndex = pendingTransactions.indexWhere(
      (item) => item.transaction.id == savedTransaction.id,
    );
    if (existingIndex != -1) {
      pendingTransactions[existingIndex] = PendingTransaction(
        transaction: savedTransaction,
        isCreate: pendingTransactions[existingIndex].isCreate,
      );
    } else {
      pendingTransactions.add(
        PendingTransaction(transaction: savedTransaction, isCreate: isCreate),
      );
    }
    await _writeJsonList(
      prefs,
      _pendingTransactionsKey,
      pendingTransactions.map((item) => item.toJson()).toList(),
    );
    return savedTransaction;
  }

  // Save category offline
  static Future<void> saveCategoryOffline(CategoryModel category) async {
    final prefs = await SharedPreferences.getInstance();
    final categoryWithId = CategoryModel.fromJson({
      ...category.toJson(),
      'id': category.id ?? newLocalId(),
    });

    final pendingCategories = await getPendingCategories();
    final existingIndex = pendingCategories.indexWhere(
      (item) => item.id == categoryWithId.id,
    );
    if (existingIndex == -1) {
      pendingCategories.add(categoryWithId);
    } else {
      pendingCategories[existingIndex] = categoryWithId;
    }

    await _writeJsonList(
      prefs,
      _pendingCategoriesKey,
      pendingCategories.map((c) => c.toJson()).toList(),
    );
  }

  // Get pending transactions
  static Future<List<TransactionModel>> getPendingTransactions() async {
    return (await _getPendingTransactionRecords())
        .map((item) => item.transaction)
        .toList();
  }

  static Future<List<PendingTransaction>>
  _getPendingTransactionRecords() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeJsonList(
      prefs.getString(_pendingTransactionsKey),
      PendingTransaction.fromJson,
    );
  }

  static Future<bool> deletePendingTransaction(String transactionId) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = await _getPendingTransactionRecords();
    final existing = pending
        .where((item) => item.transaction.id == transactionId)
        .firstOrNull;
    if (existing == null) return false;

    pending.removeWhere((item) => item.transaction.id == transactionId);
    await _writeJsonList(
      prefs,
      _pendingTransactionsKey,
      pending.map((item) => item.toJson()).toList(),
    );
    if (!existing.isCreate) {
      final deletions = await getPendingDeletions();
      if (!deletions.contains(transactionId)) {
        deletions.add(transactionId);
        await prefs.setStringList(_pendingDeletionsKey, deletions);
      }
    }
    return true;
  }

  // Get pending categories
  static Future<List<CategoryModel>> getPendingCategories() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeJsonList(
      prefs.getString(_pendingCategoriesKey),
      CategoryModel.fromJson,
    );
  }

  // Cache categories for offline use
  static Future<void> cacheCategories(List<CategoryModel> categories) async {
    final prefs = await SharedPreferences.getInstance();
    await _writeJsonList(
      prefs,
      _cachedCategoriesKey,
      categories.map((c) => c.toJson()).toList(),
    );
  }

  // Get cached categories
  static Future<List<CategoryModel>> getCachedCategories() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeJsonList(
      prefs.getString(_cachedCategoriesKey),
      CategoryModel.fromJson,
    );
  }

  static Future<void> deleteTransactionOffline(String transactionId) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingDeletions = await getPendingDeletions();
    if (!pendingDeletions.contains(transactionId)) {
      pendingDeletions.add(transactionId);
      await prefs.setStringList(_pendingDeletionsKey, pendingDeletions);
    }
  }

  static Future<List<String>> getPendingDeletions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_pendingDeletionsKey) ?? [];
  }

  static Future<SyncResult> syncPendingData() {
    final inFlight = _syncInFlight;
    if (inFlight != null) return inFlight;
    final operation = _performSyncPendingData();
    _syncInFlight = operation;
    return operation.whenComplete(() => _syncInFlight = null);
  }

  static Future<SyncResult> _performSyncPendingData() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingTransactions = await _getPendingTransactionRecords();
    final pendingCategories = await getPendingCategories();
    final pendingDeletions = await getPendingDeletions();

    if (pendingTransactions.isEmpty &&
        pendingCategories.isEmpty &&
        pendingDeletions.isEmpty) {
      return SyncResult(); // Nothing to sync
    }

    final syncedCategoryIds = <String>{};
    final syncedTransactionIds = <String>{};
    final syncedDeletionIds = <String>{};
    final errors = <String>[];

    for (final category in pendingCategories) {
      try {
        // Only create new categories, updates are not handled in this logic
        await CategoryService.addCategory(category);
        if (category.id != null) syncedCategoryIds.add(category.id!);
      } catch (e) {
        final errorMsg = 'Failed to sync category ${category.name}: $e';
        errors.add(errorMsg);
        debugPrint(errorMsg);
      }
    }

    for (final pending in pendingTransactions) {
      final transaction = pending.transaction;
      try {
        if (pending.isCreate) {
          await TransactionService.saveTransaction(transaction);
        } else if (transaction.id != null) {
          await TransactionService.updateTransaction(
            transaction.id!,
            transaction,
          );
        }
        if (transaction.id != null) syncedTransactionIds.add(transaction.id!);
      } catch (e) {
        final errorMsg =
            'Failed to sync transaction ${transaction.description}: $e';
        errors.add(errorMsg);
        debugPrint(errorMsg);
      }
    }

    for (final transactionId in pendingDeletions) {
      try {
        await TransactionService.deleteTransaction(transactionId);
        syncedDeletionIds.add(transactionId);
      } catch (e) {
        final errorMsg = 'Failed to sync deletion for ID $transactionId: $e';
        errors.add(errorMsg);
        debugPrint(errorMsg);
      }
    }

    // Atomically remove only the successfully synced items
    if (syncedCategoryIds.isNotEmpty) {
      final remaining = pendingCategories
          .where((c) => !syncedCategoryIds.contains(c.id))
          .toList();
      await _writeJsonList(
        prefs,
        _pendingCategoriesKey,
        remaining.map((c) => c.toJson()).toList(),
      );
    }
    if (syncedTransactionIds.isNotEmpty) {
      final remaining = pendingTransactions
          .where((item) => !syncedTransactionIds.contains(item.transaction.id))
          .toList();
      await _writeJsonList(
        prefs,
        _pendingTransactionsKey,
        remaining.map((item) => item.toJson()).toList(),
      );
    }
    if (syncedDeletionIds.isNotEmpty) {
      final remaining = pendingDeletions
          .where((id) => !syncedDeletionIds.contains(id))
          .toList();
      await prefs.setStringList(_pendingDeletionsKey, remaining);
    }

    return SyncResult(
      successCount:
          syncedCategoryIds.length +
          syncedTransactionIds.length +
          syncedDeletionIds.length,
      failureCount: errors.length,
      errors: errors,
    );
  }

  static Future<void> clearPendingData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingTransactionsKey);
    await prefs.remove(_pendingCategoriesKey);
    await prefs.remove(_pendingDeletionsKey);
  }

  static Future<int> getPendingItemsCount() async {
    final transactions = await getPendingTransactions();
    final categories = await getPendingCategories();
    final deletions = await getPendingDeletions();
    return transactions.length + categories.length + deletions.length;
  }

  // --- Private Helpers ---

  static Future<void> _writeJsonList(
    SharedPreferences prefs,
    String key,
    List<Map<String, dynamic>> list,
  ) async {
    await prefs.setString(key, jsonEncode(list));
  }

  static List<T> _decodeJsonList<T>(
    String? jsonString,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (jsonString == null || jsonString.isEmpty) return [];
    final jsonList = jsonDecode(jsonString) as List;
    return jsonList.map((json) => fromJson(json)).toList();
  }
}
