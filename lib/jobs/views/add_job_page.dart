import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/job_controller.dart';
import '../models/job.dart';
import 'package:tra_list/services/pdf/advance_payment_pdf.dart';
import 'package:tra_list/services/profile_service.dart';

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
  final _total = TextEditingController();
  final _advance = TextEditingController();
  final _description = TextEditingController(); // NEW
  DateTime? _startDate;
  DateTime? _dueDate;
  bool _paidInFull = false;
  bool _important = false;

  bool _saving = false; // NEW: saving state
  bool _triedSave =
      false; // NEW: show missing date error after first save attempt

  final _c = Get.find<JobController>();
  final _fmt = DateFormat.yMMMd();

  // New: money formatter and locale for consistent formatting
  late final String _localeTag;
  late final NumberFormat _moneyFmt;

  bool get _isEditing => widget.job != null;

  @override
  void initState() {
    super.initState();
    _localeTag = Get.locale?.toString() ?? 'en_US';
    _moneyFmt = NumberFormat.currency(
      locale: _localeTag,
      symbol: '',
      decimalDigits: 2,
    );

    if (_isEditing) {
      final j = widget.job!;
      _client.text = j.customerName;
      _jobType.text = j.jobType;
      _phone1.text = j.phonePrimary;
      _phone2.text = j.phoneSecondary ?? '';
      _total.text = _moneyFmt.format(j.totalAmount);
      _advance.text = _moneyFmt.format(j.advancePaid);
      _startDate = j.startDate;
      _dueDate = j.dueDate;
      _important = j.isImportant;
      _paidInFull = j.advancePaid >= j.totalAmount;
    } else {
      _advance.text = _moneyFmt.format(0);
      _startDate = DateTime.now();
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
    _description.dispose(); // NEW
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
    final d = _parseAmount(v);
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

  // Parse and format helpers for money
  double _parseAmount(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  String _formatAmount(double v) => _moneyFmt.format(v);

  Future<void> _onSave() async {
    setState(() => _triedSave = true);
    if (!_form.currentState!.validate() ||
        _startDate == null ||
        _dueDate == null) {
      if (_startDate == null || _dueDate == null) {
        Get.snackbar('error'.tr, 'validation_required'.tr);
      }
      return;
    }

    final total = _parseAmount(_total.text);
    final adv = _paidInFull ? total : _parseAmount(_advance.text);
    if (adv > total) {
      Get.snackbar('error'.tr, 'validation_advance_not_exceed'.tr);
      return;
    }

    setState(() => _saving = true);
    try {
      final newJobData = Job(
        id: _isEditing ? widget.job!.id : null,
        customerName: _client.text.trim(),
        jobType: _jobType.text.trim(),
        phonePrimary: _phone1.text.trim(),
        phoneSecondary: _phone2.text.trim().isEmpty
            ? null
            : _phone2.text.trim(),
        totalAmount: total,
        advancePaid: adv,
        startDate: _startDate!,
        dueDate: _dueDate!,
        isImportant: _important,
        isCompleted: _isEditing ? widget.job!.isCompleted : false,
        createdAt: _isEditing ? widget.job!.createdAt : null,
      );

      if (_isEditing) {
        await _c.updateJob(newJobData);
        if (mounted) Navigator.of(context).pop();
      } else {
        await _c.addJob(newJobData);
        if (mounted) Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _normalizeCompany(Map<String, dynamic>? raw) {
    final m = (raw ?? {}).map((k, v) => MapEntry(k.toString(), v));
    String joinAddr(List parts) => parts
        .where((e) => (e?.toString().trim().isNotEmpty ?? false))
        .join(', ');

    return {
      'name': m['name'] ?? m['companyName'] ?? m['businessName'] ?? '',
      'address':
          m['address'] ??
          joinAddr([m['street'], m['city'], m['region'], m['country']]),
      'phone': m['phone'] ?? m['phoneNumber'] ?? m['tel'] ?? '',
      'email': m['email'] ?? '',
      'taxId': m['taxId'] ?? m['tin'] ?? m['vat'] ?? '',
      'logoUrl': m['logoUrl'] ?? m['logo'] ?? m['logoURL'] ?? '',
      'website': m['website'] ?? m['site'] ?? '',
      'handle':
          m['handle'] ?? m['social'] ?? m['instagram'] ?? m['facebook'] ?? '',
      'beneficiary': m['beneficiary'] ?? m['accountName'] ?? '',
      'bank': m['bank'] ?? m['bankName'] ?? '',
      'account': m['account'] ?? m['accountNo'] ?? m['accountNumber'] ?? '',
      'swift': m['swift'] ?? m['swiftCode'] ?? '',
      'colors':
          m['colors'] is Map
                ? m['colors']
                : {
                    // optional brand colors if you store hex strings
                    if (m['brandColor'] != null)
                      'brand':
                          int.tryParse(
                            m['brandColor'].toString().replaceFirst(
                              '#',
                              '0xFF',
                            ),
                          ) ??
                          null,
                    if (m['accentColor'] != null)
                      'accent':
                          int.tryParse(
                            m['accentColor'].toString().replaceFirst(
                              '#',
                              '0xFF',
                            ),
                          ) ??
                          null,
                    if (m['footerColor'] != null)
                      'footer':
                          int.tryParse(
                            m['footerColor'].toString().replaceFirst(
                              '#',
                              '0xFF',
                            ),
                          ) ??
                          null,
                  }
            ..removeWhere((k, v) => v == null),
    }..removeWhere((k, v) => v == null);
  }

  // Build data map for your AdvancePaymentPdf (now pulls and normalizes company)
  Future<Map<String, dynamic>> _buildAdvancePdfData(Job j) async {
    final profile = await ProfileService.loadOrCreate();
    final company = _normalizeCompany((profile ?? {}) as Map<String, dynamic>?);

    final now = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final due = j.dueDate != null
        ? DateFormat('yyyy-MM-dd').format(j.dueDate)
        : '';
    final desc = _description.text.trim();
    final lineDesc = [
      if (j.jobType.isNotEmpty) j.jobType,
      if (desc.isNotEmpty) desc,
    ].join(' - ');

    return {
      'company': company,
      'client': {
        'name': j.customerName,
        'address': [
          j.phonePrimary,
          if ((j.phoneSecondary ?? '').isNotEmpty) j.phoneSecondary,
        ].join(' / '),
      },
      'invoice': {
        'number': (j.id ?? DateTime.now().millisecondsSinceEpoch).toString(),
        'issueDate': now,
        'advanceDueDate': due,
        'paymentMethod': _paidInFull ? 'Full (Advance 100%)' : 'Advance',
        'notes': desc.isEmpty ? 'This is computer generated document.' : desc,
      },
      'items': [
        {
          'description': lineDesc.isEmpty ? 'Service' : lineDesc,
          'qty': 1,
          'unit': j.totalAmount,
          'amount': j.totalAmount,
        },
      ],
      'subtotal': j.totalAmount,
      'tax': 0,
      'total': j.totalAmount,
      'advancePaid': j.advancePaid,
    };
  }

  Future<void> _offerAdvanceReceipt(Job job) async {
    final data = await _buildAdvancePdfData(job);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Advance payment receipt'),
        content: const Text('Generate receipt now?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'skip'),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save PDF'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'print'),
            child: const Text('Print'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (choice == 'print') {
      await AdvancePaymentPdf.generate(data);
    } else if (choice == 'save') {
      final safeClient = job.customerName.replaceAll(
        RegExp(r'[^A-Za-z0-9_-]+'),
        '_',
      );
      final ts = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final fileName = 'advance_invoice_${safeClient}_$ts.pdf';
      final path = await AdvancePaymentPdf.generateAndSave(
        data,
        fileName: fileName,
      );
      Get.snackbar(
        'Saved',
        'PDF saved to $path',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
    // Either way (print, save, or later), close the page now.
    Get.back();
  }

  // Helper: required field label with red asterisk
  Widget _reqLabel(String label) {
    final color = Theme.of(context).colorScheme.error;
    return Text.rich(
      TextSpan(
        text: label,
        children: [
          TextSpan(
            text: ' *',
            style: TextStyle(color: color),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amountFormatter = CurrencyTextInputFormatter(
      locale: _localeTag,
      decimalDigits: 2,
    );

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _onSave,
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 1000;
          final maxBodyWidth = isDesktop ? 1200.0 : double.infinity;

          final total = _parseAmount(_total.text);
          final adv = _paidInFull ? total : _parseAmount(_advance.text);
          final balance = (total - adv).clamp(0, double.infinity).toDouble();

          final formContent = Form(
            key: _form,
            autovalidateMode: AutovalidateMode.onUserInteraction, // NEW
            child: Column(
              children: [
                // Client & Job
                _SectionCard(
                  title: 'Client & Job',
                  child: _TwoColWrap(
                    isDesktop: isDesktop,
                    children: [
                      TextFormField(
                        controller: _client,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          label: _reqLabel('client_name'.tr), // NEW
                          prefixIcon: const Icon(Icons.person),
                          filled: true,
                        ),
                        validator: _required,
                      ),
                      TextFormField(
                        controller: _jobType,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          label: _reqLabel('job_type'.tr), // NEW
                          prefixIcon: const Icon(Icons.work_outline),
                          filled: true,
                        ),
                        validator: _required,
                      ),
                    ],
                  ),
                ),
                // NEW: Description
                _SectionCard(
                  title: 'Details',
                  child: TextFormField(
                    controller: _description,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 500,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      labelText: 'description'.tr.isEmpty
                          ? 'Description'
                          : 'description'.tr,
                      alignLabelWithHint: true,
                      prefixIcon: const Icon(Icons.description_outlined),
                      filled: true,
                    ),
                  ),
                ),

                // Contacts
                _SectionCard(
                  title: 'Contacts',
                  child: _TwoColWrap(
                    isDesktop: isDesktop,
                    children: [
                      TextFormField(
                        controller: _phone1,
                        decoration: InputDecoration(
                          label: _reqLabel('phone_primary'.tr), // NEW
                          prefixIcon: const Icon(Icons.phone),
                          filled: true,
                        ),
                        keyboardType: TextInputType.phone,
                        validator: _required,
                      ),
                      TextFormField(
                        controller: _phone2,
                        decoration: InputDecoration(
                          labelText: 'phone_secondary'.tr,
                          prefixIcon: const Icon(Icons.phone_outlined),
                          filled: true,
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                    ],
                  ),
                ),

                // Amounts
                _SectionCard(
                  title: 'Amounts',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TwoColWrap(
                        isDesktop: isDesktop,
                        children: [
                          TextFormField(
                            controller: _total,
                            decoration: InputDecoration(
                              labelText: 'total_amount'.tr,
                              prefixIcon: const Icon(Icons.attach_money),
                              hintText: 'e.g. 150000',
                              filled: true,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [amountFormatter],
                            validator: _amountVal,
                            onChanged: (_) {
                              if (_paidInFull) {
                                _advance.text = _total.text;
                              }
                              setState(() {});
                            },
                          ),
                          TextFormField(
                            controller: _advance,
                            decoration: InputDecoration(
                              labelText: 'advance_paid'.tr,
                              prefixIcon: const Icon(Icons.payments_outlined),
                              hintText: 'e.g. 50000',
                              filled: true,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [amountFormatter],
                            validator: _amountVal,
                            enabled: !_paidInFull,
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Quick advance chips
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final p in const [25, 50, 75, 100])
                            ActionChip(
                              avatar: const Icon(Icons.percent, size: 16),
                              label: Text('$p%'),
                              onPressed: () {
                                final t = _parseAmount(_total.text);
                                final v = (t * (p / 100)).toDouble();
                                setState(() {
                                  if (p == 100) {
                                    _syncPaidInFull(true);
                                  } else {
                                    _paidInFull = false;
                                    _advance.text = _formatAmount(v);
                                  }
                                });
                              },
                            ),
                          ActionChip(
                            avatar: const Icon(Icons.refresh, size: 16),
                            label: Text('reset'.tr),
                            onPressed: () {
                              setState(() {
                                _paidInFull = false;
                                _advance.text = _moneyFmt.format(0);
                              });
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: _paidInFull,
                        onChanged: (v) => _syncPaidInFull(v),
                        title: Text('paid_in_full'.tr),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.verified_outlined),
                      ),
                      const SizedBox(height: 4),

                      // Balance display
                      Row(
                        children: [
                          Icon(
                            balance <= 0
                                ? Icons.verified
                                : Icons.account_balance_wallet_outlined,
                            color: balance <= 0
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${'balance'.tr.isEmpty ? 'Balance' : 'balance'.tr}: ${_formatAmount(balance)}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Schedule
                _SectionCard(
                  title: 'Schedule',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TwoColWrap(
                        isDesktop: isDesktop,
                        children: [
                          _DatePickerField(
                            label: 'start_date'.tr,
                            valueText: _startDate == null
                                ? '-'
                                : _fmt.format(_startDate!),
                            onTap: () => _pickDate(isStart: true),
                            icon: Icons.event,
                          ),
                          _DatePickerField(
                            label: 'due_date'.tr,
                            valueText: _dueDate == null
                                ? '-'
                                : _fmt.format(_dueDate!),
                            onTap: () => _pickDate(isStart: false),
                            icon: Icons.event_available,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final d in const [1, 3, 7])
                            OutlinedButton.icon(
                              icon: const Icon(Icons.add),
                              label: Text('+${d}d'),
                              onPressed: () {
                                setState(() {
                                  final base = _startDate ?? DateTime.now();
                                  _dueDate = base.add(Duration(days: d));
                                });
                              },
                            ),
                          if (_startDate != null && _dueDate != null)
                            TextButton.icon(
                              icon: const Icon(Icons.swap_horiz),
                              label: Text(
                                'swap'.tr.isEmpty ? 'Swap dates' : 'swap'.tr,
                              ),
                              onPressed: () {
                                setState(() {
                                  final tmp = _startDate;
                                  _startDate = _dueDate;
                                  _dueDate = tmp;
                                });
                              },
                            ),
                        ],
                      ),
                      if (_triedSave &&
                          (_startDate == null ||
                              _dueDate == null)) // NEW: inline error
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${'start_date'.tr} / ${'due_date'.tr} ${'validation_required'.tr}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Options
                _SectionCard(
                  title: 'Options',
                  child: Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          value: _important,
                          onChanged: (v) => setState(() => _important = v),
                          title: Text('jobs_important'.tr),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.star_border),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

          final page = Scaffold(
            appBar: AppBar(
              title: Text(
                _isEditing ? 'edit_job_title'.tr : 'add_job_title'.tr,
              ),
              actions: [
                IconButton(
                  tooltip: 'save_job'.tr,
                  onPressed: _saving
                      ? null
                      : _onSave, // NEW: disable while saving
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                ),
              ],
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxBodyWidth),
                child: isDesktop
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Form area (scrollable)
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: formContent,
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Summary panel (sticky)
                          SizedBox(
                            width: 320,
                            child: _SummaryCard(
                              client: _client.text.trim(),
                              jobType: _jobType.text.trim(),
                              total: total,
                              advance: adv,
                              balance: balance,
                              startDate: _startDate,
                              dueDate: _dueDate,
                              important: _important,
                              paidInFull: _paidInFull,
                              moneyFmt: _moneyFmt,
                              dateFmt: _fmt,
                              description: _description.text.trim(),
                            ),
                          ),
                        ],
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: formContent,
                      ),
              ),
            ),
            bottomNavigationBar: SafeArea(
              top: false,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  isDesktop ? 24 : 16,
                  12,
                  isDesktop ? 24 : 16,
                  16,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => Get.back(), // NEW: disable while saving
                      icon: const Icon(Icons.close),
                      label: Text('cancel'.tr),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _onSave, // NEW
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: Text(
                          _saving ? 'Saving...' : 'save_job'.tr,
                        ), // NEW
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

          // NEW: full-page loading overlay
          return Stack(
            fit: StackFit.expand,
            children: [
              page,
              if (_saving) ...[
                const ModalBarrier(color: Colors.black26, dismissible: false),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0.5,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _TwoColWrap extends StatelessWidget {
  const _TwoColWrap({required this.isDesktop, required this.children});

  final bool isDesktop;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final colWidth = isDesktop
            ? (constraints.maxWidth - 16) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: children
              .map((w) => SizedBox(width: colWidth, child: w))
              .toList(growable: false),
        );
      },
    );
  }
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.label,
    required this.valueText,
    required this.onTap,
    required this.icon,
  });

  final String label;
  final String valueText;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          filled: true,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            valueText,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: valueText == '-' ? scheme.outline : null,
            ),
          ),
        ),
      ),
    );
  }
}

// New: currency input formatter with thousands separators and decimals
class CurrencyTextInputFormatter extends TextInputFormatter {
  CurrencyTextInputFormatter({required this.locale, this.decimalDigits = 2})
    : _formatter = NumberFormat.decimalPattern(locale);

  final String locale;
  final int decimalDigits;
  final NumberFormat _formatter;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text;

    // Allow empty
    if (text.isEmpty) {
      return newValue;
    }

    // Keep only digits and dot
    text = text.replaceAll(RegExp(r'[^0-9.]'), '');

    // Split into integer and decimal parts
    final parts = text.split('.');
    String intPart = parts[0].replaceAll(RegExp(r'[^0-9]'), '');
    String decPart = parts.length > 1
        ? parts[1].replaceAll(RegExp(r'[^0-9]'), '')
        : '';

    if (intPart.isEmpty) intPart = '0';
    if (decimalDigits >= 0 && decPart.length > decimalDigits) {
      decPart = decPart.substring(0, decimalDigits);
    }

    // Format integer part with thousands separators
    final intVal = int.tryParse(intPart) ?? 0;
    final formattedInt = _formatter.format(intVal);

    final result = decPart.isNotEmpty ? '$formattedInt.$decPart' : formattedInt;

    // Place caret at the end (simple and reliable)
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}

// New: Desktop summary card
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.client,
    required this.jobType,
    required this.total,
    required this.advance,
    required this.balance,
    required this.startDate,
    required this.dueDate,
    required this.important,
    required this.paidInFull,
    required this.moneyFmt,
    required this.dateFmt,
    required this.description, // NEW
  });

  final String client;
  final String jobType;
  final double total;
  final double advance;
  final double balance;
  final DateTime? startDate;
  final DateTime? dueDate;
  final bool important;
  final bool paidInFull;
  final NumberFormat moneyFmt;
  final DateFormat dateFmt;
  final String description; // NEW

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isOverdue =
        dueDate != null &&
        dueDate!.isBefore(DateTime(now.year, now.month, now.day));

    return Card(
      margin: const EdgeInsets.fromLTRB(0, 24, 24, 24),
      elevation: 0.5,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle(
          style: theme.textTheme.bodyMedium!,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Summary', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              if (client.isNotEmpty)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person),
                  title: Text(client),
                  subtitle: jobType.isNotEmpty ? Text(jobType) : null,
                ),
              if (description.isNotEmpty) // NEW
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.notes_outlined, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          description,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.request_quote_outlined),
                title: Text('${'total_amount'.tr}: ${moneyFmt.format(total)}'),
                subtitle: Text(
                  '${'advance_paid'.tr}: ${moneyFmt.format(advance)}',
                ),
                trailing: Chip(
                  label: Text(
                    '${'balance'.tr.isEmpty ? 'Balance' : 'balance'.tr}: ${moneyFmt.format(balance)}',
                  ),
                  avatar: Icon(
                    balance <= 0
                        ? Icons.verified
                        : Icons.account_balance_wallet_outlined,
                    size: 18,
                  ),
                ),
              ),
              const Divider(),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(
                  '${'start_date'.tr}: ${startDate == null ? '-' : dateFmt.format(startDate!)}',
                ),
                subtitle: Text(
                  '${'due_date'.tr}: ${dueDate == null ? '-' : dateFmt.format(dueDate!)}',
                ),
                trailing: dueDate == null
                    ? null
                    : Icon(
                        isOverdue
                            ? Icons.warning_amber_rounded
                            : Icons.schedule,
                        color: isOverdue
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
              ),
              const Divider(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(Icons.star_border, size: 16),
                    label: Text(important ? 'Important' : 'Normal'),
                  ),
                  Chip(
                    avatar: const Icon(Icons.check_circle_outline, size: 16),
                    label: Text(paidInFull ? 'Paid in full' : 'Pending'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
