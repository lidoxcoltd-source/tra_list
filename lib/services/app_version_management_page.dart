import 'package:flutter/material.dart';

import 'app_version_service.dart';

class AppVersionManagementPage extends StatefulWidget {
  const AppVersionManagementPage({super.key});

  @override
  State<AppVersionManagementPage> createState() =>
      _AppVersionManagementPageState();
}

class _AppVersionManagementPageState extends State<AppVersionManagementPage> {
  static const _platforms = [
    ('android', 'Android', Icons.android_rounded),
    ('windows', 'Windows', Icons.desktop_windows_rounded),
    ('web', 'Web', Icons.language_rounded),
  ];

  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  final Map<String, TextEditingController> _versionControllers = {};
  final Map<String, TextEditingController> _buildControllers = {};
  final Map<String, TextEditingController> _urlControllers = {};
  final Map<String, bool> _enabled = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final (key, _, _) in _platforms) {
      _versionControllers[key] = TextEditingController(text: '0.0.0');
      _buildControllers[key] = TextEditingController(text: '0');
      _urlControllers[key] = TextEditingController();
      _enabled[key] = false;
    }
    _messageController.text =
        'A new app version is required to continue. Please update to keep using MJASI POS.';
    _loadPolicy();
  }

  @override
  void dispose() {
    _messageController.dispose();
    for (final controller in [
      ..._versionControllers.values,
      ..._buildControllers.values,
      ..._urlControllers.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPolicy() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final policy = await AppVersionService.loadManagedPolicy();
      _messageController.text = policy.message;
      for (final (key, _, _) in _platforms) {
        final item = policy.forPlatform(key);
        _versionControllers[key]!.text = item.minimumVersion;
        _buildControllers[key]!.text = '${item.minimumBuild}';
        _urlControllers[key]!.text = item.updateUrl;
        _enabled[key] = item.enabled;
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (error, stackTrace) {
      debugPrint('Failed to load app version policy: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _savePolicy() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      PlatformVersionPolicy policyFor(String key) => PlatformVersionPolicy(
        enabled: _enabled[key] ?? false,
        minimumVersion: _versionControllers[key]!.text.trim(),
        minimumBuild: int.parse(_buildControllers[key]!.text.trim()),
        updateUrl: _urlControllers[key]!.text.trim(),
      );

      await AppVersionService.savePolicy(
        AppVersionPolicy(
          android: policyFor('android'),
          windows: policyFor('windows'),
          web: policyFor('web'),
          message: _messageController.text.trim(),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('App version policy saved.')),
      );
      setState(() => _saving = false);
    } catch (error, stackTrace) {
      debugPrint('Failed to save app version policy: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F8),
      appBar: AppBar(
        title: const Text('App version control'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadPolicy,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _introCard(),
                  const SizedBox(height: 16),
                  for (final platform in _platforms) ...[
                    _platformCard(platform.$1, platform.$2, platform.$3),
                    const SizedBox(height: 12),
                  ],
                  _messageCard(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFF9B3E35)),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _saving ? null : _savePolicy,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(_saving ? 'Saving…' : 'Save version policy'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _introCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Require users to update',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enable a platform and set its minimum version. Users below that version will be stopped at launch until they open the update link and install a compatible build. Super admins can still enter the app to correct a policy.',
          ),
        ],
      ),
    ),
  );

  Widget _platformCard(String key, String title, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF0E5962)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Switch(
                value: _enabled[key] ?? false,
                onChanged: (value) => setState(() => _enabled[key] = value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final versionField = _textField(
                controller: _versionControllers[key]!,
                label: 'Minimum version',
                hint: '1.2.3',
                validator: (value) {
                  if (!RegExp(r'^\d+(\.\d+){1,3}$').hasMatch(value ?? '')) {
                    return 'Use a numeric version like 1.2.3.';
                  }
                  return null;
                },
              );
              final buildField = _textField(
                controller: _buildControllers[key]!,
                label: 'Minimum build number',
                hint: '1',
                keyboardType: TextInputType.number,
                validator: (value) {
                  final build = int.tryParse(value ?? '');
                  return build == null || build < 0
                      ? 'Enter 0 or a higher number.'
                      : null;
                },
              );
              if (constraints.maxWidth < 560) {
                return Column(
                  children: [
                    versionField,
                    const SizedBox(height: 12),
                    buildField,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: versionField),
                  const SizedBox(width: 12),
                  Expanded(child: buildField),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _textField(
            controller: _urlControllers[key]!,
            label: 'HTTPS update URL',
            hint: 'https://…',
            keyboardType: TextInputType.url,
            validator: (value) {
              if (!(_enabled[key] ?? false)) return null;
              final uri = Uri.tryParse(value?.trim() ?? '');
              return uri == null || uri.scheme != 'https' || uri.host.isEmpty
                  ? 'Enter a valid HTTPS update link.'
                  : null;
            },
          ),
        ],
      ),
    ),
  );

  Widget _messageCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: _textField(
        controller: _messageController,
        label: 'Message shown to users',
        hint: 'Explain why the update is required',
        maxLines: 3,
        validator: (value) =>
            value == null || value.trim().isEmpty || value.length > 500
            ? 'Enter a message with 1 to 500 characters.'
            : null,
      ),
    ),
  );

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) => TextFormField(
    controller: controller,
    keyboardType: keyboardType,
    maxLines: maxLines,
    validator: validator,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
    ),
  );
}
