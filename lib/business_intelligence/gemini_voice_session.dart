import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:record/record.dart';
import 'package:tra_list/business_intelligence/ai_provider.dart';
import 'package:tra_list/business_intelligence/realtime_voice.dart';
import 'package:tra_list/business_intelligence/voice_business_tools.dart';

const _liveSocket =
    'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained';
final _greetingRandom = math.Random();
final _lastGreetingVariants = <String, int>{};

@visibleForTesting
double pcmLevel(Uint8List bytes) {
  final samples = bytes.length ~/ 2;
  if (samples == 0) return 0;
  final data = ByteData.sublistView(bytes);
  var sum = 0.0;
  for (var i = 0; i < samples; i++) {
    final value = data.getInt16(i * 2, Endian.little) / 32768;
    sum += value * value;
  }
  return (math.sqrt(sum / samples) * 4).clamp(0, 1).toDouble();
}

@visibleForTesting
String geminiGreetingText(String language, {int? variant}) {
  final sw = language == 'sw';
  final greetings = sw
      ? const [
          'Habari, mimi ni Isher. Nipo tayari kukusaidia na biashara yako.',
          'Karibu, mimi ni Isher. Tuangalie biashara yako pamoja.',
          'Hujambo! Mimi ni Isher. Ungependa tuanze na nini kuhusu biashara yako?',
          'Mimi ni Isher, nipo hapa kukusaidia. Tuangalie nini leo?',
        ]
      : const [
          'Hello, I am Isher. I am ready to help with your business.',
          'Welcome, I am Isher. Let us look at your business together.',
          'Hi! I am Isher. What would you like to start with today?',
          'I am Isher, and I am here to help. What shall we look at today?',
        ];
  final key = sw ? 'sw' : 'en';
  final previous = _lastGreetingVariants[key];
  var selected =
      variant ??
      _greetingRandom.nextInt(
        previous == null ? greetings.length : greetings.length - 1,
      );
  if (variant == null) {
    if (previous != null && selected >= previous) selected++;
    _lastGreetingVariants[key] = selected;
  }
  return sw
      ? 'Sema salamu hii kwa sauti bila kuongeza maneno: "${greetings[selected]}"'
      : 'Say this greeting aloud without adding words: "${greetings[selected]}"';
}

@visibleForTesting
Future<List<Map<String, dynamic>>> geminiToolResponses(
  List<dynamic> calls,
  VoiceToolHandler? handler,
) async {
  final responses = <Map<String, dynamic>>[];
  for (final call in calls) {
    if (call is! Map || call['id'] is! String || call['name'] is! String) {
      throw const FormatException('Invalid voice tool call');
    }
    final name = call['name'] as String;
    final args = call['args'];
    final result = args is Map && handler != null
        ? await handler(name, args)
        : <String, dynamic>{'error': 'Tool unavailable. Do not guess.'};
    responses.add({'id': call['id'], 'name': name, 'response': result});
  }
  return responses;
}

class GeminiVoiceActiveException implements Exception {
  const GeminiVoiceActiveException(this.retryAfterSeconds);
  final int? retryAfterSeconds;
}

@visibleForTesting
class GeminiPlaybackIndicator {
  GeminiPlaybackIndicator(this.onSpeaking, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final void Function(bool) onSpeaking;
  final DateTime Function() _clock;
  DateTime _until = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _timer;
  bool _speaking = false;

  void addSamples(int samples) {
    if (samples <= 0) return;
    final now = _clock();
    final start = _until.isAfter(now) ? _until : now;
    _until = start.add(Duration(microseconds: samples * 1000000 ~/ 24000));
    if (!_speaking) {
      _speaking = true;
      onSpeaking(true);
    }
    _timer?.cancel();
    _timer = Timer(_until.difference(now), stop);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _until = DateTime.fromMillisecondsSinceEpoch(0);
    if (_speaking) {
      _speaking = false;
      onSpeaking(false);
    }
  }
}

/// Live voice through the Gemini Live API. The server issues a short-lived,
/// single-use token; no API key is ever stored in the app.
class GeminiVoiceSession implements VoiceSession {
  GeminiVoiceSession(
    this.onEnded,
    this.onMicrophoneLevel, {
    void Function(bool)? onAiSpeaking,
    this.toolHandler,
    @visibleForTesting AudioRecorder Function()? recorderFactory,
    @visibleForTesting
    Future<Map<String, dynamic>> Function(
      String businessId,
      String snapshotToken,
      String language,
    )?
    grantFactory,
    @visibleForTesting Future<void> Function(String leaseId)? releaseLease,
    @visibleForTesting Future<WebSocket> Function(String url)? socketFactory,
  }) : _recorderFactory = recorderFactory ?? AudioRecorder.new,
       _grantFactory = grantFactory,
       _releaseLease = releaseLease ?? _releaseServerLease,
       _socketFactory = socketFactory ?? WebSocket.connect,
       _onAiSpeaking = onAiSpeaking ?? _ignoreSpeaking {
    _playbackIndicator = GeminiPlaybackIndicator((speaking) {
      _onAiSpeaking(speaking);
    });
  }
  static void _ignoreSpeaking(bool _) {}
  void Function(String) onEnded;
  void Function(double?) onMicrophoneLevel;
  VoiceToolHandler? toolHandler;
  void Function(bool) _onAiSpeaking;
  void Function(String)? _onTranscript;
  final StringBuffer _outputTranscript = StringBuffer();
  final AudioRecorder Function() _recorderFactory;
  final Future<Map<String, dynamic>> Function(String, String, String)?
  _grantFactory;
  final Future<void> Function(String) _releaseLease;
  final Future<WebSocket> Function(String) _socketFactory;
  late final GeminiPlaybackIndicator _playbackIndicator;

  static Future<void> _releaseServerLease(String leaseId) async {
    await FirebaseFunctions.instance
        .httpsCallable('endGeminiVoice')
        .call({'leaseId': leaseId})
        .timeout(const Duration(seconds: 5));
  }

  void setCallbacks({
    required void Function(String) onEnded,
    required void Function(double?) onMicrophoneLevel,
    required void Function(bool) onAiSpeaking,
    VoiceToolHandler? toolHandler,
  }) {
    this.onEnded = onEnded;
    this.onMicrophoneLevel = onMicrophoneLevel;
    _onAiSpeaking = onAiSpeaking;
    this.toolHandler = toolHandler;
  }

  @override
  void setTranscriptCallback(void Function(String text) callback) {
    _onTranscript = callback;
  }

  WebSocket? _socket;
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _micSub;
  Future<void>? _audioSetup;
  Future<void> _audioOperation = Future.value();
  bool _audioReady = false;
  bool _microphoneRunning = false;
  Timer? _limitTimer;
  bool _closed = false;
  bool _reported = false;
  bool _muted = true;
  bool _paused = false;
  String? _leaseId;
  Future<void>? _pauseFuture;
  DateTime _playUntil = DateTime.fromMillisecondsSinceEpoch(0);

  void _ended(String reason) {
    if (_closed || _reported) return;
    _reported = true;
    onEnded(reason);
  }

  bool get _aiSpeaking => DateTime.now().isBefore(
    _playUntil.add(const Duration(milliseconds: 400)),
  );

  void _send(Map<String, dynamic> message) => _socket?.add(jsonEncode(message));

  Future<T> _withAudio<T>(Future<T> Function() action) {
    final result = _audioOperation.then((_) => action());
    _audioOperation = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<void> _startMicrophone() async {
    final stream = await _recorder!.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
      ),
    );
    _microphoneRunning = true;
    _micSub = stream.listen(_onMic);
  }

  Future<void> _stopMicrophone() async {
    final subscription = _micSub;
    _micSub = null;
    await subscription?.cancel();
    if (_microphoneRunning) {
      await _recorder!.stop();
      _microphoneRunning = false;
    }
  }

  @override
  Future<void> connect({
    required Uri endpoint,
    required AiSnapshot snapshot,
    required String businessId,
    required String language,
  }) async {
    final recorder = _recorderFactory();
    _recorder = recorder;
    if (!await recorder.hasPermission()) {
      throw StateError('Microphone permission denied');
    }
    if (_closed) throw StateError('Voice session closed');

    _audioSetup = _withAudio(() async {
      if (_closed) throw StateError('Voice session closed');
      await FlutterPcmSound.setup(sampleRate: 24000, channelCount: 1);
      _audioReady = true;
    });
    await _audioSetup;
    if (_closed) throw StateError('Voice session closed');

    final Map<String, dynamic> grant;
    try {
      if (_grantFactory != null) {
        grant = await _grantFactory(businessId, snapshot.token, language);
      } else {
        final result = await FirebaseFunctions.instance
            .httpsCallable('startGeminiVoice')
            .call({
              'businessUid': businessId,
              'token': snapshot.token,
              'language': language,
            });
        grant = Map<String, dynamic>.from(result.data as Map);
      }
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'resource-exhausted') {
        if (error.message == 'active') {
          final details = error.details;
          final retryAfter = details is Map
              ? details['retryAfterSeconds']
              : null;
          throw GeminiVoiceActiveException(
            retryAfter is int && retryAfter > 0 ? retryAfter : null,
          );
        }
        if (error.message == 'package-limit') {
          throw StateError('isher_package_exhausted');
        }
        throw StateError('bi_voice_limit');
      }
      rethrow;
    }
    if (_closed) throw StateError('Voice session closed');
    final leaseId = grant['leaseId'];
    if (leaseId is String && RegExp(r'^[a-f0-9-]{36}$').hasMatch(leaseId)) {
      _leaseId = leaseId;
    }

    final socket = await _socketFactory(
      '$_liveSocket?access_token=${Uri.encodeQueryComponent(grant['token'] as String)}',
    );
    _socket = socket;
    if (_closed) {
      await socket.close();
      throw StateError('Voice session closed');
    }

    final ready = Completer<void>();
    socket.listen(
      (data) {
        final text = data is String ? data : utf8.decode(data as List<int>);
        _onMessage(text, ready);
      },
      onError: (Object error) {
        debugPrint('Gemini voice socket error: ${error.runtimeType}');
        if (!ready.isCompleted) ready.completeError(error);
        _ended('bi_voice_connection_error');
      },
      onDone: () {
        debugPrint('Gemini voice socket closed: ${socket.closeCode}');
        if (!ready.isCompleted) {
          ready.completeError(StateError('Socket closed before setup'));
        }
        _ended('bi_voice_connection_error');
      },
    );
    final model = grant['model'] as String;
    _send({
      'setup': {
        'model': 'models/$model',
        'generationConfig': {
          'responseModalities': ['AUDIO'],
        },
        'outputAudioTranscription': {},
        'systemInstruction': {
          'parts': [
            {'text': grant['instruction'] as String},
          ],
        },
        if (grant['tools'] is List && toolHandler != null)
          'tools': grant['tools'],
      },
    });
    await ready.future.timeout(const Duration(seconds: 15));
    if (_closed) throw StateError('Voice session closed');

    FlutterPcmSound.start();

    await _withAudio(() async {
      if (_closed) throw StateError('Voice session closed');
      await _startMicrophone();
      if (_closed) throw StateError('Voice session closed');
    });

    final minutes = (grant['minutes'] as num?)?.toInt() ?? 5;
    _limitTimer = Timer(
      Duration(minutes: minutes),
      () => _ended('bi_voice_limit'),
    );

    _send({
      'realtimeInput': {'text': geminiGreetingText(language)},
    });
    setMuted(false);
  }

  void _onMic(Uint8List chunk) {
    if (_closed) return;
    if (_muted || _paused || _aiSpeaking) {
      onMicrophoneLevel(0);
      return;
    }
    onMicrophoneLevel(pcmLevel(chunk));
    _send({
      'realtimeInput': {
        'audio': {
          'data': base64Encode(chunk),
          'mimeType': 'audio/pcm;rate=16000',
        },
      },
    });
  }

  @override
  Future<void> sendText(String text) async {
    if (_closed || _paused) throw StateError('Voice session unavailable');
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > 2000) {
      throw const FormatException('Invalid voice text prompt');
    }
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw StateError('Voice connection is not ready');
    }
    _send({
      'realtimeInput': {'text': trimmed},
    });
  }

  void _onMessage(String text, Completer<void> ready) {
    final Map<String, dynamic> message;
    try {
      message = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (message.containsKey('setupComplete') && !ready.isCompleted) {
      ready.complete();
      return;
    }
    final toolCall = message['toolCall'];
    if (toolCall is Map && toolCall['functionCalls'] is List) {
      unawaited(_handleToolCalls(toolCall['functionCalls'] as List));
    }
    final content = message['serverContent'];
    if (content is! Map) return;
    final transcription = content['outputTranscription'];
    if (transcription is Map && transcription['text'] is String) {
      _outputTranscript.write(transcription['text']);
    }
    if (content['turnComplete'] == true && _outputTranscript.isNotEmpty) {
      final transcript = _outputTranscript.toString().trim();
      _outputTranscript.clear();
      if (transcript.isNotEmpty) _onTranscript?.call(transcript);
    }
    if (content['interrupted'] == true) {
      _playUntil = DateTime.now();
      _playbackIndicator.stop();
    }
    final parts = (content['modelTurn'] as Map?)?['parts'];
    if (parts is! List) return;
    for (final part in parts) {
      final data = (part is Map ? part['inlineData'] : null);
      if (data is Map && data['data'] is String) {
        _play(base64Decode(data['data'] as String));
      }
    }
  }

  Future<void> _handleToolCalls(List calls) async {
    try {
      final responses = await geminiToolResponses(calls, toolHandler);
      if (!_closed) {
        _send({
          'toolResponse': {'functionResponses': responses},
        });
      }
    } catch (error, stack) {
      debugPrint('Gemini voice tool response failed: ${error.runtimeType}');
      debugPrintStack(stackTrace: stack);
      _ended('bi_voice_connection_error');
    }
  }

  void _play(Uint8List bytes) {
    if (_closed || _paused || bytes.length < 2) return;
    final samples = bytes.length ~/ 2;
    final now = DateTime.now();
    final start = _playUntil.isAfter(now) ? _playUntil : now;
    _playUntil = start.add(Duration(microseconds: samples * 1000000 ~/ 24000));
    _playbackIndicator.addSamples(samples);
    unawaited(
      FlutterPcmSound.feed(
        PcmArrayInt16(bytes: ByteData.sublistView(bytes, 0, samples * 2)),
      ),
    );
  }

  @override
  void setMuted(bool muted) {
    _muted = muted;
    if (muted) onMicrophoneLevel(0);
    unawaited(
      _withAudio(() async {
        if (_closed || _paused || !_audioReady) return;
        if (_muted) {
          await _stopMicrophone();
        } else if (!_microphoneRunning) {
          await _startMicrophone();
        }
      }).catchError((Object error, StackTrace stack) {
        debugPrint(
          'Gemini voice microphone update failed: ${error.runtimeType}',
        );
        debugPrintStack(stackTrace: stack);
        _ended('bi_voice_connection_error');
      }),
    );
  }

  Future<void> pause() {
    if (_closed) return Future.value();
    if (_paused) return _pauseFuture ?? Future.value();
    _paused = true;
    _muted = true;
    _playbackIndicator.stop();
    _playUntil = DateTime.fromMillisecondsSinceEpoch(0);
    onMicrophoneLevel(0);
    final operation = _withAudio(() async {
      await _stopMicrophone();
      if (_audioReady) {
        await FlutterPcmSound.release();
        _audioReady = false;
      }
    });
    _pauseFuture = operation;
    return operation;
  }

  Future<bool> resume(bool Function() canResume) async {
    if (_closed || !_paused) throw StateError('Voice session unavailable');
    return _withAudio(() async {
      if (_closed) throw StateError('Voice session closed');
      await FlutterPcmSound.setup(sampleRate: 24000, channelCount: 1);
      _audioReady = true;
      await _startMicrophone();
      if (_closed || !canResume()) {
        await _stopMicrophone();
        await FlutterPcmSound.release();
        _audioReady = false;
        if (_closed) throw StateError('Voice session closed');
        return false;
      }
      _paused = false;
      _pauseFuture = null;
      _muted = false;
      return true;
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final leaseId = _leaseId;
    _leaseId = null;
    _playbackIndicator.stop();
    _limitTimer?.cancel();
    Future<void> cleanup(Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stack) {
        debugPrint('Gemini voice audio cleanup failed: ${error.runtimeType}');
        debugPrintStack(stackTrace: stack);
      }
    }

    await _withAudio(() async {
      await cleanup(_stopMicrophone);
      if (_recorder != null) await cleanup(_recorder!.dispose);
      if (_audioReady) {
        await cleanup(FlutterPcmSound.release);
        _audioReady = false;
      }
    });
    try {
      await _socket?.close();
    } catch (error) {
      debugPrint('Gemini voice socket close failed: ${error.runtimeType}');
    }
    if (leaseId != null) {
      try {
        await _releaseLease(leaseId);
      } catch (error, stack) {
        debugPrint('Gemini voice lease release failed: ${error.runtimeType}');
        debugPrintStack(stackTrace: stack);
      }
    }
  }
}
