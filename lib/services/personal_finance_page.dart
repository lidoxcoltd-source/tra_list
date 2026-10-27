import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/services/personal_finance_service.dart';
import 'package:tra_list/services/support_center_fab.dart';
import 'package:tra_list/theme/app_theme.dart';

class PersonalFinancePage extends StatefulWidget {
  const PersonalFinancePage({
    super.key,
    this.embedded = false,
    this.analyticsOnly = false,
  });

  final bool embedded;
  final bool analyticsOnly;

  @override
  PersonalFinancePageState createState() => PersonalFinancePageState();
}

class PersonalFinancePageState extends State<PersonalFinancePage>
    with SingleTickerProviderStateMixin {
  int _tabIndex = 0;
  String _transactionFilter = 'all';
  String _currency = 'TZS';
  String _dateFormat = 'dd/MM/yyyy';
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(_onTabChanged);
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final preferences = await PersonalFinanceService.loadProfile();
      if (!mounted) return;
      setState(() {
        _currency = preferences['currency'] as String;
        _dateFormat = preferences['dateFormat'] as String;
      });
    } catch (error) {
      debugPrint('Could not load personal finance preferences: $error');
    }
  }

  void _onTabChanged() {
    if (_tabController.index != _tabIndex && mounted) {
      setState(() => _tabIndex = _tabController.index);
    }
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _showAddDialog() async {
    if (_tabIndex == 0) {
      await _showTransactionDialog();
    } else {
      await _showPlanDialog(isGoal: _tabIndex == 2);
    }
  }

  Future<void> showAddDialog() => _showAddDialog();

  Future<void> _openSettings() async {
    await Get.toNamed(AppRoutes.personalSettings);
    await _loadPreferences();
  }

  Future<void> _showTransactionDialog({String initialType = 'expense'}) async {
    final formKey = GlobalKey<FormState>();
    final description = TextEditingController();
    final category = TextEditingController();
    final amount = TextEditingController();
    var type = initialType;
    try {
      final shouldSave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => _PersonalFormDialog(
            title: 'personal_add_transaction'.tr,
            subtitle: 'personal_transaction_dialog_hint'.tr,
            icon: Icons.swap_horiz_rounded,
            accent: type == 'income' ? MjasiColors.success : MjasiColors.error,
            saveLabel: 'save'.tr,
            cancelLabel: 'cancel'.tr,
            onCancel: () => Navigator.pop(dialogContext, false),
            onSave: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: 'income',
                        icon: const Icon(Icons.south_west_rounded, size: 18),
                        label: Text('personal_income'.tr),
                      ),
                      ButtonSegment(
                        value: 'expense',
                        icon: const Icon(Icons.north_east_rounded, size: 18),
                        label: Text('personal_expense'.tr),
                      ),
                    ],
                    selected: {type},
                    onSelectionChanged: (selection) {
                      setDialogState(() => type = selection.first);
                    },
                    style: ButtonStyle(
                      foregroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? (type == 'income'
                                  ? MjasiColors.success
                                  : MjasiColors.error)
                            : MjasiColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: description,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _personalFieldDecoration(
                      label: 'personal_description'.tr,
                      icon: Icons.notes_rounded,
                    ),
                    validator: _requiredText,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: category,
                    textCapitalization: TextCapitalization.words,
                    decoration: _personalFieldDecoration(
                      label: 'personal_category'.tr,
                      icon: Icons.category_outlined,
                    ),
                    validator: _requiredText,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _personalFieldDecoration(
                      label: 'personal_amount'.tr,
                      icon: Icons.payments_outlined,
                      suffix: _currency,
                    ),
                    validator: _amountValidator,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (shouldSave == true) {
        await PersonalFinanceService.addTransaction(
          type: type,
          description: description.text,
          category: category.text,
          amount: double.parse(amount.text),
          date: DateTime.now(),
        );
      }
    } finally {
      description.dispose();
      category.dispose();
      amount.dispose();
    }
  }

  Future<void> _showPlanDialog({required bool isGoal}) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final amount = TextEditingController();
    try {
      final shouldSave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => _PersonalFormDialog(
          title: isGoal ? 'personal_add_goal'.tr : 'personal_add_budget'.tr,
          subtitle: isGoal
              ? 'personal_goal_dialog_hint'.tr
              : 'personal_budget_dialog_hint'.tr,
          icon: isGoal
              ? Icons.savings_outlined
              : Icons.account_balance_wallet_outlined,
          accent: MjasiColors.primaryBlue,
          saveLabel: 'save'.tr,
          cancelLabel: 'cancel'.tr,
          onCancel: () => Navigator.pop(dialogContext, false),
          onSave: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(dialogContext, true);
            }
          },
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration: _personalFieldDecoration(
                    label: isGoal
                        ? 'personal_goal_name'.tr
                        : 'personal_budget_name'.tr,
                    icon: isGoal
                        ? Icons.flag_outlined
                        : Icons.edit_note_rounded,
                  ),
                  validator: _requiredText,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _personalFieldDecoration(
                    label: isGoal
                        ? 'personal_target_amount'.tr
                        : 'personal_budget_amount'.tr,
                    icon: Icons.payments_outlined,
                    suffix: _currency,
                  ),
                  validator: _amountValidator,
                ),
              ],
            ),
          ),
        ),
      );
      if (shouldSave == true) {
        final value = double.parse(amount.text);
        if (isGoal) {
          await PersonalFinanceService.saveGoal(
            name: name.text,
            targetAmount: value,
            savedAmount: 0,
          );
        } else {
          await PersonalFinanceService.saveBudget(
            name: name.text,
            amount: value,
          );
        }
      }
    } finally {
      name.dispose();
      amount.dispose();
    }
  }

  Future<void> _showGoalProgressDialog({
    required String id,
    required double targetAmount,
    required double currentAmount,
  }) async {
    final controller = TextEditingController(text: currentAmount.toString());
    final formKey = GlobalKey<FormState>();
    try {
      final save = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => _PersonalFormDialog(
          title: 'personal_update_savings'.tr,
          subtitle: 'personal_savings_dialog_hint'.tr,
          icon: Icons.savings_rounded,
          accent: MjasiColors.success,
          saveLabel: 'save'.tr,
          cancelLabel: 'cancel'.tr,
          onCancel: () => Navigator.pop(dialogContext, false),
          onSave: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(dialogContext, true);
            }
          },
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: MjasiColors.successBackground,
                    borderRadius: BorderRadius.circular(MjasiRadius.sm),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.track_changes_rounded,
                        color: MjasiColors.success,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'personal_target_amount'.tr,
                              style: const TextStyle(
                                color: MjasiColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '$_currency ${NumberFormat('#,##0.##').format(targetAmount)}',
                              style: const TextStyle(
                                color: MjasiColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _personalFieldDecoration(
                    label: 'personal_saved_amount'.tr,
                    icon: Icons.payments_outlined,
                    suffix: _currency,
                  ),
                  validator: (value) {
                    final amount = double.tryParse(value ?? '');
                    if (amount == null ||
                        !amount.isFinite ||
                        amount < 0 ||
                        amount > targetAmount) {
                      return 'personal_amount_invalid'.tr;
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      );
      if (save == true) {
        await PersonalFinanceService.updateGoalSavedAmount(
          id: id,
          targetAmount: targetAmount,
          savedAmount: double.parse(controller.text),
        );
      }
    } finally {
      controller.dispose();
    }
  }

  String? _requiredText(String? value) =>
      value == null || value.trim().isEmpty ? 'required'.tr : null;

  String? _amountValidator(String? value) {
    final parsed = double.tryParse(value ?? '');
    return parsed == null || !parsed.isFinite || parsed <= 0
        ? 'personal_amount_invalid'.tr
        : null;
  }

  InputDecoration _personalFieldDecoration({
    required String label,
    required IconData icon,
    String? suffix,
  }) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 20),
    suffixText: suffix,
    filled: true,
    fillColor: MjasiColors.background,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(MjasiRadius.sm),
      borderSide: const BorderSide(color: MjasiColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(MjasiRadius.sm),
      borderSide: const BorderSide(color: MjasiColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(MjasiRadius.sm),
      borderSide: const BorderSide(color: MjasiColors.primaryBlue, width: 1.5),
    ),
  );

  Tab _personalTab(IconData icon, String label) => Tab(
    height: 40,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17),
        const SizedBox(width: 6),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.analyticsOnly) return _buildPersonalAnalytics();
    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Container(
            height: 48,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: MjasiColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MjasiColors.border),
            ),
            child: TabBar(
              controller: _tabController,
              onTap: (index) => setState(() => _tabIndex = index),
              isScrollable: MediaQuery.sizeOf(context).width < 560,
              tabAlignment: MediaQuery.sizeOf(context).width < 560
                  ? TabAlignment.start
                  : TabAlignment.fill,
              dividerColor: Colors.transparent,
              splashBorderRadius: BorderRadius.circular(12),
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: MjasiColors.primaryNavy,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x2210233F),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              labelColor: Colors.white,
              unselectedLabelColor: MjasiColors.textSecondary,
              labelPadding: const EdgeInsets.symmetric(horizontal: 16),
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              tabs: [
                _personalTab(
                  Icons.receipt_long_rounded,
                  'personal_transactions'.tr,
                ),
                _personalTab(
                  Icons.account_balance_wallet_outlined,
                  'personal_budgets'.tr,
                ),
                _personalTab(
                  Icons.savings_outlined,
                  'personal_savings_goals'.tr,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildTransactions(),
              _buildPlans(isGoal: false),
              _buildPlans(isGoal: true),
            ],
          ),
        ),
      ],
    );
    if (widget.embedded) return content;

    return SupportCenterFabOverlay(
      child: Scaffold(
        backgroundColor: MjasiColors.background,
        appBar: AppBar(
          title: Text('personal_title'.tr),
          actions: [
            IconButton(
              tooltip: 'personal_settings'.tr,
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: content,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAddDialog,
          icon: const Icon(Icons.add_rounded),
          label: Text(switch (_tabIndex) {
            0 => 'personal_add_transaction'.tr,
            1 => 'personal_add_budget'.tr,
            _ => 'personal_add_goal'.tr,
          }),
        ),
      ),
    );
  }

  Widget _buildQuickAddButtons() => Row(
    children: [
      Expanded(
        child: FilledButton.icon(
          onPressed: () => _showTransactionDialog(initialType: 'income'),
          style: FilledButton.styleFrom(
            backgroundColor: MjasiColors.success,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
          ),
          icon: const Icon(Icons.south_west_rounded, size: 18),
          label: Text('personal_add_income'.tr),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: FilledButton.icon(
          onPressed: () => _showTransactionDialog(initialType: 'expense'),
          style: FilledButton.styleFrom(
            backgroundColor: MjasiColors.error,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
          ),
          icon: const Icon(Icons.north_east_rounded, size: 18),
          label: Text('personal_add_expense'.tr),
        ),
      ),
    ],
  );

  Widget _buildPersonalAnalytics() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: PersonalFinanceService.watchTransactions(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _MessageState(message: 'personal_load_error'.tr);
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final now = DateTime.now();
        final monthStart = DateTime(now.year, now.month);
        final docs = snapshot.data!.docs.where((doc) {
          final date = _transactionDate(doc.data()['date']);
          return date != null &&
              !date.isBefore(monthStart) &&
              date.isBefore(DateTime(now.year, now.month + 1));
        }).toList();
        var income = 0.0;
        var expenses = 0.0;
        final expensesByCategory = <String, double>{};
        for (final doc in docs) {
          final data = doc.data();
          final amount = (data['amount'] as num?)?.toDouble() ?? 0;
          if (!amount.isFinite || amount <= 0) continue;
          if (data['type'] == 'income') {
            income += amount;
          } else if (data['type'] == 'expense') {
            expenses += amount;
            final category = data['category']?.toString().trim();
            if (category != null && category.isNotEmpty) {
              expensesByCategory.update(
                category,
                (total) => total + amount,
                ifAbsent: () => amount,
              );
            }
          }
        }

        final categories = expensesByCategory.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final savingsRate = income > 0
            ? ((income - expenses) / income * 100).clamp(0.0, 100.0)
            : 0.0;
        final advice = _buildPersonalAdvice(
          income: income,
          expenses: expenses,
          categories: categories,
        );

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildQuickAddButtons(),
            const SizedBox(height: 16),
            Text(
              'personal_this_month'.tr,
              style: const TextStyle(
                color: MjasiColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            _SummaryCard(
              label: 'personal_net_balance'.tr,
              amount: income - expenses,
              currency: _currency,
              color: income >= expenses
                  ? MjasiColors.success
                  : MjasiColors.error,
              prominent: true,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    label: 'personal_income'.tr,
                    amount: income,
                    currency: _currency,
                    color: MjasiColors.success,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SummaryCard(
                    label: 'personal_expense'.tr,
                    amount: expenses,
                    currency: _currency,
                    color: MjasiColors.error,
                  ),
                ),
              ],
            ),
            if (income > 0) ...[
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'personal_savings_rate'.tr,
                        style: const TextStyle(
                          color: MjasiColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: savingsRate / 100,
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(8),
                              color: savingsRate >= 20
                                  ? MjasiColors.success
                                  : MjasiColors.primaryBlue,
                              backgroundColor: MjasiColors.border,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${savingsRate.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: MjasiColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'personal_spending_breakdown'.tr,
              style: const TextStyle(
                color: MjasiColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (categories.isEmpty)
              _MessageState(message: 'personal_no_spending_data'.tr)
            else
              ...categories.take(4).map((entry) {
                final share = expenses > 0 ? entry.value / expenses : 0.0;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.key,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: MjasiColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              _formatAmount(entry.value),
                              style: const TextStyle(
                                color: MjasiColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: share.clamp(0.0, 1.0),
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(6),
                          backgroundColor: MjasiColors.border,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 16),
            Text(
              'personal_advice'.tr,
              style: const TextStyle(
                color: MjasiColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (docs.isEmpty && snapshot.data!.docs.isEmpty)
              _PersonalAdviceCard(
                title: 'personal_advice_start_title'.tr,
                description: 'personal_advice_start_description'.tr,
                icon: Icons.lightbulb_outline_rounded,
                color: MjasiColors.primaryBlue,
              )
            else if (docs.isEmpty)
              _PersonalAdviceCard(
                title: 'personal_advice_no_month_title'.tr,
                description: 'personal_advice_no_month_description'.tr,
                icon: Icons.calendar_month_outlined,
                color: MjasiColors.primaryBlue,
              )
            else
              ...advice,
          ],
        );
      },
    );
  }

  DateTime? _transactionDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  List<Widget> _buildPersonalAdvice({
    required double income,
    required double expenses,
    required List<MapEntry<String, double>> categories,
  }) {
    final advice = <Widget>[];
    if (income == 0 && expenses > 0) {
      advice.add(
        _PersonalAdviceCard(
          title: 'personal_advice_income_title'.tr,
          description: 'personal_advice_income_description'.tr,
          icon: Icons.account_balance_wallet_outlined,
          color: MjasiColors.primaryBlue,
        ),
      );
    } else if (income > 0 && expenses > income) {
      advice.add(
        _PersonalAdviceCard(
          title: 'personal_advice_overspending_title'.tr,
          description: 'personal_advice_overspending_description'.trParams({
            'amount': _formatAmount(expenses - income),
          }),
          icon: Icons.warning_amber_rounded,
          color: MjasiColors.error,
        ),
      );
    } else if (income > 0 && expenses / income >= .8) {
      advice.add(
        _PersonalAdviceCard(
          title: 'personal_advice_high_spending_title'.tr,
          description: 'personal_advice_high_spending_description'.trParams({
            'percent': (expenses / income * 100).toStringAsFixed(0),
          }),
          icon: Icons.trending_up_rounded,
          color: MjasiColors.warning,
        ),
      );
    } else if (income > 0 && expenses > 0) {
      advice.add(
        _PersonalAdviceCard(
          title: 'personal_advice_saving_title'.tr,
          description: 'personal_advice_saving_description'.trParams({
            'amount': _formatAmount(income - expenses),
          }),
          icon: Icons.savings_outlined,
          color: MjasiColors.success,
        ),
      );
    } else if (income > 0) {
      advice.add(
        _PersonalAdviceCard(
          title: 'personal_advice_no_expenses_title'.tr,
          description: 'personal_advice_no_expenses_description'.tr,
          icon: Icons.receipt_long_outlined,
          color: MjasiColors.primaryBlue,
        ),
      );
    }

    if (expenses > 0 && categories.isNotEmpty) {
      final topCategory = categories.first;
      final share = topCategory.value / expenses;
      if (share >= .5 && categories.length > 1) {
        advice.add(
          _PersonalAdviceCard(
            title: 'personal_advice_category_title'.tr,
            description: 'personal_advice_category_description'.trParams({
              'category': topCategory.key,
              'percent': (share * 100).toStringAsFixed(0),
            }),
            icon: Icons.pie_chart_outline_rounded,
            color: MjasiColors.primaryBlue,
          ),
        );
      }
    }
    return advice;
  }

  Widget _buildTransactions() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: PersonalFinanceService.watchTransactions(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _MessageState(message: 'personal_load_error'.tr);
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        final income = docs.fold<double>(
          0,
          (total, item) =>
              total +
              (item.data()['type'] == 'income'
                  ? (item.data()['amount'] as num?)?.toDouble() ?? 0
                  : 0),
        );
        final expenses = docs.fold<double>(
          0,
          (total, item) =>
              total +
              (item.data()['type'] == 'expense'
                  ? (item.data()['amount'] as num?)?.toDouble() ?? 0
                  : 0),
        );
        final monthTotals = _monthlyTotals(docs);
        final visibleDocs = docs.where((doc) {
          final type = doc.data()['type'];
          return _transactionFilter == 'all' || type == _transactionFilter;
        }).toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildQuickAddButtons(),
            const SizedBox(height: 14),
            _SummaryCard(
              label: 'personal_net_balance'.tr,
              amount: income - expenses,
              currency: _currency,
              color: income >= expenses
                  ? MjasiColors.success
                  : MjasiColors.error,
              prominent: true,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    label: 'personal_income'.tr,
                    amount: income,
                    currency: _currency,
                    color: MjasiColors.success,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryCard(
                    label: 'personal_expense'.tr,
                    amount: expenses,
                    currency: _currency,
                    color: MjasiColors.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (docs.isNotEmpty) ...[
              _buildCashFlowChart(monthTotals),
              const SizedBox(height: 14),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'home_transactions'.tr,
                style: const TextStyle(
                  color: MjasiColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _transactionFilterChip('all', 'personal_filter_all'.tr),
                _transactionFilterChip('income', 'personal_income'.tr),
                _transactionFilterChip('expense', 'personal_expense'.tr),
              ],
            ),
            const SizedBox(height: 8),
            if (visibleDocs.isEmpty)
              _MessageState(message: 'personal_empty_transactions'.tr)
            else
              ...visibleDocs.map((doc) => _transactionTile(doc)),
          ],
        );
      },
    );
  }

  List<_PersonalMonthTotal> _monthlyTotals(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final now = DateTime.now();
    final months = List.generate(
      6,
      (index) => DateTime(now.year, now.month - 5 + index),
    );
    final totals = {
      for (final month in months)
        '${month.year}-${month.month}': _PersonalMonthTotal(
          DateFormat('MMM').format(month),
        ),
    };
    for (final doc in docs) {
      final data = doc.data();
      final rawDate = data['date'];
      final date = rawDate is Timestamp
          ? rawDate.toDate()
          : rawDate is DateTime
          ? rawDate
          : null;
      if (date == null) continue;
      final total = totals['${date.year}-${date.month}'];
      if (total == null) continue;
      final amount = (data['amount'] as num?)?.toDouble() ?? 0;
      if (data['type'] == 'income') {
        total.income += amount;
      } else if (data['type'] == 'expense') {
        total.expense += amount;
      }
    }
    return totals.values.toList();
  }

  Widget _buildCashFlowChart(List<_PersonalMonthTotal> totals) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'personal_cash_flow'.tr,
            style: const TextStyle(
              color: MjasiColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 190,
            child: SfCartesianChart(
              margin: EdgeInsets.zero,
              legend: const Legend(
                isVisible: true,
                position: LegendPosition.bottom,
                overflowMode: LegendItemOverflowMode.wrap,
              ),
              primaryXAxis: const CategoryAxis(
                majorGridLines: MajorGridLines(width: 0),
                axisLine: AxisLine(width: 0),
              ),
              primaryYAxis: const NumericAxis(
                axisLine: AxisLine(width: 0),
                majorTickLines: MajorTickLines(size: 0),
                majorGridLines: MajorGridLines(
                  color: MjasiColors.border,
                  width: .7,
                ),
                labelFormat: '{value}',
              ),
              series: <CartesianSeries<_PersonalMonthTotal, String>>[
                ColumnSeries<_PersonalMonthTotal, String>(
                  dataSource: totals,
                  xValueMapper: (item, _) => item.month,
                  yValueMapper: (item, _) => item.income,
                  name: 'personal_income'.tr,
                  color: MjasiColors.success,
                  width: .72,
                  spacing: .12,
                ),
                ColumnSeries<_PersonalMonthTotal, String>(
                  dataSource: totals,
                  xValueMapper: (item, _) => item.month,
                  yValueMapper: (item, _) => item.expense,
                  name: 'personal_expense'.tr,
                  color: MjasiColors.error,
                  width: .72,
                  spacing: .12,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _transactionFilterChip(String value, String label) => ChoiceChip(
    label: Text(label),
    selected: _transactionFilter == value,
    showCheckmark: false,
    selectedColor: MjasiColors.lightBlue,
    side: BorderSide(
      color: _transactionFilter == value
          ? MjasiColors.primaryBlue
          : MjasiColors.border,
    ),
    labelStyle: TextStyle(
      color: _transactionFilter == value
          ? MjasiColors.primaryBlue
          : MjasiColors.textSecondary,
      fontWeight: FontWeight.w600,
    ),
    onSelected: (_) => setState(() => _transactionFilter = value),
  );

  Widget _transactionTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final isIncome = data['type'] == 'income';
    final amount = (data['amount'] as num?)?.toDouble() ?? 0;
    final date = data['date'];
    final amountColor = isIncome ? MjasiColors.success : MjasiColors.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: amountColor.withValues(alpha: .10),
              child: Icon(
                isIncome ? Icons.south_west_rounded : Icons.north_east_rounded,
                color: amountColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data['description']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MjasiColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${data['category'] ?? ''} · ${date is Timestamp ? DateFormat(_dateFormat).format(date.toDate()) : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MjasiColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 112),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${isIncome ? '+' : '-'}${_formatAmount(amount)}',
                      style: TextStyle(
                        color: amountColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 32,
                  width: 36,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'delete'.tr,
                    onPressed: () =>
                        PersonalFinanceService.deleteTransaction(doc.id),
                    icon: const Icon(Icons.delete_outline, size: 19),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlans({required bool isGoal}) {
    final stream = isGoal
        ? PersonalFinanceService.watchGoals()
        : PersonalFinanceService.watchBudgets();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _MessageState(message: 'personal_load_error'.tr);
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return _MessageState(
            message: isGoal
                ? 'personal_empty_goals'.tr
                : 'personal_empty_budgets'.tr,
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: docs.map((doc) {
            final data = doc.data();
            final target =
                ((data['targetAmount'] ?? data['amount']) as num?)
                    ?.toDouble() ??
                0;
            final saved = (data['savedAmount'] as num?)?.toDouble() ?? 0;
            final progress = target <= 0
                ? 0.0
                : (saved / target).clamp(0.0, 1.0);
            return Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      isGoal
                          ? Icons.savings_outlined
                          : Icons.account_balance_wallet_outlined,
                      color: MjasiColors.primaryBlue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['name']?.toString() ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          if (isGoal) ...[
                            LinearProgressIndicator(value: progress),
                            const SizedBox(height: 4),
                          ],
                          Text(
                            isGoal
                                ? '${_formatAmount(saved)} / ${_formatAmount(target)}'
                                : '${'personal_budget_amount'.tr}: ${_formatAmount(target)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: MjasiColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isGoal)
                      IconButton(
                        tooltip: 'personal_update_savings'.tr,
                        onPressed: () => _showGoalProgressDialog(
                          id: doc.id,
                          targetAmount: target,
                          currentAmount: saved,
                        ),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    IconButton(
                      tooltip: 'delete'.tr,
                      onPressed: () => isGoal
                          ? PersonalFinanceService.deleteGoal(doc.id)
                          : PersonalFinanceService.deleteBudget(doc.id),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  String _formatAmount(double amount) =>
      '$_currency ${NumberFormat('#,##0.##').format(amount)}';
}

class _PersonalFormDialog extends StatelessWidget {
  const _PersonalFormDialog({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.saveLabel,
    required this.cancelLabel,
    required this.onCancel,
    required this.onSave,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final String saveLabel;
  final String cancelLabel;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final Widget child;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 460,
        maxHeight: MediaQuery.sizeOf(context).height * .84,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: MjasiColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: MjasiColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A10233F),
              blurRadius: 32,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(icon, color: accent, size: 23),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: MjasiColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: MjasiColors.textSecondary,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: onCancel,
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        backgroundColor: MjasiColors.background,
                        foregroundColor: MjasiColors.textSecondary,
                      ),
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: MjasiColors.border),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: child,
                ),
              ),
              const Divider(height: 1, color: MjasiColors.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: onCancel,
                      child: Text(cancelLabel),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: onSave,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(saveLabel),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PersonalMonthTotal {
  _PersonalMonthTotal(this.month);

  final String month;
  double income = 0;
  double expense = 0;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.amount,
    required this.currency,
    required this.color,
    this.prominent = false,
  });

  final String label;
  final double amount;
  final String currency;
  final Color color;
  final bool prominent;

  @override
  Widget build(BuildContext context) => Card(
    color: prominent ? MjasiColors.primaryNavy : MjasiColors.surface,
    child: Padding(
      padding: EdgeInsets.all(prominent ? 20 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: prominent ? Colors.white70 : MjasiColors.textSecondary,
              fontSize: prominent ? 13 : 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$currency ${NumberFormat('#,##0.##').format(amount)}',
              style: TextStyle(
                color: prominent ? Colors.white : color,
                fontSize: prominent ? 28 : 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -.4,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PersonalAdviceCard extends StatelessWidget {
  const _PersonalAdviceCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: MjasiColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: const TextStyle(
                    color: MjasiColors.textSecondary,
                    height: 1.4,
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

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}
