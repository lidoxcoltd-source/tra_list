import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

import 'market_blob_stub.dart' if (dart.library.html) 'market_blob_web.dart';
import 'market_palette.dart';
import 'market_video.dart';

class LocalVideoInfo {
  const LocalVideoInfo({this.path, this.url, this.thumbnail});

  final String? path;
  final String? url;
  final Uint8List? thumbnail;

  bool get hasPreview => path != null || url != null;
}

/// Prepares a preview source: a temp file on mobile (plus a cover frame) or a
/// blob URL on web.
Future<LocalVideoInfo> prepareLocalVideo(
  Uint8List bytes,
  String extension,
) async {
  if (kIsWeb) {
    return LocalVideoInfo(
      url: createVideoBlobUrl(bytes, marketVideoContentType(extension)),
    );
  }
  try {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/market_preview_${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    Uint8List? thumb;
    try {
      thumb = await VideoCompress.getByteThumbnail(
        file.path,
        quality: 75,
        position: 500000,
      );
    } catch (error) {
      debugPrint('Video thumbnail failed: $error');
    }
    return LocalVideoInfo(path: file.path, thumbnail: thumb);
  } catch (error) {
    debugPrint('Video prepare failed: $error');
    return const LocalVideoInfo();
  }
}

/// Inline player for a locally picked video with play/pause and a seek bar.
class MarketLocalVideoPreview extends StatefulWidget {
  const MarketLocalVideoPreview({super.key, this.path, this.url});

  final String? path;
  final String? url;

  @override
  State<MarketLocalVideoPreview> createState() =>
      _MarketLocalVideoPreviewState();
}

class _MarketLocalVideoPreviewState extends State<MarketLocalVideoPreview> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.url != null
        ? VideoPlayerController.networkUrl(Uri.parse(widget.url!))
        : VideoPlayerController.file(File(widget.path!));
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();
      await _controller.setLooping(true);
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _toggle() {
    if (!_ready) return;
    _controller.value.isPlaying ? _controller.pause() : _controller.play();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(child: Icon(Icons.videocam_off_rounded)),
      );
    }
    if (!_ready) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final playing = _controller.value.isPlaying;
    final size = _controller.value.size;
    final ratio = size.width / size.height;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: Colors.black,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: GestureDetector(
                onTap: _toggle,
                child: AspectRatio(
                  aspectRatio: ratio.isFinite && ratio > 0 ? ratio : 16 / 9,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_controller),
                      if (!playing)
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            VideoProgressIndicator(
              _controller,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
              colors: const VideoProgressColors(
                playedColor: MarketPalette.blue,
                bufferedColor: Colors.white24,
                backgroundColor: Colors.white12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
