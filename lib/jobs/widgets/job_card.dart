import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/jobs/controllers/job_controller.dart';
import 'package:tra_list/jobs/views/add_job_page.dart';
import '../models/job.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class JobCard extends StatelessWidget {
  final Job job;
  // final VoidCallback onToggleImportant;
  // final VoidCallback onMarkComplete;
  // final VoidCallback onDelete;
  // final VoidCallback onEdit;

  const JobCard({
    super.key,
    required this.job,
    // required this.onToggleImportant,
    // required this.onMarkComplete,
    // required this.onDelete,
    // required this.onEdit,
  });

  Color _statusColor() {
    if (job.isCompleted) return Colors.blueGrey;
    if (job.isOverdue) return Colors.red.shade700;
    if (job.dueDanger) return Colors.red;
    if (job.dueWarning) return Colors.orange;
    return Colors.green;
  }

  String _statusText() {
    if (job.isCompleted) return 'jobs_completed'.tr;
    if (job.isOverdue) {
      final days = job.remainingDays.abs();
      return 'overdue_by_days'.trParams({'days': '$days'});
    }
    if (job.dueToday) return 'due_today'.tr;
    if (job.dueDanger || job.dueWarning) {
      return 'due_in_days'.trParams({'days': '${job.remainingDays}'});
    }
    return 'due_in_days'.trParams({'days': '${job.remainingDays}'});
  }

  Future<void> _launchWhatsApp(String phoneNumber) async {
    // Basic formatting for Tanzanian numbers
    String formattedPhone = phoneNumber
        .trim()
        .replaceAll('+', '')
        .replaceAll(' ', '');
    if (formattedPhone.startsWith('0')) {
      formattedPhone = '255${formattedPhone.substring(1)}';
    } else if (formattedPhone.length == 9 &&
        !formattedPhone.startsWith('255')) {
      // Handles cases like 712345678 -> 255712345678
      formattedPhone = '255$formattedPhone';
    }

    final Uri whatsappUrl = Uri.parse('https://wa.me/$formattedPhone');

    if (!await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication)) {
      Get.snackbar(
        'Error',
        'Could not open WhatsApp. Is it installed?',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = Get.find<JobController>();
    return Card(
      child: ListTile(
        leading: Icon(Icons.work, color: _statusColor()),
        title: Text(
          '${job.customerName} • ${job.jobType}',
          style: theme.textTheme.titleMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Wrap(
              spacing: 8.0,
              runSpacing: 4.0,
              children: [
                InkWell(
                  onTap: () => _launchWhatsApp(job.phonePrimary),
                  borderRadius: BorderRadius.circular(8),
                  child: Text(
                    job.phonePrimary,
                    style: TextStyle(
                      color: theme.primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (job.phoneSecondary != null &&
                    job.phoneSecondary!.isNotEmpty)
                  InkWell(
                    onTap: () => _launchWhatsApp(job.phoneSecondary!),
                    borderRadius: BorderRadius.circular(8),
                    child: Text(
                      '| ${job.phoneSecondary}',
                      style: TextStyle(
                        color: theme.primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.play_circle_outline,
                  size: 14,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '${'start_date'.tr}: ${DateFormat.yMd().format(job.startDate)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.flag_outlined,
                  size: 14,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '${'due_date'.tr}: ${DateFormat.yMd().format(job.dueDate)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                  label: Text(_statusText()),
                  backgroundColor: _statusColor().withOpacity(.12),
                  labelStyle: TextStyle(color: _statusColor()),
                  side: BorderSide(color: _statusColor()),
                ),
                Chip(
                  label: Text('${'paid'.tr}: ${job.paid.toStringAsFixed(2)}'),
                ),
                Chip(
                  label: Text(
                    '${'balance'.tr}: ${job.balance.toStringAsFixed(2)}',
                  ),
                  backgroundColor: job.paidInFull
                      ? Colors.green.withOpacity(.12)
                      : null,
                  labelStyle: job.paidInFull
                      ? const TextStyle(color: Colors.green)
                      : null,
                ),
                if (job.isImportant)
                  Chip(
                    avatar: const Icon(
                      Icons.star,
                      size: 18,
                      color: Colors.amber,
                    ),
                    label: Text('jobs_important'.tr),
                  ),
              ],
            ),
          ],
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: 'jobs_important'.tr,
              icon: Icon(
                job.isImportant ? Icons.star : Icons.star_border,
                color: job.isImportant ? Colors.amber : null,
              ),
              onPressed: () => c.toggleImportant(job.id),
            ),
            IconButton(
              tooltip: job.paymentRecorded
                  ? 'Payment already recorded'.tr
                  : 'record_payment_in_transactions'.tr,
              icon: Icon(
                job.paymentRecorded
                    ? Icons.check_circle
                    : Icons.add_card_outlined,
                color: job.paymentRecorded ? Colors.green : null,
              ),
              onPressed: job.paymentRecorded
                  ? null
                  : () => c.recordPaymentAsTransaction(job),
            ),
            if (job.isOverdue && job.balance > 0)
              IconButton(
                tooltip: 'send_payment_reminder'.tr,
                icon: Icon(
                  Icons.notification_add_outlined,
                  color: Colors.blue.shade700,
                ),
                onPressed: () => c.sendPaymentReminder(job),
              ),
            IconButton(
              tooltip: 'edit'.tr,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Get.to(() => AddJobPage(job: job)),
            ),
            IconButton(
              tooltip: 'mark_complete'.tr,
              icon: Icon(
                job.isCompleted ? Icons.undo : Icons.check_circle,
                color: job.isCompleted ? Colors.blueGrey : Colors.green,
              ),
              onPressed: () => c.markCompleted(job.id, value: !job.isCompleted),
            ),
            IconButton(
              tooltip: 'delete_job'.tr,
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: () async {
                if (await c.confirmAndDeleteJob(job.id)) c.deleteJob(job.id);
              },
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}
