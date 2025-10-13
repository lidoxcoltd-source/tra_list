import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tra_list/invoice/transaction_model.dart';
import 'package:tra_list/invoice/category_model.dart';
import 'package:tra_list/invoice/transaction_service.dart';
import 'package:tra_list/invoice/category_service.dart';

class OfflineService {
  static const String _pendingTransactionsKey = 'pending_transactions';
  static const String _pendingCategoriesKey = 'pending_categories';
  static const String _cachedCategoriesKey = 'cached_categories';

  // Save transaction offline
  static Future<void> saveTransactionOffline(
    TransactionModel transaction,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    // Generate a temporary ID if none exists
    final transactionWithId = TransactionModel.fromJson({
      ...transaction.toJson(),
      'id':
          transaction.id ?? 'offline_${DateTime.now().millisecondsSinceEpoch}',
    });

    final pendingTransactions = await getPendingTransactions();
    pendingTransactions.add(transactionWithId);

    final jsonList = pendingTransactions.map((t) => t.toJson()).toList();
    await prefs.setString(_pendingTransactionsKey, jsonEncode(jsonList));
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

    final jsonList = pendingCategories.map((c) => c.toJson()).toList();
    await prefs.setString(_pendingCategoriesKey, jsonEncode(jsonList));
  }

  // Get pending transactions
  static Future<List<TransactionModel>> getPendingTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_pendingTransactionsKey);

    if (jsonString == null) return [];

    final jsonList = jsonDecode(jsonString) as List;
    return jsonList.map((json) => TransactionModel.fromJson(json)).toList();
  }

  // Get pending categories
  static Future<List<CategoryModel>> getPendingCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_pendingCategoriesKey);

    if (jsonString == null) return [];

    final jsonList = jsonDecode(jsonString) as List;
    return jsonList.map((json) => CategoryModel.fromJson(json)).toList();
  }

  // Cache categories for offline use
  static Future<void> cacheCategories(List<CategoryModel> categories) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = categories.map((c) => c.toJson()).toList();
    await prefs.setString(_cachedCategoriesKey, jsonEncode(jsonList));
  }

  // Get cached categories
  static Future<List<CategoryModel>> getCachedCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_cachedCategoriesKey);

    if (jsonString == null) return [];

    final jsonList = jsonDecode(jsonString) as List;
    return jsonList.map((json) => CategoryModel.fromJson(json)).toList();
  }

  // Sync all pending data when online
  static Future<void> syncPendingTransactions() async {
    final pendingTransactions = await getPendingTransactions();
    final pendingCategories = await getPendingCategories();

    for (final category in pendingCategories) {
      try {
        await CategoryService.addCategory(
          CategoryModel.fromJson({...category.toJson(), 'id': null}),
        );
      } catch (e) {
        // Log error but continue with other categories
        print('Failed to sync category ${category.name}: $e');
      }
    }

    for (final transaction in pendingTransactions) {
      try {
        await TransactionService.saveTransaction(
          TransactionModel.fromJson({...transaction.toJson(), 'id': null}),
        );
      } catch (e) {
        // Log error but continue with other transactions
        print('Failed to sync transaction ${transaction.description}: $e');
      }
    }

    // Clear pending data after successful sync
    await clearPendingData();
  }

  // Clear all pending offline data
  static Future<void> clearPendingData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingTransactionsKey);
    await prefs.remove(_pendingCategoriesKey);
  }

  // Get count of pending items
  static Future<int> getPendingItemsCount() async {
    final transactions = await getPendingTransactions();
    final categories = await getPendingCategories();
    return transactions.length + categories.length;
  }
}
