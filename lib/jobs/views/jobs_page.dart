import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/job_controller.dart';
import '../widgets/job_card.dart';
import 'add_job_page.dart';

class JobsPage extends StatefulWidget {
  const JobsPage({super.key});

  @override
  State<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends State<JobsPage>
    with SingleTickerProviderStateMixin {
  late final JobController c;
  late final TabController tab;

  @override
  void initState() {
    super.initState();
    c = Get.put(JobController());
    tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(
          kToolbarHeight + 48.0,
        ), // AppBar height + TabBar height
        child: Obx(
          () => AppBar(
            title: c.isSearching.value
                ? TextField(
                    controller: c.searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '${'search'.tr}...',
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(fontSize: 18, color: Colors.white),
                  )
                : Text('jobs_title'.tr),
            actions: [
              IconButton(
                tooltip: 'search'.tr,
                icon: Icon(c.isSearching.value ? Icons.close : Icons.search),
                onPressed: c.toggleSearch,
              ),
              if (!c.isSearching.value)
                PopupMenuButton<JobSortOption>(
                  tooltip: 'Sort by'.tr,
                  icon: const Icon(Icons.sort),
                  onSelected: (option) => c.sortOption.value = option,
                  itemBuilder: (context) => [
                    CheckedPopupMenuItem(
                      value: JobSortOption.createdAtDesc,
                      checked:
                          c.sortOption.value == JobSortOption.createdAtDesc,
                      child: Text('Date Added (Newest)'.tr),
                    ),
                    CheckedPopupMenuItem(
                      value: JobSortOption.createdAtAsc,
                      checked: c.sortOption.value == JobSortOption.createdAtAsc,
                      child: Text('Date Added (Oldest)'.tr),
                    ),
                    const PopupMenuDivider(),
                    CheckedPopupMenuItem(
                      value: JobSortOption.dueDateAsc,
                      checked: c.sortOption.value == JobSortOption.dueDateAsc,
                      child: Text('Due Date (Soonest)'.tr),
                    ),
                    CheckedPopupMenuItem(
                      value: JobSortOption.customerNameAsc,
                      checked:
                          c.sortOption.value == JobSortOption.customerNameAsc,
                      child: Text('Client Name (A-Z)'.tr),
                    ),
                    CheckedPopupMenuItem(
                      value: JobSortOption.customerNameDesc,
                      checked:
                          c.sortOption.value == JobSortOption.customerNameDesc,
                      child: Text('Client Name (Z-A)'.tr),
                    ),
                  ],
                ),
            ],
            bottom: TabBar(
              controller: tab,
              isScrollable: true,
              tabs: [
                Tab(text: '${'jobs_all'.tr} (${c.all.length})'),
                Tab(text: '${'jobs_active'.tr} (${c.active.length})'),
                Tab(text: '${'jobs_completed'.tr} (${c.completed.length})'),
                Tab(text: '${'jobs_important'.tr} (${c.important.length})'),
              ],
            ),
          ),
        ),
      ),
      body: Obx(() {
        if (c.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        final lists = [c.all, c.active, c.completed, c.important];
        return TabBarView(
          controller: tab,
          children: List.generate(lists.length, (i) {
            final data = lists[i];
            if (data.isEmpty) {
              return Center(child: Text('no_jobs'.tr));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: data.length,
              itemBuilder: (_, idx) {
                final job = data[idx];
                return Dismissible(
                  key: ValueKey(job.id),
                  background: Container(
                    color: Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    alignment: Alignment.centerLeft,
                    child: const Row(
                      children: [
                        Icon(Icons.edit, color: Colors.white),
                        SizedBox(width: 8),
                        Text('Edit', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  secondaryBackground: Container(
                    color: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    alignment: Alignment.centerRight,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('Delete', style: TextStyle(color: Colors.white)),
                        SizedBox(width: 8),
                        Icon(Icons.delete, color: Colors.white),
                      ],
                    ),
                  ),
                  confirmDismiss: (direction) async {
                    if (direction == DismissDirection.startToEnd) {
                      // Edit action (slide right)
                      Get.to(() => AddJobPage(job: job));
                      return false; // Don't dismiss the card
                    } else {
                      // Delete action (slide left)
                      return await c.confirmAndDeleteJob(job.id);
                    }
                  },
                  onDismissed: (direction) {
                    if (direction == DismissDirection.endToStart) {
                      c.deleteJob(job.id);
                    }
                  },
                  child: JobCard(job: job),
                );
              },
            );
          }),
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Get.to(() => const AddJobPage()),
        child: const Icon(Icons.add),
      ),
    );
  }
}
