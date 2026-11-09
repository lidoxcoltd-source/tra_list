import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tra_list/business_intelligence/ai_models.dart';

AiModelOption model(String id, String provider, {bool enabled = true}) =>
    AiModelOption(
      id: id,
      provider: provider,
      label: id,
      enabled: enabled,
      messagePrice: 0,
      creditCost: 1,
    );

void main() {
  test('saved chat choice is loaded before a new selection', () async {
    SharedPreferences.setMockInitialValues({'isher_ai_model': 'gpt-4o-mini'});
    await AiModelSelection.load();
    expect(AiModelSelection.selectedId.value, 'gpt-4o-mini');
    await AiModelSelection.select('gemini-3.8-flash');
    await AiModelSelection.load();
    expect(AiModelSelection.selectedId.value, 'gemini-3.8-flash');
  });

  test('chat defaults to enabled Gemini Flash regardless of list order', () {
    expect(
      defaultAiModelId([
        model('gpt-4o-mini', 'openai'),
        model('gemini-3.1-pro-preview', 'gemini'),
        model('gemini-3.8-flash', 'gemini'),
      ]),
      'gemini-3.8-flash',
    );
  });

  test('chat defaults to another enabled model if Gemini is disabled', () {
    expect(
      defaultAiModelId([
        model('gpt-4o-mini', 'openai'),
        model('gemini-3.8-flash', 'gemini', enabled: false),
        model('gemini-3.1-pro-preview', 'gemini'),
      ]),
      'gemini-3.1-pro-preview',
    );
    expect(defaultAiModelId([model('gpt-4o-mini', 'openai')]), 'gpt-4o-mini');
    expect(() => defaultAiModelId([]), throwsStateError);
  });

  test('voice defaults to Gemini only when enabled', () {
    expect(defaultVoiceEngine(['openai', 'gemini']), 'gemini');
    expect(defaultVoiceEngine(['openai']), 'openai');
    expect(() => defaultVoiceEngine([]), throwsStateError);
  });
}
