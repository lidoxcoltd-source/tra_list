import 'dart:async';
import 'dart:io';

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
    final mime = marketVideoContentType(extension);
    final url = createVideoBlobUrl(bytes, mime);
    final thumbnail = await createVideoThumbnail(bytes, mime);
    return LocalVideoInfo(url: url, thumbnail: thumbnail);
  }
  try {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/market_preview_${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    final thumb = await _extractNativeThumbnail(file.path);
    return LocalVideoInfo(path: file.path, thumbnail: thumb);
  } catch (error) {
    debugPrint('Video prepare failed: $error');
    return const LocalVideoInfo();
  }
}

/// Extracts a poster frame from a video byte buffer on the current platform.
Future<Uint8List?> extractVideoThumbnail(
  Uint8List bytes,
  String extension,
) async {
  if (kIsWeb) {
    return createVideoThumbnail(bytes, marketVideoContentType(extension));
  }
  try {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/market_backfill_${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    try {
      return await _extractNativeThumbnail(file.path);
    } finally {
      await file.delete().catchError((_) => file);
    }
  } catch (error) {
    debugPrint('Video thumbnail extraction failed: $error');
    return null;
  }
}

Future<Uint8List?> _extractNativeThumbnail(String path) async {
  try {
    return await VideoCompress.getByteThumbnail(
      path,
      quality: 75,
      position: 500000,
    );
  } catch (error) {
    debugPrint('Video thumbnail failed: $error');
    return null;
  }
}

/// Inline player for a locally picked video with play/pause and a seek bar.
class MarketLocalVideoPreview extends StatefulWidget {
  const MarketLocalVideoPreview({
    super.key,
    this.path,
    this.url,
    this.thumbnail,
  });

  final String? path;
  final String? url;
  final Uint8List? thumbnail;

  @override
  State<MarketLocalVideoPreview> createState() =>
      _MarketLocalVideoPreviewState();
}

class _MarketLocalVideoPreviewState extends State<MarketLocalVideoPreview> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;
  String _error = '';

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
    } catch (error) {
      debugPrint('Video preview failed: $error');
      if (mounted) {
        setState(() {
          _failed = true;
          _error = '$error';
        });
      }
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
    final poster = widget.thumbnail == null
        ? const MarketMediaPlaceholder(icon: Icons.play_circle_outline)
        : Image.memory(
            widget.thumbnail!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) =>
                const MarketMediaPlaceholder(icon: Icons.play_circle_outline),
          );
    if (_failed) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            poster,
            const Icon(Icons.videocam_off_rounded, color: Colors.white),
            if (kIsWeb && _error.isNotEmpty)
              Align(
                alignment: Alignment.bottomCenter,
                child: Text(
                  _error,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ),
          ],
        ),
      );
    }
    if (!_ready) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              poster,
              const Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
                      ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: _controller,
                        builder: (context, value, _) {
                          final firstFramePlaying =
                              value.position >
                              const Duration(milliseconds: 120);
                          return IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: firstFramePlaying ? 0 : 1,
                              duration: const Duration(milliseconds: 180),
                              child: poster,
                            ),
                          );
                        },
                      ),
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
