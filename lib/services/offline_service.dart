import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
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

class OfflineService {
  static const String _pendingTransactionsKey = 'pending_transactions';
  static const String _pendingCategoriesKey = 'pending_categories';
  static const String _cachedCategoriesKey = 'cached_categories';
  static const String _pendingDeletionsKey = 'pending_deletions';

  static String _categoriesKey(String key) {
    return '$key.${BusinessAccessService.businessId}';
  }

  // Save transaction offline
  static Future<void> saveTransactionOffline(
    TransactionModel transaction,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final pendingTransactions = await getPendingTransactions();

    // Check if it's an update to an existing offline or online item
    final existingIndex = pendingTransactions.indexWhere(
      (t) => t.id == transaction.id,
    );

    if (existingIndex != -1) {
      // It's an update to an already pending item
      pendingTransactions[existingIndex] = transaction;
    } else {
      // It's a new item or an update to an item that was online
      // If it's new, generate a temporary ID
      final transactionWithId = transaction.id == null
          ? TransactionModel.fromJson({
              ...transaction.toJson(),
              'id': 'offline_${DateTime.now().millisecondsSinceEpoch}',
            })
          : transaction;
      pendingTransactions.add(transactionWithId);
    }

    await _writeJsonList(
      prefs,
      _pendingTransactionsKey,
      pendingTransactions.map((t) => t.toJson()).toList(),
    );
  }

  // Save category offline
  static Future<void> saveCategoryOffline(CategoryModel category) async {
    final prefs = await SharedPreferences.getInstance();
    final categoryWithId = CategoryModel.fromJson({
      ...category.toJson(),
      'id': category.id ?? 'offline_${DateTime.now().millisecondsSinceEpoch}',
    });

    final pendingCategories = await getPendingCategories();
    pendingCategories.add(categoryWithId);

    await _writeJsonList(
      prefs,
      _categoriesKey(_pendingCategoriesKey),
      pendingCategories.map((c) => c.toJson()).toList(),
    );
  }

  // Get pending transactions
  static Future<List<TransactionModel>> getPendingTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_pendingTransactionsKey);

    return _decodeJsonList(jsonString, TransactionModel.fromJson);
  }

  // Get pending categories
  static Future<List<CategoryModel>> getPendingCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_categoriesKey(_pendingCategoriesKey));
    return _decodeJsonList(jsonString, CategoryModel.fromJson);
  }

  // Cache categories for offline use
  static Future<void> cacheCategories(List<CategoryModel> categories) async {
    final prefs = await SharedPreferences.getInstance();
    await _writeJsonList(
      prefs,
      _categoriesKey(_cachedCategoriesKey),
      categories.map((c) => c.toJson()).toList(),
    );
  }

  // Get cached categories
  static Future<List<CategoryModel>> getCachedCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_categoriesKey(_cachedCategoriesKey));
    return _decodeJsonList(jsonString, CategoryModel.fromJson);
  }

  // NEW: Queue a transaction for deletion
  static Future<void> deleteTransactionOffline(String transactionId) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingDeletions = await getPendingDeletions();
    if (!pendingDeletions.contains(transactionId)) {
      pendingDeletions.add(transactionId);
      await prefs.setStringList(_pendingDeletionsKey, pendingDeletions);
    }
  }

  // NEW: Get pending deletions
  static Future<List<String>> getPendingDeletions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_pendingDeletionsKey) ?? [];
  }

  // Sync all pending data when online
  static Future<SyncResult> syncPendingData() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingTransactions = await getPendingTransactions();
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
        await CategoryService.addCategory(
          CategoryModel.fromJson({...category.toJson(), 'id': null}),
        );
        if (category.id != null) syncedCategoryIds.add(category.id!);
      } catch (e) {
        final errorMsg = 'Failed to sync category ${category.name}: $e';
        errors.add(errorMsg);
        print(errorMsg);
      }
    }

    for (final transaction in pendingTransactions) {
      try {
        // If ID is an 'offline_' ID, it's a new transaction.
        // Otherwise, it's an update to an existing one.
        if (transaction.id != null && transaction.id!.startsWith('offline_')) {
          await TransactionService.saveTransaction(
            TransactionModel.fromJson({...transaction.toJson(), 'id': null}),
          );
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
        print(errorMsg);
      }
    }

    for (final transactionId in pendingDeletions) {
      try {
        await TransactionService.deleteTransaction(transactionId);
        syncedDeletionIds.add(transactionId);
      } catch (e) {
        final errorMsg = 'Failed to sync deletion for ID $transactionId: $e';
        errors.add(errorMsg);
        print(errorMsg);
      }
    }

    // Atomically remove only the successfully synced items
    if (syncedCategoryIds.isNotEmpty) {
      final remaining = pendingCategories
          .where((c) => !syncedCategoryIds.contains(c.id))
          .toList();
      await _writeJsonList(
        prefs,
        _categoriesKey(_pendingCategoriesKey),
        remaining.map((c) => c.toJson()).toList(),
      );
    }
    if (syncedTransactionIds.isNotEmpty) {
      final remaining = pendingTransactions
          .where((t) => !syncedTransactionIds.contains(t.id))
          .toList();
      await _writeJsonList(
        prefs,
        _pendingTransactionsKey,
        remaining.map((t) => t.toJson()).toList(),
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

  // Clear all pending offline data
  static Future<void> clearPendingData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingTransactionsKey);
    await prefs.remove(_categoriesKey(_pendingCategoriesKey));
    await prefs.remove(_pendingDeletionsKey);
  }

  // Get count of pending items
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
