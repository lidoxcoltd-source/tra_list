import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/services/offline_service.dart';
import 'package:tra_list/services/profile_service.dart';
import 'category_model.dart';
import 'category_service.dart';
import 'transaction_model.dart';
import 'transaction_service.dart';

class AddTransactionController extends GetxController {
  // Transaction Data
  final descC = TextEditingController();
  final amountC = TextEditingController();
  final isExpense = true.obs;
  final selectedCategory = ''.obs;
  final selectedDate = DateTime.now().obs;

  // UI State
  final RxBool busy = false.obs;
  final RxBool categoriesLoading = true.obs;

  // Categories
  final RxList<CategoryModel> incomeCategories = <CategoryModel>[].obs;
  final RxList<CategoryModel> expenseCategories = <CategoryModel>[].obs;

  // Theming
  final Rx<Color> brandColor = const Color(0xFF1976D2).obs;
  final Rx<Color> accentColor = const Color(0xFF42A5F5).obs;

  // Connectivity
  final RxBool isOnline = true.obs;
  final Connectivity _connectivity = Connectivity();

  // Original transaction for editing
  final TransactionModel? _originalTransaction;

  // Helper to know if we are creating a new transaction or editing an existing one.
  bool get isNewTransaction => _originalTransaction == null;

  AddTransactionController({
    TransactionModel? transaction,
    TransactionType? initialType,
  }) : _originalTransaction = transaction {
    if (transaction != null) {
      isExpense.value = transaction.type == TransactionType.expense;
      descC.text = transaction.description;
      amountC.text = transaction.amount.toStringAsFixed(
        0,
      ); // Assuming no decimals for display
      selectedCategory.value = transaction.category;
      selectedDate.value = transaction.date;
    } else if (initialType != null) {
      isExpense.value = initialType == TransactionType.expense;
    }
  }

  @override
  Future<void> onInit() async {
    super.onInit();
    ProfileService.loadAndSetLanguage();

    // **FIX**: Await connectivity check before loading data
    await _initConnectivity();
    await loadCategories();
    await loadBrandColors();

    _connectivity.onConnectivityChanged.listen((results) {
      if (results.isNotEmpty) {
        _updateConnectionStatus(results.first);
      }
    });
  }

  @override
  void onClose() {
    descC.dispose();
    amountC.dispose();
    super.onClose();
  }

  Future<void> _initConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      await _updateConnectionStatus(results.first);
    } catch (e) {
      await _updateConnectionStatus(ConnectivityResult.none);
    }
  }

  Future<void> _updateConnectionStatus(ConnectivityResult result) async {
    final wasOnline = isOnline.value;
    bool newOnlineStatus = result != ConnectivityResult.none;

    if (newOnlineStatus) {
      newOnlineStatus = await _hasInternetConnection();
    }

    isOnline.value = newOnlineStatus;

    if (!wasOnline && isOnline.value) {
      _showConnectivityStatus();
      _syncOfflineData();
    }
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  void _showConnectivityStatus() {
    final message = isOnline.isTrue
        ? 'Back online - transactions will sync automatically'.tr
        : 'No internet connection - transactions will be saved offline'.tr;
    final backgroundColor = isOnline.isTrue ? Colors.green : Colors.orange;

    Get.snackbar(
      isOnline.isTrue ? 'Connected'.tr : 'Offline Mode'.tr,
      message,
      snackPosition: SnackPosition.TOP,
      backgroundColor: backgroundColor,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
      icon: Icon(
        isOnline.isTrue ? Icons.wifi : Icons.wifi_off,
        color: Colors.white,
      ),
    );
  }

  Future<void> _syncOfflineData() async {
    final result = await OfflineService.syncPendingData();
    if (result.failureCount > 0) {
      Get.snackbar(
        'Sync Error'.tr,
        '${'Failed to sync some offline transactions'.tr}: ${result.errors.join(", ")}',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
    } else if (result.successCount > 0) {
      Get.snackbar(
        'Sync Complete'.tr,
        '${result.successCount} offline item(s) have been synced'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    }
  }

  Future<void> loadBrandColors() async {
    try {
      final profile = await ProfileService.loadOrCreate();
      if (profile.containsKey('colors')) {
        final colors = profile['colors'] as Map<String, dynamic>;
        brandColor.value = Color(colors['brand'] as int? ?? 0xFF1976D2);
        accentColor.value = Color(colors['accent'] as int? ?? 0xFFFFA000);
      }
    } catch (e) {
      debugPrint('Could not load profile colors: $e');
    }
  }

  Future<void> loadCategories() async {
    categoriesLoading.value = true;
    try {
      List<CategoryModel> allCategories;
      if (isOnline.value) {
        try {
          final snapshot = await CategoryService.getCategoriesStream().first;
          allCategories = snapshot.docs.map((doc) => doc.data()).toList();
          await OfflineService.cacheCategories(allCategories);
        } catch (e) {
          allCategories = await OfflineService.getCachedCategories();
        }
      } else {
        allCategories = await OfflineService.getCachedCategories();
      }
      _updateCategoryState(allCategories);
    } catch (e) {
      _useDefaultCategories();
    } finally {
      categoriesLoading.value = false;
    }
  }

  void _updateCategoryState(List<CategoryModel> allCategories) {
    incomeCategories.value = allCategories
        .where((c) => c.type == TransactionType.income)
        .toList();
    expenseCategories.value = allCategories
        .where((c) => c.type == TransactionType.expense)
        .toList();
  }

  void _useDefaultCategories() {
    expenseCategories.value = [
      CategoryModel(name: 'Food & Dining', type: TransactionType.expense),
      CategoryModel(name: 'Transportation', type: TransactionType.expense),
    ];
    incomeCategories.value = [
      CategoryModel(name: 'Salary', type: TransactionType.income),
      CategoryModel(name: 'Business', type: TransactionType.income),
    ];
  }

  Future<void> addNewCategory(String newCategoryName) async {
    try {
      final newCategory = CategoryModel(
        name: newCategoryName,
        type: isExpense.value
            ? TransactionType.expense
            : TransactionType.income,
      );

      // Optimistically update the UI
      if (isExpense.value) {
        expenseCategories.add(newCategory);
      } else {
        incomeCategories.add(newCategory);
      }
      selectedCategory.value = newCategoryName;

      // Persist to the database
      await CategoryService.addCategory(newCategory);
      Get.snackbar('Success', 'Category added successfully');
    } catch (e) {
      debugPrint('Failed to add category: $e');
      Get.snackbar('Error', 'Failed to add category');
      await loadCategories(); // Reload from DB to revert optimistic update on failure
    }
  }

  Future<void> save() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated.');

      final amount = double.parse(amountC.text.replaceAll(',', ''));
      final transaction = TransactionModel(
        id: _originalTransaction?.id,
        uid: user.uid,
        description: descC.text.trim(),
        amount: amount,
        type: isExpense.value
            ? TransactionType.expense
            : TransactionType.income,
        category: selectedCategory.value,
        date: selectedDate.value,
      );

      if (_originalTransaction != null &&
          (_originalTransaction!.id ?? '').isNotEmpty) {
        // Use TransactionService to update
        await TransactionService.updateTransaction(
          _originalTransaction!.id!,
          transaction,
        );
      } else {
        // Use TransactionService to save a new transaction
        await TransactionService.saveTransaction(transaction);
      }
    } on FirebaseException catch (e) {
      debugPrint('Firestore save failed: ${e.code} ${e.message}');
      rethrow;
    } catch (e, st) {
      debugPrint('Save error: $e\n$st');
      rethrow;
    }
  }
}
