import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:get/get.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:tra_list/home/isher_speech_error.dart';
import 'package:tra_list/home/isher_voice_command.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/theme/app_theme.dart';

enum _WakePhase { wake, responding, choice, unavailable }

class HomeIsherWakeWordControl extends StatefulWidget {
  const HomeIsherWakeWordControl({
    super.key,
    required this.onChat,
    required this.onVoice,
  });

  final VoidCallback onChat;
  final VoidCallback onVoice;

  @override
  State<HomeIsherWakeWordControl> createState() =>
      _HomeIsherWakeWordControlState();
}

class _HomeIsherWakeWordControlState extends State<HomeIsherWakeWordControl>
    with WidgetsBindingObserver {
  final _speech = SpeechToText();
  final _tts = FlutterTts();
  Timer? _routeTimer;
  Timer? _restartTimer;
  _WakePhase _phase = _WakePhase.wake;
  bool _enabled = !kIsWeb;
  bool _foreground = true;
  bool _routeVisible = false;
  bool _speechReady = false;
  bool _initializing = false;
  bool _handlingResult = false;
  int _choiceRetries = 0;
  int _restartAttempts = 0;
  String? _speechLocaleId;
  String _pendingWebTranscript = '';

  bool get _supported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _enabled) unawaited(_initializeAndListen());
    });
    _routeTimer = Timer.periodic(
      const Duration(milliseconds: 700),
      (_) => _checkRouteVisibility(),
    );
  }

  Future<void> _initializeAndListen() async {
    if (_initializing) return;
    _initializing = true;
    _speechReady = false;
    if (!_supported) {
      if (mounted) setState(() => _phase = _WakePhase.unavailable);
      _initializing = false;
      return;
    }
    try {
      final available = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onSpeechError,
      );
      if (!mounted || !_enabled) return;
      if (!available) {
        setState(() {
          _enabled = false;
          _phase = _WakePhase.unavailable;
        });
        return;
      }
      final locales = await _speech.locales();
      final language = _language;
      final matchingLocales = locales.where(
        (locale) => locale.localeId.toLowerCase().startsWith(language),
      );
      _speechLocaleId = kIsWeb
          ? language == 'sw'
                ? 'sw-TZ'
                : 'en-US'
          : matchingLocales.isEmpty
          ? null
          : matchingLocales.first.localeId;
      _speechReady = true;
      _routeVisible = _isHomeRoute;
      if (_foreground && _routeVisible) await _listen();
    } catch (error, stack) {
      debugPrint('Could not initialize Isher Home speech: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        setState(() {
          _enabled = false;
          _phase = _WakePhase.unavailable;
        });
      }
    } finally {
      _initializing = false;
    }
  }

  bool get _isHomeRoute {
    final route = Get.currentRoute;
    return route == AppRoutes.home || route.startsWith('/home/');
  }

  void _checkRouteVisibility() {
    final visible = _isHomeRoute;
    if (visible == _routeVisible) return;
    _routeVisible = visible;
    if (!visible) {
      _restartTimer?.cancel();
      unawaited(_speech.stop());
      unawaited(_tts.stop());
      return;
    }
    if (_enabled && _speechReady && _foreground) unawaited(_listen());
  }

  Future<void> _listen() async {
    if (!mounted ||
        !_enabled ||
        !_speechReady ||
        !_foreground ||
        !_routeVisible ||
        _phase == _WakePhase.responding ||
        _speech.isListening) {
      return;
    }
    _restartTimer?.cancel();
    try {
      await _speech.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          cancelOnError: true,
          listenFor: const Duration(seconds: 45),
          listenMode: ListenMode.confirmation,
          localeId: _speechLocaleId,
          partialResults: true,
          pauseFor: const Duration(seconds: 5),
        ),
      );
      if (mounted && _enabled) {
        setState(() {
          if (_phase == _WakePhase.unavailable) _phase = _WakePhase.wake;
        });
      }
    } catch (error, stack) {
      debugPrint('Could not listen for Isher wake word: $error');
      debugPrintStack(stackTrace: stack);
      if (isRetryableIsherSpeechError(error.toString())) {
        _scheduleListeningRestart();
      } else if (mounted) {
        setState(() {
          _enabled = false;
          _phase = _WakePhase.unavailable;
        });
      }
    }
  }

  void _onStatus(String status) {
    if (!mounted ||
        !_enabled ||
        !_speechReady ||
        !_foreground ||
        !_routeVisible) {
      return;
    }
    if (status == SpeechToText.listeningStatus) {
      _restartTimer?.cancel();
      _restartAttempts = 0;
      return;
    }
    if (status != SpeechToText.notListeningStatus &&
        status != SpeechToText.doneStatus) {
      return;
    }
    if (kIsWeb && status == SpeechToText.doneStatus) {
      final transcript = _pendingWebTranscript;
      _pendingWebTranscript = '';
      if (transcript.isNotEmpty) _handleTranscript(transcript);
    }
    if (_phase == _WakePhase.responding) return;
    _scheduleListeningRestart();
  }

  void _onSpeechError(SpeechRecognitionError error) {
    final message = error.errorMsg;
    debugPrint('Isher Home speech recognition failed: $message');
    if (!mounted || !_enabled) return;
    if (isRetryableIsherSpeechError(message)) {
      _scheduleListeningRestart();
      return;
    }
    _restartTimer?.cancel();
    setState(() {
      _enabled = false;
      _phase = _WakePhase.unavailable;
    });
  }

  void _scheduleListeningRestart() {
    if (!mounted ||
        !_enabled ||
        !_speechReady ||
        !_foreground ||
        !_routeVisible) {
      return;
    }
    if (_restartTimer?.isActive ?? false) return;
    final backoffExponent = _restartAttempts < 3 ? _restartAttempts : 3;
    final backoffSeconds = 1 << backoffExponent;
    _restartAttempts++;
    _restartTimer = Timer(Duration(seconds: backoffSeconds), () {
      if (!mounted || !_enabled || !_foreground || !_routeVisible) return;
      if (_phase == _WakePhase.choice) {
        unawaited(_repeatChoiceQuestion());
      } else {
        unawaited(_listen());
      }
    });
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!mounted || _handlingResult) return;
    final words = result.recognizedWords.trim();
    if (kIsWeb) {
      _pendingWebTranscript = words;
      return;
    }
    if (!result.finalResult) return;
    _handleTranscript(words);
  }

  void _handleTranscript(String words) {
    if (!mounted || _handlingResult) return;
    if (_phase == _WakePhase.wake && IsherVoiceCommand.isWakePhrase(words)) {
      _handlingResult = true;
      unawaited(_answerWakeWord());
      return;
    }
    if (_phase == _WakePhase.choice) {
      final intent = IsherVoiceCommand.parseChoice(words);
      _handlingResult = true;
      if (intent == null) {
        unawaited(_repeatChoiceQuestion());
      } else {
        unawaited(_openAssistant(intent));
      }
    }
  }

  String get _language => Get.locale?.languageCode == 'sw' ? 'sw' : 'en';

  Future<void> _speak(String text) async {
    await _speech.stop();
    try {
      await _tts.setLanguage(_language == 'sw' ? 'sw-TZ' : 'en-US');
      await _tts.awaitSpeakCompletion(true);
      await _tts.speak(text);
    } catch (error, stack) {
      debugPrint('Isher Home voice response failed: $error');
      debugPrintStack(stackTrace: stack);
    }
  }

  Future<void> _answerWakeWord() async {
    if (!mounted) return;
    setState(() => _phase = _WakePhase.responding);
    await _speak(
      _language == 'sw'
          ? 'Ndiyo, habari? Unataka kuchat au kupiga simu?'
          : 'Yes, hello! Would you like to chat or make a call?',
    );
    if (!mounted || !_enabled) return;
    _choiceRetries = 0;
    _handlingResult = false;
    setState(() => _phase = _WakePhase.choice);
    await _listen();
  }

  Future<void> _repeatChoiceQuestion() async {
    if (!mounted || !_enabled || _phase == _WakePhase.responding) return;
    _restartTimer?.cancel();
    _handlingResult = true;
    setState(() => _phase = _WakePhase.responding);
    _choiceRetries++;
    await _speak(
      _language == 'sw'
          ? 'Samahani, sikusikia vizuri. Unataka kuchat au kupiga simu?'
          : 'Sorry, I did not catch that. Would you like to chat or make a call?',
    );
    if (!mounted || !_enabled) return;
    if (_choiceRetries >= 3) {
      _choiceRetries = 0;
      setState(() => _phase = _WakePhase.wake);
    } else {
      setState(() => _phase = _WakePhase.choice);
    }
    _handlingResult = false;
    await _listen();
  }

  Future<void> _openAssistant(IsherVoiceIntent intent) async {
    setState(() => _phase = _WakePhase.responding);
    await _speak(
      _language == 'sw'
          ? intent == IsherVoiceIntent.chat
                ? 'Sawa, nafungua chat sasa.'
                : 'Sawa, nafungua mazungumzo ya sauti sasa.'
          : intent == IsherVoiceIntent.chat
          ? 'Okay, opening chat now.'
          : 'Okay, opening voice now.',
    );
    if (!mounted) return;
    setState(() => _enabled = false);
    if (intent == IsherVoiceIntent.chat) {
      widget.onChat();
    } else {
      widget.onVoice();
    }
  }

  String get _statusText {
    return switch (_phase) {
      _WakePhase.wake => 'isher_wake_listening'.tr,
      _WakePhase.responding => 'isher_wake_responding'.tr,
      _WakePhase.choice => 'isher_wake_waiting_choice'.tr,
      _WakePhase.unavailable => 'isher_wake_unavailable'.tr,
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _restartTimer?.cancel();
      unawaited(_speech.stop());
      unawaited(_tts.stop());
    } else if (_enabled && _speechReady && _routeVisible) {
      unawaited(_listen());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _routeTimer?.cancel();
    _restartTimer?.cancel();
    unawaited(_speech.cancel());
    unawaited(_tts.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported ||
        !_enabled ||
        (_phase != _WakePhase.responding && _phase != _WakePhase.choice)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Material(
        color: const Color(0xFFF2F6FC),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              const Icon(
                Icons.graphic_eq_rounded,
                color: MjasiColors.primaryBlue,
                size: 20,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _statusText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: MjasiColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'isher_wake_privacy'.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MjasiColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.mic_rounded,
                color: MjasiColors.primaryBlue,
                size: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
