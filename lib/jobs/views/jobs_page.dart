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

  bool get _isDesktop {
    final w = MediaQuery.sizeOf(context).width;
    return w >= 900; // breakpoint for desktop layout
  }

  @override
  void initState() {
    super.initState();
    c = Get.put(JobController());
    tab = TabController(length: 5, vsync: this, initialIndex: 1);
  }

  @override
  void dispose() {
    tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Colors and paddings for a cleaner, more professional look
    final borderColor = Theme.of(context).colorScheme.outlineVariant;
    final cardPadding = EdgeInsets.symmetric(
      horizontal: _isDesktop ? 20 : 12,
      vertical: _isDesktop ? 16 : 12,
    );

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(
          kToolbarHeight + (_isDesktop ? 56.0 : 48.0),
        ),
        child: Obx(
          () => AppBar(
            elevation: _isDesktop ? 0.5 : 0,
            titleSpacing: _isDesktop ? 16 : null,
            title: _isDesktop
                ? Row(
                    children: [
                      // Inline search for desktop
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: TextField(
                            controller: c.searchController,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search),
                              hintText: '${'search'.tr}...',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              filled: true,
                              fillColor: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Sort menu (desktop)
                      _SortMenu(
                        current: c.sortOption.value,
                        onSelected: (opt) => c.sortOption.value = opt,
                      ),
                      const SizedBox(width: 12),
                      // Add button (desktop)
                      ElevatedButton.icon(
                        onPressed: () => Get.to(() => const AddJobPage()),
                        icon: const Icon(Icons.add),
                        label: Text('add'.tr),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  )
                : (c.isSearching.value
                      ? TextField(
                          controller: c.searchController,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: '${'search'.tr}...',
                            border: InputBorder.none,
                          ),
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        )
                      : Text('jobs_title'.tr)),
            actions: _isDesktop
                ? null
                : [
                    IconButton(
                      tooltip: 'search'.tr,
                      icon: Icon(
                        c.isSearching.value ? Icons.close : Icons.search,
                      ),
                      onPressed: c.toggleSearch,
                    ),
                    if (!c.isSearching.value)
                      _SortMenu(
                        current: c.sortOption.value,
                        onSelected: (opt) => c.sortOption.value = opt,
                        iconOnly: true,
                      ),
                  ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.symmetric(horizontal: _isDesktop ? 12 : 0),
                child: TabBar(
                  controller: tab,
                  isScrollable: true,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                  tabs: [
                    Tab(text: '${'jobs_all'.tr} (${c.all.length})'), // Index 0
                    Tab(
                      text: '${'jobs_active'.tr} (${c.active.length})',
                    ), // Index 1
                    Tab(
                      text: '${'jobs_completed'.tr} (${c.completed.length})',
                    ), // Index 2
                    Tab(
                      text: '${'jobs_important'.tr} (${c.important.length})',
                    ), // Index 3
                    Tab(
                      text: '${'jobs_out_of_time'.tr} (${c.outOfTime.length})',
                    ), // Index 4
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: Obx(() {
        if (c.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        final lists = [c.all, c.active, c.completed, c.important, c.outOfTime];

        Widget buildEmpty() {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.work_outline,
                    size: 64,
                    color: Theme.of(context).hintColor,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'no_jobs'.tr,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isDesktop)
                    OutlinedButton.icon(
                      onPressed: () => Get.to(() => const AddJobPage()),
                      icon: const Icon(Icons.add),
                      label: Text('add'.tr),
                    ),
                ],
              ),
            ),
          );
        }

        return TabBarView(
          controller: tab,
          children: List.generate(lists.length, (i) {
            final data = lists[i];

            if (data.isEmpty) return buildEmpty();

            // Desktop: grid layout to better use space
            if (_isDesktop) {
              return Padding(
                padding: cardPadding,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 520, // card max width
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio:
                        1.2, // was 1.6; make tiles taller to avoid overflow
                  ),
                  itemCount: data.length,
                  itemBuilder: (_, idx) {
                    final job = data[idx];
                    return Material(
                      elevation: 1,
                      clipBehavior: Clip.antiAlias,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () {
                          // Optional: navigate to edit on click
                          Get.to(() => AddJobPage(job: job));
                        },
                        child: JobCard(job: job),
                      ),
                    );
                  },
                ),
              );
            }

            // Mobile: list with swipe actions
            return ListView.builder(
              padding: cardPadding,
              itemCount: data.length,
              itemBuilder: (_, idx) {
                final job = data[idx];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Dismissible(
                    key: ValueKey(job.id),
                    background: Container(
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          const Icon(Icons.edit, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            'edit'.tr,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    secondaryBackground: Container(
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'delete'.tr,
                            style: const TextStyle(color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.delete, color: Colors.white),
                        ],
                      ),
                    ),
                    confirmDismiss: (direction) async {
                      if (direction == DismissDirection.startToEnd) {
                        // Edit
                        Get.to(() => AddJobPage(job: job));
                        return false;
                      } else {
                        // Delete
                        return await c.confirmAndDeleteJob(job.id);
                      }
                    },
                    onDismissed: (direction) {
                      if (direction == DismissDirection.endToStart) {
                        c.deleteJob(job.id);
                      }
                    },
                    child: JobCard(job: job),
                  ),
                );
              },
            );
          }),
        );
      }),
      // FAB only on mobile. Desktop has an Add button in the toolbar.
      floatingActionButton: _isDesktop
          ? null
          : FloatingActionButton(
              onPressed: () => Get.to(() => const AddJobPage()),
              tooltip: 'add'.tr,
              child: const Icon(Icons.add),
            ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({
    required this.current,
    required this.onSelected,
    this.iconOnly = false,
  });

  final JobSortOption current;
  final ValueChanged<JobSortOption> onSelected;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<JobSortOption>(
      tooltip: 'Sort by'.tr,
      icon: iconOnly ? const Icon(Icons.sort) : null,
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: JobSortOption.createdAtDesc,
          checked: current == JobSortOption.createdAtDesc,
          child: Text('Date Added (Newest)'.tr),
        ),
        CheckedPopupMenuItem(
          value: JobSortOption.createdAtAsc,
          checked: current == JobSortOption.createdAtAsc,
          child: Text('Date Added (Oldest)'.tr),
        ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          value: JobSortOption.dueDateAsc,
          checked: current == JobSortOption.dueDateAsc,
          child: Text('Due Date (Soonest)'.tr),
        ),
        CheckedPopupMenuItem(
          value: JobSortOption.customerNameAsc,
          checked: current == JobSortOption.customerNameAsc,
          child: Text('Client Name (A-Z)'.tr),
        ),
        CheckedPopupMenuItem(
          value: JobSortOption.customerNameDesc,
          checked: current == JobSortOption.customerNameDesc,
          child: Text('Client Name (Z-A)'.tr),
        ),
      ],
      child: iconOnly
          ? null
          : OutlinedButton.icon(
              onPressed: null, // handled by PopupMenuButton
              icon: const Icon(Icons.sort),
              label: Text('Sort by'.tr),
            ),
    );
  }
}
