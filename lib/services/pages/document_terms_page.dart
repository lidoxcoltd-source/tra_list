import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/document_terms_service.dart';
import 'package:tra_list/services/profile_service.dart';

class DocumentTermsPage extends StatefulWidget {
  const DocumentTermsPage({super.key});

  @override
  State<DocumentTermsPage> createState() => _DocumentTermsPageState();
}

class _DocumentTermsPageState extends State<DocumentTermsPage> {
  static const _brand = Color(0xFF0E5962);
  static const _ink = Color(0xFF19313A);
  static const _muted = Color(0xFF75838A);
  static const _canvas = Color(0xFFF5F7F8);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();
  final _deliveryController = TextEditingController();
  final _conditionsController = TextEditingController();

  final List<Map<String, dynamic>> _versions = [];
  final Map<String, String> _selectedVersions = {
    for (final type in DocumentTermsService.documentTypes.keys) type: '',
  };
  String _saveFor = 'invoice';
  String _editingVersionId = '';
  bool _loading = true;
  bool _saving = false;
  bool get _canEdit => BusinessAccessService.can('profile', 'edit');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    _deliveryController.dispose();
    _conditionsController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profile = await ProfileService.loadOrCreate();
      _versions
        ..clear()
        ..addAll(
          (profile['documentTermsVersions'] as List? ?? const [])
              .whereType<Map>()
              .map((version) => Map<String, dynamic>.from(version)),
        );
      _selectedVersions
        ..clear()
        ..addAll({
          for (final type in DocumentTermsService.documentTypes.keys)
            type:
                (profile['selectedDocumentTerms'] as Map?)?[type]?.toString() ??
                '',
        });

      if (_versions.isNotEmpty) {
        _editingVersionId = _versions.last['id']?.toString() ?? '';
        _setEditorVersion(_versions.last);
      } else {
        _setEditorVersion(DocumentTermsService.defaultVersion());
      }
    } catch (error) {
      if (mounted) {
        Get.snackbar('Error', 'Could not load document terms: $error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setEditorVersion(Map<String, dynamic> version) {
    _nameController.text = version['name']?.toString() ?? '';
    _noteController.text = version['note']?.toString() ?? '';
    _deliveryController.text = version['delivery']?.toString() ?? '';
    _conditionsController.text = version['conditions']?.toString() ?? '';
  }

  String _versionLabel(Map<String, dynamic> version) {
    final name = version['name']?.toString().trim() ?? '';
    final createdAt = DateTime.tryParse(version['createdAt']?.toString() ?? '');
    if (createdAt == null) return name;
    return '$name · ${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }

  Future<void> _saveVersion() async {
    if (!_canEdit || !_formKey.currentState!.validate()) return;
    final version = <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'name': _nameController.text.trim(),
      'note': _noteController.text.trim(),
      'delivery': _deliveryController.text.trim(),
      'conditions': _conditionsController.text.trim(),
      'createdAt': DateTime.now().toIso8601String(),
    };
    final versions = [..._versions, version];
    final selected = {..._selectedVersions, _saveFor: version['id'] as String};
    await _save(
      versions: versions,
      selectedVersions: selected,
      successMessage:
          'Version saved and selected for ${DocumentTermsService.documentTypes[_saveFor]}.',
    );
  }

  Future<void> _saveSelections() async {
    if (!_canEdit) return;
    await _save(
      versions: _versions,
      selectedVersions: _selectedVersions,
      successMessage: 'Document version choices saved.',
    );
  }

  Future<void> _save({
    required List<Map<String, dynamic>> versions,
    required Map<String, String> selectedVersions,
    required String successMessage,
  }) async {
    setState(() => _saving = true);
    try {
      await ProfileService.save({
        'documentTermsVersions': versions,
        'selectedDocumentTerms': selectedVersions,
      });
      if (!mounted) return;
      setState(() {
        _versions
          ..clear()
          ..addAll(versions);
        _selectedVersions
          ..clear()
          ..addAll(selectedVersions);
      });
      Get.snackbar('Saved', successMessage);
    } catch (error) {
      if (mounted) {
        Get.snackbar('Error', 'Could not save document terms: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _canvas,
        body: Center(child: CircularProgressIndicator(color: _brand)),
      );
    }

    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        title: const Text(
          'Document terms',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Manage the wording on your business documents.',
                  style: TextStyle(color: _muted, fontSize: 14),
                ),
                const SizedBox(height: 20),
                _buildSectionCard(
                  icon: Icons.tune_rounded,
                  title: 'Active versions',
                  subtitle: 'Choose which saved terms to use on each document.',
                  child: Column(
                    children: [
                      for (final entry
                          in DocumentTermsService.documentTypes.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: DropdownButtonFormField<String>(
                            initialValue:
                                _versions.any(
                                  (version) =>
                                      version['id']?.toString() ==
                                      _selectedVersions[entry.key],
                                )
                                ? _selectedVersions[entry.key]
                                : '',
                            decoration: _inputDecoration(
                              '${entry.value} terms',
                              prefixIcon: _documentIcon(entry.key),
                            ),
                            isExpanded: true,
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('Built-in default'),
                              ),
                              ..._versions.map(
                                (version) => DropdownMenuItem(
                                  value: version['id'].toString(),
                                  child: Text(
                                    _versionLabel(version),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: _canEdit
                                ? (value) {
                                    if (value == null) return;
                                    setState(
                                      () =>
                                          _selectedVersions[entry.key] = value,
                                    );
                                  }
                                : null,
                          ),
                        ),
                      if (_canEdit)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _saving ? null : _saveSelections,
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Save active choices'),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_canEdit) ...[
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    icon: Icons.edit_note_rounded,
                    title: 'Create a terms version',
                    subtitle:
                        'Start with a saved version or the built-in wording. '
                        'Saving creates a new version and keeps previous ones.',
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue:
                                _versions.any(
                                  (version) =>
                                      version['id']?.toString() ==
                                      _editingVersionId,
                                )
                                ? _editingVersionId
                                : '',
                            decoration: _inputDecoration(
                              'Start from a version',
                              prefixIcon: Icons.history_rounded,
                            ),
                            isExpanded: true,
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('Built-in default'),
                              ),
                              ..._versions.map(
                                (version) => DropdownMenuItem(
                                  value: version['id'].toString(),
                                  child: Text(
                                    _versionLabel(version),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              final version = value.isEmpty
                                  ? DocumentTermsService.defaultVersion()
                                  : _versions.firstWhere(
                                      (candidate) =>
                                          candidate['id']?.toString() == value,
                                    );
                              setState(() {
                                _editingVersionId = value;
                                _setEditorVersion(version);
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _nameController,
                            decoration: _inputDecoration(
                              'Version name',
                              hintText: 'e.g. Standard terms 2026',
                              prefixIcon: Icons.label_outline_rounded,
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Enter a version name'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _saveFor,
                            decoration: _inputDecoration(
                              'Use this version for',
                              prefixIcon: Icons.description_outlined,
                            ),
                            isExpanded: true,
                            items: [
                              for (final entry
                                  in DocumentTermsService.documentTypes.entries)
                                DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _saveFor = value);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          _textField(
                            controller: _noteController,
                            label: 'Payment or completion note',
                            hint: 'A short note shown on the document.',
                            prefixIcon: Icons.payments_outlined,
                          ),
                          const SizedBox(height: 12),
                          _textField(
                            controller: _deliveryController,
                            label: 'Delivery terms',
                            hint: 'For example, estimated delivery time.',
                            prefixIcon: Icons.local_shipping_outlined,
                          ),
                          const SizedBox(height: 12),
                          _textField(
                            controller: _conditionsController,
                            label: 'Terms and conditions',
                            hint: 'Add any other conditions for your customer.',
                            prefixIcon: Icons.gavel_outlined,
                            minLines: 4,
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: _brand,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _saving ? null : _saveVersion,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined, size: 18),
                              label: Text(
                                _saving ? 'Saving…' : 'Save new version',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (!_canEdit)
                  _buildSectionCard(
                    icon: Icons.lock_outline_rounded,
                    title: 'View only',
                    subtitle:
                        'You can view the active versions. Ask a business '
                        'owner or administrator to make changes.',
                    child: const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE8EDEF)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _brand.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: _brand),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (child is! SizedBox) ...[const SizedBox(height: 18), child],
      ],
    ),
  );

  IconData _documentIcon(String type) => switch (type) {
    'invoice' => Icons.receipt_long_outlined,
    'proforma' => Icons.request_quote_outlined,
    'quotation' => Icons.description_outlined,
    _ => Icons.payments_outlined,
  };

  InputDecoration _inputDecoration(
    String label, {
    String? hintText,
    required IconData prefixIcon,
  }) => InputDecoration(
    labelText: label,
    hintText: hintText,
    prefixIcon: Icon(prefixIcon, size: 19, color: _muted),
    filled: true,
    fillColor: const Color(0xFFFAFBFB),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE1E7E9)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE1E7E9)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _brand, width: 1.5),
    ),
  );

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData prefixIcon,
    int minLines = 2,
  }) => TextFormField(
    controller: controller,
    minLines: minLines,
    maxLines: null,
    decoration: _inputDecoration(label, hintText: hint, prefixIcon: prefixIcon),
  );
}
