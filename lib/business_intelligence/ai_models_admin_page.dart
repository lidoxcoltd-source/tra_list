import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/ai_models.dart';

class AiModelsAdminPage extends StatefulWidget {
  const AiModelsAdminPage({super.key});

  @override
  State<AiModelsAdminPage> createState() => _AiModelsAdminPageState();
}

class _AiModelsAdminPageState extends State<AiModelsAdminPage> {
  final _repository = AiModelRepository();
  final _price = <String, TextEditingController>{};
  final _credits = <String, TextEditingController>{};
  final _nicknames = <String, TextEditingController>{};
  final _providerNicknames = <String, TextEditingController>{
    'openai': TextEditingController(),
    'gemini': TextEditingController(),
    'claude': TextEditingController(),
  };
  final _enabled = <String, bool>{};
  List<AiModelOption> _models = const [];
  bool _loading = true;
  String? _error;

  String _greetingProvider = 'openai';
  Set<String> _voiceProviders = {'openai'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      ..._price.values,
      ..._credits.values,
      ..._nicknames.values,
      ..._providerNicknames.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await _repository.adminModels();
      final voice = await _repository.voiceSettings();
      if (!mounted) return;
      _greetingProvider = voice.greeting;
      _voiceProviders = voice.voice.toSet();
      for (final entry in _providerNicknames.entries) {
        entry.value.text = catalog.providerNicknames[entry.key] ?? '';
      }
      for (final m in catalog.models) {
        (_price[m.id] ??= TextEditingController()).text = '${m.messagePrice}';
        (_credits[m.id] ??= TextEditingController()).text = '${m.creditCost}';
        (_nicknames[m.id] ??= TextEditingController()).text = m.nickname;
        _enabled[m.id] = m.enabled;
      }
      setState(() => _models = catalog.models);
    } catch (error) {
      debugPrint('AI models admin load failed: $error');
      if (mounted) setState(() => _error = 'bi_models_load_error'.tr);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final updated = <AiModelOption>[];
    for (final m in _models) {
      final price = int.tryParse(_price[m.id]!.text.trim());
      final credits = int.tryParse(_credits[m.id]!.text.trim());
      if (price == null || price < 0 || price > 100000000 ||
          credits == null || credits < 1 || credits > 100) {
        _notice('bi_quota_invalid'.tr);
        return;
      }
      updated.add(
        AiModelOption(
          id: m.id,
          label: m.label,
          provider: m.provider,
          nickname: _nicknames[m.id]!.text.trim(),
          enabled: _enabled[m.id] ?? m.enabled,
          messagePrice: price,
          creditCost: credits,
        ),
      );
    }
    if (!updated.any((m) => m.enabled)) {
      _notice('bi_models_one_enabled'.tr);
      return;
    }
    setState(() => _loading = true);
    try {
      await _repository.save(updated, {
        for (final entry in _providerNicknames.entries)
          entry.key: entry.value.text.trim(),
      });
      await _repository.saveVoiceSettings(
        _greetingProvider,
        _voiceProviders.toList(),
      );
      if (mounted) _notice('bi_quota_saved'.tr);
    } catch (error) {
      debugPrint('AI models save failed: $error');
      if (mounted) _notice('bi_quota_save_error'.tr);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _notice(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('bi_models_admin_title'.tr)),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(child: Text(_error!))
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'bi_models_greeting_provider'.tr,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'openai', label: Text('OpenAI')),
                  ButtonSegment(value: 'gemini', label: Text('Gemini')),
                ],
                selected: {_greetingProvider},
                onSelectionChanged: (value) =>
                    setState(() => _greetingProvider = value.first),
              ),
              const SizedBox(height: 16),
              Text(
                'bi_models_voice_providers'.tr,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final entry in const {
                'openai': 'OpenAI',
                'gemini': 'Gemini',
              }.entries)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value),
                  value: _voiceProviders.contains(entry.key),
                  onChanged: (on) => setState(() {
                    if (on == true) {
                      _voiceProviders.add(entry.key);
                    } else if (_voiceProviders.length > 1) {
                      _voiceProviders.remove(entry.key);
                    }
                  }),
                ),
              const Divider(height: 32),
              Text(
                'bi_models_provider_nicknames'.tr,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final entry in const {
                'openai': 'OpenAI',
                'gemini': 'Google Gemini',
                'claude': 'Anthropic Claude',
              }.entries) ...[
                TextField(
                  controller: _providerNicknames[entry.key],
                  maxLength: 40,
                  decoration: InputDecoration(
                    labelText: 'bi_models_nickname_for'.trParams({'name': entry.value}),
                    hintText: 'bi_models_nickname_hint'.tr,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const Divider(height: 32),
              for (final m in _models) ...[
                Text(m.label, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _nicknames[m.id],
                  maxLength: 40,
                  decoration: InputDecoration(
                    labelText: 'bi_models_version_nickname'.tr,
                    hintText: 'bi_models_nickname_hint'.tr,
                    border: const OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('bi_models_enabled'.tr),
                  value: _enabled[m.id] ?? m.enabled,
                  onChanged: (value) => setState(() => _enabled[m.id] = value),
                ),
                TextField(
                  controller: _price[m.id],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'bi_models_price'.tr,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _credits[m.id],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'bi_models_credits'.tr,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const Divider(height: 32),
              ],
              FilledButton(onPressed: _save, child: Text('bi_quota_save'.tr)),
            ],
          ),
  );
}
