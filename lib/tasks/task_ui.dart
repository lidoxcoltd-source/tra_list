import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:tra_list/theme/app_theme.dart';

import 'task_model.dart';

class TaskColors {
  static const navy = MjasiColors.primaryNavy;
  static const brand = MjasiColors.primaryBlue;
  static const canvas = MjasiColors.background;
  static const ink = MjasiColors.textPrimary;
  static const muted = MjasiColors.textSecondary;
  static const border = MjasiColors.border;
  static const lightBlue = MjasiColors.lightBlue;
  static const green = MjasiColors.success;
  static const amber = MjasiColors.warning;
  static const red = MjasiColors.error;
}

class TaskUi {
  TaskUi._();

  static final _dateFormat = DateFormat('d MMM yyyy, HH:mm');
  static final _money = NumberFormat('#,##0');

  static String date(DateTime? value) =>
      value == null ? '—' : _dateFormat.format(value);

  static String money(num value) => 'TSh ${_money.format(value)}';

  static (String, Color) status(TaskModel task) {
    if (task.isOverdue) return ('tk_s_overdue'.tr, TaskColors.red);
    return switch (task.status) {
      TaskStatus.assigned => ('tk_s_assigned'.tr, TaskColors.muted),
      TaskStatus.inProgress => ('tk_s_progress'.tr, TaskColors.brand),
      TaskStatus.submitted => ('tk_s_submitted'.tr, TaskColors.amber),
      TaskStatus.approved => ('tk_s_approved'.tr, TaskColors.green),
      TaskStatus.returned => ('tk_s_returned'.tr, TaskColors.red),
      _ => ('tk_s_cancelled'.tr, TaskColors.muted),
    };
  }

  static String priorityLabel(String priority) => switch (priority) {
    'high' => 'tk_p_high'.tr,
    'low' => 'tk_p_low'.tr,
    _ => 'tk_p_normal'.tr,
  };

  static Color priorityColor(String priority) => switch (priority) {
    'high' => TaskColors.red,
    'low' => TaskColors.muted,
    _ => TaskColors.brand,
  };

  static String typeLabel(TaskModel task) =>
      task.isCollection ? 'tk_t_collection'.tr : 'tk_t_task'.tr;

  static String actionLabel(String action) => switch (action) {
    'created' => 'tk_h_created'.tr,
    'edited' => 'tk_h_edited'.tr,
    'step_done' => 'tk_h_step_done'.tr,
    'step_undone' => 'tk_h_step_undone'.tr,
    'submitted' => 'tk_h_submitted'.tr,
    'approved' => 'tk_h_approved'.tr,
    'returned' => 'tk_h_returned'.tr,
    'cancelled' => 'tk_h_cancelled'.tr,
    'income_recorded' => 'tk_h_income'.tr,
    _ => action,
  };
}

class TaskChip extends StatelessWidget {
  const TaskChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.solid = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final fg = solid ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
