import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/business_intelligence/isher_greeting_voice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('selects only an offline matching language voice', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getVoices') {
            return [
              {'name': 'online', 'locale': 'sw-TZ', 'network_required': '1'},
              {'name': 'offline', 'locale': 'sw-TZ', 'network_required': '0'},
            ];
          }
          return 1;
        });
    await DeviceIsherGreetingVoice().speak(
      'Habari Duka',
      'sw',
      () => true,
      greetingVariant: 0,
      provider: 'gemini',
    );
    final selected = calls.firstWhere((call) => call.method == 'setVoice');
    expect((selected.arguments as Map)['name'], 'offline');
    expect(calls.where((call) => call.method == 'speak'), hasLength(1));
  });

  test('does not send speech if only network voices exist', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getVoices') {
            return [
              {'name': 'online', 'locale': 'sw-TZ', 'network_required': '1'},
            ];
          }
          return 1;
        });
    await expectLater(
      DeviceIsherGreetingVoice().speak(
        'Habari Duka',
        'sw',
        () => true,
        greetingVariant: 0,
        provider: 'gemini',
      ),
      throwsStateError,
    );
    expect(calls.where((call) => call.method == 'speak'), isEmpty);
  });

  test('speech settings reports direct and general settings', () async {
    const settings = MethodChannel('mjasi/speech_settings');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(settings, null));
    var response = 'speech';
    messenger.setMockMethodCallHandler(settings, (call) async {
      expect(call.method, 'open');
      return response;
    });
    expect(await IsherSpeechSettings.open(), isTrue);
    response = 'general';
    expect(await IsherSpeechSettings.open(), isFalse);
    response = 'unknown';
    await expectLater(IsherSpeechSettings.open(), throwsStateError);
  });
}
