import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;
import 'scan_frame.dart';

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

Future<String?> scanLiveCamera(
  BuildContext context, {
  required Future<String?> Function(ImageSource source) scanImage,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => _WebCameraScanner(scanImage: scanImage)),
  );
}

class _WebCameraScanner extends StatefulWidget {
  const _WebCameraScanner({required this.scanImage});

  final Future<String?> Function(ImageSource source) scanImage;

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
      for (var attempt = 0; attempt < 24 && _video.videoWidth == 0; attempt++) {
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

  Future<void> _scanImage(ImageSource source) async {
    final code = await widget.scanImage(source);
    if (code != null && code.trim().isNotEmpty && mounted) {
      Navigator.of(context).pop(code.trim());
    }
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
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: const Color(0xFF071525),
      appBar: AppBar(
        title: Text('stk_scan'.tr),
        backgroundColor: const Color(0xFF0D2239),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: EdgeInsets.fromLTRB(width >= 700 ? 24 : 14, 14,
                  width >= 700 ? 24 : 14, 12),
              child: Column(
                children: [
                  _instructionCard(),
                  const SizedBox(height: 14),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: const Color(0xFF101D2B),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF000000).withValues(alpha: .3),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_error == null)
                            HtmlElementView(viewType: _viewType)
                          else
                            _fallback(),
                          if (_starting && _error == null)
                            Container(
                              color: const Color(0xFF101D2B)
                                  .withValues(alpha: .72),
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0D2239),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: Colors.white
                                          .withValues(alpha: .12),
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(
                                        width: 26,
                                        height: 26,
                                        child: CircularProgressIndicator(
                                          color: Color(0xFFFFC629),
                                          strokeWidth: 2.5,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'stk_cam_starting'.tr,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (!_starting && _error == null) ...[
                            Center(
                              child: ScanFrame(
                                width: width < 360 ? 250 : 290,
                                height: 210,
                              ),
                            ),
                            if (!_decoderAvailable)
                              Positioned(
                                left: 14,
                                right: 14,
                                bottom: 14,
                                child: _decoderWarning(),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _controlPanel(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _instructionCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF183654), Color(0xFF10263D)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white.withValues(alpha: .09)),
    ),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFFFC629).withValues(alpha: .15),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(
            Icons.qr_code_scanner_rounded,
            color: Color(0xFFFFC629),
            size: 25,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'stk_scan_align'.tr,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'stk_scan_hint'.tr,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .68),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _cameraStatus(),
      ],
    ),
  );

  Widget _cameraStatus() {
    final active = !_starting && _error == null;
    final failed = !_starting && _error != null;
    final color = active
        ? const Color(0xFF55D6A2)
        : failed
        ? const Color(0xFFFF7777)
        : const Color(0xFFFFC629);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active
                ? Icons.circle
                : failed
                ? Icons.error_outline
                : Icons.hourglass_top_rounded,
            color: color,
            size: active ? 8 : 14,
          ),
          const SizedBox(width: 6),
          Text(
            active
                ? 'stk_cam_ready'.tr
                : failed
                ? 'stk_cam_error_short'.tr
                : 'stk_cam_connecting'.tr,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlPanel() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
    decoration: BoxDecoration(
      color: const Color(0xFF10263D),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: .1)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'stk_scan_controls'.tr,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .8),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC629),
                  foregroundColor: const Color(0xFF17212B),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                icon: const Icon(Icons.photo_camera_rounded),
                label: Text('stk_scan_take_photo'.tr),
                onPressed: () => _scanImage(ImageSource.camera),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  side: BorderSide(color: Colors.white.withValues(alpha: .24)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text('stk_scan_upload'.tr),
                onPressed: () => _scanImage(ImageSource.gallery),
              ),
            ),
          ],
        ),
        if (_error == null && !_starting) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: .78),
                minimumSize: const Size.fromHeight(42),
              ),
              icon: const Icon(Icons.cameraswitch_outlined),
              label: Text('stk_camera_switch'.tr),
              onPressed: _switchCamera,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _decoderWarning() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF071525).withValues(alpha: .88),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFFFC629).withValues(alpha: .5)),
    ),
    child: Text(
      'stk_cam_decoder_unavailable'.tr,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white, fontSize: 12),
    ),
  );

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
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text('stk_scan_take_photo'.tr),
            onPressed: () => _scanImage(ImageSource.camera),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.photo_library_outlined),
            label: Text('stk_scan_upload'.tr),
            onPressed: () => _scanImage(ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
}
