import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';

import 'market_audio.dart';
import 'market_audio_trim.dart';
import 'market_palette.dart';

const marketAudioSourceMaxBytes = 60 * 1024 * 1024;
const marketCoverMaxBytes = 2 * 1024 * 1024;
const marketCoverExtensions = ['jpg', 'jpeg', 'png', 'webp'];

String marketCoverContentType(String extension) => switch (extension) {
  'png' => 'image/png',
  'webp' => 'image/webp',
  _ => 'image/jpeg',
};

class MarketAudioEdit {
  const MarketAudioEdit({
    required this.title,
    required this.bytes,
    required this.extension,
    required this.duration,
    this.coverBytes,
    this.coverExtension = '',
  });

  final String title;
  final Uint8List bytes;
  final String extension;
  final Duration duration;
  final Uint8List? coverBytes;
  final String coverExtension;
}

/// Lets the user pick any audio file (up to 60 MB), then trim it to fit.
Future<MarketAudioEdit?> pickAndEditMarketSound(
  BuildContext context, {
  bool withCover = false,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: marketAudioExtensions,
    withData: true,
  );
  final file = result?.files.single;
  final bytes = file?.bytes;
  if (file == null || bytes == null || !context.mounted) return null;
  if (bytes.length > marketAudioSourceMaxBytes) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('market_sound_file_huge'.tr)));
    return null;
  }
  return Navigator.of(context).push<MarketAudioEdit>(
    MaterialPageRoute(
      builder: (_) => MarketAudioEditorPage(
        bytes: bytes,
        extension: (file.extension ?? '').toLowerCase(),
        fileName: file.name,
        withCover: withCover,
      ),
    ),
  );
}

class _BytesSource extends StreamAudioSource {
  _BytesSource(this.bytes, this.type);

  final Uint8List bytes;
  final String type;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final from = start ?? 0;
    final to = end ?? bytes.length;
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: to - from,
      offset: from,
      stream: Stream.value(bytes.sublist(from, to)),
      contentType: type,
    );
  }
}

class MarketAudioEditorPage extends StatefulWidget {
  const MarketAudioEditorPage({
    super.key,
    required this.bytes,
    required this.extension,
    required this.fileName,
    this.withCover = false,
  });

  final Uint8List bytes;
  final String extension;
  final String fileName;
  final bool withCover;

  @override
  State<MarketAudioEditorPage> createState() => _MarketAudioEditorPageState();
}

class _MarketAudioEditorPageState extends State<MarketAudioEditorPage> {
  late final TextEditingController _title;
  late final MarketAudioClip? _clip;
  final AudioPlayer _preview = AudioPlayer();
  StreamSubscription<PlayerState>? _sub;
  double _start = 0;
  double _end = 0;
  bool _playing = false;
  Uint8List? _coverBytes;
  String _coverExtension = '';

  double get _duration => _clip?.durationSec ?? 0;
  double get _maxSpan => marketAudioMaxSeconds.toDouble();

  int get _size {
    final clip = _clip;
    return clip == null ? widget.bytes.length : clip.cutSize(_start, _end);
  }

  bool get _fits => _size <= marketAudioMaxBytes;

  @override
  void initState() {
    super.initState();
    final name = widget.fileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    _title = TextEditingController(
      text: name.length > 60 ? name.substring(0, 60) : name,
    );
    _clip = parseMarketAudio(widget.bytes, widget.extension);
    final clip = _clip;
    if (clip != null) {
      _end = clip.durationSec < _maxSpan ? clip.durationSec : _maxSpan;
      if (!_fits) _autoFit();
    }
    unawaited(MarketAudioPlayer.instance.pause());
    _sub = _preview.playerStateStream.listen((state) {
      final playing =
          state.playing && state.processingState != ProcessingState.completed;
      if (mounted && playing != _playing) setState(() => _playing = playing);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    unawaited(_preview.dispose());
    _title.dispose();
    super.dispose();
  }

  void _autoFit() {
    final clip = _clip;
    if (clip == null) return;
    var low = _start;
    var high = (_start + _maxSpan).clamp(0, clip.durationSec).toDouble();
    if (clip.cutSize(_start, high) <= marketAudioMaxBytes) {
      setState(() => _end = high);
      return;
    }
    for (var i = 0; i < 24; i++) {
      final mid = (low + high) / 2;
      if (clip.cutSize(_start, mid) <= marketAudioMaxBytes) {
        low = mid;
      } else {
        high = mid;
      }
    }
    setState(() => _end = low < _start + 0.5 ? _start + 0.5 : low);
  }

  void _onRange(RangeValues values) {
    var start = values.start;
    var end = values.end;
    if (end - start > _maxSpan) {
      if (start != _start) {
        end = start + _maxSpan;
      } else {
        start = end - _maxSpan;
      }
    }
    setState(() {
      _start = start;
      _end = end;
    });
    if (_playing) unawaited(_preview.stop());
  }

  Future<void> _togglePreview() async {
    final clip = _clip;
    try {
      if (_playing) {
        await _preview.stop();
        return;
      }
      final bytes = clip == null ? widget.bytes : clip.cut(_start, _end);
      final type =
          clip?.contentType ?? marketAudioContentType(widget.extension);
      try {
        await _preview.setAudioSource(_BytesSource(bytes, type));
      } catch (first) {
        debugPrint('Sound preview (stream source) failed: $first');
        await _preview.setAudioSource(
          AudioSource.uri(Uri.dataFromBytes(bytes, mimeType: type)),
        );
      }
      unawaited(_preview.play());
    } catch (error) {
      debugPrint('Sound preview failed: $error');
      if (mounted) _snack('${'market_sound_unreadable'.tr}: $error');
    }
  }

  Future<void> _pickCover() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: marketCoverExtensions,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null || !mounted) return;
    if (bytes.length > marketCoverMaxBytes) {
      _snack('market_sound_cover_large'.tr);
      return;
    }
    setState(() {
      _coverBytes = bytes;
      _coverExtension = (file.extension ?? 'jpg').toLowerCase();
    });
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _done() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _snack('market_sound_title_required'.tr);
      return;
    }
    final clip = _clip;
    if (clip == null && widget.bytes.length > marketAudioMaxBytes) {
      _snack('market_sound_no_trim'.tr);
      return;
    }
    if (!_fits) {
      _snack(
        'market_sound_still_big'.trParams({
          'mb': (marketAudioMaxBytes / 1024 / 1024).toStringAsFixed(0),
        }),
      );
      return;
    }
    final Uint8List bytes;
    final Duration duration;
    if (clip == null) {
      bytes = widget.bytes;
      duration = Duration.zero;
    } else {
      bytes = clip.cut(_start, _end);
      duration = Duration(milliseconds: ((_end - _start) * 1000).round());
    }
    Navigator.pop(
      context,
      MarketAudioEdit(
        title: title.length > 80 ? title.substring(0, 80) : title,
        bytes: bytes,
        extension: clip?.extension ?? widget.extension,
        duration: duration,
        coverBytes: _coverBytes,
        coverExtension: _coverExtension,
      ),
    );
  }

  String _fmt(double seconds) {
    final total = seconds.round();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';

  Widget _stat(String label, String value, {Color? color}) => Expanded(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: MarketPalette.surface,
        border: Border.all(color: MarketPalette.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: color ?? MarketPalette.text,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MarketPalette.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _coverPicker() {
    final cover = _coverBytes;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 72,
            height: 72,
            child: cover == null
                ? const ColoredBox(
                    color: MarketPalette.surfaceRaised,
                    child: Icon(
                      Icons.album_rounded,
                      color: MarketPalette.textMuted,
                      size: 34,
                    ),
                  )
                : Image.memory(cover, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _pickCover,
                icon: const Icon(Icons.image_outlined),
                label: Text(
                  cover == null
                      ? 'market_sound_cover_add'.tr
                      : 'market_sound_cover_change'.tr,
                ),
              ),
              if (cover != null)
                IconButton(
                  onPressed: () => setState(() => _coverBytes = null),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final clip = _clip;
    final canTrim = clip != null && _duration > 0;
    return Theme(
      data: MarketPalette.darkTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: MarketPalette.canvas,
        appBar: AppBar(
          backgroundColor: MarketPalette.topBar,
          foregroundColor: Colors.white,
          title: Text('market_sound_trim_title'.tr),
          actions: [
            TextButton(
              onPressed: _done,
              child: Text(
                'market_sound_use'.tr,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _title,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: 'market_sound_admin_title_label'.tr,
                prefixIcon: const Icon(Icons.music_note_rounded),
              ),
            ),
            if (widget.withCover) ...[
              const SizedBox(height: 4),
              _coverPicker(),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                _stat(
                  'market_sound_total'.tr,
                  canTrim ? _fmt(_duration) : '--',
                ),
                const SizedBox(width: 8),
                _stat(
                  'market_sound_selected'.tr,
                  canTrim ? _fmt(_end - _start) : '--',
                ),
                const SizedBox(width: 8),
                _stat(
                  'market_sound_result_size'.tr,
                  _mb(_size),
                  color: _fits ? MarketPalette.mint : MarketPalette.red,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!canTrim)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: MarketPalette.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: MarketPalette.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'market_sound_no_trim'.tr,
                    style: const TextStyle(color: MarketPalette.textMuted),
                  ),
                ),
              )
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _fmt(_start),
                    style: const TextStyle(color: MarketPalette.text),
                  ),
                  Text(
                    _fmt(_end),
                    style: const TextStyle(color: MarketPalette.text),
                  ),
                ],
              ),
              RangeSlider(
                values: RangeValues(_start, _end),
                min: 0,
                max: _duration,
                onChanged: _onRange,
              ),
              Text(
                'market_sound_limits'.trParams({
                  'seconds': '$marketAudioMaxSeconds',
                }),
                style: const TextStyle(
                  color: MarketPalette.textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _autoFit,
                    icon: const Icon(Icons.auto_fix_high_rounded),
                    label: Text('market_sound_autofit'.tr),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _start = 0;
                      _end = _duration < _maxSpan ? _duration : _maxSpan;
                    }),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: Text('market_sound_reset'.tr),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _togglePreview,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: Icon(
                _playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
              ),
              label: Text(
                _playing ? 'market_sound_stop'.tr : 'market_sound_preview'.tr,
              ),
            ),
            if (!_fits) ...[
              const SizedBox(height: 10),
              Text(
                'market_sound_still_big'.trParams({
                  'mb': (marketAudioMaxBytes / 1024 / 1024).toStringAsFixed(0),
                }),
                style: const TextStyle(color: MarketPalette.red, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
