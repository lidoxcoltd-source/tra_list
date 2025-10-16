import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/jobs/controllers/job_controller.dart';
import 'package:tra_list/jobs/views/add_job_page.dart';
import '../models/job.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class JobCard extends StatelessWidget {
  final Job job;
  const JobCard({super.key, required this.job});

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
    final textTheme = theme.textTheme;
    final c = Get.find<JobController>();
    final double paymentProgress = (job.totalAmount > 0)
        ? (job.paid / job.totalAmount).clamp(0, 1)
        : 0;

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.1),
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _statusColor(), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min, // add this
          crossAxisAlignment:
              CrossAxisAlignment.start, // optional: keeps content aligned
          children: [
            // --- Header: Title, Status, and Actions ---
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (job.isImportant)
                  Icon(Icons.star, color: Colors.amber.shade600, size: 20),
                if (job.isImportant) const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(job.customerName, style: textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(job.jobType, style: textTheme.bodyMedium),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (job.phonePrimary.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.message),
                    color: Colors.green,
                    tooltip: 'Chat on WhatsApp',
                    onPressed: () => _launchWhatsApp(job.phonePrimary),
                  ),
                _buildPopupMenu(c, context),
              ],
            ),
            const SizedBox(height: 12),

            // --- Status Badge ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor().withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusText().toUpperCase(),
                style: textTheme.labelMedium?.copyWith(
                  color: _statusColor(),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const Divider(height: 24),

            // --- Financials ---
            _buildStatRow(
              context,
              'Total',
              'TSH ${job.totalAmount.toStringAsFixed(0)}',
              'Balance',
              'TSH ${job.balance.toStringAsFixed(0)}',
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: paymentProgress,
                minHeight: 8,
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(_statusColor()),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${(paymentProgress * 100).toStringAsFixed(0)}% Paid',
                style: textTheme.labelSmall?.copyWith(color: Colors.grey[600]),
              ),
            ),
            const Divider(height: 24),

            // --- Dates ---
            _buildStatRow(
              context,
              'Start Date',
              DateFormat.yMMMd().format(job.startDate),
              'Due Date',
              DateFormat.yMMMd().format(job.dueDate),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(
    BuildContext context,
    String label1,
    String value1,
    String label2,
    String value2,
  ) {
    return Row(
      children: [
        Expanded(child: _buildStat(context, label1, value1)),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStat(
            context,
            label2,
            value2,
            alignment: CrossAxisAlignment.end,
          ),
        ),
      ],
    );
  }

  Widget _buildStat(
    BuildContext context,
    String label,
    String value, {
    CrossAxisAlignment alignment = CrossAxisAlignment.start,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          label.tr,
          style: textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
        ),
        const SizedBox(height: 2),
        Text(value, style: textTheme.titleMedium),
      ],
    );
  }

  Widget _buildPopupMenu(JobController c, BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More actions'.tr,
      icon: const Icon(Icons.more_vert),
      onSelected: (value) async {
        switch (value) {
          case 'edit':
            Get.to(() => AddJobPage(job: job));
            break;
          case 'toggle_important':
            c.toggleImportant(job.id);
            break;
          case 'record_payment':
            c.recordPaymentAsTransaction(job);
            break;
          case 'send_reminder':
            c.sendPaymentReminder(job);
            break;
          case 'mark_complete':
            c.markCompleted(job.id, value: !job.isCompleted);
            break;
          case 'delete':
            if (await c.confirmAndDeleteJob(job.id)) {
              c.deleteJob(job.id);
            }
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: const Icon(Icons.edit),
            title: Text('edit'.tr),
          ),
        ),
        PopupMenuItem(
          value: 'toggle_important',
          child: ListTile(
            leading: Icon(
              job.isImportant ? Icons.star : Icons.star_border,
              color: Colors.amber.shade700,
            ),
            title: Text('jobs_important'.tr),
          ),
        ),
        if (!job.isCompleted)
          PopupMenuItem(
            value: 'mark_complete',
            child: ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: Text('mark_complete'.tr),
            ),
          ),
        if (job.isCompleted)
          PopupMenuItem(
            value: 'mark_complete',
            child: ListTile(
              leading: const Icon(Icons.undo),
              title: Text('Mark as Active'.tr),
            ),
          ),
        const PopupMenuDivider(),
        if (job.advancePaid > 0)
          PopupMenuItem(
            value: 'record_payment',
            enabled: !job.paymentRecorded,
            child: ListTile(
              leading: Icon(
                job.paymentRecorded ? Icons.check_circle : Icons.add_card,
                color: job.paymentRecorded ? Colors.green : null,
              ),
              title: Text('record_payment_in_transactions'.tr),
            ),
          ),
        if (job.isOverdue && job.balance > 0)
          PopupMenuItem(
            value: 'send_reminder',
            child: ListTile(
              leading: Icon(
                Icons.notification_add,
                color: Colors.blue.shade700,
              ),
              title: Text('send_payment_reminder'.tr),
            ),
          ),
        if (job.phonePrimary.isNotEmpty)
          PopupMenuItem(
            value: 'whatsapp',
            child: ListTile(
              leading: const Icon(Icons.message, color: Colors.green),
              title: Text('Chat on WhatsApp'.tr),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: Text('delete'.tr, style: const TextStyle(color: Colors.red)),
          ),
        ),
      ],
    );
  }
}
