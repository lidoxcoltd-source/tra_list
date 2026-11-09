import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class AiTransactionRequest {
  const AiTransactionRequest(this.type, this.amount);
  final String type;
  final int amount;
}

AiTransactionRequest? pendingAiTransaction(List<Map<String, String>> messages) {
  if (messages.length < 2) return null;
  final question = messages[messages.length - 2];
  final response = messages.last;
  const prompts = {
    'Tafadhali tuma kundi na maelezo kwa muundo: kundi: Kodi; maelezo: Kodi ya duka. Tumia kundi lililopo; tarehe itakuwa leo.',
    'Please send the category and description in this format: category: Rent; description: Shop rent. Use an existing category; the date will be today.',
  };
  if (question['role'] != 'user' ||
      response['role'] != 'assistant' ||
      !prompts.contains(response['content'])) {
    return null;
  }
  final match = RegExp(
    r'^(?:record|rekodi|sajili|hifadhi|andika)\s+(?:ya\s+)?(matumizi|mapato|expense|income)\s+(?:ya\s+)?(?:tsh\s*|tzs\s*)?(\d{1,3}(?:,\d{3})+|\d+)\s*$',
    caseSensitive: false,
  ).firstMatch(question['content']?.trim() ?? '');
  if (match == null) return null;
  final amount = int.tryParse(match[2]!.replaceAll(',', ''));
  if (amount == null || amount <= 0 || amount > 9007199254740991) return null;
  final type = match[1]!.toLowerCase();
  return AiTransactionRequest(
    type == 'matumizi' || type == 'expense' ? 'expense' : 'income',
    amount,
  );
}

class AiTransactionSuggestions extends StatefulWidget {
  const AiTransactionSuggestions({
    super.key,
    required this.request,
    required this.loadCategories,
    required this.onSubmit,
    required this.enabled,
  });
  final AiTransactionRequest request;
  final Future<List<String>> Function(String type) loadCategories;
  final void Function(String command) onSubmit;
  final bool enabled;

  @override
  State<AiTransactionSuggestions> createState() =>
      _AiTransactionSuggestionsState();
}

class _AiTransactionSuggestionsState extends State<AiTransactionSuggestions> {
  final _description = TextEditingController();
  late Future<List<String>> _categories;
  String? _selected;
  String? _validationError;
  Timer? _clock;
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    _load();
    _scheduleMidnight();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        _scheduleMidnight();
        setState(() {});
      }
    });
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(nextDay.difference(now), () {
      if (!mounted) return;
      _scheduleMidnight();
      setState(() {});
    });
  }

  void _load() {
    _categories = widget.loadCategories(widget.request.type);
  }

  @override
  void dispose() {
    _description.dispose();
    _clock?.cancel();
    _midnight?.cancel();
    super.dispose();
  }

  void _submit() {
    final description = _description.text.trim();
    if (_selected == null ||
        description.isEmpty ||
        description.length > 300 ||
        description.contains(';') ||
        description.contains('\n') ||
        description.contains('\r')) {
      setState(() => _validationError = 'bi_transaction_suggestion_invalid'.tr);
      return;
    }
    widget.onSubmit('kundi: $_selected; maelezo: $description');
  }

  Future<void> _chooseCategory(List<String> categories) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) =>
          _CategoryPicker(categories: categories, selected: _selected),
    );
    if (!mounted || !widget.enabled || selected == null) return;
    setState(() {
      _selected = selected;
      _validationError = null;
    });
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Card(
        color: const Color(0xFF25213D),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'bi_transaction_suggestion_amount'.trParams({
                  'type':
                      (widget.request.type == 'expense' ? 'expense' : 'income')
                          .tr,
                  'amount': NumberFormat.decimalPattern().format(
                    widget.request.amount,
                  ),
                }),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'bi_transaction_suggestion_date'.trParams({
                  'date': DateFormat.yMMMd().format(DateTime.now()),
                }),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<String>>(
                future: _categories,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'bi_transaction_suggestion_load_error'.tr,
                          style: const TextStyle(color: Colors.white),
                        ),
                        TextButton(
                          onPressed: () => setState(_load),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFDACFFF),
                          ),
                          child: Text('refresh'.tr),
                        ),
                      ],
                    );
                  }
                  if (!snapshot.hasData) return const LinearProgressIndicator();
                  if (snapshot.data!.isEmpty) {
                    return Text(
                      'bi_transaction_suggestion_empty'.tr,
                      style: const TextStyle(color: Colors.white70),
                    );
                  }
                  return SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF0EAFE),
                        disabledForegroundColor: Colors.white54,
                        side: const BorderSide(color: Color(0xFF81739F)),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: widget.enabled
                          ? () => _chooseCategory(snapshot.data!)
                          : null,
                      icon: const Icon(Icons.category_outlined),
                      label: Text(
                        _selected ?? 'bi_transaction_suggestion_choose'.tr,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  );
                },
              ),
              if (_selected != null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFDACFFF),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: widget.enabled
                      ? () {
                          _description.text = _selected!;
                          setState(() => _validationError = null);
                        }
                      : null,
                  icon: const Icon(Icons.edit_note),
                  label: Text('bi_transaction_suggestion_use_category'.tr),
                ),
              TextField(
                controller: _description,
                enabled: widget.enabled,
                maxLength: 300,
                maxLines: 1,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF19162C),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  labelText: 'bi_transaction_suggestion_description'.tr,
                  labelStyle: const TextStyle(color: Colors.white70),
                  errorText: _validationError,
                  errorStyle: const TextStyle(color: Color(0xFFFFB4AB)),
                  counterStyle: const TextStyle(color: Colors.white70),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF81739F)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(
                      color: Color(0xFFDACFFF),
                      width: 1.5,
                    ),
                  ),
                  disabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white38),
                  ),
                ),
              ),
              FilledButton(
                onPressed: widget.enabled && _selected != null ? _submit : null,
                child: Text('bi_transaction_suggestion_save'.tr),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CategoryPicker extends StatefulWidget {
  const _CategoryPicker({required this.categories, required this.selected});

  final List<String> categories;
  final String? selected;

  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final matching = widget.categories
        .where((name) => name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    final theme = Theme.of(context);
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: 368),
      title: Text('bi_transaction_suggestion_choose'.tr),
      content: SizedBox(
        width: 320,
        height: math.min(220, math.max(80, availableHeight - 210)),
        child: Column(
          children: [
            TextField(
              autofocus: false,
              style: TextStyle(color: theme.colorScheme.onSurface),
              cursorColor: theme.colorScheme.primary,
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: 'bi_transaction_suggestion_search'.tr,
                filled: true,
                fillColor: theme.colorScheme.surface,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: matching.isEmpty
                  ? Center(child: Text('bi_transaction_suggestion_no_match'.tr))
                  : ListView.builder(
                      itemCount: matching.length,
                      itemBuilder: (context, index) {
                        final category = matching[index];
                        return ListTile(
                          title: Text(category),
                          trailing: category == widget.selected
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => Navigator.pop(context, category),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('cancel'.tr),
        ),
      ],
    );
  }
}
