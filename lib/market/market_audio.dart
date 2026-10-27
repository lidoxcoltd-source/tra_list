import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'market_audio_trim_page.dart';
import 'market_palette.dart';
import 'market_models.dart';

const marketAudioMaxSeconds = 40;
const marketAudioMaxBytes = 5 * 1024 * 1024;
const marketAudioExtensions = ['mp3', 'm4a', 'aac', 'wav', 'ogg'];

String marketAudioContentType(String extension) =>
    switch (extension.toLowerCase()) {
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'aac' => 'audio/aac',
      'wav' => 'audio/wav',
      'ogg' => 'audio/ogg',
      _ => throw ArgumentError('Unsupported audio format.'),
    };

class MarketSound {
  const MarketSound({
    required this.id,
    required this.title,
    required this.url,
    this.coverUrl = '',
    this.durationMs = 0,
  });

  final String id;
  final String title;
  final String url;
  final String coverUrl;
  final int durationMs;

  factory MarketSound.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return MarketSound(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      url: (data['url'] ?? '').toString(),
      coverUrl: (data['coverUrl'] ?? '').toString(),
      durationMs: (data['durationMs'] as num?)?.toInt() ?? 0,
    );
  }
}

String formatMarketDuration(int milliseconds) {
  final total = (milliseconds / 1000).round();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// Square album-style cover with a music icon fallback.
class MarketSoundCover extends StatelessWidget {
  const MarketSoundCover({super.key, required this.url, this.size = 48});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: MarketPalette.blueSoft,
      child: Icon(
        Icons.music_note_rounded,
        color: MarketPalette.blue,
        size: size * 0.5,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? fallback
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

/// A sound chosen in the composer: either a library [url] or own [bytes].
class MarketAudioSelection {
  const MarketAudioSelection({
    required this.title,
    this.url = '',
    this.bytes,
    this.extension = '',
  });

  final String title;
  final String url;
  final Uint8List? bytes;
  final String extension;
}

/// One shared player so only a single sound plays at a time.
class MarketAudioPlayer {
  MarketAudioPlayer._();
  static final instance = MarketAudioPlayer._();

  final AudioPlayer _player = AudioPlayer();
  final ValueNotifier<bool> muted = ValueNotifier(false);
  String? _url;
  Timer? _cap;

  String? get currentUrl => _url;
  bool _wanted = false;
  bool _gestureHooked = false;

  // Browsers block autoplay; retry on the first tap/click if playback never started.
  void _hookGesture() {
    if (_gestureHooked) return;
    _gestureHooked = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute((event) {
      if (event is PointerDownEvent &&
          _wanted &&
          _url != null &&
          !_player.playing) {
        unawaited(_startPlayback());
      }
    });
  }

  Future<void> _startPlayback() async {
    try {
      await _player.play();
    } catch (e) {
      debugPrint('Market audio play failed: $e');
    }
  }

  Future<void> play(String url) async {
    _hookGesture();
    _wanted = true;
    try {
      if (_url != url) {
        await _player.setUrl(url);
        await _player.setLoopMode(LoopMode.off);
        _url = url;
      }
      await _player.setVolume(muted.value ? 0 : 1);
      await _player.seek(Duration.zero);
      _cap?.cancel();
      _cap = Timer(
        const Duration(seconds: marketAudioMaxSeconds),
        () => unawaited(_player.pause()),
      );
      unawaited(_startPlayback());
    } catch (e) {
      _url = null;
      debugPrint('Market audio load failed: $e');
    }
  }

  Future<void> pause() async {
    _wanted = false;
    try {
      await _player.pause();
    } catch (_) {}
  }

  Future<void> resume() async {
    if (_url == null) return;
    _wanted = true;
    unawaited(_startPlayback());
  }

  Future<void> stop() async {
    _wanted = false;
    _cap?.cancel();
    _url = null;
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> toggleMute() async {
    muted.value = !muted.value;
    try {
      await _player.setVolume(muted.value ? 0 : 1);
    } catch (_) {}
  }
}

/// Small pill showing the sound title with a mute toggle.
class MarketSoundBadge extends StatelessWidget {
  const MarketSoundBadge({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final player = MarketAudioPlayer.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: player.muted,
      builder: (context, muted, _) => InkWell(
        onTap: player.toggleMute,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                muted ? Icons.volume_off_rounded : Icons.music_note_rounded,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title.isEmpty ? 'market_sound'.tr : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Plays the post sound while at least 60% of [child] is on screen.
class MarketPostAudio extends StatefulWidget {
  const MarketPostAudio({super.key, required this.post, required this.child});

  final MarketPost post;
  final Widget child;

  @override
  State<MarketPostAudio> createState() => _MarketPostAudioState();
}

class _MarketPostAudioState extends State<MarketPostAudio> {
  @override
  void dispose() {
    final player = MarketAudioPlayer.instance;
    if (player.currentUrl == widget.post.audioUrl) unawaited(player.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    if (post.audioUrl.isEmpty) return widget.child;
    final player = MarketAudioPlayer.instance;
    return VisibilityDetector(
      key: Key('market-audio-${post.id}'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction >= 0.6) {
          if (player.currentUrl != post.audioUrl) {
            unawaited(player.play(post.audioUrl));
          } else {
            unawaited(player.resume());
          }
        } else if (player.currentUrl == post.audioUrl) {
          unawaited(player.stop());
        }
      },
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned(
            left: 10,
            top: 10,
            child: MarketSoundBadge(title: post.audioTitle),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for choosing a library sound or uploading your own file.
Future<MarketAudioSelection?> pickMarketSound(BuildContext context) =>
    showModalBottomSheet<MarketAudioSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: MarketPalette.surface,
      builder: (_) => const _SoundPickerSheet(),
    );

class _SoundPickerSheet extends StatefulWidget {
  const _SoundPickerSheet();

  @override
  State<_SoundPickerSheet> createState() => _SoundPickerSheetState();
}

class _SoundPickerSheetState extends State<_SoundPickerSheet> {
  final _preview = AudioPlayer();
  String? _previewUrl;

  @override
  void initState() {
    super.initState();
    unawaited(MarketAudioPlayer.instance.pause());
  }

  @override
  void dispose() {
    unawaited(_preview.dispose());
    super.dispose();
  }

  Future<void> _togglePreview(MarketSound sound) async {
    try {
      if (_previewUrl == sound.url && _preview.playing) {
        await _preview.pause();
      } else {
        if (_previewUrl != sound.url) {
          _previewUrl = sound.url;
          await _preview.setUrl(sound.url);
        }
        await _preview.seek(Duration.zero);
        unawaited(_preview.play());
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _pickOwn() async {
    final edit = await pickAndEditMarketSound(context);
    if (edit == null || !mounted) return;
    Navigator.pop(
      context,
      MarketAudioSelection(
        title: edit.title.length > 60
            ? edit.title.substring(0, 60)
            : edit.title,
        bytes: edit.bytes,
        extension: edit.extension,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: MarketPalette.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                const Icon(Icons.music_note_rounded, color: MarketPalette.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'market_sound_pick'.tr,
                    style: const TextStyle(
                      color: MarketPalette.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: OutlinedButton.icon(
              onPressed: _pickOwn,
              style: OutlinedButton.styleFrom(
                foregroundColor: MarketPalette.text,
                side: const BorderSide(color: MarketPalette.border),
                minimumSize: const Size.fromHeight(46),
              ),
              icon: const Icon(Icons.upload_file_rounded),
              label: Text('market_sound_upload'.tr),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'market_sound_limits'.trParams({
                  'seconds': '$marketAudioMaxSeconds',
                }),
                style: const TextStyle(
                  color: MarketPalette.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: MarketPalette.border),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('marketSounds')
                  .orderBy('createdAt', descending: true)
                  .limit(100)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final sounds = snapshot.data!.docs
                    .map(MarketSound.fromDoc)
                    .toList();
                if (sounds.isEmpty) {
                  return Center(
                    child: Text(
                      'market_sound_empty'.tr,
                      style: const TextStyle(color: MarketPalette.textMuted),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: sounds.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: MarketPalette.border),
                  itemBuilder: (context, index) {
                    final sound = sounds[index];
                    final playing =
                        _previewUrl == sound.url && _preview.playing;
                    return ListTile(
                      leading: InkWell(
                        onTap: () => _togglePreview(sound),
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            MarketSoundCover(url: sound.coverUrl, size: 48),
                            Icon(
                              playing
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.play_circle_fill_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ],
                        ),
                      ),
                      title: Text(
                        sound.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: MarketPalette.text),
                      ),
                      subtitle: sound.durationMs > 0
                          ? Text(
                              formatMarketDuration(sound.durationMs),
                              style: const TextStyle(
                                color: MarketPalette.textMuted,
                                fontSize: 12,
                              ),
                            )
                          : null,
                      trailing: FilledButton(
                        onPressed: () => Navigator.pop(
                          context,
                          MarketAudioSelection(
                            title: sound.title,
                            url: sound.url,
                          ),
                        ),
                        child: Text('market_sound_use'.tr),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
