import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:tra_list/jobs/controllers/debt_controller.dart';
import 'package:tra_list/jobs/models/debt.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/profile_service.dart';
import 'package:tra_list/services/thousands_separator_formatter.dart';

class AddDebtPage extends StatefulWidget {
  final Debt? debt;

  const AddDebtPage({super.key, this.debt});

  @override
  State<AddDebtPage> createState() => _AddDebtPageState();
}

class _AddDebtPageState extends State<AddDebtPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _controller = Get.find<DebtController>();

  DebtDirection _direction = DebtDirection.customerOwesShop;
  String _reason = 'advance';
  String _shopNickname = '';
  DateTime? _dueDate;
  bool _loadingShops = true;
  bool _saving = false;
  List<String> _shops = [];

  bool get _isEditing => widget.debt != null;

  @override
  void initState() {
    super.initState();
    final debt = widget.debt;
    if (debt != null) {
      _nameController.text = debt.debtorName;
      _phoneController.text = debt.phone;
      _amountController.text = ThousandsSeparatorFormatter.format(
        debt.principal,
      );
      _notesController.text = debt.notes;
      _direction = debt.direction;
      _reason = debt.reason;
      _dueDate = debt.dueDate;
      _shopNickname = debt.shopNickname;
    }
    _loadShops();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadShops() async {
    if (!BusinessAccessService.isOwner.value) {
      _shopNickname = BusinessAccessService.shopNickname.value.trim();
      _shops = [_shopNickname];
      if (mounted) setState(() => _loadingShops = false);
      return;
    }

    try {
      final profile = await ProfileService.loadOrCreate();
      final ownShop =
          profile['shopNickname']?.toString().trim().isNotEmpty == true
          ? profile['shopNickname'].toString().trim()
          : profile['name']?.toString().trim() ?? '';
      final shops = <String>{
        if (ownShop.isNotEmpty) ownShop,
        if (widget.debt?.shopNickname.isNotEmpty == true)
          widget.debt!.shopNickname,
      };
      final memberships = await FirebaseFirestore.instance
          .collection('employeeMemberships')
          .where('businessUid', isEqualTo: BusinessAccessService.businessId)
          .get();
      for (final membership in memberships.docs) {
        final shop = membership.data()['shopNickname']?.toString().trim() ?? '';
        if (shop.isNotEmpty) shops.add(shop);
      }
      final sortedShops = shops.toList()..sort();
      if (!mounted) return;
      setState(() {
        _shops = sortedShops;
        _shopNickname =
            widget.debt?.shopNickname ??
            (ownShop.isNotEmpty
                ? ownShop
                : (sortedShops.isEmpty ? '' : sortedShops.first));
        _loadingShops = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load debt shop options: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _loadingShops = false);
      Get.snackbar('error'.tr, 'debt_shops_load_error'.tr);
    }
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  double _parseAmount() =>
      double.tryParse(_amountController.text.trim().replaceAll(',', '')) ?? 0;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_loadingShops) return;
    if (_shops.isEmpty || _shopNickname.isEmpty) {
      Get.snackbar('error'.tr, 'debt_shop_required'.tr);
      return;
    }

    setState(() => _saving = true);
    try {
      final existing = widget.debt;
      await _controller.save(
        Debt(
          id: existing?.id,
          debtorName: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          direction: _direction,
          reason: _reason,
          notes: _notesController.text.trim(),
          principal: _parseAmount(),
          amountPaid: existing?.amountPaid ?? 0,
          dueDate: _dueDate,
          shopNickname: _shopNickname,
          createdAt: existing?.createdAt,
        ),
        isEditing: _isEditing,
      );
      if (mounted) Get.back();
    } catch (_) {
      // The controller reports save errors to the user.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF19313A);
    const brand = Color(0xFF0E5962);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F8),
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Get.back(),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          (_isEditing ? 'debt_edit_title' : 'debt_add_title').tr,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.white,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0E5962), Color(0xFF247C78)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: brand.withValues(alpha: 0.16),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(
                          _isEditing
                              ? Icons.edit_note_rounded
                              : Icons.account_balance_wallet_rounded,
                          color: Colors.white,
                          size: 25,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (_isEditing
                                      ? 'debt_edit_title'
                                      : 'debt_add_title')
                                  .tr,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'debt_form_intro'.tr,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.82),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _sectionCard(
                  context,
                  icon: Icons.swap_horiz_rounded,
                  title: 'debt_direction'.tr,
                  subtitle: 'debt_direction_hint'.tr,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 430;
                      final first = _directionOption(
                        context,
                        direction: DebtDirection.customerOwesShop,
                        title: 'debt_customer_owes'.tr,
                        icon: Icons.call_received_rounded,
                        color: const Color(0xFF176C55),
                      );
                      final second = _directionOption(
                        context,
                        direction: DebtDirection.shopOwesOther,
                        title: 'debt_shop_owes'.tr,
                        icon: Icons.call_made_rounded,
                        color: const Color(0xFF8C5A17),
                      );
                      if (isNarrow) {
                        return Column(
                          children: [first, const SizedBox(height: 10), second],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: first),
                          const SizedBox(width: 12),
                          Expanded(child: second),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                _sectionCard(
                  context,
                  icon: Icons.person_outline_rounded,
                  title: 'debt_person_section'.tr,
                  subtitle: 'debt_person_section_hint'.tr,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _decoration(
                          'debt_person_name'.tr,
                          Icons.person_outline_rounded,
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'validation_required'.tr
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: _decoration(
                          'phone_primary'.tr,
                          Icons.phone_outlined,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _sectionCard(
                  context,
                  icon: Icons.payments_outlined,
                  title: 'debt_details_section'.tr,
                  subtitle: 'debt_details_section_hint'.tr,
                  child: Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final reason = DropdownButtonFormField<String>(
                            initialValue: _reason,
                            isExpanded: true,
                            decoration: _decoration(
                              'debt_reason'.tr,
                              Icons.receipt_long_outlined,
                            ),
                            items: [
                              for (final value in const [
                                'advance',
                                'goods_credit',
                                'service',
                                'other',
                              ])
                                DropdownMenuItem(
                                  value: value,
                                  child: Text(
                                    'debt_reason_$value'.tr,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _reason = value);
                              }
                            },
                          );
                          final amount = TextFormField(
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [ThousandsSeparatorFormatter()],
                            decoration: _decoration(
                              'debt_original_amount'.tr,
                              Icons.payments_outlined,
                            ).copyWith(suffixText: 'TZS'),
                            validator: (value) {
                              final amount =
                                  double.tryParse(
                                    (value ?? '').trim().replaceAll(',', ''),
                                  ) ??
                                  0;
                              if (amount <= 0) {
                                return 'validation_amount_positive'.tr;
                              }
                              if (_isEditing &&
                                  amount < widget.debt!.amountPaid) {
                                return 'debt_amount_below_paid'.tr;
                              }
                              return null;
                            },
                          );
                          if (constraints.maxWidth < 520) {
                            return Column(
                              children: [
                                reason,
                                const SizedBox(height: 12),
                                amount,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: reason),
                              const SizedBox(width: 12),
                              Expanded(child: amount),
                            ],
                          );
                        },
                      ),
                      if (_isEditing) ...[
                        const SizedBox(height: 14),
                        _buildExistingDebtSummary(ink, brand),
                      ],
                      if (BusinessAccessService.isOwner.value) ...[
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _shops.contains(_shopNickname)
                              ? _shopNickname
                              : null,
                          isExpanded: true,
                          decoration: _decoration(
                            'transactions_filter_shop'.tr,
                            Icons.storefront_outlined,
                          ),
                          items: [
                            for (final shop in _shops)
                              DropdownMenuItem(
                                value: shop,
                                child: Text(
                                  shop,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: _loadingShops
                              ? null
                              : (shop) {
                                  if (shop != null) {
                                    setState(() => _shopNickname = shop);
                                  }
                                },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _sectionCard(
                  context,
                  icon: Icons.event_outlined,
                  title: 'debt_due_date_optional'.tr,
                  subtitle: 'debt_due_date_hint'.tr,
                  child: _buildDueDateTile(context),
                ),
                const SizedBox(height: 14),
                _sectionCard(
                  context,
                  icon: Icons.notes_rounded,
                  title: 'debt_notes_optional'.tr,
                  subtitle: 'debt_notes_hint'.tr,
                  child: TextFormField(
                    controller: _notesController,
                    minLines: 3,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'debt_notes_placeholder'.tr,
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE5EAEC))),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 728),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _saving || _loadingShops ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: brand,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _isEditing ? Icons.check_rounded : Icons.add_rounded,
                        ),
                  label: Text(
                    _saving
                        ? 'debt_saving'.tr
                        : (_isEditing
                                  ? 'debt_update_action'
                                  : 'debt_save_action')
                              .tr,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5EAEC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3F3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF0E5962), size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF19313A),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF75838A),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _directionOption(
    BuildContext context, {
    required DebtDirection direction,
    required String title,
    required IconData icon,
    required Color color,
  }) {
    final selected = _direction == direction;
    return Material(
      color: selected ? color.withValues(alpha: 0.07) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => setState(() => _direction = direction),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? color : const Color(0xFFE5EAEC),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 21),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: selected ? color : const Color(0xFF19313A),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? color : const Color(0xFF9AA5AA),
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExistingDebtSummary(Color ink, Color brand) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _summaryValue(
              'debt_paid_so_far'.tr,
              widget.debt!.amountPaid,
              ink,
            ),
          ),
          Container(width: 1, height: 34, color: const Color(0xFFDDE5E6)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 14),
              child: _summaryValue(
                'debt_balance'.tr,
                widget.debt!.balance,
                brand,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryValue(String label, double amount, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: Color(0xFF75838A), fontSize: 11),
      ),
      const SizedBox(height: 4),
      Text(
        'TZS ${amount.toStringAsFixed(0)}',
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    ],
  );

  Widget _buildDueDateTile(BuildContext context) {
    final hasDate = _dueDate != null;
    return Material(
      color: const Color(0xFFF7F9F9),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5EAEC)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_month_outlined, color: Color(0xFF0E5962)),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: _pickDueDate,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasDate
                            ? MaterialLocalizations.of(
                                context,
                              ).formatMediumDate(_dueDate!)
                            : 'debt_due_date_optional'.tr,
                        style: const TextStyle(
                          color: Color(0xFF19313A),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (hasDate) ...[
                        const SizedBox(height: 3),
                        Text(
                          'debt_due_date_selected'.tr,
                          style: const TextStyle(
                            color: Color(0xFF75838A),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (hasDate)
              IconButton(
                tooltip: 'debt_remove_due_date'.tr,
                onPressed: () => setState(() => _dueDate = null),
                icon: const Icon(Icons.close_rounded),
              )
            else
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF75838A)),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );
}
