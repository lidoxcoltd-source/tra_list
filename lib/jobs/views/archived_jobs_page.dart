import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:tra_list/job_service.dart';
import 'package:tra_list/jobs/models/job.dart';

class ArchivedJobsPage extends StatelessWidget {
  const ArchivedJobsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: Get.locale?.toString() ?? 'en_TZ',
      symbol: 'TZS ',
      decimalDigits: 0,
    );
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F8),
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Get.back(),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text('debt_legacy_archive'.tr),
        backgroundColor: const Color(0xFFF5F7F8),
        foregroundColor: const Color(0xFF19313A),
      ),
      body: StreamBuilder(
        stream: JobService.getJobsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('debt_archive_load_error'.tr));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final jobs = snapshot.data!.docs.map((doc) => doc.data()).toList();
          if (jobs.isEmpty) {
            return Center(child: Text('debt_archive_empty'.tr));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: jobs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) =>
                _ArchivedJobCard(job: jobs[index], money: money),
          );
        },
      ),
    );
  }
}

class _ArchivedJobCard extends StatelessWidget {
  const _ArchivedJobCard({required this.job, required this.money});

  final Job job;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              job.customerName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (job.jobType.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(job.jobType),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                Text('${'total_amount'.tr}: ${money.format(job.totalAmount)}'),
                Text('${'balance'.tr}: ${money.format(job.balance)}'),
                Text('${'paid'.tr}: ${money.format(job.paid)}'),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${'start_date'.tr}: ${DateFormat.yMMMd().format(job.startDate)}'
              '  ·  ${'due_date'.tr}: ${DateFormat.yMMMd().format(job.dueDate)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
