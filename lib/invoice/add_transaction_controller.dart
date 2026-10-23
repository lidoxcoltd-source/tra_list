import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/services/offline_service.dart';
import 'package:tra_list/services/profile_service.dart';
import 'package:tra_list/services/business_access_service.dart';
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
  final RxString categoriesError = ''.obs;

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
    categoriesError.value = '';
    try {
      List<CategoryModel> allCategories;
      try {
        final snapshot = await CategoryService.getCategoriesFromServer();
        allCategories = snapshot.docs.map((doc) => doc.data()).toList();
        await OfflineService.cacheCategories(allCategories);
      } catch (error, stackTrace) {
        debugPrint('Could not load categories from Firestore: $error');
        debugPrintStack(stackTrace: stackTrace);
        allCategories = await OfflineService.getCachedCategories();
        if (isOnline.value) {
          categoriesError.value = 'categories_load_failed'.tr;
        } else if (allCategories.isEmpty) {
          categoriesError.value = 'categories_offline_empty'.tr;
        }
      }
      final pendingCategories = await OfflineService.getPendingCategories();
      final knownCategories = allCategories
          .map((category) => '${category.type.name}:${category.name.trim()}')
          .toSet();
      allCategories.addAll(
        pendingCategories.where(
          (category) => knownCategories.add(
            '${category.type.name}:${category.name.trim()}',
          ),
        ),
      );
      _updateCategoryState(allCategories);
    } catch (error, stackTrace) {
      debugPrint('Could not load transaction categories: $error');
      debugPrintStack(stackTrace: stackTrace);
      categoriesError.value = 'categories_load_failed'.tr;
      incomeCategories.clear();
      expenseCategories.clear();
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

  Future<void> addNewCategory(String newCategoryName) async {
    final name = newCategoryName.trim();
    if (name.isEmpty) return;

    final categories = isExpense.value ? expenseCategories : incomeCategories;
    final existingCategory = categories.firstWhereOrNull(
      (category) => category.name.trim().toLowerCase() == name.toLowerCase(),
    );
    if (existingCategory != null) {
      selectedCategory.value = existingCategory.name;
      Get.snackbar('category'.tr, 'category_already_exists'.tr);
      return;
    }

    final newCategory = CategoryModel(
      name: name,
      type: isExpense.value ? TransactionType.expense : TransactionType.income,
    );
    categories.add(newCategory);
    selectedCategory.value = name;

    try {
      if (isOnline.value) {
        await CategoryService.addCategory(newCategory);
        Get.snackbar('success'.tr, 'category_added_success'.tr);
      } else {
        await OfflineService.saveCategoryOffline(newCategory);
        Get.snackbar('Saved Offline'.tr, 'category_saved_offline'.tr);
      }
      await loadCategories();
      selectedCategory.value = name;
    } catch (error, stackTrace) {
      debugPrint('Failed to save category "$name": $error');
      debugPrintStack(stackTrace: stackTrace);
      categories.removeWhere((category) => category.name == name);
      if (selectedCategory.value == name) selectedCategory.value = '';
      Get.snackbar('error'.tr, 'category_add_failed'.tr);
    }
  }

  Future<void> save() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated.');

      final amount = double.parse(amountC.text.replaceAll(',', ''));
      var shopNickname = _originalTransaction?.shopNickname ?? '';
      if (shopNickname.isEmpty && !BusinessAccessService.isOwner.value) {
        shopNickname = BusinessAccessService.shopNickname.value.trim();
      } else if (shopNickname.isEmpty) {
        final profile = await ProfileService.loadOrCreate();
        shopNickname = profile['shopNickname']?.toString().trim() ?? '';
        if (shopNickname.isEmpty) {
          shopNickname = profile['name']?.toString().trim() ?? '';
        }
      }
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
        shopNickname: shopNickname,
      );

      if (_originalTransaction != null &&
          (_originalTransaction.id ?? '').isNotEmpty) {
        // Use TransactionService to update
        await TransactionService.updateTransaction(
          _originalTransaction.id!,
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
