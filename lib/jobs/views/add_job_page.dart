import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/job_controller.dart';
import '../models/job.dart';

class AddJobPage extends StatefulWidget {
  final Job? job;

  const AddJobPage({super.key, this.job});

  @override
  State<AddJobPage> createState() => _AddJobPageState();
}

class _AddJobPageState extends State<AddJobPage> {
  final _form = GlobalKey<FormState>();
  final _client = TextEditingController();
  final _jobType = TextEditingController();
  final _phone1 = TextEditingController();
  final _phone2 = TextEditingController();
  final _total = TextEditingController(text: '0');
  final _advance = TextEditingController(text: '0');
  DateTime? _startDate;
  DateTime? _dueDate;
  bool _paidInFull = false;
  bool _important = false;

  final _c = Get.find<JobController>();
  final _fmt = DateFormat.yMMMd();

  bool get _isEditing => widget.job != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final j = widget.job!;
      _client.text = j.customerName;
      _jobType.text = j.jobType;
      _phone1.text = j.phonePrimary;
      _phone2.text = j.phoneSecondary ?? '';
      _total.text = j.totalAmount.toString();
      _advance.text = j.advancePaid.toString();
      _startDate = j.startDate;
      _dueDate = j.dueDate;
      _important = j.isImportant;
    }
  }

  @override
  void dispose() {
    _client.dispose();
    _jobType.dispose();
    _phone1.dispose();
    _phone2.dispose();
    _total.dispose();
    _advance.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_startDate ?? now)
        : (_dueDate ?? now.add(const Duration(days: 1)));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_dueDate != null && _dueDate!.isBefore(_startDate!)) {
            _dueDate = _startDate!.add(const Duration(days: 1));
          }
        } else {
          _dueDate = picked;
        }
      });
    }
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'validation_required'.tr : null;

  String? _amountVal(String? v) {
    if (v == null || v.trim().isEmpty) return 'validation_required'.tr;
    final d = double.tryParse(v) ?? -1;
    if (d < 0) return 'validation_amount_positive'.tr;
    return null;
  }

  void _syncPaidInFull(bool value) {
    setState(() {
      _paidInFull = value;
      if (_paidInFull) {
        _advance.text = _total.text;
      }
    });
  }

  Future<void> _onSave() async {
    if (!_form.currentState!.validate()) return;
    if (_startDate == null || _dueDate == null) {
      Get.snackbar('error'.tr, 'validation_required'.tr);
      return;
    }
    final total = double.tryParse(_total.text) ?? 0;
    final adv = double.tryParse(_advance.text) ?? 0;
    if (adv > total) {
      Get.snackbar('error'.tr, 'validation_advance_not_exceed'.tr);
      return;
    }
    final newJobData = Job(
      id: _isEditing ? widget.job!.id : null,
      customerName: _client.text.trim(),
      jobType: _jobType.text.trim(),
      phonePrimary: _phone1.text.trim(),
      phoneSecondary: _phone2.text.trim().isEmpty ? null : _phone2.text.trim(),
      totalAmount: total,
      advancePaid: _paidInFull ? total : adv,
      startDate: _startDate!,
      dueDate: _dueDate!,
      isImportant: _important,
      isCompleted: _isEditing ? widget.job!.isCompleted : false,
      createdAt: _isEditing ? widget.job!.createdAt : null,
    );

    if (_isEditing) {
      await _c.updateJob(newJobData);
    } else {
      await _c.addJob(newJobData);
    }

    // After saving, check if we should offer to record the payment.
    // We only do this if an advance was paid and it hasn't been recorded yet.
    if (newJobData.advancePaid > 0 && !newJobData.paymentRecorded) {
      // This method in the controller already contains a confirmation dialog.
      await _c.recordPaymentAsTransaction(newJobData);
    }

    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'edit_job_title'.tr : 'add_job_title'.tr),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _client,
              decoration: InputDecoration(labelText: 'client_name'.tr),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _jobType,
              decoration: InputDecoration(labelText: 'job_type'.tr),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone1,
              decoration: InputDecoration(labelText: 'phone_primary'.tr),
              keyboardType: TextInputType.phone,
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone2,
              decoration: InputDecoration(labelText: 'phone_secondary'.tr),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _total,
                    decoration: InputDecoration(labelText: 'total_amount'.tr),
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: _amountVal,
                    onChanged: (v) {
                      if (_paidInFull) {
                        _advance.text = _total.text;
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _advance,
                    decoration: InputDecoration(labelText: 'advance_paid'.tr),
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: _amountVal,
                    enabled: !_paidInFull,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _paidInFull,
              onChanged: (v) => _syncPaidInFull(v ?? false),
              title: Text('paid_in_full'.tr),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('start_date'.tr),
              subtitle: Text(
                _startDate == null ? '-' : _fmt.format(_startDate!),
              ),
              trailing: OutlinedButton(
                onPressed: () => _pickDate(isStart: true),
                child: Text('edit'.tr),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('due_date'.tr),
              subtitle: Text(_dueDate == null ? '-' : _fmt.format(_dueDate!)),
              trailing: OutlinedButton(
                onPressed: () => _pickDate(isStart: false),
                child: Text('edit'.tr),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _important,
              onChanged: (v) => setState(() => _important = v),
              title: Text('jobs_important'.tr),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _onSave, child: Text('save_job'.tr)),
          ],
        ),
      ),
    );
  }
}
