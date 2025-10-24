import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/job_service.dart';
import '../models/job.dart';
import 'package:tra_list/invoice/transaction_model.dart';
import 'package:tra_list/invoice/transaction_service.dart';
import 'package:tra_list/services/profile_service.dart';
import 'package:url_launcher/url_launcher.dart';

enum JobSortOption {
  createdAtDesc,
  createdAtAsc,
  dueDateAsc,
  dueDateDesc,
  customerNameAsc,
  customerNameDesc,
}

class JobController extends GetxController {
  final jobs = <Job>[].obs;
  final isLoading = true.obs;

  // Search and Filter State
  final isSearching = false.obs;
  final searchQuery = ''.obs;
  final searchController = TextEditingController();

  // Sorting State
  final sortOption = JobSortOption.createdAtDesc.obs;

  @override
  void onInit() {
    super.onInit();
    jobs.bindStream(
      JobService.getJobsStream().map((snapshot) {
        isLoading.value = false;
        return snapshot.docs.map((doc) => doc.data()).toList();
      }),
    );

    searchController.addListener(() {
      searchQuery.value = searchController.text;
    });
  }

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }

  Future<void> addJob(Job job) async {
    try {
      await JobService.addJob(job);
      Get.snackbar('Success', 'Job added successfully');
    } catch (e) {
      Get.snackbar('Error', 'Failed to add job: $e');
    }
  }

  Future<void> updateJob(Job job) async {
    try {
      await JobService.updateJob(job.id, job.toFirestore());
      Get.snackbar('Success', 'Job updated successfully');
    } catch (e) {
      Get.snackbar('Error', 'Failed to update job: $e');
    }
  }

  Future<bool> confirmAndDeleteJob(String id) async {
    final confirm = await Get.dialog<bool>(
      AlertDialog(
        title: Text('delete_job'.tr),
        content: Text('Are you sure you want to delete this job?'.tr),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: Text('delete'.tr, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return confirm ?? false;
  }

  Future<void> deleteJob(String id) async {
    try {
      await JobService.deleteJob(id);
      Get.snackbar('Success', 'Job deleted');
    } catch (e) {
      Get.snackbar('Error', 'Failed to delete job: $e');
    }
  }

  Future<void> recordPaymentAsTransaction(Job job) async {
    if (job.advancePaid <= 0) {
      Get.snackbar('Info', 'No payment amount to record.');
      return;
    }

    final confirm = await Get.dialog<bool>(
      AlertDialog(
        title: Text('record_payment_confirm_title'.tr),
        content: Text(
          'record_payment_confirm_content'.trParams({
            'amount': job.advancePaid.toStringAsFixed(2),
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('cancel'.tr),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            child: Text('record_payment_in_transactions'.tr),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final transaction = TransactionModel(
        type: TransactionType.income,
        amount: job.advancePaid,
        description: 'Payment for job: ${job.jobType} from ${job.customerName}',
        category:
            'Job Payments', // This category will be auto-created if not present
        uid: JobService.getCollectionRef().parent!.id,
        date: DateTime.now(),
      );
      await TransactionService.saveTransaction(transaction);
      // Mark the job's payment as recorded
      await JobService.updateJob(job.id, {'paymentRecorded': true});

      Get.snackbar('success'.tr, 'Payment recorded in transactions.');
    } catch (e) {
      Get.snackbar('error'.tr, 'Failed to record payment: $e');
    }
  }

  Future<void> sendPaymentReminder(Job job) async {
    if (!job.isOverdue || job.balance <= 0) {
      Get.snackbar('Info', 'No overdue balance to remind for.');
      return;
    }

    try {
      final profile = await ProfileService.loadOrCreate();
      final companyName = profile['name']?.toString() ?? 'Us';

      final message = 'payment_reminder_message'.trParams({
        'client': job.customerName,
        'job_type': job.jobType,
        'balance': job.balance.toStringAsFixed(0),
        'company_name': companyName,
      });

      // Format phone number for WhatsApp URL
      String formattedPhone = job.phonePrimary
          .trim()
          .replaceAll('+', '')
          .replaceAll(' ', '');
      if (formattedPhone.startsWith('0')) {
        formattedPhone = '255${formattedPhone.substring(1)}';
      } else if (formattedPhone.length == 9 &&
          !formattedPhone.startsWith('255')) {
        formattedPhone = '255$formattedPhone';
      }

      final Uri whatsappUrl = Uri.parse(
        'https://wa.me/$formattedPhone?text=${Uri.encodeComponent(message)}',
      );

      if (!await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication)) {
        Get.snackbar(
          'Error',
          'Could not open WhatsApp. Is it installed?'.tr,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to send reminder: $e');
    }
  }

  Future<void> toggleImportant(String id) async {
    final job = jobs.firstWhereOrNull((j) => j.id == id);
    if (job != null) {
      await JobService.updateJob(id, {'isImportant': !job.isImportant});
    }
  }

  Future<void> markCompleted(String id, {bool value = true}) async {
    final job = jobs.firstWhereOrNull((j) => j.id == id);
    if (job == null) return;

    // If un-completing, just update and return.
    if (!value) {
      await JobService.updateJob(id, {'isCompleted': false});
      return;
    }

    // If completing the job, check for a balance.
    final balance = job.balance;
    bool recordFinalPayment = false;

    if (balance > 0) {
      final confirm = await Get.dialog<bool>(
        AlertDialog(
          title: Text('record_final_payment_title'.tr),
          content: Text(
            'record_final_payment_content'.trParams({
              'amount': balance.toStringAsFixed(2),
            }),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: Text('cancel'.tr),
            ),
            ElevatedButton(
              onPressed: () => Get.back(result: true),
              child: Text('save'.tr),
            ),
          ],
        ),
      );
      if (confirm == true) {
        recordFinalPayment = true;
      }
    }

    try {
      if (recordFinalPayment) {
        final transaction = TransactionModel(
          type: TransactionType.income,
          amount: balance,
          description:
              'Final payment for job: ${job.jobType} from ${job.customerName}',
          category:
              'Job Payments', // This category will be auto-created if not present
          uid: JobService.getCollectionRef().parent!.id,
          date: DateTime.now(),
        );
        await TransactionService.saveTransaction(transaction);
      }
      // Update job status to completed and mark as fully paid if balance was recorded.
      await JobService.updateJob(id, {
        'isCompleted': true,
        if (recordFinalPayment) 'advancePaid': job.totalAmount,
      });
    } catch (e) {
      Get.snackbar('error'.tr, 'Failed to update job status: $e');
    }
  }

  void toggleSearch() {
    isSearching.toggle();
    if (!isSearching.value) {
      searchController.clear();
    }
  }

  List<Job> get _sortedAndFilteredJobs {
    final sorted = List<Job>.from(jobs);
    sorted.sort((a, b) {
      switch (sortOption.value) {
        case JobSortOption.dueDateAsc:
          return a.dueDate.compareTo(b.dueDate);
        case JobSortOption.dueDateDesc:
          return b.dueDate.compareTo(a.dueDate);
        case JobSortOption.customerNameAsc:
          return a.customerName.toLowerCase().compareTo(
            b.customerName.toLowerCase(),
          );
        case JobSortOption.customerNameDesc:
          return b.customerName.toLowerCase().compareTo(
            a.customerName.toLowerCase(),
          );
        case JobSortOption.createdAtAsc:
          return a.createdAt.compareTo(b.createdAt);
        case JobSortOption.createdAtDesc:
        default:
          return b.createdAt.compareTo(a.createdAt);
      }
    });

    if (searchQuery.value.isEmpty) {
      return sorted;
    }

    final query = searchQuery.value.toLowerCase();
    return sorted.where((job) {
      return job.customerName.toLowerCase().contains(query) ||
          job.jobType.toLowerCase().contains(query) ||
          job.phonePrimary.contains(query);
    }).toList();
  }

  List<Job> get all => _sortedAndFilteredJobs;
  List<Job> get active => jobs.where((j) => !j.isCompleted).toList();
  List<Job> get completed => jobs.where((j) => j.isCompleted).toList();
  List<Job> get important => _sortedAndFilteredJobs
      .where((j) => j.isImportant && !j.isCompleted)
      .toList();
  List<Job> get outOfTime {
    final now = DateTime.now();
    return jobs.where((j) => !j.isCompleted && j.isOverdue).toList();
  }

  List<Job> get dueSoon =>
      active.where((j) => j.dueDanger || j.dueWarning || j.dueToday).toList();
}
