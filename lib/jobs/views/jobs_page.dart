import 'package:flutter/material.dart';
import 'package:tra_list/services/thousands_separator_formatter.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:tra_list/jobs/controllers/debt_controller.dart';
import 'package:tra_list/jobs/models/debt.dart';
import 'package:tra_list/jobs/services/debt_service.dart';
import 'package:tra_list/jobs/views/add_debt_page.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:url_launcher/url_launcher.dart';

class JobsPage extends StatefulWidget {
  const JobsPage({super.key});

  @override
  State<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends State<JobsPage> {
  late final DebtController _controller;
  late final NumberFormat _currency;
  final _dateFormat = DateFormat.yMMMd();

  @override
  void initState() {
    super.initState();
    _controller = Get.isRegistered<DebtController>()
        ? Get.find<DebtController>()
        : Get.put(DebtController());
    _currency = NumberFormat.currency(
      locale: Get.locale?.toString() ?? 'en_TZ',
      symbol: 'TZS ',
      decimalDigits: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F8),
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Get.back(),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          'debts_title'.tr,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: const Color(0xFFF5F7F8),
        foregroundColor: const Color(0xFF19313A),
        elevation: 0,
        actions: [
          PopupMenuButton<DebtSortOption>(
            tooltip: 'debt_sort'.tr,
            icon: const Icon(Icons.sort_rounded),
            onSelected: (option) => _controller.sortOption.value = option,
            itemBuilder: (context) => [
              _sortItem(DebtSortOption.newest, 'debt_sort_newest'.tr),
              _sortItem(DebtSortOption.oldest, 'debt_sort_oldest'.tr),
              _sortItem(
                DebtSortOption.highestBalance,
                'debt_sort_highest_balance'.tr,
              ),
              _sortItem(
                DebtSortOption.lowestBalance,
                'debt_sort_lowest_balance'.tr,
              ),
              _sortItem(DebtSortOption.dueSoonest, 'debt_sort_due_soonest'.tr),
            ],
          ),
          if (BusinessAccessService.isOwner.value)
            IconButton(
              tooltip: 'debt_legacy_archive'.tr,
              onPressed: () => Get.toNamed(AppRoutes.jobsArchive),
              icon: const Icon(Icons.inventory_2_outlined),
            ),
        ],
      ),
      floatingActionButton: BusinessAccessService.can('jobs', 'create')
          ? FloatingActionButton.extended(
              onPressed: () => Get.to(() => const AddDebtPage()),
              icon: const Icon(Icons.add),
              label: Text('debt_add_title'.tr),
            )
          : null,
      body: Obx(() {
        if (_controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_controller.loadError.value.isNotEmpty) {
          return _message(
            context,
            Icons.error_outline_rounded,
            'debt_load_error'.tr,
            onRetry: _controller.reload,
          );
        }

        final debts = _controller.filtered;
        return RefreshIndicator(
          onRefresh: () async => _controller.reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              _buildSummary(context),
              const SizedBox(height: 16),
              _buildSearchAndFilters(),
              const SizedBox(height: 14),
              if (debts.isEmpty)
                _message(
                  context,
                  Icons.account_balance_wallet_outlined,
                  _controller.debts.isEmpty
                      ? 'debt_empty'.tr
                      : 'debt_no_filter_results'.tr,
                )
              else
                for (final debt in debts)
                  _DebtCard(
                    debt: debt,
                    currency: _currency,
                    dateFormat: _dateFormat,
                    showShopName: BusinessAccessService.isOwner.value,
                    canEdit: BusinessAccessService.can('jobs', 'edit'),
                    onEdit: () => Get.to(() => AddDebtPage(debt: debt)),
                    onPayment: () => _recordPayment(debt),
                    onHistory: () => _showPaymentHistory(debt),
                  ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildSummary(BuildContext context) {
    return Obx(
      () => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _summaryCard(
            context,
            'debt_receivable'.tr,
            _currency.format(_controller.receivableBalance),
            Icons.call_received_rounded,
            const Color(0xFF176C55),
            const Color(0xFFE5F3ED),
          ),
          _summaryCard(
            context,
            'debt_payable'.tr,
            _currency.format(_controller.payableBalance),
            Icons.call_made_rounded,
            const Color(0xFF8C5A17),
            const Color(0xFFFBF1E2),
          ),
          _summaryCard(
            context,
            'debt_overdue'.tr,
            '${_controller.overdueCount}',
            Icons.event_busy_outlined,
            const Color(0xFFAD3D3D),
            const Color(0xFFF9EAEA),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
    Color background,
  ) {
    final width = (MediaQuery.sizeOf(context).width - 42) / 2;
    return Container(
      width: width.clamp(150, 420).toDouble(),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5EAEC)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11)),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller.searchController,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: 'debt_search_hint'.tr,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE5EAEC)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE5EAEC)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Obx(
            () => Row(
              children: [
                for (final filter in DebtFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_filterLabel(filter)),
                      selected: _controller.filter.value == filter,
                      onSelected: (_) => _controller.filter.value = filter,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Obx(
          () => DropdownButtonFormField<String>(
            initialValue: _controller.reasonFilter.value,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'debt_reason_filter'.tr,
              prefixIcon: const Icon(Icons.filter_alt_outlined),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE5EAEC)),
              ),
            ),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text('debt_reason_filter_all'.tr),
              ),
              for (final reason in const [
                'advance',
                'goods_credit',
                'service',
                'other',
              ])
                DropdownMenuItem(
                  value: reason,
                  child: Text('debt_reason_$reason'.tr),
                ),
            ],
            onChanged: (reason) {
              if (reason != null) _controller.reasonFilter.value = reason;
            },
          ),
        ),
      ],
    );
  }

  CheckedPopupMenuItem<DebtSortOption> _sortItem(
    DebtSortOption option,
    String label,
  ) => CheckedPopupMenuItem(
    value: option,
    checked: _controller.sortOption.value == option,
    child: Text(label),
  );

  String _filterLabel(DebtFilter filter) => switch (filter) {
    DebtFilter.all => 'debt_filter_all'.tr,
    DebtFilter.customerOwesShop => 'debt_customer_owes_short'.tr,
    DebtFilter.shopOwesOther => 'debt_shop_owes_short'.tr,
    DebtFilter.overdue => 'debt_overdue'.tr,
    DebtFilter.settled => 'debt_settled'.tr,
  };

  Widget _message(
    BuildContext context,
    IconData icon,
    String message, {
    VoidCallback? onRetry,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).hintColor),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text('retry'.tr),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _recordPayment(Debt debt) async {
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    var paidAt = DateTime.now();
    var method = 'cash';
    final formKey = GlobalKey<FormState>();
    await Get.dialog<void>(
      StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('debt_record_payment'.tr),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${'debt_balance'.tr}: ${_currency.format(debt.balance)}',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: amountController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [ThousandsSeparatorFormatter()],
                  decoration: InputDecoration(
                    labelText: 'debt_payment_amount'.tr,
                    suffixText: 'TZS',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final amount =
                        double.tryParse(
                          (value ?? '').trim().replaceAll(',', ''),
                        ) ??
                        0;
                    if (amount <= 0) return 'validation_amount_positive'.tr;
                    if (amount > debt.balance) {
                      return 'debt_payment_exceeds_balance'.tr;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: InputDecoration(
                    labelText: 'debt_payment_method'.tr,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final value in const [
                      'cash',
                      'mobile_money',
                      'bank',
                      'other',
                    ])
                      DropdownMenuItem(
                        value: value,
                        child: Text('debt_payment_method_$value'.tr),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => method = value);
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: notesController,
                  decoration: InputDecoration(
                    labelText: 'debt_payment_notes_optional'.tr,
                    border: const OutlineInputBorder(),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final date = await showDatePicker(
                      context: context,
                      initialDate: paidAt,
                      firstDate: DateTime(now.year - 10),
                      lastDate: DateTime(now.year + 1),
                    );
                    if (date != null) setDialogState(() => paidAt = date);
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    '${'debt_payment_date'.tr}: ${_dateFormat.format(paidAt)}',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Get.back(), child: Text('cancel'.tr)),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final amount = double.parse(
                  amountController.text.trim().replaceAll(',', ''),
                );
                try {
                  await _controller.recordPayment(
                    debtId: debt.id,
                    amount: amount,
                    paidAt: paidAt,
                    method: method,
                    notes: notesController.text,
                  );
                  if (Get.isDialogOpen == true) Get.back();
                } catch (_) {
                  // The controller reports payment errors to the user.
                }
              },
              child: Text('save'.tr),
            ),
          ],
        ),
      ),
    );
    amountController.dispose();
    notesController.dispose();
  }

  Future<void> _showPaymentHistory(Debt debt) async {
    final context = Get.context!;
    await Get.bottomSheet<void>(
      SafeArea(
        child: Container(
          height: MediaQuery.sizeOf(context).height * 0.65,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'debt_payment_history'.tr,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Get.back(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder(
                  stream: DebtService.watchPayments(debt.id),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text('debt_payment_history_error'.tr),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final payments = snapshot.data!.docs
                        .map((doc) => doc.data())
                        .toList();
                    if (payments.isEmpty) {
                      return Center(child: Text('debt_no_payments'.tr));
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: payments.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final payment = payments[index];
                        return ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.payments_outlined),
                          ),
                          title: Text(_currency.format(payment.amount)),
                          subtitle: Text(
                            [
                              _dateFormat.format(payment.paidAt),
                              'debt_payment_method_${payment.method}'.tr,
                              if (payment.notes.isNotEmpty) payment.notes,
                            ].join(' • '),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }
}

class _DebtCard extends StatelessWidget {
  const _DebtCard({
    required this.debt,
    required this.currency,
    required this.dateFormat,
    required this.showShopName,
    required this.canEdit,
    required this.onEdit,
    required this.onPayment,
    required this.onHistory,
  });

  final Debt debt;
  final NumberFormat currency;
  final DateFormat dateFormat;
  final bool showShopName;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onPayment;
  final VoidCallback onHistory;

  Color get _statusColor => debt.isSettled
      ? const Color(0xFF267A54)
      : debt.isOverdue
      ? const Color(0xFFB14444)
      : const Color(0xFF246C9A);

  String get _status => debt.isSettled
      ? 'debt_settled'.tr
      : debt.isOverdue
      ? 'debt_overdue'.tr
      : debt.amountPaid > 0
      ? 'debt_partially_paid'.tr
      : 'debt_unpaid'.tr;

  @override
  Widget build(BuildContext context) {
    final isReceivable = debt.direction == DebtDirection.customerOwesShop;
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5EAEC)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    debt.debtorName,
                    style: const TextStyle(
                      color: Color(0xFF19313A),
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (debt.phone.isNotEmpty)
                  IconButton(
                    tooltip: 'debt_call'.tr,
                    onPressed: () =>
                        launchUrl(Uri(scheme: 'tel', path: debt.phone)),
                    icon: const Icon(Icons.call_outlined),
                  ),
                PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'edit') onEdit();
                    if (action == 'payment') onPayment();
                    if (action == 'history') onHistory();
                  },
                  itemBuilder: (context) => [
                    if (canEdit)
                      PopupMenuItem(value: 'edit', child: Text('edit'.tr)),
                    if (canEdit && !debt.isSettled)
                      PopupMenuItem(
                        value: 'payment',
                        child: Text('debt_record_payment'.tr),
                      ),
                    PopupMenuItem(
                      value: 'history',
                      child: Text('debt_payment_history'.tr),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _badge(
                  isReceivable
                      ? 'debt_customer_owes_short'.tr
                      : 'debt_shop_owes_short'.tr,
                  isReceivable
                      ? const Color(0xFFE5F3ED)
                      : const Color(0xFFFBF1E2),
                  isReceivable
                      ? const Color(0xFF176C55)
                      : const Color(0xFF8C5A17),
                ),
                _badge(
                  'debt_reason_${debt.reason}'.tr,
                  const Color(0xFFF0F3F4),
                  const Color(0xFF55636A),
                ),
                if (showShopName && debt.shopNickname.isNotEmpty)
                  _badge(
                    debt.shopNickname,
                    const Color(0xFFEAF3F9),
                    const Color(0xFF246C9A),
                  ),
                _badge(
                  _status,
                  _statusColor.withValues(alpha: 0.10),
                  _statusColor,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _amountStat(
                    'debt_original_amount'.tr,
                    currency.format(debt.principal),
                    const Color(0xFF19313A),
                  ),
                ),
                Expanded(
                  child: _amountStat(
                    'debt_balance'.tr,
                    currency.format(debt.balance),
                    _statusColor,
                  ),
                ),
              ],
            ),
            if (debt.amountPaid > 0) ...[
              const SizedBox(height: 7),
              Text(
                '${'debt_paid_so_far'.tr}: ${currency.format(debt.amountPaid)}',
                style: const TextStyle(color: Color(0xFF75838A), fontSize: 12),
              ),
            ],
            if (debt.dueDate != null) ...[
              const SizedBox(height: 8),
              Text(
                '${'due_date'.tr}: ${dateFormat.format(debt.dueDate!)}',
                style: TextStyle(
                  color: debt.isOverdue
                      ? _statusColor
                      : const Color(0xFF75838A),
                  fontSize: 12,
                  fontWeight: debt.isOverdue ? FontWeight.w700 : null,
                ),
              ),
            ],
            if (debt.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                debt.notes,
                style: const TextStyle(color: Color(0xFF75838A), fontSize: 12),
              ),
            ],
            if (canEdit && !debt.isSettled) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onPayment,
                  icon: const Icon(Icons.add_card_rounded),
                  label: Text('debt_record_payment'.tr),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _amountStat(String label, String amount, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: Color(0xFF75838A), fontSize: 11),
      ),
      const SizedBox(height: 3),
      Text(
        amount,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    ],
  );

  Widget _badge(String label, Color background, Color foreground) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: foreground,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
