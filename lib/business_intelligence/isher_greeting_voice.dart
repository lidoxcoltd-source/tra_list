import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

abstract class IsherGreetingVoice {
  Future<void> speak(
    String text,
    String language,
    bool Function() isCurrent, {
    required int greetingVariant,
  });
  Future<void> stop();
}

class IsherSpeechSettings {
  static const _channel = MethodChannel('mjasi/speech_settings');

  static Future<bool> open() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Speech settings are only available on Android');
    }
    final result = await _channel.invokeMethod<String>('open');
    if (result == 'speech') return true;
    if (result == 'general') return false;
    throw StateError('Unexpected speech settings response');
  }
}

class _GreetingAudioSource extends StreamAudioSource {
  _GreetingAudioSource(this.bytes);
  final Uint8List bytes;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final from = start ?? 0;
    final to = end ?? bytes.length;
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: to - from,
      offset: from,
      stream: Stream.value(bytes.sublist(from, to)),
      contentType: 'audio/wav',
    );
  }
}

class CloudIsherGreetingVoice implements IsherGreetingVoice {
  CloudIsherGreetingVoice({required this.businessId, required this.onFallback});

  final String? Function() businessId;
  final void Function() onFallback;
  final _device = DeviceIsherGreetingVoice();
  final _player = AudioPlayer();
  Uint8List? _cachedAudio;
  String? _cacheKey;

  @override
  Future<void> speak(
    String text,
    String language,
    bool Function() isCurrent, {
    required int greetingVariant,
  }
  ) async {
    try {
      final id = businessId();
      if (id == null || id.isEmpty) throw StateError('Business unavailable');
      final key = '$id:$language:$text';
      Uint8List bytes;
      if (_cacheKey == key && _cachedAudio != null) {
        bytes = _cachedAudio!;
      } else {
        final response = await FirebaseFunctions.instance
            .httpsCallable('generateIsherGreeting')
            .call({
              'businessUid': id,
              'language': language,
              'greetingVariant': greetingVariant,
            });
        final data = response.data;
        if (data is! Map || data['audio'] is! String) {
          throw StateError('Invalid greeting audio');
        }
        bytes = base64Decode(data['audio'] as String);
        if (bytes.length <= 44) throw StateError('Empty greeting audio');
        if (!isCurrent()) return;
        _cacheKey = key;
        _cachedAudio = bytes;
      }
      if (!isCurrent()) return;
      await _player.setAudioSource(
        kIsWeb || defaultTargetPlatform == TargetPlatform.android
            ? AudioSource.uri(Uri.dataFromBytes(bytes, mimeType: 'audio/wav'))
            : _GreetingAudioSource(bytes),
      );
      if (!isCurrent()) {
        await _player.stop();
        return;
      }
      await _player.play();
    } catch (error, stack) {
      debugPrint('Cloud greeting failed: $error');
      debugPrintStack(stackTrace: stack);
      if (!isCurrent()) return;
      onFallback();
      await _device.speak(
        text,
        language,
        isCurrent,
        greetingVariant: greetingVariant,
      );
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await _device.stop();
  }

  Future<void> dispose() => _player.dispose();
}

class DeviceIsherGreetingVoice implements IsherGreetingVoice {
  final FlutterTts _tts = FlutterTts();

  @override
  Future<void> speak(
    String text,
    String language,
    bool Function() isCurrent, {
    required int greetingVariant,
  }
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Offline greeting voice is not supported');
    }
    final voices = await _tts.getVoices;
    if (!isCurrent()) return;
    if (voices is! List) throw StateError('Device voices unavailable');
    final candidates = voices.whereType<Map>().where((voice) {
      final locale = voice['locale'];
      final features = voice['features'];
      return locale is String &&
          locale.toLowerCase().split('-').first == language &&
          voice['network_required'] == '0' &&
          !(features is String && features.contains('notInstalled'));
    }).toList();
    if (candidates.isEmpty) {
      throw StateError('Offline language voice unavailable');
    }
    final voice = candidates.first;
    final name = voice['name'];
    final locale = voice['locale'];
    if (name is! String || locale is! String) {
      throw StateError('Invalid device voice');
    }
    final selected = await _tts.setVoice({'name': name, 'locale': locale});
    if (selected != 1) throw StateError('Could not select device voice');
    if (!isCurrent()) return;
    final result = await _tts.speak(text);
    if (result != 1) throw StateError('Could not play greeting');
    if (!isCurrent()) await _tts.stop();
  }

  @override
  Future<void> stop() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _tts.stop();
  }
}
