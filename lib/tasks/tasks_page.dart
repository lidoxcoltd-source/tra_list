import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/services/business_access_service.dart';

import 'task_detail_page.dart';
import 'task_editor_page.dart';
import 'task_inbox.dart';
import 'task_model.dart';
import 'task_service.dart';
import 'task_ui.dart';

enum _Filter { all, today, pending, progress, review, done, overdue }

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  late Stream<List<TaskModel>> _stream = TaskService.watchTasks();
  _Filter _filter = _Filter.all;

  bool _matches(TaskModel t, _Filter f) {
    final now = DateTime.now();
    return switch (f) {
      _Filter.all => true,
      _Filter.today =>
        t.dueDate != null &&
            t.dueDate!.year == now.year &&
            t.dueDate!.month == now.month &&
            t.dueDate!.day == now.day,
      _Filter.pending =>
        t.status == TaskStatus.assigned || t.status == TaskStatus.returned,
      _Filter.progress => t.status == TaskStatus.inProgress,
      _Filter.review => t.status == TaskStatus.submitted,
      _Filter.done => t.status == TaskStatus.approved,
      _Filter.overdue => t.isOverdue,
    };
  }

  String _label(_Filter f) => switch (f) {
    _Filter.all => 'tk_f_all'.tr,
    _Filter.today => 'tk_f_today'.tr,
    _Filter.pending => 'tk_f_pending'.tr,
    _Filter.progress => 'tk_f_progress'.tr,
    _Filter.review => 'tk_f_review'.tr,
    _Filter.done => 'tk_f_done'.tr,
    _Filter.overdue => 'tk_f_overdue'.tr,
  };

  @override
  Widget build(BuildContext context) {
    final manager = TaskService.canViewAll;
    final filters = _Filter.values
        .where((f) => f != _Filter.review || manager)
        .toList();
    return Scaffold(
      backgroundColor: TaskColors.canvas,
      appBar: AppBar(
        backgroundColor: TaskColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(manager ? 'tk_all'.tr : 'tk_my'.tr),
        actions: [
          if (BusinessAccessService.isOwner.value)
            IconButton(
              tooltip: 'home_manage_staff'.tr,
              icon: const Icon(Icons.groups_2_outlined),
              onPressed: () => Get.toNamed(AppRoutes.staff),
            ),
          const TaskBell(),
        ],
      ),
      floatingActionButton: TaskService.canAssign
          ? FloatingActionButton.extended(
              backgroundColor: TaskColors.brand,
              foregroundColor: Colors.white,
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const TaskEditorPage())),
              icon: const Icon(Icons.add_rounded),
              shape: const StadiumBorder(),
              label: Text('tk_new'.tr),
            )
          : null,
      body: StreamBuilder<List<TaskModel>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _message(
              Icons.error_outline_rounded,
              'tk_error'.tr,
              action: TextButton(
                onPressed: () =>
                    setState(() => _stream = TaskService.watchTasks()),
                child: Text('tk_retry'.tr),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: TaskColors.brand),
            );
          }
          final all = snapshot.data!;
          final shown = all.where((t) => _matches(t, _filter)).toList();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                children: [
                  _summary(all),
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final f in filters)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              showCheckmark: false,
                              selected: _filter == f,
                              selectedColor: TaskColors.navy,
                              backgroundColor: Colors.white,
                              side: BorderSide(
                                color: _filter == f
                                    ? TaskColors.navy
                                    : TaskColors.border,
                              ),
                              shape: const StadiumBorder(),
                              label: Text(
                                '${_label(f)} (${all.where((t) => _matches(t, f)).length})',
                              ),
                              labelStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _filter == f
                                    ? Colors.white
                                    : TaskColors.ink,
                              ),
                              onSelected: (_) => setState(() => _filter = f),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: shown.isEmpty
                        ? _message(Icons.task_alt_rounded, 'tk_empty'.tr)
                        : LayoutBuilder(
                            builder: (context, c) {
                              final cols = c.maxWidth >= 760 ? 2 : 1;
                              const gap = 12.0;
                              final w =
                                  (c.maxWidth - 32 - gap * (cols - 1)) / cols;
                              return SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  96,
                                ),
                                child: Wrap(
                                  spacing: gap,
                                  runSpacing: gap,
                                  children: [
                                    for (final t in shown)
                                      SizedBox(width: w, child: _card(t)),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _summary(List<TaskModel> all) {
    int count(bool Function(TaskModel) test) => all.where(test).length;
    Widget stat(String label, int value, Color color) => Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [TaskColors.navy, Color(0xFF2563EB)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Row(
        children: [
          stat(
            'tk_f_pending'.tr,
            count(
              (t) =>
                  t.status == TaskStatus.assigned ||
                  t.status == TaskStatus.returned,
            ),
            Colors.white,
          ),
          stat(
            'tk_f_progress'.tr,
            count((t) => t.status == TaskStatus.inProgress),
            const Color(0xFF93C5FD),
          ),
          stat(
            'tk_f_review'.tr,
            count((t) => t.status == TaskStatus.submitted),
            const Color(0xFFFCD34D),
          ),
          stat(
            'tk_f_done'.tr,
            count((t) => t.status == TaskStatus.approved),
            const Color(0xFF6EE7B7),
          ),
          stat(
            'tk_f_overdue'.tr,
            count((t) => t.isOverdue),
            const Color(0xFFFCA5A5),
          ),
        ],
      ),
    );
  }

  Widget _card(TaskModel t) {
    final (statusLabel, statusColor) = TaskUi.status(t);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: TaskColors.navy.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TaskDetailPage(taskId: t.id)),
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: statusColor, width: 5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: TaskColors.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TaskChip(label: statusLabel, color: statusColor),
                  ],
                ),
                if (TaskService.canViewAll && t.assigneeName.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.person_outline_rounded,
                        size: 14,
                        color: TaskColors.muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        t.assigneeName,
                        style: const TextStyle(
                          color: TaskColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
                if (t.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    t.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TaskColors.muted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    TaskChip(
                      label: TaskUi.priorityLabel(t.priority),
                      color: TaskUi.priorityColor(t.priority),
                      icon: Icons.flag_rounded,
                    ),
                    TaskChip(
                      label: TaskUi.typeLabel(t),
                      color: t.isCollection
                          ? TaskColors.green
                          : TaskColors.navy,
                      icon: t.isCollection
                          ? Icons.payments_outlined
                          : Icons.checklist_rounded,
                    ),
                    if (t.dueDate != null)
                      TaskChip(
                        label: TaskUi.date(t.dueDate),
                        color: t.isOverdue ? TaskColors.red : TaskColors.muted,
                        icon: Icons.event_rounded,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: t.progressFraction,
                          minHeight: 7,
                          backgroundColor: TaskColors.lightBlue,
                          color: t.progressFraction >= 1
                              ? TaskColors.green
                              : TaskColors.brand,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${t.doneCount}/${t.steps.length}',
                      style: const TextStyle(
                        color: TaskColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _message(IconData icon, String text, {Widget? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: TaskColors.lightBlue,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: TaskColors.brand),
            ),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: TaskColors.muted),
            ),
            if (action != null) action,
          ],
        ),
      ),
    );
  }
}
