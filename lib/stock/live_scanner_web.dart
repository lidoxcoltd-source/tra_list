import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:web/web.dart' as web;

@JS('BarcodeDetector')
extension type _BarcodeDetector._(JSObject _) implements JSObject {
  external factory _BarcodeDetector();
  external JSPromise<JSArray<_DetectedBarcode>> detect(
    web.HTMLVideoElement source,
  );
}

@JS()
extension type _DetectedBarcode._(JSObject _) implements JSObject {
  external String get rawValue;
}

int _viewCount = 0;

Future<String?> scanLiveCamera(BuildContext context) {
  return Navigator.of(
    context,
  ).push<String>(MaterialPageRoute(builder: (_) => const _WebCameraScanner()));
}

class _WebCameraScanner extends StatefulWidget {
  const _WebCameraScanner();

  @override
  State<_WebCameraScanner> createState() => _WebCameraScannerState();
}

class _WebCameraScannerState extends State<_WebCameraScanner> {
  late final String _viewType;
  late final web.HTMLVideoElement _video;
  web.MediaStream? _stream;
  _BarcodeDetector? _detector;
  Timer? _timer;
  bool _starting = true;
  bool _decoding = false;
  bool _backCamera = true;
  String? _error;
  bool _decoderAvailable = true;

  @override
  void initState() {
    super.initState();
    _viewType = 'mjasipos-live-camera-${_viewCount++}';
    _video = web.HTMLVideoElement()
      ..autoplay = true
      ..muted = true
      ..playsInline = true;
    _video.style
      ..display = 'block'
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'cover'
      ..backgroundColor = '#000';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) => _video);
    _start();
  }

  Future<void> _start() async {
    await _stopStream();
    if (mounted) {
      setState(() {
        _starting = true;
        _error = null;
      });
    }
    try {
      final devices = web.window.navigator.mediaDevices;
      final constraints = web.MediaStreamConstraints(
        video: {
          'facingMode': {'ideal': _backCamera ? 'environment' : 'user'},
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        }.jsify()!,
      );
      final stream = await devices
          .getUserMedia(constraints)
          .toDart
          .timeout(const Duration(seconds: 12));
      _stream = stream;
      _video.srcObject = stream;
      await _video.play().toDart;
      for (var attempt = 0;
          attempt < 24 && _video.videoWidth == 0;
          attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (_video.videoWidth == 0 || _video.videoHeight == 0) {
        throw StateError('Camera stream started without video frames');
      }

      try {
        _detector = _BarcodeDetector();
      } catch (_) {
        _decoderAvailable = false;
      }
      _timer?.cancel();
      if (_decoderAvailable) {
        _timer = Timer.periodic(
          const Duration(milliseconds: 350),
          (_) => _detect(),
        );
      }
      if (mounted) setState(() => _starting = false);
    } catch (e) {
      await _stopStream();
      if (mounted) {
        setState(() {
          _starting = false;
          _error = _errorKey(e);
        });
      }
    }
  }

  String _errorKey(Object error) {
    final text = error.toString();
    if (!web.window.isSecureContext) return 'stk_cam_insecure';
    if (text.contains('NotAllowedError') || text.contains('SecurityError')) {
      return 'stk_cam_denied';
    }
    if (text.contains('NotFoundError') ||
        text.contains('OverconstrainedError')) {
      return 'stk_cam_notfound';
    }
    if (text.contains('NotReadableError') || text.contains('AbortError')) {
      return 'stk_cam_busy';
    }
    return 'stk_cam_other';
  }

  Future<void> _detect() async {
    final detector = _detector;
    if (_decoding ||
        detector == null ||
        _video.readyState < 2 ||
        _video.videoWidth == 0 ||
        _video.videoHeight == 0) {
      return;
    }
    _decoding = true;
    try {
      final results = await detector.detect(_video).toDart;
      for (final result in results.toDart) {
        final code = result.rawValue.trim();
        if (code.isNotEmpty && mounted) {
          Navigator.of(context).pop(code);
          return;
        }
      }
    } catch (_) {
      // A frame can be unavailable while the browser is starting the camera.
    } finally {
      _decoding = false;
    }
  }

  Future<void> _switchCamera() async {
    _backCamera = !_backCamera;
    await _stopStream();
    await _start();
  }

  Future<void> _stopStream() async {
    _timer?.cancel();
    _timer = null;
    _video.pause();
    _video.srcObject = null;
    for (final track
        in _stream?.getTracks().toDart ?? <web.MediaStreamTrack>[]) {
      track.stop();
    }
    _stream = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _video.pause();
    _video.srcObject = null;
    for (final track
        in _stream?.getTracks().toDart ?? <web.MediaStreamTrack>[]) {
      track.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('stk_scan'.tr),
        backgroundColor: const Color(0xFF102B49),
        foregroundColor: Colors.white,
        actions: [
          if (_error == null && !_starting)
            IconButton(
              tooltip: 'stk_camera_switch'.tr,
              icon: const Icon(Icons.cameraswitch_outlined),
              onPressed: _switchCamera,
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_error == null)
            HtmlElementView(viewType: _viewType)
          else
            _fallback(),
          if (_starting && _error == null)
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 12),
                    Text(
                      'stk_cam_starting'.tr,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          if (!_starting && _error == null) ...[
            Center(
              child: Container(
                width: 260,
                height: 220,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            if (!_decoderAvailable)
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Text(
                  'stk_cam_decoder_unavailable'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _fallback() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _error!.tr,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.refresh),
            label: Text('stk_cam_retry'.tr),
            onPressed: _start,
          ),
        ],
      ),
    ),
  );
}
