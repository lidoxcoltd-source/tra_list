import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'task_model.dart';
import 'task_service.dart';

/// Compact strip for the home hero: what needs the user's attention in Tasks.
class TaskBanner extends StatefulWidget {
  const TaskBanner({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<TaskBanner> createState() => _TaskBannerState();
}

class _TaskBannerState extends State<TaskBanner> {
  late final Stream<List<TaskModel>> _stream = TaskService.watchTasks();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TaskModel>>(
      stream: _stream,
      builder: (context, snap) {
        final tasks = snap.data;
        if (snap.hasError || tasks == null) return const SizedBox.shrink();
        final manager = TaskService.canViewAll;
        final mine = tasks.where(
          (t) => t.assigneeUid == TaskService.currentUid && t.staffCanWork,
        );
        final review = manager
            ? tasks.where((t) => t.status == TaskStatus.submitted).length
            : 0;
        final overdue = tasks.where((t) => t.isOverdue).length;
        final pending = manager
            ? tasks.where((t) => t.staffCanWork).length
            : mine.length;
        if (pending == 0 && review == 0 && overdue == 0) {
          return const SizedBox.shrink();
        }

        final parts = <String>[
          if (review > 0) 'tk_banner_review'.trParams({'n': '$review'}),
          if (pending > 0)
            (manager ? 'tk_banner_open' : 'tk_banner_mine').trParams({
              'n': '$pending',
            }),
          if (overdue > 0) 'tk_banner_overdue'.trParams({'n': '$overdue'}),
        ];
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Material(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.task_alt_rounded,
                      size: 16,
                      color: overdue > 0
                          ? const Color(0xFFFCA5A5)
                          : const Color(0xFF93C5FD),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        parts.join(' • '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
