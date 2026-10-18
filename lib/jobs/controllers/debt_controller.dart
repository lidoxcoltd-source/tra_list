import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/jobs/models/debt.dart';
import 'package:tra_list/jobs/services/debt_service.dart';

enum DebtFilter { all, customerOwesShop, shopOwesOther, overdue, settled }

enum DebtSortOption {
  newest,
  oldest,
  highestBalance,
  lowestBalance,
  dueSoonest,
}

class DebtController extends GetxController {
  final debts = <Debt>[].obs;
  final isLoading = true.obs;
  final loadError = ''.obs;
  final filter = DebtFilter.all.obs;
  final reasonFilter = ''.obs;
  final sortOption = DebtSortOption.newest.obs;
  final searchQuery = ''.obs;
  final searchController = TextEditingController();
  StreamSubscription? _subscription;

  List<Debt> get filtered {
    final query = searchQuery.value.trim().toLowerCase();
    final results = debts.where((debt) {
      final matchesSearch =
          query.isEmpty ||
          debt.debtorName.toLowerCase().contains(query) ||
          debt.phone.toLowerCase().contains(query) ||
          debt.reason.toLowerCase().contains(query);
      final matchesFilter = switch (filter.value) {
        DebtFilter.all => true,
        DebtFilter.customerOwesShop =>
          debt.direction == DebtDirection.customerOwesShop,
        DebtFilter.shopOwesOther =>
          debt.direction == DebtDirection.shopOwesOther,
        DebtFilter.overdue => debt.isOverdue,
        DebtFilter.settled => debt.isSettled,
      };
      return matchesSearch &&
          matchesFilter &&
          (reasonFilter.value.isEmpty || debt.reason == reasonFilter.value);
    }).toList();
    return results..sort((a, b) {
      switch (sortOption.value) {
        case DebtSortOption.newest:
          return b.createdAt.compareTo(a.createdAt);
        case DebtSortOption.oldest:
          return a.createdAt.compareTo(b.createdAt);
        case DebtSortOption.highestBalance:
          return b.balance.compareTo(a.balance);
        case DebtSortOption.lowestBalance:
          return a.balance.compareTo(b.balance);
        case DebtSortOption.dueSoonest:
          if (a.dueDate == null) return b.dueDate == null ? 0 : 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
      }
    });
  }

  double get receivableBalance => debts
      .where((debt) => debt.direction == DebtDirection.customerOwesShop)
      .fold(0, (sum, debt) => sum + debt.balance);

  double get payableBalance => debts
      .where((debt) => debt.direction == DebtDirection.shopOwesOther)
      .fold(0, (sum, debt) => sum + debt.balance);

  int get overdueCount => debts.where((debt) => debt.isOverdue).length;

  @override
  void onInit() {
    super.onInit();
    searchController.addListener(() {
      searchQuery.value = searchController.text;
    });
    reload();
  }

  void reload() {
    isLoading.value = true;
    loadError.value = '';
    try {
      unawaited(_subscription?.cancel());
      _subscription = DebtService.watchDebts().listen(
        (snapshot) {
          debts.assignAll(snapshot.docs.map((doc) => doc.data()));
          isLoading.value = false;
          loadError.value = '';
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Failed to load debts: $error');
          debugPrintStack(stackTrace: stackTrace);
          loadError.value = error.toString();
          isLoading.value = false;
        },
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to subscribe to debts: $error');
      debugPrintStack(stackTrace: stackTrace);
      loadError.value = error.toString();
      isLoading.value = false;
    }
  }

  @override
  void onClose() {
    unawaited(_subscription?.cancel());
    searchController.dispose();
    super.onClose();
  }

  Future<void> save(Debt debt, {required bool isEditing}) async {
    try {
      await DebtService.save(debt, isEditing: isEditing);
      Get.snackbar(
        'success'.tr,
        isEditing ? 'debt_updated'.tr : 'debt_added'.tr,
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to save debt: $error');
      debugPrintStack(stackTrace: stackTrace);
      Get.snackbar('error'.tr, 'debt_save_error'.trParams({'error': '$error'}));
      rethrow;
    }
  }

  Future<void> recordPayment({
    required String debtId,
    required double amount,
    required DateTime paidAt,
    required String method,
    required String notes,
  }) async {
    try {
      await DebtService.recordPayment(
        debtId: debtId,
        amount: amount,
        paidAt: paidAt,
        method: method,
        notes: notes,
      );
      Get.snackbar('success'.tr, 'debt_payment_saved'.tr);
    } catch (error, stackTrace) {
      debugPrint('Failed to record debt payment: $error');
      debugPrintStack(stackTrace: stackTrace);
      Get.snackbar(
        'error'.tr,
        'debt_payment_save_error'.trParams({'error': '$error'}),
      );
      rethrow;
    }
  }
}
