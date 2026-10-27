import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'market_audio.dart';
import 'market_audio_trim.dart';
import 'market_audio_trim_page.dart';

class _Box {
  const _Box(this.type, this.start, this.end);

  final String type;
  final int start;
  final int end;
}

List<_Box> _boxes(ByteData data, int start, int end) {
  final result = <_Box>[];
  var offset = start;
  while (offset + 8 <= end) {
    var size = data.getUint32(offset);
    final type = String.fromCharCodes([
      for (var i = 4; i < 8; i++) data.getUint8(offset + i),
    ]);
    var header = 8;
    if (size == 1) {
      if (offset + 16 > end) break;
      size = data.getUint64(offset + 8);
      header = 16;
    } else if (size == 0) {
      size = end - offset;
    }
    if (size < header || offset + size > end) break;
    result.add(_Box(type, offset + header, offset + size));
    offset += size;
  }
  return result;
}

_Box? _find(List<_Box> boxes, String type) {
  for (final box in boxes) {
    if (box.type == type) return box;
  }
  return null;
}

int _descriptorLength(ByteData data, List<int> cursor) {
  var length = 0;
  for (var i = 0; i < 4; i++) {
    final value = data.getUint8(cursor[0]++);
    length = (length << 7) | (value & 0x7f);
    if (value & 0x80 == 0) break;
  }
  return length;
}

/// Reads the AAC track of an MP4/M4V/MOV file and rewraps it as an ADTS
/// stream (.aac). Returns null when there is no AAC audio track.
Uint8List? extractMp4Aac(Uint8List bytes) {
  try {
    final data = ByteData.sublistView(bytes);
    final moov = _find(_boxes(data, 0, bytes.length), 'moov');
    if (moov == null) return null;
    for (final trak in _boxes(data, moov.start, moov.end)) {
      if (trak.type != 'trak') continue;
      final mdia = _find(_boxes(data, trak.start, trak.end), 'mdia');
      if (mdia == null) continue;
      final mdiaBoxes = _boxes(data, mdia.start, mdia.end);
      final hdlr = _find(mdiaBoxes, 'hdlr');
      if (hdlr == null) continue;
      final handler = String.fromCharCodes([
        for (var i = 8; i < 12; i++) data.getUint8(hdlr.start + i),
      ]);
      if (handler != 'soun') continue;
      final minf = _find(mdiaBoxes, 'minf');
      if (minf == null) continue;
      final stbl = _find(_boxes(data, minf.start, minf.end), 'stbl');
      if (stbl == null) continue;
      final result = _extractFromTable(bytes, data, stbl);
      if (result != null) return result;
    }
  } catch (_) {}
  return null;
}

Uint8List? _extractFromTable(Uint8List bytes, ByteData data, _Box stbl) {
  final table = _boxes(data, stbl.start, stbl.end);
  final stsd = _find(table, 'stsd');
  final stsz = _find(table, 'stsz');
  final stsc = _find(table, 'stsc');
  final stco = _find(table, 'stco');
  final co64 = _find(table, 'co64');
  if (stsd == null || stsz == null || stsc == null) return null;
  if (stco == null && co64 == null) return null;

  // stsd: version/flags (4), entry count (4), then the sample entry.
  final entry = _boxes(data, stsd.start + 8, stsd.end);
  if (entry.isEmpty || entry.first.type != 'mp4a') return null;
  final esds = _find(
    _boxes(data, entry.first.start + 28, entry.first.end),
    'esds',
  );
  if (esds == null) return null;

  final cursor = [esds.start + 4];
  int? config;
  while (cursor[0] < esds.end) {
    final tag = data.getUint8(cursor[0]++);
    final length = _descriptorLength(data, cursor);
    if (tag == 0x03) {
      cursor[0] += 3;
    } else if (tag == 0x04) {
      if (data.getUint8(cursor[0]) != 0x40) return null;
      cursor[0] += 13;
    } else if (tag == 0x05) {
      config = data.getUint16(cursor[0]);
      break;
    } else {
      cursor[0] += length;
    }
  }
  if (config == null) return null;
  final objectType = config >> 11;
  final frequencyIndex = (config >> 7) & 0xF;
  final channels = (config >> 3) & 0xF;
  if (objectType < 1 || objectType > 4 || frequencyIndex > 12) return null;

  final sampleSize = data.getUint32(stsz.start + 4);
  final sampleCount = data.getUint32(stsz.start + 8);
  int sizeOf(int index) => sampleSize != 0
      ? sampleSize
      : data.getUint32(stsz.start + 12 + index * 4);

  final stscCount = data.getUint32(stsc.start + 4);
  final firstChunks = <int>[];
  final perChunk = <int>[];
  for (var i = 0; i < stscCount; i++) {
    final base = stsc.start + 8 + i * 12;
    firstChunks.add(data.getUint32(base));
    perChunk.add(data.getUint32(base + 4));
  }

  final chunkCount = stco != null
      ? data.getUint32(stco.start + 4)
      : data.getUint32(co64!.start + 4);
  int chunkOffset(int index) => stco != null
      ? data.getUint32(stco.start + 8 + index * 4)
      : data.getUint64(co64!.start + 8 + index * 8);

  final out = BytesBuilder(copy: false);
  var sample = 0;
  var group = 0;
  for (var chunk = 0; chunk < chunkCount && sample < sampleCount; chunk++) {
    while (group + 1 < stscCount && firstChunks[group + 1] <= chunk + 1) {
      group++;
    }
    var offset = chunkOffset(chunk);
    for (var i = 0; i < perChunk[group] && sample < sampleCount; i++) {
      final size = sizeOf(sample++);
      if (offset + size > bytes.length) return null;
      final length = size + 7;
      out.add([
        0xFF,
        0xF1,
        ((objectType - 1) << 6) | (frequencyIndex << 2) | (channels >> 2),
        ((channels & 3) << 6) | ((length >> 11) & 3),
        (length >> 3) & 0xFF,
        ((length & 7) << 5) | 0x1F,
        0xFC,
      ]);
      out.add(Uint8List.sublistView(bytes, offset, offset + size));
      offset += size;
    }
  }
  final result = out.takeBytes();
  return result.length > 1024 ? result : null;
}

/// Publishes an edited sound to the shared library for every user.
Future<void> shareMarketSound(MarketAudioEdit edit) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw StateError('Sign in to share sounds.');
  final doc = FirebaseFirestore.instance.collection('marketSounds').doc();
  final base = 'marketSounds/shared/${user.uid}';
  final audioRef = FirebaseStorage.instance.ref(
    '$base/${doc.id}.${edit.extension}',
  );
  await audioRef.putData(
    edit.bytes,
    SettableMetadata(contentType: marketAudioContentType(edit.extension)),
  );
  final url = await audioRef.getDownloadURL();
  var coverUrl = '';
  final cover = edit.coverBytes;
  if (cover != null) {
    final ext = marketCoverExtensions.contains(edit.coverExtension)
        ? edit.coverExtension
        : 'jpg';
    final coverRef = FirebaseStorage.instance.ref('$base/${doc.id}_cover.$ext');
    await coverRef.putData(
      cover,
      SettableMetadata(contentType: marketCoverContentType(ext)),
    );
    coverUrl = await coverRef.getDownloadURL();
  }
  await doc.set({
    'title': edit.title,
    'url': url,
    if (coverUrl.isNotEmpty) 'coverUrl': coverUrl,
    if (edit.duration.inMilliseconds > 0)
      'durationMs': edit.duration.inMilliseconds,
    'ownerUid': user.uid,
    'source': 'video',
    'createdAt': FieldValue.serverTimestamp(),
  });
}

/// Silently extracts the sound of a published [video] and adds it to the
/// shared library, using a video frame as cover. Never throws.
Future<void> autoShareVideoSound({
  required Uint8List video,
  required String videoName,
  required String title,
  Uint8List? cover,
}) async {
  try {
    final aac = extractMp4Aac(video);
    if (aac == null || aac.length > marketAudioMaxBytes) return;
    final clip = parseMarketAudio(aac, 'aac');
    final seconds = clip?.durationSec ?? 0;
    if (seconds > marketAudioMaxSeconds) return;
    final dot = videoName.lastIndexOf('.');
    final fallback = dot > 0 ? videoName.substring(0, dot) : videoName;
    final clean = title.trim().isEmpty ? fallback : title.trim();
    await shareMarketSound(
      MarketAudioEdit(
        title: clean.length > 80 ? clean.substring(0, 80) : clean,
        bytes: aac,
        extension: 'aac',
        duration: Duration(milliseconds: (seconds * 1000).round()),
        coverBytes: cover != null && cover.length <= marketCoverMaxBytes
            ? cover
            : null,
        coverExtension: 'jpg',
      ),
    );
  } catch (error) {
    debugPrint('Auto share sound failed: $error');
  }
}

/// Extracts the sound of [video], lets the user trim it, then shares it.
Future<void> extractAndShareVideoSound(
  BuildContext context, {
  required Uint8List video,
  required String videoName,
}) async {
  void snack(String text) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  final aac = extractMp4Aac(video);
  if (aac == null) {
    snack('market_video_no_audio'.tr);
    return;
  }
  final dot = videoName.lastIndexOf('.');
  final fileName = '${dot > 0 ? videoName.substring(0, dot) : videoName}.aac';
  if (!context.mounted) return;
  final edit = await Navigator.of(context).push<MarketAudioEdit>(
    MaterialPageRoute(
      builder: (_) => MarketAudioEditorPage(
        bytes: aac,
        extension: 'aac',
        fileName: fileName,
        withCover: true,
      ),
    ),
  );
  if (edit == null) return;
  snack('market_video_sharing'.tr);
  try {
    await shareMarketSound(edit);
    snack('market_video_shared'.tr);
  } catch (error) {
    snack(error.toString());
  }
}
