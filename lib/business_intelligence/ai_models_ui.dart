import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/ai_models.dart';

String isherProviderNickname(String provider, Map<String, String> nicknames) {
  final nickname = nicknames[provider]?.trim() ?? '';
  if (nickname.isNotEmpty) return nickname;
  final number = switch (provider) {
    'openai' => 1,
    'gemini' => 2,
    'claude' => 3,
    _ => 4,
  };
  return 'bi_models_generic_provider'.trParams({'number': '$number'});
}

String isherModelNickname(AiModelOption model, List<AiModelOption> models) {
  if (model.nickname.trim().isNotEmpty) return model.nickname.trim();
  final number = switch (model.id) {
    'gpt-4o-mini' => 1,
    'gpt-6-luna' => 2,
    'gemini-2.5-flash' => 1,
    'gemini-2.5-pro' => 2,
    'gemini-3.8-flash' => 3,
    'gemini-3.1-pro-preview' => 4,
    _ => models.where((item) => item.provider == model.provider)
            .toList()
            .indexWhere((item) => item.id == model.id) +
        5,
  };
  return 'bi_models_generic_version'.trParams({'number': '$number'});
}

class AiModelPickerButton extends StatelessWidget {
  const AiModelPickerButton({
    super.key,
    AiModelRepository? repository,
    this.onModelSelected,
  }) : _repository = repository;
  final AiModelRepository? _repository;
  final VoidCallback? onModelSelected;

  Future<void> _open(BuildContext context) async {
    final repository = _repository ?? AiModelRepository();
    AiModelCatalog catalog;
    var engines = const <String>[];
    try {
      catalog = await repository.available();
      try {
        engines = await repository.voiceProviders();
      } catch (error) {
        debugPrint('Voice engines load failed: $error');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('bi_models_voice_load_error'.tr)),
          );
        }
      }
      await AiVoiceEngineSelection.load();
    } catch (error) {
      debugPrint('AI models load failed: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('bi_models_load_error'.tr)));
      }
      return;
    }
    if (!context.mounted) return;
    if (catalog.models.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('bi_models_load_error'.tr)),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1D1A2B),
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: _PickerBody(
            models: catalog.models,
            providerNicknames: catalog.providerNicknames,
            engines: engines,
            onModelSelected: onModelSelected,
            onDone: () => Navigator.pop(sheet),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'bi_models_title'.tr,
    icon: const Icon(Icons.tune),
    onPressed: () => _open(context),
  );
}

class _PickerBody extends StatelessWidget {
  const _PickerBody({
    required this.models,
    required this.engines,
    required this.providerNicknames,
    this.onModelSelected,
    required this.onDone,
  });
  final List<AiModelOption> models;
  final List<String> engines;
  final Map<String, String> providerNicknames;
  final VoidCallback? onModelSelected;
  final VoidCallback onDone;

  static const _accent = Color(0xFFC7A9FF);

  @override
  Widget build(BuildContext context) {
    final providers = <String>[];
    for (final model in models) {
      if (!providers.contains(model.provider)) providers.add(model.provider);
    }
    return ValueListenableBuilder<String?>(
      valueListenable: AiModelSelection.selectedId,
      builder: (context, current, _) {
        final active = models.any((model) => model.id == current)
            ? current
            : defaultAiModelId(models);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heading('bi_models_title'.tr),
            for (final provider in providers) ...[
              _section(isherProviderNickname(provider, providerNicknames)),
              for (final model in models.where((m) => m.provider == provider))
                ListTile(
                  dense: true,
                  leading: Icon(
                    model.id == active
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: _accent,
                  ),
                  title: Text(
                    isherModelNickname(model, models),
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    'bi_models_cost'.trParams({
                      'price': '${model.messagePrice}',
                      'credits': '${model.creditCost}',
                    }),
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  onTap: () async {
                    await AiModelSelection.select(model.id);
                    onModelSelected?.call();
                    onDone();
                  },
                ),
            ],
            if (engines.length > 1)
              ValueListenableBuilder<String?>(
                valueListenable: AiVoiceEngineSelection.selected,
                builder: (context, engine, _) {
                  final activeEngine = engines.contains(engine)
                      ? engine
                      : defaultVoiceEngine(engines);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(color: Colors.white24),
                      _heading('bi_voice_engine'.tr),
                      for (final e in engines)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            e == activeEngine
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: _accent,
                          ),
                          title: Text(
                            isherProviderNickname(e, providerNicknames),
                            style: const TextStyle(color: Colors.white),
                          ),
                          onTap: () => AiVoiceEngineSelection.select(e),
                        ),
                    ],
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Text(
      text,
      style: const TextStyle(color: _accent, fontSize: 12, letterSpacing: 0.5),
    ),
  );
}
