import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:get/get.dart' hide navigator;
import 'package:tra_list/business_intelligence/ai_chat.dart';
import 'package:tra_list/business_intelligence/ai_models.dart';
import 'package:tra_list/business_intelligence/ai_models_ui.dart';
import 'package:tra_list/business_intelligence/gemini_voice_session.dart';
import 'package:tra_list/business_intelligence/retained_gemini_voice.dart';
import 'package:tra_list/business_intelligence/ai_provider.dart';
import 'package:tra_list/business_intelligence/business_context.dart';
import 'package:tra_list/business_intelligence/voice_business_tools.dart';
import 'package:tra_list/business_intelligence/ai_document_draft.dart';
import 'package:tra_list/business_intelligence/voice_transaction_draft.dart';
import 'package:tra_list/business_intelligence/isher_navigation.dart';
import 'package:tra_list/services/business_access_service.dart';

String voiceServiceUrl(String configuredUrl, String firebaseProjectId) {
  if (configuredUrl.isNotEmpty) return configuredUrl;
  if (firebaseProjectId == 'tra-verify') {
    return 'wss://mjasi-ai-voice-903048450592.us-central1.run.app';
  }
  return '';
}

@visibleForTesting
double? microphoneLevel(List<StatsReport> reports) {
  for (final report in reports) {
    if (report.type != 'media-source' ||
        (report.values['kind'] != 'audio' &&
            report.values['mediaType'] != 'audio')) {
      continue;
    }
    final level = report.values['audioLevel'];
    if (level is num && level.isFinite) return level.toDouble().clamp(0, 1);
  }
  return null;
}

@visibleForTesting
bool? openAiPlaybackState(String? type) => switch (type) {
  'output_audio_buffer.started' => true,
  'output_audio_buffer.stopped' || 'output_audio_buffer.cleared' => false,
  _ => null,
};

@visibleForTesting
Map<String, dynamic> voiceConnectedGreeting(String language) => {
  'type': 'response.create',
  'response': {
    'output_modalities': ['audio'],
    'instructions': language == 'sw'
        ? 'Salimia mtumiaji kwa Kiswahili kwa sentensi fupi, jitambulishe kama Isher AI na muulize unamsaidiaje kuhusu biashara yake.'
        : 'Briefly greet the user in English, introduce yourself as Isher AI and ask how you can help with their business.',
  },
};

abstract class VoiceSession {
  Future<void> connect({
    required Uri endpoint,
    required AiSnapshot snapshot,
    required String businessId,
    required String language,
  });
  void setMuted(bool muted);
  Future<void> close();
}

typedef VoiceSessionFactory =
    VoiceSession Function(
      void Function(String) onEnded,
      void Function(double?) onMicrophoneLevel,
      void Function(bool) onAiSpeaking,
    );

class _VoiceSession implements VoiceSession {
  _VoiceSession(
    this.onEnded,
    this.onMicrophoneLevel,
    this.onAiSpeaking,
    this.toolHandler,
  );
  final void Function(String) onEnded;
  final void Function(double?) onMicrophoneLevel;
  final void Function(bool) onAiSpeaking;
  final VoiceToolHandler toolHandler;
  RTCPeerConnection? _peer;
  MediaStream? _microphone;
  WebSocket? _socket;
  bool _closed = false;
  bool _reported = false;
  bool _muted = true;
  Timer? _levelTimer;
  bool _readingLevel = false;
  Completer<bool>? _channelOpen;

  void _checkOpen() {
    if (_closed) throw StateError('Voice session closed');
  }

  void _ended(String reason) {
    if (_closed || _reported) return;
    _reported = true;
    onEnded(reason);
  }

  @override
  Future<void> connect({
    required Uri endpoint,
    required AiSnapshot snapshot,
    required String businessId,
    required String language,
  }) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) throw StateError('Not signed in');
    _checkOpen();
    final peer = await createPeerConnection({'iceServers': []});
    _peer = peer;
    if (_closed) {
      await peer.close();
      throw StateError('Voice session closed');
    }
    peer.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _ended('bi_voice_connection_error');
      }
    };
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    _microphone = stream;
    if (_closed) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
      throw StateError('Voice session closed');
    }
    for (final track in stream.getAudioTracks()) {
      track.enabled = false;
      await peer.addTrack(track, stream);
    }
    await Helper.setSpeakerphoneOnButPreferBluetooth();
    final events = await peer.createDataChannel(
      'oai-events',
      RTCDataChannelInit(),
    );
    final channelOpen = Completer<bool>();
    _channelOpen = channelOpen;
    events.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen &&
          !channelOpen.isCompleted) {
        channelOpen.complete(true);
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        if (!channelOpen.isCompleted) {
          channelOpen.complete(false);
        } else {
          _ended('bi_voice_connection_error');
        }
      }
    };
    events.onMessage = (message) {
      if (message.isBinary) return;
      try {
        final event = jsonDecode(message.text);
        if (event is Map) {
          final speaking = openAiPlaybackState(
            event['type'] is String ? event['type'] as String : null,
          );
          if (speaking != null && !_closed) onAiSpeaking(speaking);
          if (event['type'] == 'error') {
            _ended('bi_voice_connection_error');
          } else if (event['type'] == 'response.done' &&
              event['response'] is Map &&
              (event['response'] as Map)['status'] == 'failed') {
            _ended('bi_voice_connection_error');
          } else if (event['type'] == 'response.done' &&
              event['response'] is Map &&
              (event['response'] as Map)['status'] == 'completed') {
            final output = (event['response'] as Map)['output'];
            if (output is List) unawaited(_handleToolCalls(events, output));
          }
        }
      } catch (error, stack) {
        debugPrint('Invalid voice event: $error');
        debugPrintStack(stackTrace: stack);
        _ended('bi_voice_connection_error');
      }
    };
    final gathered = Completer<void>();
    peer.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !gathered.isCompleted) {
        gathered.complete();
      }
    };
    final offer = await peer.createOffer();
    await peer.setLocalDescription(offer);
    await gathered.future.timeout(const Duration(seconds: 15));
    _checkOpen();
    final sdp = (await peer.getLocalDescription())?.sdp;
    if (sdp == null) throw StateError('Missing SDP offer');
    final socket = await WebSocket.connect(
      endpoint.toString(),
    ).timeout(const Duration(seconds: 15));
    _socket = socket;
    if (_closed) {
      await socket.close();
      throw StateError('Voice session closed');
    }
    final answer = Completer<String>();
    var established = false;
    socket.listen(
      (message) {
        try {
          final data = jsonDecode(message as String) as Map<String, dynamic>;
          if (data['type'] == 'answer' && !answer.isCompleted) {
            answer.complete(data['sdp'] as String);
          } else if (data['type'] == 'error') {
            final reason = switch (data['code']) {
              'limit' => 'bi_voice_limit',
              'active' => 'bi_voice_active',
              _ => 'bi_voice_connection_error',
            };
            if (!answer.isCompleted) {
              answer.completeError(StateError(reason));
            } else {
              _ended(reason);
            }
          }
        } catch (error) {
          if (!answer.isCompleted) answer.completeError(error);
          _ended('bi_voice_connection_error');
        }
      },
      onError: (Object error) {
        if (!answer.isCompleted) answer.completeError(error);
        if (established) _ended('bi_voice_connection_error');
      },
      onDone: () {
        if (!answer.isCompleted) {
          answer.completeError(StateError('Voice connection closed'));
        }
        if (established) _ended('bi_voice_ended');
      },
    );
    socket.add(
      jsonEncode({
        'idToken': token,
        'businessUid': businessId,
        'snapshot': snapshot.token,
        'language': language,
        'sdp': sdp,
      }),
    );
    final remote = await answer.future.timeout(const Duration(seconds: 45));
    _checkOpen();
    await peer.setRemoteDescription(RTCSessionDescription(remote, 'answer'));
    _checkOpen();
    if (events.state == RTCDataChannelState.RTCDataChannelOpen &&
        !channelOpen.isCompleted) {
      channelOpen.complete(true);
    }
    if (!await channelOpen.future.timeout(const Duration(seconds: 15))) {
      throw StateError('Voice data channel closed');
    }
    _checkOpen();
    if (socket.readyState != WebSocket.open) {
      throw StateError('Voice connection closed');
    }
    await events.send(
      RTCDataChannelMessage(jsonEncode(voiceConnectedGreeting(language))),
    );
    _checkOpen();
    established = true;
    setMuted(false);
    _levelTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      unawaited(_readMicrophoneLevel());
    });
  }

  Future<void> _handleToolCalls(RTCDataChannel events, List output) async {
    var count = 0;
    for (final item in output) {
      if (item is! Map || item['type'] != 'function_call') continue;
      final id = item['call_id'];
      final name = item['name'];
      if (id is! String || name is! String || item['arguments'] is! String) {
        _ended('bi_voice_connection_error');
        return;
      }
      Map<String, dynamic> result;
      try {
        final args = jsonDecode(item['arguments'] as String);
        result = args is Map
            ? await toolHandler(name, args)
            : {'error': 'Invalid arguments. Do not guess.'};
      } on FormatException {
        result = {'error': 'Invalid arguments. Do not guess.'};
      }
      if (_closed) return;
      try {
        await events.send(
          RTCDataChannelMessage(
            jsonEncode({
              'type': 'conversation.item.create',
              'item': {
                'type': 'function_call_output',
                'call_id': id,
                'output': jsonEncode(result),
              },
            }),
          ),
        );
        count++;
      } catch (error, stack) {
        debugPrint('Voice tool response failed: ${error.runtimeType}');
        debugPrintStack(stackTrace: stack);
        _ended('bi_voice_connection_error');
        return;
      }
    }
    if (count > 0 && !_closed) {
      try {
        await events.send(
          RTCDataChannelMessage(jsonEncode({'type': 'response.create'})),
        );
      } catch (error, stack) {
        debugPrint('Voice response request failed: ${error.runtimeType}');
        debugPrintStack(stackTrace: stack);
        _ended('bi_voice_connection_error');
      }
    }
  }

  Future<void> _readMicrophoneLevel() async {
    if (_closed || _muted || _readingLevel) return;
    final track = _microphone?.getAudioTracks().firstOrNull;
    final peer = _peer;
    if (track == null || peer == null) return;
    _readingLevel = true;
    try {
      final level = microphoneLevel(await peer.getStats(track));
      if (!_closed && !_muted) onMicrophoneLevel(level);
    } catch (error, stack) {
      debugPrint('Microphone level unavailable: $error');
      debugPrintStack(stackTrace: stack);
      _levelTimer?.cancel();
      if (!_closed) onMicrophoneLevel(null);
    } finally {
      _readingLevel = false;
    }
  }

  @override
  void setMuted(bool muted) {
    _muted = muted;
    if (muted) onMicrophoneLevel(0);
    for (final track in _microphone?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _levelTimer?.cancel();
    final channelOpen = _channelOpen;
    if (channelOpen != null && !channelOpen.isCompleted) {
      channelOpen.complete(false);
    }
    final tracks = _microphone?.getTracks() ?? <MediaStreamTrack>[];
    for (final track in tracks) {
      track.enabled = false;
    }
    Future<void> cleanup(Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stack) {
        debugPrint('Voice cleanup failed: $error');
        debugPrintStack(stackTrace: stack);
      }
    }

    await Future.wait([
      for (final track in tracks) cleanup(track.stop),
      if (_socket != null)
        cleanup(() async {
          await _socket!.close().timeout(const Duration(seconds: 5));
        }),
      if (_peer != null) cleanup(_peer!.close),
    ]);
    if (_microphone != null) await cleanup(_microphone!.dispose);
  }
}

class BusinessRealtimeVoice extends StatefulWidget {
  const BusinessRealtimeVoice({
    super.key,
    required this.businessContext,
    required this.isCurrent,
    required this.provider,
    this.visible = true,
    this.onOpenChat,
    this.onOpenDocument,
    this.onOpenTransaction,
    this.sessionFactory,
    this.onToolsReady,
  });
  final BusinessContext businessContext;
  final bool Function() isCurrent;
  final AIProvider provider;
  final bool visible;
  final VoidCallback? onOpenChat;
  final void Function(AiDocumentDraft draft)? onOpenDocument;
  final void Function(VoiceTransactionDraft draft)? onOpenTransaction;
  @visibleForTesting
  final VoiceSessionFactory? sessionFactory;
  @visibleForTesting
  final void Function(VoiceToolHandler handler)? onToolsReady;

  @override
  State<BusinessRealtimeVoice> createState() => _BusinessRealtimeVoiceState();
}

class _BusinessRealtimeVoiceState extends State<BusinessRealtimeVoice>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _voiceUrl = String.fromEnvironment('MJASI_VOICE_URL');
  VoiceSession? _session;
  List<String> _engines = const ['openai'];
  Map<String, String> _providerNicknames = const {};
  String _engine = 'openai';
  bool _engineReady = false;
  bool _enginesLoading = false;
  bool _transactionReviewOpen = false;
  bool _navigationReviewOpen = false;
  bool _busy = false;
  bool _active = false;
  bool _paused = false;
  bool _foreground = true;
  bool _muted = false;
  bool _aiSpeaking = false;
  double? _microphoneLevel = 0;
  int _generation = 0;
  String? _geminiScope;
  String? _geminiUid;
  late final AnimationController _orbAnimation;

  String _snapshotScope(AiSnapshot snapshot, String uid) {
    final parts = snapshot.token.split('.');
    if (parts.length != 2) throw const FormatException('Invalid snapshot');
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts.first))),
    );
    if (payload is! Map ||
        payload['uid'] != uid ||
        payload['businessUid'] != widget.businessContext.businessId ||
        payload['scope'] is! Map) {
      throw const FormatException('Invalid snapshot scope');
    }
    return jsonEncode(payload['scope']);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _orbAnimation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _engineReady = widget.sessionFactory != null;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (widget.sessionFactory == null &&
          GeminiVoiceRetention.instance.available(
            widget.businessContext,
            FirebaseAuth.instance.currentUser?.uid,
          )) {
        _paused = true;
        _engine = 'gemini';
      }
      _orbAnimation.repeat(reverse: true);
      if (widget.sessionFactory == null) unawaited(_loadEngines());
    }
  }

  Future<void> _loadEngines() async {
    if (_enginesLoading) return;
    _enginesLoading = true;
    try {
      final repository = AiModelRepository();
      final engines = await repository.voiceProviders();
      final catalog = await repository.available();
      await AiVoiceEngineSelection.load();
      if (!mounted || engines.isEmpty) return;
      setState(() {
        _engines = engines;
        _providerNicknames = catalog.providerNicknames;
        _syncEngine();
        _engineReady = true;
      });
      AiVoiceEngineSelection.selected.addListener(_onEngineChanged);
    } catch (error) {
      debugPrint('Voice engines load failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('bi_models_voice_load_error'.tr)),
        );
      }
    } finally {
      _enginesLoading = false;
    }
  }

  void _syncEngine() {
    if (_paused) return;
    final saved = AiVoiceEngineSelection.selected.value;
    _engine = _engines.contains(saved) ? saved! : defaultVoiceEngine(_engines);
  }

  void _onEngineChanged() {
    if (mounted && !_active && !_paused && !_busy) setState(_syncEngine);
  }

  Future<void> _selectEngine(String engine) =>
      AiVoiceEngineSelection.select(engine);

  Future<void> _reviewVoiceTransaction(VoiceTransactionDraft draft) async {
    bool canReview() =>
        mounted &&
        widget.visible &&
        !_paused &&
        widget.isCurrent() &&
        BusinessAccessService.hasBusinessAccess &&
        BusinessAccessService.isOwner.value &&
        BusinessAccessService.businessId == widget.businessContext.businessId;
    if (!canReview() ||
        widget.onOpenTransaction == null ||
        _transactionReviewOpen) {
      throw StateError('Transaction access unavailable');
    }

    final generation = _generation;
    _transactionReviewOpen = true;
    bool? proceed;
    try {
      proceed = await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'cancel'.tr,
        transitionDuration: const Duration(milliseconds: 220),
        transitionBuilder: (context, animation, _, child) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOut),
            ),
            child: child,
          ),
        ),
        pageBuilder: (context, _, _) => AlertDialog(
          title: Text('bi_voice_transaction_review'.tr),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('bi_voice_transaction_not_saved'.tr),
                const SizedBox(height: 12),
                SelectableText(
                  [
                    '${'bi_voice_transaction_type'.tr}: ${(draft.type == 'income' ? 'bi_voice_transaction_income' : 'bi_voice_transaction_expense').tr}',
                    '${'bi_voice_transaction_amount'.tr}: TZS ${draft.amount}',
                    '${'bi_voice_transaction_category'.tr}: ${draft.category}',
                    '${'bi_voice_transaction_description'.tr}: ${draft.description}',
                    'bi_voice_transaction_today'.tr,
                  ].join('\n'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('cancel'.tr),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('bi_voice_transaction_chat'.tr),
            ),
          ],
        ),
      );
    } finally {
      _transactionReviewOpen = false;
    }
    if (proceed == true && canReview() && generation == _generation) {
      widget.onOpenTransaction!(draft);
    }
  }

  Future<bool> _openVoicePage(IsherDestination destination) async {
    if (!mounted ||
        !widget.visible ||
        !_foreground ||
        !_active ||
        _busy ||
        _navigationReviewOpen ||
        !widget.isCurrent()) {
      return false;
    }
    final generation = _generation;
    final session = _session;
    final sessionIsGemini = session is GeminiVoiceSession;
    _navigationReviewOpen = true;
    bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('bi_navigation_confirm_title'.tr),
          content: Text(
            '${'bi_navigation_confirm_message'.trParams({'page': destination.label})}\n\n'
            '${(sessionIsGemini ? 'bi_navigation_gemini_notice' : 'bi_navigation_openai_notice').tr}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('cancel'.tr),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('bi_navigation_open'.tr),
            ),
          ],
        ),
      );
    } finally {
      _navigationReviewOpen = false;
    }
    if (confirmed != true ||
        !mounted ||
        !widget.visible ||
        !_foreground ||
        !widget.isCurrent() ||
        !_active ||
        generation != _generation ||
        _session != session) {
      return false;
    }
    return openIsherDestination(
      context: context,
      destination: destination,
      businessId: widget.businessContext.businessId,
      isCurrent: widget.isCurrent,
      beforeOpen: () async {
        if (!mounted ||
            !widget.visible ||
            !_foreground ||
            !_active ||
            generation != _generation ||
            _session != session) {
          throw StateError('Voice session changed');
        }
        await _pauseOrStop();
        if (!mounted ||
            _active ||
            _busy ||
            (sessionIsGemini && (!_paused || _session != session))) {
          throw StateError('Voice could not be paused');
        }
      },
      afterReturn: () async {
        if (mounted &&
            widget.visible &&
            _foreground &&
            widget.isCurrent() &&
            sessionIsGemini &&
            _session == session &&
            _paused &&
            !_busy) {
          await _start();
        }
      },
    );
  }

  @override
  void didUpdateWidget(covariant BusinessRealtimeVoice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible && !widget.visible) {
      unawaited(_pauseOrStop());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _foreground = true;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      unawaited(_pauseOrStop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AiVoiceEngineSelection.selected.removeListener(_onEngineChanged);
    _orbAnimation.dispose();
    final session = _session;
    final uid = _geminiUid;
    final scope = _geminiScope;
    _session = null;
    _generation++;
    if (session is GeminiVoiceSession &&
        (_active || _paused) &&
        uid != null &&
        scope != null &&
        FirebaseAuth.instance.currentUser?.uid == uid &&
        widget.isCurrent() &&
        BusinessAccessService.hasBusinessAccess &&
        BusinessAccessService.businessId == widget.businessContext.businessId) {
      GeminiVoiceRetention.instance.retain(
        session,
        widget.businessContext,
        uid,
        scope,
      );
    } else {
      unawaited(session?.close());
    }
    super.dispose();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _session?.setMuted(_muted);
  }

  Future<void> _pauseOrStop() async {
    final session = _session;
    if (session is! GeminiVoiceSession || !_active || _busy) {
      if (!_paused) await _stop();
      return;
    }
    setState(() {
      _paused = true;
      _active = false;
      _busy = true;
      _muted = true;
      _microphoneLevel = 0;
      _aiSpeaking = false;
    });
    try {
      await session.pause();
    } catch (error, stack) {
      debugPrint('Gemini voice pause failed: $error');
      debugPrintStack(stackTrace: stack);
      await _stop('bi_voice_connection_error');
      return;
    }
    if (mounted && _session == session) setState(() => _busy = false);
  }

  Future<void> _stop([
    String? notice,
    Map<String, String>? noticeParams,
  ]) async {
    _generation++;
    final session = _session;
    _session = null;
    _geminiScope = null;
    _geminiUid = null;
    await session?.close();
    if (!mounted) return;
    setState(() {
      _active = false;
      _paused = false;
      _busy = false;
      _muted = false;
      _microphoneLevel = 0;
      _aiSpeaking = false;
      if (_engineReady && widget.sessionFactory == null) _syncEngine();
    });
    if (notice != null && widget.isCurrent()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            noticeParams == null ? notice.tr : notice.trParams(noticeParams),
          ),
        ),
      );
    }
  }

  Future<void> _start() async {
    if (_busy || _active || !_foreground) return;
    if (_paused && _session == null) {
      final retained = GeminiVoiceRetention.instance.take(
        widget.businessContext,
        FirebaseAuth.instance.currentUser?.uid,
      );
      if (retained == null) {
        setState(() => _paused = false);
        if (_engineReady) setState(_syncEngine);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('bi_voice_connection_error'.tr)));
        return;
      }
      final session = retained.session;
      _session = session;
      _geminiUid = retained.uid;
      _geminiScope = retained.scope;
      final generation = ++_generation;
      final tools = _voiceTools();
      widget.onToolsReady?.call(tools.call);
      session.setCallbacks(
        onEnded: (reason) {
          if (mounted && generation == _generation) unawaited(_stop(reason));
        },
        onMicrophoneLevel: (level) {
          if (mounted && generation == _generation && widget.isCurrent()) {
            setState(() => _microphoneLevel = level);
          }
        },
        onAiSpeaking: (speaking) {
          if (mounted && generation == _generation && widget.isCurrent()) {
            setState(() => _aiSpeaking = speaking);
          }
        },
        toolHandler: tools.call,
      );
      setState(() => _busy = true);
      try {
        await retained.pausing;
      } catch (error, stack) {
        debugPrint('Retained voice pause failed: ${error.runtimeType}');
        debugPrintStack(stackTrace: stack);
        if (mounted && _session == session) {
          await _stop('bi_voice_connection_error');
        }
        return;
      } finally {
        if (mounted && _session == session) setState(() => _busy = false);
      }
      if (!mounted || _session != session || !_foreground || !widget.visible) {
        return;
      }
    }
    final pausedSession = _session;
    if (_paused && pausedSession is GeminiVoiceSession) {
      setState(() => _busy = true);
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (!widget.isCurrent() ||
            uid == null ||
            uid != _geminiUid ||
            !BusinessAccessService.hasBusinessAccess ||
            BusinessAccessService.businessId !=
                widget.businessContext.businessId) {
          throw StateError('Business access changed');
        }
        final snapshot = await widget.provider.prepare(widget.businessContext);
        if (FirebaseAuth.instance.currentUser?.uid != uid ||
            _snapshotScope(snapshot, uid) != _geminiScope) {
          throw StateError('Business access changed');
        }
        if (!mounted ||
            !widget.visible ||
            !widget.isCurrent() ||
            !BusinessAccessService.hasBusinessAccess ||
            BusinessAccessService.businessId !=
                widget.businessContext.businessId ||
            _session != pausedSession) {
          return;
        }
        final resumed = await pausedSession.resume(
          () =>
              mounted &&
              _foreground &&
              widget.visible &&
              widget.isCurrent() &&
              FirebaseAuth.instance.currentUser?.uid == uid &&
              BusinessAccessService.hasBusinessAccess &&
              BusinessAccessService.businessId ==
                  widget.businessContext.businessId &&
              _session == pausedSession,
        );
        if (!resumed) return;
        setState(() {
          _paused = false;
          _active = true;
          _muted = false;
        });
      } catch (error, stack) {
        debugPrint('Gemini voice resume failed: $error');
        debugPrintStack(stackTrace: stack);
        await _stop('bi_voice_connection_error');
      } finally {
        if (mounted && _session == pausedSession) {
          setState(() => _busy = false);
        }
      }
      return;
    }
    if (!_engineReady) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('bi_models_load_error'.tr)));
      await _loadEngines();
      return;
    }
    final useGemini = _engine == 'gemini' && widget.sessionFactory == null;
    final serviceUrl = voiceServiceUrl(
      _voiceUrl,
      Firebase.app().options.projectId,
    );
    final endpoint = Uri.tryParse(serviceUrl);
    if (!useGemini &&
        (endpoint == null ||
            endpoint.scheme != 'wss' ||
            endpoint.host.isEmpty)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('bi_voice_not_configured'.tr)));
      return;
    }
    setState(() => _busy = true);
    final generation = ++_generation;
    try {
      final snapshot = await widget.provider.prepare(widget.businessContext);
      if (!mounted ||
          !widget.visible ||
          !widget.isCurrent() ||
          generation != _generation) {
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => Obx(
          () => AlertDialog(
            title: Text('bi_voice_review'.tr),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'bi_voice_privacy'.trParams({
                      'provider': useGemini ? 'Google Gemini' : 'OpenAI',
                    }),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert(
                      localizedAiSnapshot(
                        snapshot.context,
                        Get.locale?.languageCode ?? 'en',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text('cancel'.tr),
              ),
              if (widget.isCurrent())
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text('bi_voice_consent'.tr),
                ),
            ],
          ),
        ),
      );
      if (confirmed != true ||
          !mounted ||
          !widget.visible ||
          !widget.isCurrent() ||
          generation != _generation) {
        return;
      }
      if (useGemini) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) throw StateError('Not signed in');
        _geminiScope = _snapshotScope(snapshot, uid);
        _geminiUid = uid;
      }
      final tools = _voiceTools();
      widget.onToolsReady?.call(tools.call);
      final factory =
          widget.sessionFactory ??
          (useGemini
              ? (ended, level, speaking) => GeminiVoiceSession(
                  ended,
                  level,
                  onAiSpeaking: speaking,
                  toolHandler: tools.call,
                )
              : (ended, level, speaking) =>
                    _VoiceSession(ended, level, speaking, tools.call));
      final session = factory(
        (reason) {
          if (mounted && generation == _generation) {
            unawaited(_stop(reason));
          }
        },
        (level) {
          if (mounted && generation == _generation && widget.isCurrent()) {
            setState(() => _microphoneLevel = level);
          }
        },
        (speaking) {
          if (mounted && generation == _generation && widget.isCurrent()) {
            setState(() => _aiSpeaking = speaking);
          }
        },
      );
      _session = session;
      await session.connect(
        endpoint: endpoint ?? Uri(),
        snapshot: snapshot,
        businessId: widget.businessContext.businessId,
        language: Get.locale?.languageCode ?? 'en',
      );
      if (!mounted ||
          !widget.visible ||
          !widget.isCurrent() ||
          _session != session) {
        await session.close();
        return;
      }
      setState(() => _active = true);
    } catch (error, stack) {
      debugPrint('Voice session failed: $error');
      debugPrintStack(stackTrace: stack);
      if (generation == _generation) {
        if (error is GeminiVoiceActiveException) {
          final seconds = error.retryAfterSeconds;
          await _stop(
            seconds == null ? 'bi_voice_active' : 'bi_voice_active_wait',
            seconds == null ? null : {'seconds': '$seconds'},
          );
        } else {
          await _stop(
            error.toString().contains('bi_voice_limit')
                ? 'bi_voice_limit'
                : error.toString().contains('bi_voice_active')
                ? 'bi_voice_active'
                : error.toString().contains('Microphone permission denied')
                ? 'bi_voice_microphone_permission'
                : error is MissingPluginException
                ? 'bi_voice_plugin_missing'
                : 'bi_voice_connection_error',
          );
        }
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  VoiceBusinessTools _voiceTools() => VoiceBusinessTools(
    provider: widget.provider,
    business: widget.businessContext,
    isCurrent: () =>
        mounted &&
        _foreground &&
        widget.visible &&
        !_paused &&
        widget.isCurrent(),
    onDocument: widget.onOpenDocument,
    onTransaction: _reviewVoiceTransaction,
    onNavigate: _openVoicePage,
  );

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'bi_voice_android_only'.tr,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            if (widget.onOpenChat != null)
              TextButton.icon(
                onPressed: widget.onOpenChat,
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: Text('bi_tab_chat'.tr),
              ),
          ],
        ),
      );
    }
    final status = _busy
        ? 'bi_voice_connecting'
        : _active
        ? (_muted ? 'bi_voice_muted' : 'bi_voice_live')
        : _paused
        ? 'bi_voice_paused'
        : 'bi_voice_idle_prompt';
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF080817), Color(0xFF100D21), Color(0xFF17102D)],
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight > 40
                    ? constraints.maxHeight - 40
                    : 0,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const SizedBox(height: 16),
                      _IsherOrb(
                        animation: _orbAnimation,
                        active: _active && !_muted,
                        busy: _busy,
                        level: _active && !_muted ? _microphoneLevel : 0,
                        speaking: _aiSpeaking,
                      ),
                      const SizedBox(height: 28),
                      Text(
                        _active
                            ? 'bi_voice_session_title'.tr
                            : 'bi_voice_welcome'.tr,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        status == 'bi_voice_live'
                            ? status.trParams({
                                'provider': _engine == 'gemini'
                                    ? 'Google Gemini'
                                    : 'OpenAI',
                              })
                            : status.tr,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFBDB9D0),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (_busy)
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          _active && !_muted
                              ? Icons.graphic_eq_rounded
                              : Icons.mic_none_rounded,
                          color: const Color(0xFFB9A4FF),
                        ),
                      const SizedBox(height: 14),
                      if (!_active &&
                          !_paused &&
                          !_busy &&
                          _engines.length > 1) ...[
                        SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: [
                            for (final e in _engines)
                              ButtonSegment(
                                value: e,
                                label: Text(
                                  isherProviderNickname(e, _providerNicknames),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          selected: {_engine},
                          onSelectionChanged: (v) => _selectEngine(v.first),
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (_active && !_muted && _microphoneLevel == null)
                        Text(
                          'bi_voice_level_unavailable'.tr,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      Semantics(
                        button: true,
                        label:
                            (_active
                                    ? (_muted
                                          ? 'bi_voice_unmute'
                                          : 'bi_voice_mute')
                                    : (_paused
                                          ? 'bi_voice_resume'
                                          : 'bi_voice_start'))
                                .tr,
                        child: Material(
                          color: const Color(0xFF625C7A),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _busy
                                ? null
                                : (_active ? _toggleMute : _start),
                            child: Container(
                              width: 88,
                              height: 88,
                              margin: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFFB9A4FF),
                                    Color(0xFF7048ED),
                                  ],
                                ),
                              ),
                              child: Icon(
                                _muted
                                    ? Icons.mic_off_rounded
                                    : Icons.mic_rounded,
                                color: Colors.white,
                                size: 34,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        (_active
                                ? (_muted ? 'bi_voice_unmute' : 'bi_voice_mute')
                                : (_paused
                                      ? 'bi_voice_resume'
                                      : 'bi_voice_start'))
                            .tr,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _VoiceControl(
                            icon: _muted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                            label:
                                (_muted ? 'bi_voice_unmute' : 'bi_voice_mute')
                                    .tr,
                            onPressed: _active && !_busy ? _toggleMute : null,
                          ),
                          const SizedBox(width: 24),
                          _VoiceControl(
                            icon: Icons.chat_bubble_outline_rounded,
                            label: 'bi_tab_chat'.tr,
                            onPressed: _busy ? null : widget.onOpenChat,
                          ),
                          const SizedBox(width: 24),
                          _VoiceControl(
                            icon: Icons.call_end_rounded,
                            label:
                                (_session is GeminiVoiceSession
                                        ? 'bi_voice_pause'
                                        : 'bi_voice_end')
                                    .tr,
                            onPressed: _active && !_busy ? _pauseOrStop : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceControl extends StatelessWidget {
  const _VoiceControl({
    required this.icon,
    required this.label,
    this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    tooltip: label,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: const Color(0xFF302A48),
      foregroundColor: Colors.white,
      disabledBackgroundColor: const Color(0xFF231F34),
      disabledForegroundColor: Colors.white24,
    ),
    icon: Icon(icon, size: 20),
  );
}

class _IsherOrb extends StatelessWidget {
  const _IsherOrb({
    required this.animation,
    required this.active,
    required this.busy,
    required this.level,
    required this.speaking,
  });
  final Animation<double> animation;
  final bool active;
  final bool busy;
  final double? level;
  final bool speaking;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, child) {
      final pulse = MediaQuery.disableAnimationsOf(context)
          ? 0.0
          : animation.value;
      final loudness = MediaQuery.disableAnimationsOf(context)
          ? 0.0
          : ((level ?? 0) * 4).clamp(0.0, 1.0);
      final reducedMotion = MediaQuery.disableAnimationsOf(context);
      final voicePulse = reducedMotion
          ? 0.0
          : (math.sin(pulse * math.pi * 8) + 1) / 2;
      final gaze = reducedMotion ? 0.0 : math.sin(pulse * math.pi * 2);
      return Transform.scale(
        key: const ValueKey('voice_orb_scale'),
        scale: speaking
            ? 1.02 + voicePulse * 0.08
            : active
            ? 1 + loudness * 0.14
            : 0.97 + pulse * 0.03,
        child: Container(
          key: const ValueKey('voice_orb_surface'),
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-0.4, -0.55),
              radius: 0.9,
              colors: [
                speaking ? const Color(0xFFB2FFF5) : const Color(0xFFB9A4FF),
                speaking ? const Color(0xFF168DAD) : const Color(0xFF5434A5),
                const Color(0xFF17102D),
                speaking
                    ? const Color(0xFF80FFE4)
                    : active
                    ? const Color(0xFF00D9FF)
                    : const Color(0xFF2878FF),
                const Color(0xFF080817),
              ],
              stops: const [0, 0.2, 0.53, 0.82, 1],
            ),
            boxShadow: [
              BoxShadow(
                color:
                    (speaking
                            ? const Color(0xFF4DFFE0)
                            : active
                            ? const Color(0xFF00D9FF)
                            : const Color(0xFF7048ED))
                        .withValues(
                          alpha: speaking
                              ? 0.35 + voicePulse * 0.2
                              : 0.22 + pulse * 0.12,
                        ),
                blurRadius: speaking
                    ? 40 + voicePulse * 18
                    : busy
                    ? 48
                    : 38,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 118,
              height: 118,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-0.25, -0.45),
                  colors: [Color(0xFF443B75), Color(0xFF090817)],
                ),
                border: Border.all(
                  color: const Color(0xFFB9A4FF).withValues(alpha: 0.35),
                ),
              ),
              child: Center(
                child: Transform.translate(
                  key: const ValueKey('voice_orb_eye'),
                  offset: Offset(
                    gaze * 8,
                    reducedMotion ? 0 : math.sin(pulse * math.pi) * -3,
                  ),
                  child: Container(
                    width: 44,
                    height: speaking ? 44 + voicePulse * 8 : 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: speaking
                            ? const [
                                Color(0xFFE7FFFC),
                                Color(0xFF37DCCB),
                                Color(0xFF12617D),
                              ]
                            : const [
                                Color(0xFFF3EBFF),
                                Color(0xFFAF99FF),
                                Color(0xFF5743A5),
                              ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              (speaking
                                      ? const Color(0xFF69FFE8)
                                      : const Color(0xFFB9A4FF))
                                  .withValues(alpha: 0.5),
                          blurRadius: speaking ? 18 + voicePulse * 8 : 12,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
