import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'market_media_route_observer.dart';
import 'market_video_trim_page.dart';

const marketVideoMaxSeconds = 30;
const marketVideoMaxBytes = 50 * 1024 * 1024;
const marketVideoExtensions = ['mp4', 'webm', 'mov'];

String marketVideoContentType(String extension) => switch (extension) {
  'webm' => 'video/webm',
  'mov' => 'video/quicktime',
  _ => 'video/mp4',
};

class MarketVideoSelection {
  const MarketVideoSelection({
    required this.bytes,
    required this.extension,
    required this.name,
  });

  final Uint8List bytes;
  final String extension;
  final String name;
}

/// Picks a short video. Duration is verified on mobile; web checks size only.
Future<MarketVideoSelection?> pickMarketVideo(BuildContext context) async {
  Future<void> warn(String key) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      content: Text(key.tr),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
        ),
      ],
    ),
  );

  final FilePickerResult? result;
  try {
    result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      withData: kIsWeb,
    );
  } catch (error) {
    debugPrint('Video pick failed: $error');
    if (context.mounted) await warn('market_video_invalid');
    return null;
  }
  final file = result?.files.single;
  if (file == null) return null;
  final extension = (file.extension ?? 'mp4').toLowerCase();
  final path = kIsWeb ? null : file.path;

  if (path != null) {
    if (file.size > marketVideoSourceMaxBytes) {
      if (context.mounted) await warn('market_video_too_large');
      return null;
    }
    if (!context.mounted) return null;
    return Navigator.of(context).push<MarketVideoSelection>(
      MaterialPageRoute(
        builder: (_) => MarketVideoEditorPage(
          path: path,
          fileName: file.name,
          extension: extension,
        ),
      ),
    );
  }

  final bytes = file.bytes;
  if (bytes == null || !marketVideoExtensions.contains(extension)) {
    if (context.mounted) await warn('market_video_invalid');
    return null;
  }
  if (bytes.length > marketVideoMaxBytes) {
    if (context.mounted) await warn('market_video_too_large');
    return null;
  }
  return MarketVideoSelection(
    bytes: bytes,
    extension: extension,
    name: file.name,
  );
}

/// Muted looping video that plays while mostly visible. Tap toggles sound.
class MarketVideoView extends StatefulWidget {
  const MarketVideoView({
    super.key,
    required this.url,
    required this.visibilityKey,
    this.cover,
    this.fit = BoxFit.cover,
    this.paused,
    this.onTap,
  });

  final VoidCallback? onTap;
  final ValueListenable<bool>? paused;
  final String url;
  final String visibilityKey;
  final Widget? cover;
  final BoxFit fit;

  @override
  State<MarketVideoView> createState() => _MarketVideoViewState();
}

class _MarketVideoViewState extends State<MarketVideoView> with RouteAware {
  VideoPlayerController? _controller;
  bool _visible = false;
  bool _muted = true;
  bool _failed = false;
  ModalRoute<dynamic>? _route;

  bool get _held => widget.paused?.value ?? false;

  @override
  void initState() {
    super.initState();
    widget.paused?.addListener(_onHoldChanged);
  }

  @override
  void didUpdateWidget(MarketVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paused != widget.paused) {
      oldWidget.paused?.removeListener(_onHoldChanged);
      widget.paused?.addListener(_onHoldChanged);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == _route) return;
    if (_route != null) marketMediaRouteObserver.unsubscribe(this);
    _route = route;
    if (route != null) marketMediaRouteObserver.subscribe(this, route);
  }

  @override
  void didPushNext() {
    unawaited(_controller?.pause());
  }

  @override
  void didPopNext() {
    final controller = _controller;
    if (_visible &&
        !_held &&
        controller != null &&
        controller.value.isInitialized) {
      unawaited(controller.play());
    }
  }

  void _onHoldChanged() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_held) {
      unawaited(controller.pause());
    } else if (_visible) {
      unawaited(controller.play());
    }
  }

  Timer? _initTimer;
  Timer? _releaseTimer;

  Future<void> _ensureController() async {
    if (_controller != null || _failed) return;
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      if (!mounted || _controller != controller) {
        await controller.dispose();
        return;
      }
      setState(() {});
      if (_visible && !_held) unawaited(controller.play());
    } catch (_) {
      if (_controller == controller) _controller = null;
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  // Frees the decoder once the video is far off-screen so lists stay light.
  void _release() {
    final controller = _controller;
    if (controller == null || _visible) return;
    _controller = null;
    unawaited(controller.dispose());
    if (mounted) setState(() {});
  }

  void _onVisibility(VisibilityInfo info) {
    _visible = info.visibleFraction >= 0.6;
    if (_visible) {
      _releaseTimer?.cancel();
      final controller = _controller;
      if (controller == null) {
        // Waiting a moment avoids starting decoders during fast flings.
        _initTimer?.cancel();
        _initTimer = Timer(const Duration(milliseconds: 250), () {
          if (mounted && _visible) unawaited(_ensureController());
        });
      } else if (controller.value.isInitialized && !_held) {
        unawaited(controller.play());
      }
    } else {
      _initTimer?.cancel();
      unawaited(_controller?.pause());
      if (info.visibleFraction < 0.05) {
        _releaseTimer?.cancel();
        _releaseTimer = Timer(const Duration(seconds: 2), _release);
      }
    }
  }

  void _toggleSound() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() => _muted = !_muted);
    unawaited(controller.setVolume(_muted ? 0 : 1));
  }

  @override
  void dispose() {
    _initTimer?.cancel();
    _releaseTimer?.cancel();
    marketMediaRouteObserver.unsubscribe(this);
    widget.paused?.removeListener(_onHoldChanged);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return VisibilityDetector(
      key: Key('market-video-${widget.visibilityKey}'),
      onVisibilityChanged: _onVisibility,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap ?? _toggleSound,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.cover != null) widget.cover!,
            if (ready)
              FittedBox(
                fit: widget.fit,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
            if (!ready && !_failed)
              const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            Positioned(
              right: 10,
              bottom: 10,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
