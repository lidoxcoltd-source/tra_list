import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:tra_list/services/analytics_advice_service.dart';
import 'package:tra_list/theme/app_theme.dart';

class AnalyticsAdviceAdminPage extends StatefulWidget {
  const AnalyticsAdviceAdminPage({super.key});

  @override
  State<AnalyticsAdviceAdminPage> createState() =>
      _AnalyticsAdviceAdminPageState();
}

class _AnalyticsAdviceAdminPageState extends State<AnalyticsAdviceAdminPage> {
  bool _loading = true;
  bool _authorized = false;
  String? _error;
  List<AnalyticsAdvice> _advice = [];
  Set<String> _builtInIds = {};
  String _search = '';
  String? _categoryFilter;
  bool _transferring = false;

  List<AnalyticsAdvice> get _visibleAdvice {
    final query = _search.trim().toLowerCase();
    return _advice.where((item) {
      if (_categoryFilter != null && item.category != _categoryFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      return item.id.toLowerCase().contains(query) ||
          item.title.values.any(
            (value) => value.toLowerCase().contains(query),
          ) ||
          item.description.values.any(
            (value) => value.toLowerCase().contains(query),
          );
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _authorized = false;
          _loading = false;
        });
        return;
      }
      final profile = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('profile')
          .doc('company')
          .get();
      final role = (profile.data()?['role']?.toString() ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (!mounted) return;
      if (role != 'superadmin') {
        setState(() {
          _authorized = false;
          _loading = false;
        });
        return;
      }
      final bundledJson = await rootBundle.loadString(
        'assets/analytics_advice.json',
      );
      final bundled = AnalyticsAdviceService.decodeJson(bundledJson);
      final custom = await AnalyticsAdviceService.loadAllForAdmin();
      final adviceById = {for (final item in bundled) item.id: item};
      for (final item in custom) {
        adviceById[item.id] = item;
      }
      if (!mounted) return;
      setState(() {
        _authorized = true;
        _builtInIds = bundled.map((item) => item.id).toSet();
        _advice = adviceById.values.toList()
          ..sort((first, second) {
            final firstTitle = first.title['en'] ?? first.id;
            final secondTitle = second.title['en'] ?? second.id;
            return firstTitle.compareTo(secondTitle);
          });
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Could not load analytics advice for admin: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _editAdvice([AnalyticsAdvice? current]) async {
    final advice = await showDialog<AnalyticsAdvice>(
      context: context,
      builder: (context) => _AdviceEditorDialog(initial: current),
    );
    if (advice == null) return;
    try {
      await AnalyticsAdviceService.save(advice);
      await _load();
      if (!mounted) return;
      Get.snackbar('success'.tr, 'analytics_advice_saved'.tr);
    } catch (error, stackTrace) {
      debugPrint('Could not save analytics advice: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      Get.snackbar(
        'error'.tr,
        'analytics_advice_save_error'.trParams({'error': error.toString()}),
      );
    }
  }

  Future<void> _deleteAdvice(AnalyticsAdvice advice) async {
    if (_builtInIds.contains(advice.id)) {
      Get.snackbar('error'.tr, 'analytics_advice_builtin_delete_hint'.tr);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('analytics_advice_delete_title'.tr),
        content: Text(
          'analytics_advice_delete_confirm'.trParams({
            'title':
                advice.title[Get.locale?.languageCode == 'sw' ? 'sw' : 'en'] ??
                advice.id,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: MjasiColors.error),
            child: Text('delete'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AnalyticsAdviceService.delete(advice.id);
      await _load();
      if (!mounted) return;
      Get.snackbar('success'.tr, 'analytics_advice_deleted'.tr);
    } catch (error, stackTrace) {
      debugPrint('Could not delete analytics advice: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      Get.snackbar(
        'error'.tr,
        'analytics_advice_delete_error'.trParams({'error': error.toString()}),
      );
    }
  }

  Future<void> _setAdviceEnabled(AnalyticsAdvice advice, bool enabled) async {
    try {
      await AnalyticsAdviceService.save(
        AnalyticsAdvice(
          id: advice.id,
          category: advice.category,
          title: advice.title,
          description: advice.description,
          conditions: advice.conditions,
          enabled: enabled,
        ),
      );
      await _load();
    } catch (error, stackTrace) {
      debugPrint('Could not update analytics advice state: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      Get.snackbar(
        'error'.tr,
        'analytics_advice_save_error'.trParams({'error': error.toString()}),
      );
    }
  }

  Future<void> _downloadJson() async {
    setState(() => _transferring = true);
    try {
      final content = AnalyticsAdviceService.encodeJson(_advice);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'analytics_advice_export'.tr,
        fileName: 'mjasipos_analytics_advice.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: utf8.encode(content),
      );
      if (path == null || !mounted) return;
      Get.snackbar(
        'success'.tr,
        'analytics_advice_exported'.trParams({'path': path}),
      );
    } catch (error, stackTrace) {
      debugPrint('Could not export analytics advice JSON: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      Get.snackbar(
        'error'.tr,
        'analytics_advice_export_error'.trParams({'error': error.toString()}),
      );
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  Future<void> _importJson() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      final file = result?.files.single;
      final bytes = file?.bytes;
      if (file == null || bytes == null) return;

      final incoming = AnalyticsAdviceService.decodeJson(utf8.decode(bytes));
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('analytics_advice_import_title'.tr),
          content: Text(
            'analytics_advice_import_confirm'.trParams({
              'count': '${incoming.length}',
            }),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('cancel'.tr),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.upload_file_rounded),
              label: Text('analytics_advice_import'.tr),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      setState(() => _transferring = true);
      await AnalyticsAdviceService.upsertAll(incoming);
      await _load();
      if (!mounted) return;
      Get.snackbar(
        'success'.tr,
        'analytics_advice_imported'.trParams({'count': '${incoming.length}'}),
      );
    } catch (error, stackTrace) {
      debugPrint('Could not import analytics advice JSON: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      Get.snackbar(
        'error'.tr,
        'analytics_advice_import_error'.trParams({'error': error.toString()}),
      );
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MjasiColors.background,
      appBar: AppBar(
        title: Text('analytics_advice_admin_title'.tr),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'analytics_advice_json_tools'.tr,
            enabled: !_loading && !_transferring,
            onSelected: (action) {
              if (action == 'import') _importJson();
              if (action == 'export') _downloadJson();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.file_upload_outlined),
                  title: Text('analytics_advice_import'.tr),
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.file_download_outlined),
                  title: Text('analytics_advice_export'.tr),
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: 'refresh'.tr,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: _authorized && !_loading
          ? FloatingActionButton.extended(
              onPressed: () => _editAdvice(),
              icon: const Icon(Icons.add_rounded),
              label: Text('analytics_advice_add'.tr),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_authorized
          ? Center(child: Text('staff_no_permission'.tr))
          : _transferring
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _errorView()
          : RefreshIndicator(
              onRefresh: _load,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 92),
                    children: [
                      _introCard(),
                      const SizedBox(height: 14),
                      _managementToolbar(),
                      const SizedBox(height: 14),
                      if (_advice.isEmpty)
                        _emptyView()
                      else if (_visibleAdvice.isEmpty)
                        _noSearchResults()
                      else
                        for (final item in _visibleAdvice) ...[
                          _adviceCard(item),
                          const SizedBox(height: 12),
                        ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _introCard() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [MjasiColors.primaryNavy, MjasiColors.primaryBlue],
      ),
      borderRadius: BorderRadius.circular(MjasiRadius.md),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.tips_and_updates_rounded,
          color: Colors.white,
          size: 32,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'analytics_advice_admin_title'.tr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'analytics_advice_admin_description'.tr,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _managementToolbar() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(MjasiRadius.md),
      border: Border.all(color: MjasiColors.border),
      boxShadow: [
        BoxShadow(
          color: MjasiColors.primaryNavy.withValues(alpha: .035),
          blurRadius: 16,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'analytics_advice_list_title'.tr,
                style: const TextStyle(
                  color: MjasiColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _countBadge(
              '${_visibleAdvice.length} / ${_advice.length}',
              MjasiColors.primaryBlue,
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final search = TextField(
              onChanged: (value) => setState(() => _search = value),
              decoration: InputDecoration(
                hintText: 'analytics_advice_search'.tr,
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                filled: true,
                fillColor: MjasiColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(MjasiRadius.sm),
                  borderSide: BorderSide.none,
                ),
              ),
            );
            final category = DropdownButtonFormField<String?>(
              initialValue: _categoryFilter,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'analytics_advice_category'.tr,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(MjasiRadius.sm),
                ),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('analytics_advice_all_categories'.tr),
                ),
                for (final value in AnalyticsAdviceService.categories)
                  DropdownMenuItem<String?>(
                    value: value,
                    child: Text('analytics_advice_category_$value'.tr),
                  ),
              ],
              onChanged: (value) => setState(() => _categoryFilter = value),
            );
            if (constraints.maxWidth < 560) {
              return Column(
                children: [search, const SizedBox(height: 10), category],
              );
            }
            return Row(
              children: [
                Expanded(flex: 3, child: search),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: category),
              ],
            );
          },
        ),
      ],
    ),
  );

  Widget _countBadge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
    ),
  );

  Widget _noSearchResults() => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      children: [
        Icon(Icons.search_off_rounded, size: 42, color: Colors.grey.shade400),
        const SizedBox(height: 10),
        Text(
          'analytics_advice_no_results'.tr,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700),
        ),
      ],
    ),
  );

  Widget _adviceCard(AnalyticsAdvice advice) {
    final language = Get.locale?.languageCode == 'sw' ? 'sw' : 'en';
    final categoryColor = _categoryColor(advice.category);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MjasiColors.border),
        boxShadow: [
          BoxShadow(
            color: MjasiColors.primaryNavy.withValues(alpha: .035),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.lightbulb_outline_rounded,
                  color: categoryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      advice.title[language] ?? advice.title['en'] ?? advice.id,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MjasiColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _countBadge(
                          'analytics_advice_category_${advice.category}'.tr,
                          categoryColor,
                        ),
                        if (_builtInIds.contains(advice.id))
                          _countBadge(
                            'analytics_advice_default'.tr,
                            Colors.blueGrey,
                          ),
                        if (advice.conditions.length > 1)
                          _countBadge(
                            'analytics_advice_conditions_count'.trParams({
                              'count': '${advice.conditions.length}',
                            }),
                            const Color(0xFF6D28D9),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: advice.enabled,
                onChanged: (enabled) => _setAdviceEnabled(advice, enabled),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            advice.description[language] ?? advice.description['en'] ?? '',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final condition in advice.conditions)
                _countBadge(
                  '${'analytics_advice_metric_${condition.metric}'.tr} '
                  '${'analytics_advice_operator_${condition.operator}'.tr} '
                  '${condition.value}',
                  const Color(0xFF334155),
                ),
              Text(
                advice.id,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _editAdvice(advice),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text('edit'.tr),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (!_builtInIds.contains(advice.id))
                IconButton(
                  tooltip: 'delete'.tr,
                  onPressed: () => _deleteAdvice(advice),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: MjasiColors.error,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.tips_and_updates_outlined, size: 48),
          const SizedBox(height: 12),
          Text('analytics_advice_empty'.tr, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _editAdvice(),
            icon: const Icon(Icons.add_rounded),
            label: Text('analytics_advice_add'.tr),
          ),
        ],
      ),
    ),
  );

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'analytics_advice_load_error'.trParams({'error': _error ?? ''}),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: Text('refresh'.tr),
          ),
        ],
      ),
    ),
  );

  Color _categoryColor(String category) => switch (category) {
    'costs' => MjasiColors.warning,
    'growth' => MjasiColors.success,
    'tasks' => const Color(0xFF7C3AED),
    'sales' => MjasiColors.primaryBlue,
    'staff' => const Color(0xFF0F766E),
    _ => Colors.blueGrey,
  };
}

class _AdviceEditorDialog extends StatefulWidget {
  const _AdviceEditorDialog({this.initial});

  final AnalyticsAdvice? initial;

  @override
  State<_AdviceEditorDialog> createState() => _AdviceEditorDialogState();
}

class _AdviceEditorDialogState extends State<_AdviceEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleEn;
  late final TextEditingController _titleSw;
  late final TextEditingController _descriptionEn;
  late final TextEditingController _descriptionSw;
  late final TextEditingController _threshold;
  late String _metric;
  late String _operator;
  late String _category;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _titleEn = TextEditingController(text: initial?.title['en'] ?? '');
    _titleSw = TextEditingController(text: initial?.title['sw'] ?? '');
    _descriptionEn = TextEditingController(
      text: initial?.description['en'] ?? '',
    );
    _descriptionSw = TextEditingController(
      text: initial?.description['sw'] ?? '',
    );
    final condition = initial?.conditions.firstOrNull;
    _metric = condition?.metric ?? 'income';
    _operator = condition?.operator ?? 'gt';
    _category = initial?.category ?? 'growth';
    _threshold = TextEditingController(
      text: condition?.value.toString() ?? '0',
    );
  }

  @override
  void dispose() {
    _titleEn.dispose();
    _titleSw.dispose();
    _descriptionEn.dispose();
    _descriptionSw.dispose();
    _threshold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      title: Text(
        widget.initial == null
            ? 'analytics_advice_add'.tr
            : 'analytics_advice_edit'.tr,
      ),
      content: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .68,
          ),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _localizedInput(
                    controller: _titleEn,
                    label: 'analytics_advice_title_en'.tr,
                    maxLength: 120,
                  ),
                  _localizedInput(
                    controller: _titleSw,
                    label: 'analytics_advice_title_sw'.tr,
                    maxLength: 120,
                  ),
                  _localizedInput(
                    controller: _descriptionEn,
                    label: 'analytics_advice_description_en'.tr,
                    maxLength: 500,
                    maxLines: 3,
                  ),
                  _localizedInput(
                    controller: _descriptionSw,
                    label: 'analytics_advice_description_sw'.tr,
                    maxLength: 500,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: InputDecoration(
                      labelText: 'analytics_advice_category'.tr,
                    ),
                    items: [
                      for (final category in AnalyticsAdviceService.categories)
                        DropdownMenuItem(
                          value: category,
                          child: Text('analytics_advice_category_$category'.tr),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _category = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _metric,
                    decoration: InputDecoration(
                      labelText: 'analytics_advice_metric'.tr,
                    ),
                    items: [
                      for (final metric
                          in AnalyticsAdviceService.metrics.toList()..sort())
                        DropdownMenuItem(
                          value: metric,
                          child: Text('analytics_advice_metric_$metric'.tr),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _metric = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: _operator,
                          decoration: InputDecoration(
                            labelText: 'analytics_advice_operator'.tr,
                          ),
                          items: [
                            for (final operator
                                in AnalyticsAdviceService.operators)
                              DropdownMenuItem(
                                value: operator,
                                child: Text(
                                  'analytics_advice_operator_$operator'.tr,
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _operator = value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _threshold,
                          decoration: InputDecoration(
                            labelText: 'analytics_advice_threshold'.tr,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          validator: (value) {
                            final number = double.tryParse(value ?? '');
                            return number == null || !number.isFinite
                                ? 'analytics_advice_threshold_invalid'.tr
                                : null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'analytics_advice_placeholder_help'.tr,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('cancel'.tr),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_rounded),
          label: Text('save'.tr),
        ),
      ],
    );
  }

  Widget _localizedInput({
    required TextEditingController controller,
    required String label,
    required int maxLength,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
      validator: (value) =>
          (value ?? '').trim().isEmpty ? 'analytics_advice_required'.tr : null,
    ),
  );

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final threshold = double.parse(_threshold.text.trim());
    final existing = widget.initial;
    final id =
        existing?.id ??
        'admin_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final advice = AnalyticsAdvice(
      id: id,
      category: _category,
      title: {'en': _titleEn.text.trim(), 'sw': _titleSw.text.trim()},
      description: {
        'en': _descriptionEn.text.trim(),
        'sw': _descriptionSw.text.trim(),
      },
      conditions: [
        AnalyticsAdviceCondition(
          metric: _metric,
          operator: _operator,
          value: threshold,
        ),
        ...?widget.initial?.conditions.skip(1),
      ],
      enabled: existing?.enabled ?? true,
    );
    Navigator.pop(context, advice);
  }
}
