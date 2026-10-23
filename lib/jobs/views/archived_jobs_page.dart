import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:tra_list/job_service.dart';
import 'package:tra_list/jobs/models/job.dart';

class ArchivedJobsPage extends StatefulWidget {
  const ArchivedJobsPage({super.key});

  @override
  State<ArchivedJobsPage> createState() => _ArchivedJobsPageState();
}

class _ArchivedJobsPageState extends State<ArchivedJobsPage> {
  late final Stream<QuerySnapshot<Job>> _jobsStream;
  final List<QueryDocumentSnapshot<Job>> _olderJobs = [];
  DocumentSnapshot<Job>? _lastJob;
  bool _hasMore = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _jobsStream = JobService.getJobsStream();
  }

  Future<void> _loadMore() async {
    final cursor = _lastJob;
    if (cursor == null || !_hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await JobService.getJobsAfter(cursor);
      if (!mounted) return;
      setState(() {
        _olderJobs.addAll(page.docs);
        _lastJob = page.docs.isEmpty ? cursor : page.docs.last;
        _hasMore = page.docs.length == JobService.pageSize;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load more archived jobs: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        Get.snackbar('error'.tr, 'debt_archive_load_error'.tr);
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

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
        stream: _jobsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('debt_archive_load_error'.tr));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final firstPage = snapshot.data!.docs;
          if (_olderJobs.isEmpty) {
            _lastJob = firstPage.isEmpty ? null : firstPage.last;
            _hasMore = firstPage.length == JobService.pageSize;
          }
          final byId = <String, Job>{
            for (final doc in firstPage) doc.id: doc.data(),
            for (final doc in _olderJobs) doc.id: doc.data(),
          };
          final jobs = byId.values.toList();
          if (jobs.isEmpty) {
            return Center(child: Text('debt_archive_empty'.tr));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: jobs.length + (_hasMore ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              if (index == jobs.length) {
                return Center(
                  child: OutlinedButton.icon(
                    onPressed: _loadingMore ? null : _loadMore,
                    icon: _loadingMore
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.expand_more_rounded),
                    label: Text(_loadingMore ? 'Loading...' : 'Load more jobs'),
                  ),
                );
              }
              return _ArchivedJobCard(job: jobs[index], money: money);
            },
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
