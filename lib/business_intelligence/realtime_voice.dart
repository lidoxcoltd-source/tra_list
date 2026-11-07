import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:get/get.dart' hide navigator;
import 'package:tra_list/business_intelligence/ai_chat.dart';
import 'package:tra_list/business_intelligence/ai_provider.dart';
import 'package:tra_list/business_intelligence/business_context.dart';

class _VoiceSession {
  _VoiceSession(this.onEnded);
  final void Function(String) onEnded;
  RTCPeerConnection? _peer;
  MediaStream? _microphone;
  WebSocket? _socket;
  bool _closed = false;
  bool _reported = false;

  void _checkOpen() {
    if (_closed) throw StateError('Voice session closed');
  }

  void _ended(String reason) {
    if (_closed || _reported) return;
    _reported = true;
    onEnded(reason);
  }

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
    events.onMessage = (message) {
      if (message.isBinary) return;
      try {
        final event = jsonDecode(message.text);
        if (event is Map && event['type'] == 'error') {
          _ended('bi_voice_connection_error');
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
    socket.listen(
      (message) {
        try {
          final data = jsonDecode(message as String) as Map<String, dynamic>;
          if (data['type'] == 'answer' && !answer.isCompleted) {
            answer.complete(data['sdp'] as String);
          } else if (data['type'] == 'error') {
            final reason = data['code'] == 'limit'
                ? 'bi_voice_limit'
                : 'bi_voice_connection_error';
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
        _ended('bi_voice_connection_error');
      },
      onDone: () {
        if (!answer.isCompleted) {
          answer.completeError(StateError('Voice connection closed'));
        }
        _ended('bi_voice_ended');
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
    setMuted(false);
  }

  void setMuted(bool muted) {
    for (final track in _microphone?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
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
  });
  final BusinessContext businessContext;
  final bool Function() isCurrent;
  final AIProvider provider;

  @override
  State<BusinessRealtimeVoice> createState() => _BusinessRealtimeVoiceState();
}

class _BusinessRealtimeVoiceState extends State<BusinessRealtimeVoice>
    with WidgetsBindingObserver {
  static const _voiceUrl = String.fromEnvironment('MJASI_VOICE_URL');
  _VoiceSession? _session;
  bool _busy = false;
  bool _active = false;
  bool _muted = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_session?.close());
    super.dispose();
  }

  Future<void> _stop([String? notice]) async {
    _generation++;
    final session = _session;
    _session = null;
    await session?.close();
    if (!mounted) return;
    setState(() {
      _active = false;
      _busy = false;
      _muted = false;
    });
    if (notice != null && widget.isCurrent()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(notice.tr)));
    }
  }

  Future<void> _start() async {
    if (_busy || _active) return;
    final endpoint = Uri.tryParse(_voiceUrl);
    if (endpoint == null || endpoint.scheme != 'wss' || endpoint.host.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('bi_voice_not_configured'.tr)));
      return;
    }
    setState(() => _busy = true);
    final generation = ++_generation;
    try {
      final snapshot = await widget.provider.prepare(widget.businessContext);
      if (!mounted || !widget.isCurrent() || generation != _generation) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => Obx(
          () => AlertDialog(
            title: Text('bi_voice_review'.tr),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('bi_voice_privacy'.tr),
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
          !widget.isCurrent() ||
          generation != _generation) {
        return;
      }
      final session = _VoiceSession((reason) => unawaited(_stop(reason)));
      _session = session;
      await session.connect(
        endpoint: endpoint,
        snapshot: snapshot,
        businessId: widget.businessContext.businessId,
        language: Get.locale?.languageCode ?? 'en',
      );
      if (!mounted || !widget.isCurrent() || _session != session) {
        await session.close();
        return;
      }
      setState(() => _active = true);
    } catch (error, stack) {
      debugPrint('Voice session failed: $error');
      debugPrintStack(stackTrace: stack);
      if (generation == _generation) {
        await _stop(
          error.toString().contains('bi_voice_limit')
              ? 'bi_voice_limit'
              : 'bi_voice_connection_error',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Text(
        'bi_voice_android_only'.tr,
        style: const TextStyle(color: Colors.white70),
        textAlign: TextAlign.center,
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: Alignment(-0.4, -0.5),
                  colors: [
                    Color(0xFFAE78FF),
                    Color(0xFF5433BC),
                    Color(0xFF101A3F),
                  ],
                ),
                boxShadow: [
                  BoxShadow(color: Color(0x885B46D8), blurRadius: 40),
                ],
              ),
              child: const Icon(
                Icons.graphic_eq_rounded,
                color: Colors.white,
                size: 60,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'bi_voice_title'.tr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              (_active
                      ? (_muted ? 'bi_voice_muted' : 'bi_voice_live')
                      : 'bi_voice_intro')
                  .tr,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_busy) const LinearProgressIndicator(),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (!_active)
                  FilledButton.icon(
                    onPressed: _busy ? null : _start,
                    icon: const Icon(Icons.mic),
                    label: Text('bi_voice_start'.tr),
                  )
                else ...[
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _muted = !_muted);
                      _session?.setMuted(_muted);
                    },
                    icon: Icon(_muted ? Icons.mic_off : Icons.mic),
                    label: Text(
                      (_muted ? 'bi_voice_unmute' : 'bi_voice_mute').tr,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _stop,
                    icon: const Icon(Icons.call_end),
                    label: Text('bi_voice_end'.tr),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
