import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';

import 'market_audio.dart';
import 'market_audio_trim_page.dart';
import 'market_palette.dart';

class AdminMarketSoundsPage extends StatefulWidget {
  const AdminMarketSoundsPage({super.key});

  @override
  State<AdminMarketSoundsPage> createState() => _AdminMarketSoundsPageState();
}

class _AdminMarketSoundsPageState extends State<AdminMarketSoundsPage> {
  final _search = TextEditingController();
  final _player = AudioPlayer();
  StreamSubscription<PlayerState>? _sub;
  bool _busy = false;
  String? _playingId;
  bool _playing = false;
  String _query = '';

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      FirebaseFirestore.instance
          .collection('marketSounds')
          .orderBy('createdAt', descending: true)
          .snapshots();

  @override
  void initState() {
    super.initState();
    unawaited(MarketAudioPlayer.instance.stop());
    _sub = _player.playerStateStream.listen((state) {
      final playing =
          state.playing && state.processingState != ProcessingState.completed;
      if (!mounted) return;
      setState(() {
        _playing = playing;
        if (!playing && state.processingState == ProcessingState.completed) {
          _playingId = null;
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    unawaited(_player.dispose());
    _search.dispose();
    super.dispose();
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _togglePlay(MarketSound sound) async {
    try {
      if (_playingId == sound.id) {
        if (_playing) {
          await _player.pause();
        } else {
          unawaited(_player.play());
        }
        return;
      }
      setState(() => _playingId = sound.id);
      await _player.setUrl(sound.url);
      unawaited(_player.play());
    } catch (error) {
      if (mounted) {
        setState(() => _playingId = null);
        _message(error.toString());
      }
    }
  }

  Future<String> _uploadCover(
    String soundId,
    Uint8List bytes,
    String extension,
  ) async {
    final ext = marketCoverExtensions.contains(extension) ? extension : 'jpg';
    final ref = FirebaseStorage.instance.ref(
      'marketSounds/${soundId}_cover.$ext',
    );
    await ref.putData(
      bytes,
      SettableMetadata(contentType: marketCoverContentType(ext)),
    );
    return ref.getDownloadURL();
  }

  Future<void> _upload() async {
    final edit = await pickAndEditMarketSound(context, withCover: true);
    if (edit == null || !mounted) return;
    await _player.stop();
    setState(() => _busy = true);
    try {
      final doc = FirebaseFirestore.instance.collection('marketSounds').doc();
      final ref = FirebaseStorage.instance.ref(
        'marketSounds/${doc.id}.${edit.extension}',
      );
      await ref.putData(
        edit.bytes,
        SettableMetadata(contentType: marketAudioContentType(edit.extension)),
      );
      final url = await ref.getDownloadURL();
      final cover = edit.coverBytes;
      final coverUrl = cover == null
          ? ''
          : await _uploadCover(doc.id, cover, edit.coverExtension);
      await doc.set({
        'title': edit.title,
        'url': url,
        if (coverUrl.isNotEmpty) 'coverUrl': coverUrl,
        if (edit.duration.inMilliseconds > 0)
          'durationMs': edit.duration.inMilliseconds,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) _message('market_sound_saved'.tr);
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    final title = TextEditingController(text: (data['title'] ?? '').toString());
    var coverUrl = (data['coverUrl'] ?? '').toString();
    Uint8List? newCover;
    var newCoverExt = 'jpg';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('market_sound_edit'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, maxLength: 80),
              const SizedBox(height: 8),
              Row(
                children: [
                  newCover == null
                      ? MarketSoundCover(url: coverUrl, size: 64)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            newCover!,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          ),
                        ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: marketCoverExtensions,
                          withData: true,
                        );
                        final file = result?.files.single;
                        final bytes = file?.bytes;
                        if (file == null || bytes == null) return;
                        if (bytes.length > marketCoverMaxBytes) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('market_sound_cover_large'.tr),
                              ),
                            );
                          }
                          return;
                        }
                        setLocal(() {
                          newCover = bytes;
                          newCoverExt = (file.extension ?? 'jpg').toLowerCase();
                        });
                      },
                      icon: const Icon(Icons.image_outlined),
                      label: Text('market_sound_cover_change'.tr),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('cancel'.tr),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('market_sound_admin_save'.tr),
            ),
          ],
        ),
      ),
    );
    final newTitle = title.text.trim();
    title.dispose();
    if (saved != true || newTitle.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final update = <String, dynamic>{'title': newTitle};
      final cover = newCover;
      if (cover != null) {
        update['coverUrl'] = await _uploadCover(doc.id, cover, newCoverExt);
      }
      await doc.reference.update(update);
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('market_sound_delete_confirm'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('delete'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final data = doc.data();
    try {
      if (_playingId == doc.id) await _player.stop();
      await doc.reference.delete();
      for (final key in const ['url', 'coverUrl']) {
        final url = (data[key] ?? '').toString();
        if (url.isEmpty) continue;
        try {
          await FirebaseStorage.instance.refFromURL(url).delete();
        } catch (_) {}
      }
    } catch (error) {
      if (mounted) _message(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: MarketPalette.darkTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: MarketPalette.canvas,
        appBar: AppBar(
          backgroundColor: MarketPalette.topBar,
          foregroundColor: Colors.white,
          title: Text('market_sound_admin_title'.tr),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _busy ? null : _upload,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_rounded),
          label: Text('market_sound_upload'.tr),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('explore_error'.tr));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final all = snapshot.data!.docs;
            final term = _query.trim().toLowerCase();
            final docs = [
              for (final doc in all)
                if (term.isEmpty ||
                    (doc.data()['title'] ?? '')
                        .toString()
                        .toLowerCase()
                        .contains(term))
                  doc,
            ];
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: TextField(
                    controller: _search,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'market_sound_search'.tr,
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'market_sound_count'.trParams({'n': '${all.length}'}),
                      style: const TextStyle(
                        color: MarketPalette.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: docs.isEmpty
                      ? Center(
                          child: Text(
                            'market_sound_empty'.tr,
                            style: const TextStyle(
                              color: MarketPalette.textMuted,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final doc = docs[index];
                            final sound = MarketSound.fromDoc(doc);
                            final active = _playingId == sound.id;
                            return Card(
                              color: MarketPalette.surface,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: active
                                      ? MarketPalette.blue
                                      : MarketPalette.border,
                                ),
                              ),
                              child: ListTile(
                                leading: InkWell(
                                  onTap: () => _togglePlay(sound),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      MarketSoundCover(
                                        url: sound.coverUrl,
                                        size: 52,
                                      ),
                                      Icon(
                                        active && _playing
                                            ? Icons.pause_circle_filled_rounded
                                            : Icons.play_circle_fill_rounded,
                                        color: Colors.white,
                                        size: 30,
                                      ),
                                    ],
                                  ),
                                ),
                                title: Text(
                                  sound.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: MarketPalette.text,
                                    fontWeight: FontWeight.w600,
                                  ),
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
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _edit(doc),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _delete(doc),
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: MarketPalette.red,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
