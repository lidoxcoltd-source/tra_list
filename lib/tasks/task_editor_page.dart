import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/services/staff_service.dart';

import 'task_model.dart';
import 'task_service.dart';
import 'task_ui.dart';

class TaskEditorPage extends StatefulWidget {
  const TaskEditorPage({super.key, this.task});

  final TaskModel? task;

  @override
  State<TaskEditorPage> createState() => _TaskEditorPageState();
}

class _TaskEditorPageState extends State<TaskEditorPage> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _expected = TextEditingController();
  final _steps = <TextEditingController>[];
  String _type = 'task';
  String _priority = 'normal';
  String? _assigneeUid;
  DateTime? _due;
  bool _saving = false;

  TaskModel? get _editing => widget.task;
  bool get _stepsLocked => (_editing?.progress.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    final task = _editing;
    if (task != null) {
      _title.text = task.title;
      _description.text = task.description;
      _type = task.type;
      _priority = task.priority;
      _assigneeUid = task.assigneeUid;
      _due = task.dueDate;
      if (task.expectedAmount != null) {
        _expected.text = task.expectedAmount!.toStringAsFixed(0);
      }
      for (final step in task.steps) {
        _steps.add(TextEditingController(text: step));
      }
    }
    if (_steps.isEmpty) _steps.add(TextEditingController());
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _expected.dispose();
    for (final c in _steps) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_due ?? now),
    );
    if (time == null) return;
    setState(
      () => _due = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _save(Map<String, Map<String, dynamic>> staff) async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      Get.snackbar('error'.tr, 'tk_need_title'.tr);
      return;
    }
    final editing = _editing;
    if (editing == null && _assigneeUid == null) {
      Get.snackbar('error'.tr, 'tk_need_assignee'.tr);
      return;
    }
    final expectedText = _expected.text.replaceAll(',', '').trim();
    final expected = expectedText.isEmpty
        ? null
        : double.tryParse(expectedText);
    if (expectedText.isNotEmpty && (expected == null || expected < 0)) {
      Get.snackbar('error'.tr, 'tk_bad_amount'.tr);
      return;
    }
    final steps = _stepsLocked
        ? editing!.steps
        : [
            for (final c in _steps)
              if (c.text.trim().isNotEmpty) c.text.trim(),
          ];
    setState(() => _saving = true);
    try {
      if (editing == null) {
        final member = staff[_assigneeUid]!;
        await TaskService.create(
          title: title,
          description: _description.text.trim(),
          type: _type,
          priority: _priority,
          assigneeUid: _assigneeUid!,
          assigneeName: (member['name'] ?? '').toString(),
          assigneeShop: (member['shopNickname'] ?? '').toString(),
          steps: steps,
          dueDate: _due,
          expectedAmount: expected,
        );
      } else {
        await TaskService.updateDetails(
          editing,
          title: title,
          description: _description.text.trim(),
          type: _type,
          priority: _priority,
          steps: steps,
          dueDate: _due,
          expectedAmount: expected,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      Get.snackbar(
        'success'.tr,
        'tk_saved'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (error) {
      if (mounted) setState(() => _saving = false);
      Get.snackbar('error'.tr, '$error');
    }
  }

  InputDecoration _decoration(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: TaskColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: TaskColors.border),
    ),
  );

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: TaskColors.ink,
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _choice(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: TaskColors.brand,
      labelStyle: TextStyle(
        color: selected ? Colors.white : TaskColors.ink,
        fontWeight: FontWeight.w600,
        fontSize: 12.5,
      ),
      onSelected: (_) => onTap(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = _editing != null;
    return Scaffold(
      backgroundColor: TaskColors.canvas,
      appBar: AppBar(
        backgroundColor: TaskColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(editing ? 'tk_edit'.tr : 'tk_new'.tr),
      ),
      body: StreamBuilder<List<StaffMember>>(
        stream: StaffService.watchStaff(),
        builder: (context, snapshot) {
          final staff = <String, Map<String, dynamic>>{
            for (final member in snapshot.data ?? const <StaffMember>[])
              if (member.data['active'] == true &&
                  member.data['removed'] != true)
                member.id: member.data,
          };
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  _section('tk_title_f'.tr),
                  TextField(
                    controller: _title,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _decoration('tk_title_f'.tr),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _description,
                    minLines: 3,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _decoration('tk_desc'.tr),
                  ),
                  if (!editing) ...[
                    _section('tk_assignee'.tr),
                    if (staff.isEmpty &&
                        snapshot.connectionState != ConnectionState.waiting)
                      Text(
                        'tk_no_staff'.tr,
                        style: const TextStyle(color: TaskColors.muted),
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue: staff.containsKey(_assigneeUid)
                            ? _assigneeUid
                            : null,
                        decoration: _decoration('tk_assignee'.tr),
                        items: [
                          for (final entry in staff.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(
                                (entry.value['name'] ?? '').toString(),
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _assigneeUid = value),
                      ),
                  ],
                  _section('tk_due'.tr),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickDue,
                          icon: const Icon(Icons.event_rounded),
                          label: Text(
                            _due == null ? 'tk_no_due'.tr : TaskUi.date(_due),
                          ),
                        ),
                      ),
                      if (_due != null)
                        IconButton(
                          onPressed: () => setState(() => _due = null),
                          icon: const Icon(Icons.close_rounded),
                        ),
                    ],
                  ),
                  _section('tk_priority'.tr),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final p in ['low', 'normal', 'high'])
                        _choice(
                          TaskUi.priorityLabel(p),
                          _priority == p,
                          () => setState(() => _priority = p),
                        ),
                    ],
                  ),
                  _section('tk_type'.tr),
                  Wrap(
                    spacing: 8,
                    children: [
                      _choice(
                        'tk_t_task'.tr,
                        _type == 'task',
                        () => setState(() => _type = 'task'),
                      ),
                      _choice(
                        'tk_t_collection'.tr,
                        _type == 'collection',
                        () => setState(() => _type = 'collection'),
                      ),
                    ],
                  ),
                  if (_type == 'collection') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _expected,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _decoration('tk_expected'.tr, hint: 'TSh'),
                    ),
                  ],
                  _section('tk_steps'.tr),
                  if (_stepsLocked)
                    Text(
                      'tk_steps_locked'.tr,
                      style: const TextStyle(
                        color: TaskColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  for (var i = 0; i < _steps.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 13,
                            backgroundColor: TaskColors.lightBlue,
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                color: TaskColors.navy,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _steps[i],
                              enabled: !_stepsLocked,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: _decoration('tk_step_hint'.tr),
                            ),
                          ),
                          if (!_stepsLocked)
                            IconButton(
                              onPressed: _steps.length > 1
                                  ? () => setState(
                                      () => _steps.removeAt(i).dispose(),
                                    )
                                  : null,
                              icon: const Icon(
                                Icons.remove_circle_outline_rounded,
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (!_stepsLocked)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () =>
                            setState(() => _steps.add(TextEditingController())),
                        icon: const Icon(Icons.add_rounded),
                        label: Text('tk_add_step'.tr),
                      ),
                    ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: TaskColors.brand,
                      ),
                      onPressed: _saving ? null : () => _save(staff),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text('tk_save'.tr),
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
}
