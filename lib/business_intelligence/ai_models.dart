import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const defaultGeminiChatModel = 'gemini-3.8-flash';

String defaultAiModelId(List<AiModelOption> models) {
  if (models.isEmpty) throw StateError('No AI models available');
  for (final model in models) {
    if (model.id == defaultGeminiChatModel && model.enabled) return model.id;
  }
  for (final model in models) {
    if (model.provider == 'gemini' && model.enabled) return model.id;
  }
  return models.firstWhere((model) => model.enabled).id;
}

String defaultVoiceEngine(List<String> engines) {
  if (engines.isEmpty) throw StateError('No voice providers available');
  return engines.contains('gemini') ? 'gemini' : engines.first;
}

class AiModelOption {
  const AiModelOption({
    required this.id,
    required this.label,
    required this.enabled,
    required this.messagePrice,
    required this.creditCost,
    this.provider = 'openai',
    this.nickname = '',
  });

  factory AiModelOption.fromMap(Map<dynamic, dynamic> map) => AiModelOption(
    id: map['id'] as String,
    label: map['label'] as String,
    enabled: map['enabled'] as bool,
    messagePrice: (map['messagePrice'] as num).toInt(),
    creditCost: (map['creditCost'] as num).toInt(),
    provider: map['provider'] as String? ?? 'openai',
    nickname: map['nickname'] as String? ?? '',
  );

  final String provider;
  final String id;
  final String label;
  final String nickname;
  final bool enabled;
  final int messagePrice;
  final int creditCost;

  Map<String, dynamic> toMap() => {
    'id': id,
    'label': label,
    'nickname': nickname,
    'enabled': enabled,
    'messagePrice': messagePrice,
    'creditCost': creditCost,
  };
}

class AiModelCatalog {
  const AiModelCatalog({required this.models, required this.providerNicknames});
  final List<AiModelOption> models;
  final Map<String, String> providerNicknames;
}

/// The user's chosen chat model. The server validates it on every request.
class AiModelSelection {
  static const _key = 'isher_ai_model';
  static final ValueNotifier<String?> selectedId = ValueNotifier<String?>(null);
  static Future<void>? _loadFuture;

  static Future<void> load() => _loadFuture ??= _load();

  static Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      selectedId.value = prefs.getString(_key);
    } catch (error) {
      debugPrint('AI model selection load failed: $error');
    }
  }

  static Future<void> select(String id) async {
    await load();
    selectedId.value = id;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, id);
    } catch (error) {
      debugPrint('AI model selection save failed: $error');
    }
  }
}

/// The user's chosen live-voice engine, shared by the picker and voice page.
class AiVoiceEngineSelection {
  static const _key = 'isher_voice_engine';
  static final ValueNotifier<String?> selected = ValueNotifier<String?>(null);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      selected.value = prefs.getString(_key);
    } catch (error) {
      debugPrint('Voice engine load failed: $error');
    }
  }

  static Future<void> select(String engine) async {
    selected.value = engine;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, engine);
    } catch (error) {
      debugPrint('Voice engine save failed: $error');
    }
  }
}

class AiModelRepository {
  AiModelRepository({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;
  final FirebaseFunctions _functions;

  Future<AiModelCatalog> _call(String name, [Object? data]) async {
    final result = await _functions.httpsCallable(name).call(data);
    final map = Map<String, dynamic>.from(result.data as Map);
    final names = map['providerNicknames'];
    return AiModelCatalog(
      models: (map['models'] as List)
          .map((item) => AiModelOption.fromMap(item as Map))
          .toList(),
      providerNicknames: names == null
          ? const {}
          : Map<String, String>.from(names as Map),
    );
  }

  Future<AiModelCatalog> available() => _call('getBusinessAiModels');

  Future<({String greeting, List<String> voice})> voiceSettings() async {
    final result = await _functions
        .httpsCallable('getBusinessAiAdminVoice')
        .call();
    final map = Map<String, dynamic>.from(result.data as Map);
    return (
      greeting: map['greetingProvider'] as String,
      voice: List<String>.from(map['voiceProviders'] as List),
    );
  }

  Future<void> saveVoiceSettings(String greeting, List<String> voice) =>
      _functions.httpsCallable('saveBusinessAiAdminVoice').call({
        'greetingProvider': greeting,
        'voiceProviders': voice,
      });

  Future<List<String>> voiceProviders() async {
    final result = await _functions
        .httpsCallable('getBusinessAiVoiceProviders')
        .call();
    final map = Map<String, dynamic>.from(result.data as Map);
    return List<String>.from(map['providers'] as List);
  }

  Future<AiModelCatalog> adminModels() =>
      _call('getBusinessAiAdminModels');
  Future<AiModelCatalog> save(
    List<AiModelOption> models,
    Map<String, String> providerNicknames,
  ) => _call(
    'saveBusinessAiAdminModels',
    {
      'models': models.map((model) => model.toMap()).toList(),
      'providerNicknames': providerNicknames,
    },
  );
}
