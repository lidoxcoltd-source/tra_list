import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/invoice/add_transaction_controller.dart';
import 'package:tra_list/invoice/transaction_form.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/chat_service.dart';
import 'transaction_model.dart';

class AddTransactionPage extends StatefulWidget {
  final TransactionModel? transaction;
  final TransactionType? initialType;

  const AddTransactionPage({super.key, this.transaction, this.initialType});

  @override
  State<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends State<AddTransactionPage> {
  late final AddTransactionController controller;
  late final Stream<int>? _unreadCountStream;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Create a unique controller instance for this page.
    // It will be automatically disposed by GetX when the page is popped.
    controller = Get.put(
      AddTransactionController(
        transaction: widget.transaction,
        initialType: widget.initialType,
      ),
      // Use a unique tag to prevent conflicts if multiple forms are open.
      tag: 'transaction_form_${widget.transaction?.id ?? 'new'}',
    );
    _unreadCountStream = BusinessAccessService.hasBusinessAccess
        ? ChatService.watchUnreadMessageCount()
        : null;
  }

  void _useCalculatorResult(String value) {
    controller.amountC.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<void> _showCalculator() {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: _DesktopCalculator(onUseResult: _useCalculatorResult),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.transaction == null;
    const canvas = Color(0xFFF4F7F7);

    return Scaffold(
      backgroundColor: canvas,
      floatingActionButton: _unreadCountStream != null
          ? StreamBuilder<int>(
              stream: _unreadCountStream,
              builder: (context, snapshot) => Stack(
                clipBehavior: Clip.none,
                children: [
                  FloatingActionButton(
                    heroTag: 'transaction_chat_fab',
                    tooltip: snapshot.hasError
                        ? '${'chat_title'.tr}: ${snapshot.error}'
                        : 'chat_title'.tr,
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    onPressed: () => Get.toNamed(AppRoutes.chat),
                    child: const Icon(Icons.chat_bubble_outline_rounded),
                  ),
                  if (!snapshot.hasError && (snapshot.data ?? 0) > 0)
                    Positioned(
                      top: -5,
                      right: -5,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 21,
                          minHeight: 21,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE4484F),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: canvas, width: 2),
                        ),
                        child: Text(
                          snapshot.data! > 99 ? '99+' : '${snapshot.data}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  if (snapshot.hasError)
                    Positioned(
                      top: -5,
                      right: -5,
                      child: Container(
                        width: 21,
                        height: 21,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE4484F),
                          shape: BoxShape.circle,
                          border: Border.all(color: canvas, width: 2),
                        ),
                        child: const Icon(
                          Icons.priority_high_rounded,
                          color: Colors.white,
                          size: 13,
                        ),
                      ),
                    ),
                ],
              ),
            )
          : null,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 14),
        child: Obx(() {
          final expense = controller.isExpense.value;
          final base = expense
              ? const Color(0xFFB64D4D)
              : const Color(0xFF237A52);
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  base,
                  Color.lerp(base, const Color(0xFF0E2A33), 0.45)!,
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(24),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 16, 10),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: Colors.white,
                      onPressed: () => Navigator.of(context).canPop()
                          ? Get.back(result: false)
                          : Get.offAllNamed('/'),
                    ),
                    Expanded(
                      child: Text(
                        isNew
                            ? 'add_transaction_title'.tr
                            : 'edit_transaction_title'.tr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 19,
                        ),
                      ),
                    ),
                    Tooltip(
                      message: expense ? 'income'.tr : 'expense'.tr,
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            controller.isExpense.value = !expense;
                            controller.selectedCategory.value = '';
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Icon(
                              expense
                                  ? Icons.north_east_rounded
                                  : Icons.south_west_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, c) {
            final form = TransactionForm(
              controller: controller,
              isSaving: _isSaving,
              onSave: (saveAction) async {
                setState(() => _isSaving = true);
                try {
                  await saveAction();
                  if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();
                  Get.back(result: true);
                } finally {
                  if (mounted) setState(() => _isSaving = false);
                }
              },
              onCancel: () => Get.back(result: false),
            );
            if (c.maxWidth < 900) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _showCalculator,
                            icon: const Icon(Icons.calculate_outlined),
                            label: const Text('Calculator'),
                          ),
                        ),
                        Expanded(child: form),
                      ],
                    ),
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(40, 28, 40, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildPreviewPanel(),
                        const SizedBox(height: 16),
                        Expanded(
                          child: _DesktopCalculator(
                            onUseResult: _useCalculatorResult,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 32),
                  Expanded(
                    flex: 6,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: form,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPreviewPanel() {
    return AnimatedBuilder(
      animation: Listenable.merge([controller.amountC, controller.descC]),
      builder: (context, _) => Obx(() {
        final expense = controller.isExpense.value;
        final color = expense
            ? const Color(0xFFB64D4D)
            : const Color(0xFF237A52);
        final amount = controller.amountC.text.trim();
        final desc = controller.descC.text.trim();
        final category = controller.selectedCategory.value;
        final date = DateFormat(
          'EEE, d MMM yyyy',
        ).format(controller.selectedDate.value);
        Widget row(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: Colors.white70),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
        );
        return Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, Color.lerp(color, const Color(0xFF0E2A33), 0.5)!],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    expense
                        ? Icons.north_east_rounded
                        : Icons.south_west_rounded,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    (expense ? 'expense' : 'income').tr,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'TZS ${amount.isEmpty ? '0' : amount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Divider(color: Colors.white24),
              row(Icons.notes_rounded, desc.isEmpty ? '—' : desc),
              row(Icons.sell_outlined, category.isEmpty ? '—' : category),
              row(Icons.event_rounded, date),
            ],
          ),
        );
      }),
    );
  }
}

class _CalculatorHistoryEntry {
  const _CalculatorHistoryEntry({
    required this.expression,
    required this.result,
    required this.createdAt,
  });

  final String expression;
  final String result;
  final DateTime createdAt;

  Map<String, Object> toJson() => {
    'expression': expression,
    'result': result,
    'createdAt': createdAt.toIso8601String(),
  };

  factory _CalculatorHistoryEntry.fromJson(Map<String, dynamic> json) {
    return _CalculatorHistoryEntry(
      expression: json['expression']?.toString() ?? '',
      result: json['result']?.toString() ?? '0',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class _DesktopCalculator extends StatefulWidget {
  const _DesktopCalculator({required this.onUseResult});

  final ValueChanged<String> onUseResult;

  @override
  State<_DesktopCalculator> createState() => _DesktopCalculatorState();
}

class _DesktopCalculatorState extends State<_DesktopCalculator> {
  static const _historyLimit = 20;
  static const _panelColor = Color(0xFF202124);
  static const _keyColor = Color(0xFFE7E8EA);
  static const _keyTextColor = Color(0xFF25272A);
  static const _operatorColor = Color(0xFF3B3D40);

  late final String _historyKey =
      'transaction_calculator_history_${BusinessAccessService.businessId}';
  final List<_CalculatorHistoryEntry> _history = [];
  String _display = '0';
  double? _leftOperand;
  String? _pendingOperator;
  bool _startNewEntry = true;
  bool _loadingHistory = true;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedHistory = preferences.getStringList(_historyKey) ?? [];
      final entries = <_CalculatorHistoryEntry>[];
      for (final item in savedHistory) {
        try {
          final decoded = jsonDecode(item);
          if (decoded is Map<String, dynamic>) {
            entries.add(_CalculatorHistoryEntry.fromJson(decoded));
          }
        } on FormatException catch (error) {
          debugPrint('Ignoring invalid calculator history entry: $error');
        }
      }
      if (!mounted) return;
      setState(() {
        _history
          ..clear()
          ..addAll(entries.take(_historyLimit));
        _loadingHistory = false;
        _historyError = null;
      });
    } catch (error, stackTrace) {
      debugPrint('Could not load calculator history: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _loadingHistory = false;
        _historyError = 'History could not be loaded on this device.';
      });
    }
  }

  Future<void> _saveHistory() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList(
        _historyKey,
        _history.map((entry) => jsonEncode(entry.toJson())).toList(),
      );
      if (mounted && _historyError != null) {
        setState(() => _historyError = null);
      }
    } catch (error, stackTrace) {
      debugPrint('Could not save calculator history: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _historyError = 'History could not be saved.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save calculator history.')),
      );
    }
  }

  void _inputDigit(String digit) {
    setState(() {
      if (_startNewEntry || _display == '0' || _display == 'Error') {
        _display = digit;
        _startNewEntry = false;
      } else if (_display.replaceAll(RegExp(r'[^0-9]'), '').length < 14) {
        _display += digit;
      }
    });
  }

  void _inputDecimal() {
    setState(() {
      if (_startNewEntry || _display == 'Error') {
        _display = '0.';
        _startNewEntry = false;
      } else if (!_display.contains('.')) {
        _display += '.';
      }
    });
  }

  void _setOperator(String operator) {
    final current = double.tryParse(_display);
    if (current == null) return;
    setState(() {
      if (_leftOperand != null && _pendingOperator != null && !_startNewEntry) {
        final result = _calculate(_leftOperand!, current, _pendingOperator!);
        if (result == null) {
          _setError();
          return;
        }
        _display = _formatNumber(result);
      }
      _leftOperand = double.tryParse(_display);
      _pendingOperator = operator;
      _startNewEntry = true;
    });
  }

  Future<void> _calculateResult() async {
    final left = _leftOperand;
    final right = double.tryParse(_display);
    final operator = _pendingOperator;
    if (left == null || right == null || operator == null) return;
    final result = _calculate(left, right, operator);
    if (result == null || !result.isFinite) {
      setState(_setError);
      return;
    }
    final resultText = _formatNumber(result);
    final entry = _CalculatorHistoryEntry(
      expression:
          '${_formatThousands(_formatNumber(left))} ${_operatorLabel(operator)} ${_formatThousands(_formatNumber(right))}',
      result: resultText,
      createdAt: DateTime.now(),
    );
    setState(() {
      _history.insert(0, entry);
      if (_history.length > _historyLimit) {
        _history.removeRange(_historyLimit, _history.length);
      }
      _display = resultText;
      _leftOperand = null;
      _pendingOperator = null;
      _startNewEntry = true;
    });
    await _saveHistory();
  }

  double? _calculate(double left, double right, String operator) {
    switch (operator) {
      case '+':
        return left + right;
      case '−':
        return left - right;
      case '×':
        return left * right;
      case '÷':
        return right == 0 ? null : left / right;
      default:
        return null;
    }
  }

  void _toggleSign() {
    final value = double.tryParse(_display);
    if (value == null || value == 0) return;
    setState(() {
      _display = _formatNumber(-value);
      _startNewEntry = false;
    });
  }

  void _applyPercent() {
    final value = double.tryParse(_display);
    if (value == null) return;
    setState(() {
      _display = _formatNumber(value / 100);
      _startNewEntry = true;
    });
  }

  void _backspace() {
    if (_startNewEntry || _display == 'Error') {
      _clear();
      return;
    }
    setState(() {
      _display = _display.length <= 1
          ? '0'
          : _display.substring(0, _display.length - 1);
      if (_display == '-') _display = '0';
    });
  }

  void _clear() {
    setState(() {
      _display = '0';
      _leftOperand = null;
      _pendingOperator = null;
      _startNewEntry = true;
    });
  }

  void _setError() {
    _display = 'Error';
    _leftOperand = null;
    _pendingOperator = null;
    _startNewEntry = true;
  }

  Future<void> _clearHistory() async {
    setState(_history.clear);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_historyKey);
      if (mounted) setState(() => _historyError = null);
    } catch (error, stackTrace) {
      debugPrint('Could not clear calculator history: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _historyError = 'History could not be cleared.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not clear calculator history.')),
      );
    }
  }

  static String _formatNumber(double value) {
    if (!value.isFinite) return 'Error';
    if (value == 0) return '0';
    return value
        .toStringAsFixed(8)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String _formatThousands(String value) {
    if (value == 'Error') return value;
    final parts = value.split('.');
    final integer = parts.first;
    final isNegative = integer.startsWith('-');
    final digits = isNegative ? integer.substring(1) : integer;
    final grouped = StringBuffer(isNegative ? '-' : '');
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        grouped.write(',');
      }
      grouped.write(digits[index]);
    }
    if (parts.length > 1) grouped.write('.${parts[1]}');
    return grouped.toString();
  }

  static String _operatorLabel(String operator) => operator;

  Widget _key({
    required String label,
    required VoidCallback onPressed,
    Color color = _keyColor,
    Color foreground = _keyTextColor,
    bool emphasized = false,
  }) {
    return SizedBox(
      height: 44,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: foreground,
          padding: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
            side: BorderSide(
              color: emphasized ? Colors.black26 : Colors.black12,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: emphasized ? 18 : 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD4D6D8)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.calculate_outlined, color: _keyTextColor, size: 18),
                SizedBox(width: 8),
                Text(
                  'Calculator',
                  style: TextStyle(
                    color: _keyTextColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Spacer(),
                Text(
                  'HISTORY SAVED',
                  style: TextStyle(
                    color: Color(0xFF73767A),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .7,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _panelColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    height: 13,
                    child: Text(
                      _pendingOperator == null
                          ? ''
                          : '${_formatThousands(_formatNumber(_leftOperand ?? 0))} ${_operatorLabel(_pendingOperator!)}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(height: 1),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Text(
                      _formatThousands(_display),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: _key(
                    label: 'AC',
                    onPressed: _clear,
                    color: const Color(0xFFD9DBDE),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _key(
                    label: '⌫',
                    onPressed: _backspace,
                    color: const Color(0xFFD9DBDE),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _key(
                    label: '%',
                    onPressed: _applyPercent,
                    color: const Color(0xFFD9DBDE),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _key(
                    label: '÷',
                    onPressed: () => _setOperator('÷'),
                    color: _operatorColor,
                    foreground: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final row in [
              [
                ('7', () => _inputDigit('7')),
                ('8', () => _inputDigit('8')),
                ('9', () => _inputDigit('9')),
                ('×', () => _setOperator('×')),
              ],
              [
                ('4', () => _inputDigit('4')),
                ('5', () => _inputDigit('5')),
                ('6', () => _inputDigit('6')),
                ('−', () => _setOperator('−')),
              ],
              [
                ('1', () => _inputDigit('1')),
                ('2', () => _inputDigit('2')),
                ('3', () => _inputDigit('3')),
                ('+', () => _setOperator('+')),
              ],
            ]) ...[
              Row(
                children: [
                  for (var index = 0; index < row.length; index++) ...[
                    if (index > 0) const SizedBox(width: 4),
                    Expanded(
                      child: _key(
                        label: row[index].$1,
                        onPressed: row[index].$2,
                        color: index == 3 ? _operatorColor : _keyColor,
                        foreground: index == 3 ? Colors.white : _keyTextColor,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
            ],
            Row(
              children: [
                Expanded(
                  child: _key(
                    label: '±',
                    onPressed: _toggleSign,
                    color: const Color(0xFFD9DBDE),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: 2,
                  child: _key(label: '0', onPressed: () => _inputDigit('0')),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _key(label: '.', onPressed: _inputDecimal),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _key(
                    label: '=',
                    onPressed: _calculateResult,
                    color: const Color(0xFF171819),
                    foreground: Colors.white,
                    emphasized: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Recent calculations',
                    style: TextStyle(
                      color: _keyTextColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_history.isNotEmpty)
                  TextButton(
                    onPressed: _clearHistory,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF5F6368),
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      minimumSize: const Size(40, 26),
                      textStyle: const TextStyle(fontSize: 10),
                    ),
                    child: const Text('Clear'),
                  ),
              ],
            ),
            Container(
              constraints: const BoxConstraints(maxHeight: 64),
              decoration: BoxDecoration(
                color: const Color(0xFFE4E5E7),
                borderRadius: BorderRadius.circular(9),
              ),
              child: _loadingHistory
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : _history.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _historyError ?? 'Your calculations will appear here.',
                        style: TextStyle(
                          color: _historyError == null
                              ? const Color(0xFF777A7E)
                              : const Color(0xFF9A3E3E),
                          fontSize: 11,
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _history.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: Color(0xFFD1D3D5)),
                      itemBuilder: (context, index) {
                        final entry = _history[index];
                        return InkWell(
                          onTap: () => widget.onUseResult(
                            _formatThousands(entry.result),
                          ),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.expression,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF686B6F),
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatThousands(entry.result),
                                  style: const TextStyle(
                                    color: _keyTextColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                const Icon(
                                  Icons.north_west_rounded,
                                  size: 12,
                                  color: Color(0xFF777A7E),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
