import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'task_editor_page.dart';
import 'task_model.dart';
import 'task_service.dart';
import 'task_ui.dart';

class TaskDetailPage extends StatefulWidget {
  const TaskDetailPage({super.key, required this.taskId});

  final String taskId;

  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  late final Stream<TaskModel?> _stream = TaskService.watchTask(widget.taskId);
  late final Stream<List<TaskHistoryEntry>> _history = TaskService.watchHistory(
    widget.taskId,
  );
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _method = 'cash';
  bool _formReady = false;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _prefill(TaskModel task) {
    if (_formReady) return;
    _formReady = true;
    if (task.collectedAmount != null) {
      _amount.text = task.collectedAmount!.toStringAsFixed(0);
    }
    _note.text = task.collectionNote;
    if (task.paymentMethod.isNotEmpty) _method = task.paymentMethod;
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (success != null) {
        Get.snackbar(
          'success'.tr,
          success,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (error) {
      Get.snackbar('error'.tr, '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('tk_confirm'.tr),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<String?> _askNote(String title, {bool required = false}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            onChanged: (_) => setLocal(() {}),
            decoration: InputDecoration(labelText: 'tk_review_note'.tr),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('cancel'.tr),
            ),
            FilledButton(
              onPressed: required && controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, controller.text.trim()),
              child: Text('tk_confirm'.tr),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _submit(TaskModel task) async {
    double? amount;
    if (task.isCollection) {
      amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
      if (amount == null || amount < 0) {
        Get.snackbar('error'.tr, 'tk_bad_amount'.tr);
        return;
      }
      if (amount == 0 && _note.text.trim().isEmpty) {
        Get.snackbar('error'.tr, 'tk_zero_note'.tr);
        return;
      }
    }
    if (!await _confirm('tk_confirm_submit'.tr)) return;
    await _run(
      () => TaskService.submit(
        task,
        collectedAmount: amount,
        paymentMethod: _method,
        note: _note.text,
      ),
      success: 'tk_submitted_ok'.tr,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TaskModel?>(
      stream: _stream,
      builder: (context, snapshot) {
        final task = snapshot.data;
        return Scaffold(
          backgroundColor: TaskColors.canvas,
          appBar: AppBar(
            backgroundColor: TaskColors.navy,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text('tk_details'.tr),
            actions: [
              if (task != null && TaskService.canAssign && !task.isFinal)
                IconButton(
                  tooltip: 'tk_edit'.tr,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TaskEditorPage(task: task),
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                ),
              if (task != null && TaskService.canDelete)
                IconButton(
                  tooltip: 'tk_delete'.tr,
                  onPressed: () async {
                    if (!await _confirm('tk_confirm_delete'.tr)) return;
                    try {
                      await TaskService.delete(task);
                      if (mounted) Navigator.of(this.context).pop();
                    } catch (error) {
                      Get.snackbar('error'.tr, '$error');
                    }
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
          body: snapshot.hasError
              ? Center(child: Text('tk_error'.tr))
              : task == null
              ? (snapshot.connectionState == ConnectionState.waiting
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: TaskColors.brand,
                        ),
                      )
                    : Center(child: Text('tk_empty'.tr)))
              : _body(task),
        );
      },
    );
  }

  Widget _card({required Widget child, Color? color, Gradient? gradient}) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: gradient == null ? (color ?? Colors.white) : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: TaskColors.navy.withValues(alpha: 0.07),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: child,
      );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        color: TaskColors.ink,
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _kv(String label, String value, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: TaskColors.muted, fontSize: 13),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color ?? TaskColors.ink,
              fontSize: 13.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(TaskModel task) {
    _prefill(task);
    final (statusLabel, statusColor) = TaskUi.status(task);
    final mine = TaskService.isAssignee(task);
    final working = mine && task.staffCanWork;
    final reviewing =
        task.status == TaskStatus.submitted && TaskService.canReview && !mine;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            _card(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [TaskColors.navy, Color(0xFF2563EB)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      TaskChip(label: statusLabel, color: Colors.white),
                      TaskChip(
                        label: TaskUi.priorityLabel(task.priority),
                        color: Colors.white,
                        icon: Icons.flag_rounded,
                      ),
                      TaskChip(
                        label: TaskUi.typeLabel(task),
                        color: Colors.white,
                        icon: task.isCollection
                            ? Icons.payments_outlined
                            : Icons.checklist_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: task.progressFraction,
                      minHeight: 8,
                      backgroundColor: Colors.white24,
                      color: const Color(0xFF6EE7B7),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${task.doneCount}/${task.steps.length} ${'tk_steps_done'.tr}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            _card(
              child: Column(
                children: [
                  _kv('tk_assigned_to'.tr, task.assigneeName),
                  _kv(
                    'tk_due'.tr,
                    TaskUi.date(task.dueDate),
                    color: task.isOverdue ? TaskColors.red : null,
                  ),
                  _kv('tk_created'.tr, TaskUi.date(task.createdAt)),
                  if (task.submittedAt != null)
                    _kv('tk_submitted_at'.tr, TaskUi.date(task.submittedAt)),
                  if (task.approvedAt != null)
                    _kv('tk_approved_at'.tr, TaskUi.date(task.approvedAt)),
                ],
              ),
            ),
            if (task.description.isNotEmpty)
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _heading('tk_desc'.tr),
                    Text(
                      task.description,
                      style: const TextStyle(
                        color: TaskColors.ink,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            if (task.reviewNote.isNotEmpty &&
                (task.status == TaskStatus.returned ||
                    task.status == TaskStatus.approved))
              _card(
                color: task.status == TaskStatus.returned
                    ? const Color(0xFFFEF2F2)
                    : const Color(0xFFECFDF5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _heading('tk_review_note'.tr),
                    Text(task.reviewNote),
                  ],
                ),
              ),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heading('tk_steps'.tr),
                  if (task.steps.isEmpty)
                    Text(
                      'tk_no_steps'.tr,
                      style: const TextStyle(color: TaskColors.muted),
                    ),
                  for (var i = 0; i < task.steps.length; i++)
                    _step(task, i, working),
                ],
              ),
            ),
            if (task.isCollection) _collection(task, working),
            if (working) _staffActions(task),
            if (reviewing) _reviewActions(task),
            if (TaskService.canReview &&
                !mine &&
                !task.isFinal &&
                task.status != TaskStatus.submitted)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          if (!await _confirm('tk_confirm_cancel'.tr)) return;
                          await _run(() => TaskService.cancel(task));
                        },
                  icon: const Icon(Icons.block_rounded, color: TaskColors.red),
                  label: Text(
                    'tk_cancel'.tr,
                    style: const TextStyle(color: TaskColors.red),
                  ),
                ),
              ),
            _historyCard(),
          ],
        ),
      ),
    );
  }

  Widget _step(TaskModel task, int index, bool working) {
    final done = task.isStepDone(index);
    final info = task.progress['$index'];
    final doneAt = info?['doneAt'];
    return InkWell(
      onTap: working && !_busy
          ? () => _run(() => TaskService.setStep(task, index, !done))
          : null,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              color: done ? TaskColors.green : TaskColors.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${index + 1}. ${task.steps[index]}',
                    style: TextStyle(
                      color: TaskColors.ink,
                      fontWeight: FontWeight.w600,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (done && info != null)
                    Text(
                      '${info['doneByName'] ?? ''} · ${doneAt is Timestamp ? TaskUi.date(doneAt.toDate()) : ''}',
                      style: const TextStyle(
                        color: TaskColors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _collection(TaskModel task, bool working) {
    final form = working;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading('tk_collected'.tr),
          if (task.expectedAmount != null)
            _kv('tk_expected_l'.tr, TaskUi.money(task.expectedAmount!)),
          if (form) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'tk_amount'.tr,
                prefixText: 'TSh ',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final m in const ['cash', 'mobile', 'bank'])
                  ChoiceChip(
                    label: Text('tk_m_$m'.tr),
                    selected: _method == m,
                    showCheckmark: false,
                    selectedColor: TaskColors.brand,
                    labelStyle: TextStyle(
                      color: _method == m ? Colors.white : TaskColors.ink,
                      fontSize: 12.5,
                    ),
                    onSelected: (_) => setState(() => _method = m),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'tk_note'.tr,
                helperText: 'tk_zero_note'.tr,
                border: const OutlineInputBorder(),
              ),
            ),
            if (task.expectedAmount != null &&
                double.tryParse(_amount.text.replaceAll(',', '').trim()) !=
                    null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _differenceRow(
                  double.parse(_amount.text.replaceAll(',', '').trim()) -
                      task.expectedAmount!,
                ),
              ),
          ] else if (task.collectedAmount != null) ...[
            _kv(
              'tk_amount'.tr,
              TaskUi.money(task.collectedAmount!),
              color: TaskColors.green,
              bold: true,
            ),
            if (task.paymentMethod.isNotEmpty)
              _kv('tk_method'.tr, 'tk_m_${task.paymentMethod}'.tr),
            if (task.collectedAt != null)
              _kv('tk_collected_at'.tr, TaskUi.date(task.collectedAt)),
            if (task.difference != null) _differenceRow(task.difference!),
            if (task.collectionNote.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                task.collectionNote,
                style: const TextStyle(color: TaskColors.muted),
              ),
            ],
            if (task.status == TaskStatus.approved) _incomeSection(task),
          ] else
            Text(
              'tk_not_reported'.tr,
              style: const TextStyle(color: TaskColors.muted),
            ),
        ],
      ),
    );
  }

  Widget _differenceRow(double diff) {
    final color = diff == 0
        ? TaskColors.green
        : (diff < 0 ? TaskColors.red : TaskColors.brand);
    return _kv(
      'tk_difference'.tr,
      '${diff > 0 ? '+' : ''}${TaskUi.money(diff)}',
      color: color,
      bold: true,
    );
  }

  Widget _incomeSection(TaskModel task) {
    final recorded = (task.transactionId ?? '').isNotEmpty;
    if (recorded) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TaskChip(
          label: 'tk_income_done'.tr,
          color: TaskColors.green,
          icon: Icons.verified_rounded,
        ),
      );
    }
    if (!TaskService.canAssign || (task.collectedAmount ?? 0) <= 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'tk_income_hint'.tr,
            style: const TextStyle(color: TaskColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    if (!await _confirm('tk_confirm_income'.tr)) return;
                    await _run(
                      () => TaskService.recordAsIncome(task),
                      success: 'tk_income_done'.tr,
                    );
                  },
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: Text('tk_record_income'.tr),
          ),
        ],
      ),
    );
  }

  Widget _staffActions(TaskModel task) {
    final ready = task.allStepsDone;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: TaskColors.brand),
              onPressed: _busy || !ready ? null : () => _submit(task),
              icon: const Icon(Icons.send_rounded),
              label: Text('tk_submit'.tr),
            ),
          ),
          if (!ready)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'tk_steps_left'.tr,
                textAlign: TextAlign.center,
                style: const TextStyle(color: TaskColors.muted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _reviewActions(TaskModel task) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: TaskColors.red,
                  side: const BorderSide(color: TaskColors.red),
                ),
                onPressed: _busy
                    ? null
                    : () async {
                        final note = await _askNote(
                          'tk_return'.tr,
                          required: true,
                        );
                        if (note == null) return;
                        await _run(
                          () =>
                              TaskService.returnForCorrection(task, note: note),
                        );
                      },
                icon: const Icon(Icons.undo_rounded),
                label: Text('tk_return'.tr),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 50,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: TaskColors.green,
                ),
                onPressed: _busy
                    ? null
                    : () async {
                        final note = await _askNote('tk_approve'.tr);
                        if (note == null) return;
                        await _run(() => TaskService.approve(task, note: note));
                      },
                icon: const Icon(Icons.verified_rounded),
                label: Text('tk_approve'.tr),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyCard() {
    return StreamBuilder<List<TaskHistoryEntry>>(
      stream: _history,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <TaskHistoryEntry>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading('tk_history'.tr),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.history_rounded,
                        size: 15,
                        color: TaskColors.muted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${TaskUi.actionLabel(item.action)}'
                          '${item.note.isNotEmpty ? ': ${item.note}' : ''}\n'
                          '${item.actorName} · ${TaskUi.date(item.createdAt)}',
                          style: const TextStyle(
                            color: TaskColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
