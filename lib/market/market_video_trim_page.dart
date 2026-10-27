import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

import 'market_palette.dart';
import 'market_video.dart';

/// Largest source file accepted before trimming/compression (mobile only).
const marketVideoSourceMaxBytes = 400 * 1024 * 1024;

class MarketVideoEditorPage extends StatefulWidget {
  const MarketVideoEditorPage({
    super.key,
    required this.path,
    required this.fileName,
    required this.extension,
  });

  final String path;
  final String fileName;
  final String extension;

  @override
  State<MarketVideoEditorPage> createState() => _MarketVideoEditorPageState();
}

class _MarketVideoEditorPageState extends State<MarketVideoEditorPage> {
  VideoPlayerController? _controller;
  Subscription? _progressSub;
  final _progress = ValueNotifier<double>(0);
  double _total = 0;
  double _start = 0;
  double _end = 0;
  bool _loading = true;
  bool _failed = false;
  bool _processing = false;
  bool _muted = false;
  late final int _sourceBytes;

  double get _maxSpan => marketVideoMaxSeconds.toDouble();

  @override
  void initState() {
    super.initState();
    _sourceBytes = File(widget.path).lengthSync();
    _load();
  }

  @override
  void dispose() {
    _progressSub?.unsubscribe();
    if (_processing) unawaited(VideoCompress.cancelCompression());
    _controller?.removeListener(_loop);
    unawaited(_controller?.dispose());
    _progress.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final controller = VideoPlayerController.file(File(widget.path));
    try {
      await controller.initialize();
      final total = controller.value.duration.inMilliseconds / 1000;
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setVolume(1);
      await controller.setLooping(false);
      controller.addListener(_loop);
      setState(() {
        _controller = controller;
        _total = total;
        _end = total > _maxSpan ? _maxSpan : total;
        _loading = false;
      });
      unawaited(controller.play());
    } catch (error) {
      debugPrint('Video editor load failed: $error');
      await controller.dispose();
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  // Keeps the preview inside the selected range.
  void _loop() {
    final controller = _controller;
    if (controller == null || !controller.value.isPlaying) return;
    final position = controller.value.position.inMilliseconds / 1000;
    if (position >= _end || position < _start - 0.3) {
      controller.seekTo(Duration(milliseconds: (_start * 1000).round()));
    }
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || _processing) return;
    if (controller.value.isPlaying) {
      controller.pause();
      return;
    }
    final position = controller.value.position.inMilliseconds / 1000;
    if (position >= _end - 0.1 || position < _start) {
      controller.seekTo(Duration(milliseconds: (_start * 1000).round()));
    }
    controller.play();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _controller?.setVolume(_muted ? 0 : 1);
  }

  void _setStartHere() {
    final position = (_controller?.value.position.inMilliseconds ?? 0) / 1000;
    if (position >= _end - 0.5) return;
    _onRange(RangeValues(position, _end));
  }

  void _setEndHere() {
    final position = (_controller?.value.position.inMilliseconds ?? 0) / 1000;
    if (position <= _start + 0.5) return;
    _onRange(RangeValues(_start, position));
    _controller?.seekTo(Duration(milliseconds: (_start * 1000).round()));
  }

  void _resetRange() {
    setState(() {
      _start = 0;
      _end = _total > _maxSpan ? _maxSpan : _total;
    });
    _controller?.seekTo(Duration.zero);
  }

  String _format(double seconds) {
    final whole = seconds.floor();
    final tenth = ((seconds - whole) * 10).floor();
    return '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}.$tenth';
  }

  String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  void _onRange(RangeValues values) {
    var start = values.start;
    var end = values.end;
    if (end - start > _maxSpan) {
      if ((start - _start).abs() > (end - _end).abs()) {
        end = start + _maxSpan;
      } else {
        start = end - _maxSpan;
      }
    }
    setState(() {
      _start = start;
      _end = end;
    });
    _controller?.seekTo(Duration(milliseconds: (start * 1000).round()));
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _confirm() async {
    final span = _end - _start;
    final untouched = _start < 0.05 && (_total - _end) < 0.05;
    final fits = span <= _maxSpan + 0.05;
    final ext = widget.extension;
    const compressAbove = 8 * 1024 * 1024;
    if (untouched &&
        fits &&
        _sourceBytes <= compressAbove &&
        marketVideoExtensions.contains(ext)) {
      await _finish(File(widget.path), ext);
      return;
    }
    await _controller?.pause();
    setState(() => _processing = true);
    _progress.value = 0;
    _progressSub = VideoCompress.compressProgress$.subscribe((value) {
      _progress.value = (value / 100).clamp(0, 1);
    });
    try {
      const qualities = [
        VideoQuality.Res960x540Quality,
        VideoQuality.Res640x480Quality,
        VideoQuality.LowQuality,
      ];
      File? result;
      for (final quality in qualities) {
        final info = await VideoCompress.compressVideo(
          widget.path,
          quality: quality,
          startTime: _start.floor(),
          duration: span.ceil().clamp(1, marketVideoMaxSeconds),
          deleteOrigin: false,
          includeAudio: true,
        );
        final file = info?.file;
        if (file == null) continue;
        if (await file.length() <= marketVideoMaxBytes) {
          result = file;
          break;
        }
      }
      if (result == null) {
        if (mounted) _snack('market_video_too_large'.tr);
        return;
      }
      await _finish(result, 'mp4');
    } catch (error) {
      debugPrint('Video processing failed: $error');
      if (mounted) _snack('market_video_invalid'.tr);
    } finally {
      _progressSub?.unsubscribe();
      _progressSub = null;
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _finish(File file, String extension) async {
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    Navigator.of(context).pop(
      MarketVideoSelection(
        bytes: bytes,
        extension: extension,
        name: widget.fileName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final span = _end - _start;
    return PopScope(
      canPop: !_processing,
      child: Scaffold(
        backgroundColor: MarketPalette.canvas,
        appBar: AppBar(
          backgroundColor: MarketPalette.topBar,
          foregroundColor: Colors.white,
          title: Text('market_video_edit_title'.tr),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _failed || controller == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'market_video_invalid'.tr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: MarketPalette.text),
                  ),
                ),
              )
            : SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: GestureDetector(
                          onTap: _togglePlay,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Center(
                                child: AspectRatio(
                                  aspectRatio: controller.value.aspectRatio,
                                  child: VideoPlayer(controller),
                                ),
                              ),
                              ValueListenableBuilder<VideoPlayerValue>(
                                valueListenable: controller,
                                builder: (context, value, _) => value.isPlaying
                                    ? const SizedBox.shrink()
                                    : Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 40,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ValueListenableBuilder<VideoPlayerValue>(
                            valueListenable: controller,
                            builder: (context, value, _) {
                              final position =
                                  value.position.inMilliseconds / 1000;
                              final span = _end - _start;
                              final progress = span <= 0
                                  ? 0.0
                                  : ((position - _start) / span).clamp(
                                      0.0,
                                      1.0,
                                    );
                              return Row(
                                children: [
                                  IconButton.filled(
                                    onPressed: _processing ? null : _togglePlay,
                                    icon: Icon(
                                      value.isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        minHeight: 5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    _format(position),
                                    style: const TextStyle(
                                      color: MarketPalette.text,
                                      fontSize: 12,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _processing ? null : _toggleMute,
                                    icon: Icon(
                                      _muted
                                          ? Icons.volume_off_rounded
                                          : Icons.volume_up_rounded,
                                      color: MarketPalette.text,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              ActionChip(
                                avatar: const Icon(
                                  Icons.vertical_align_top_rounded,
                                  size: 16,
                                ),
                                label: Text('market_video_set_start'.tr),
                                onPressed: _processing ? null : _setStartHere,
                              ),
                              ActionChip(
                                avatar: const Icon(
                                  Icons.vertical_align_bottom_rounded,
                                  size: 16,
                                ),
                                label: Text('market_video_set_end'.tr),
                                onPressed: _processing ? null : _setEndHere,
                              ),
                              ActionChip(
                                avatar: const Icon(
                                  Icons.restart_alt_rounded,
                                  size: 16,
                                ),
                                label: Text('market_sound_reset'.tr),
                                onPressed: _processing ? null : _resetRange,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _stat('market_sound_total'.tr, _format(_total)),
                              _stat(
                                'market_sound_selected'.tr,
                                '${_format(span)} / ${marketVideoMaxSeconds}s',
                              ),
                              _stat(
                                'market_sound_result_size'.tr,
                                '${_mb(_sourceBytes)} MB',
                              ),
                            ],
                          ),
                          RangeSlider(
                            min: 0,
                            max: _total <= 0 ? 1 : _total,
                            values: RangeValues(_start, _end),
                            onChanged: _processing ? null : _onRange,
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _format(_start),
                                style: const TextStyle(
                                  color: MarketPalette.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                _format(_end),
                                style: const TextStyle(
                                  color: MarketPalette.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'market_video_compress_hint'.tr,
                            style: const TextStyle(
                              color: MarketPalette.textMuted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_processing)
                            ValueListenableBuilder<double>(
                              valueListenable: _progress,
                              builder: (context, value, _) => Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  LinearProgressIndicator(
                                    value: value <= 0 ? null : value,
                                    minHeight: 6,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'market_video_processing'.tr,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: MarketPalette.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: _confirm,
                              icon: const Icon(Icons.check_rounded),
                              label: Text('market_sound_use'.tr),
                            ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: MarketPalette.textMuted, fontSize: 11),
        ),
        Text(
          value,
          style: const TextStyle(
            color: MarketPalette.text,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
