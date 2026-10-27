import 'dart:typed_data';

/// A parsed audio file that can be cut to a time range without re-encoding.
abstract class MarketAudioClip {
  double get durationSec;
  String get extension;
  String get contentType;
  int cutSize(double startSec, double endSec);
  Uint8List cut(double startSec, double endSec);
}

/// Returns null when the format cannot be cut in pure Dart (M4A, OGG).
MarketAudioClip? parseMarketAudio(Uint8List bytes, String extension) {
  try {
    return switch (extension.toLowerCase()) {
      'wav' => _parseWav(bytes),
      'mp3' => _parseMp3(bytes),
      'aac' => _parseAdts(bytes),
      _ => null,
    };
  } catch (_) {
    return null;
  }
}

class _FrameClip implements MarketAudioClip {
  _FrameClip(this._bytes, this._offsets, this._frameSec, this.extension);

  final Uint8List _bytes;
  // One offset per frame plus the end of the last frame.
  final List<int> _offsets;
  final double _frameSec;

  @override
  final String extension;

  int get _frames => _offsets.length - 1;

  @override
  double get durationSec => _frames * _frameSec;

  @override
  String get contentType => extension == 'mp3' ? 'audio/mpeg' : 'audio/aac';

  (int, int) _range(double startSec, double endSec) {
    final first = (startSec / _frameSec).floor().clamp(0, _frames - 1);
    final last = (endSec / _frameSec).ceil().clamp(first + 1, _frames);
    return (first, last);
  }

  @override
  int cutSize(double startSec, double endSec) {
    final (first, last) = _range(startSec, endSec);
    return _offsets[last] - _offsets[first];
  }

  @override
  Uint8List cut(double startSec, double endSec) {
    final (first, last) = _range(startSec, endSec);
    return Uint8List.fromList(_bytes.sublist(_offsets[first], _offsets[last]));
  }
}

class _WavClip implements MarketAudioClip {
  _WavClip({
    required this.bytes,
    required this.dataOffset,
    required this.dataLength,
    required this.format,
    required this.channels,
    required this.sampleRate,
    required this.byteRate,
    required this.blockAlign,
    required this.bitsPerSample,
  });

  final Uint8List bytes;
  final int dataOffset;
  final int dataLength;
  final int format;
  final int channels;
  final int sampleRate;
  final int byteRate;
  final int blockAlign;
  final int bitsPerSample;

  @override
  String get extension => 'wav';

  @override
  String get contentType => 'audio/wav';

  @override
  double get durationSec => dataLength / byteRate;

  (int, int) _range(double startSec, double endSec) {
    int align(int value) => value - value % blockAlign;
    final start = align((startSec * byteRate).floor().clamp(0, dataLength));
    var end = align((endSec * byteRate).ceil().clamp(0, dataLength));
    if (end <= start) end = (start + blockAlign).clamp(0, dataLength);
    return (start, end);
  }

  @override
  int cutSize(double startSec, double endSec) {
    final (start, end) = _range(startSec, endSec);
    return 44 + end - start;
  }

  @override
  Uint8List cut(double startSec, double endSec) {
    final (start, end) = _range(startSec, endSec);
    final length = end - start;
    final out = ByteData(44 + length);
    void tag(int offset, String text) {
      for (var i = 0; i < 4; i++) {
        out.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    out.setUint32(4, 36 + length, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    out.setUint32(16, 16, Endian.little);
    out.setUint16(20, format, Endian.little);
    out.setUint16(22, channels, Endian.little);
    out.setUint32(24, sampleRate, Endian.little);
    out.setUint32(28, byteRate, Endian.little);
    out.setUint16(32, blockAlign, Endian.little);
    out.setUint16(34, bitsPerSample, Endian.little);
    tag(36, 'data');
    out.setUint32(40, length, Endian.little);
    final result = out.buffer.asUint8List();
    result.setRange(
      44,
      44 + length,
      bytes.sublist(dataOffset + start, dataOffset + end),
    );
    return result;
  }
}

MarketAudioClip? _parseWav(Uint8List bytes) {
  if (bytes.length < 44) return null;
  final data = ByteData.sublistView(bytes);
  String tag(int offset) =>
      String.fromCharCodes(bytes.sublist(offset, offset + 4));
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;
  var offset = 12;
  int? format, channels, sampleRate, byteRate, blockAlign, bits;
  while (offset + 8 <= bytes.length) {
    final id = tag(offset);
    final size = data.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ' && body + 16 <= bytes.length) {
      format = data.getUint16(body, Endian.little);
      channels = data.getUint16(body + 2, Endian.little);
      sampleRate = data.getUint32(body + 4, Endian.little);
      byteRate = data.getUint32(body + 8, Endian.little);
      blockAlign = data.getUint16(body + 12, Endian.little);
      bits = data.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      if (format == null || byteRate == null || byteRate == 0) return null;
      if (blockAlign == null || blockAlign == 0) return null;
      final length = (body + size > bytes.length) ? bytes.length - body : size;
      return _WavClip(
        bytes: bytes,
        dataOffset: body,
        dataLength: length,
        format: format,
        channels: channels!,
        sampleRate: sampleRate!,
        byteRate: byteRate,
        blockAlign: blockAlign,
        bitsPerSample: bits!,
      );
    }
    offset = body + size + (size.isOdd ? 1 : 0);
  }
  return null;
}

MarketAudioClip? _parseMp3(Uint8List bytes) {
  var i = 0;
  if (bytes.length > 10 &&
      bytes[0] == 0x49 &&
      bytes[1] == 0x44 &&
      bytes[2] == 0x33) {
    final size =
        (bytes[6] & 0x7f) << 21 |
        (bytes[7] & 0x7f) << 14 |
        (bytes[8] & 0x7f) << 7 |
        (bytes[9] & 0x7f);
    i = 10 + size;
  }
  const bitratesV1 = [
    0,
    32,
    40,
    48,
    56,
    64,
    80,
    96,
    112,
    128,
    160,
    192,
    224,
    256,
    320,
  ];
  const bitratesV2 = [
    0,
    8,
    16,
    24,
    32,
    40,
    48,
    56,
    64,
    80,
    96,
    112,
    128,
    144,
    160,
  ];
  const ratesV1 = [44100, 48000, 32000];
  const ratesV2 = [22050, 24000, 16000];
  const ratesV25 = [11025, 12000, 8000];
  final offsets = <int>[];
  int? sampleRate;
  var samples = 1152;
  while (i + 4 <= bytes.length) {
    final b1 = bytes[i + 1];
    if (bytes[i] != 0xFF || (b1 & 0xE0) != 0xE0) {
      i++;
      continue;
    }
    final version = (b1 >> 3) & 3;
    final layer = (b1 >> 1) & 3;
    final b2 = bytes[i + 2];
    final bitrateIndex = b2 >> 4;
    final rateIndex = (b2 >> 2) & 3;
    if (version == 1 ||
        layer != 1 ||
        bitrateIndex == 0 ||
        bitrateIndex == 15 ||
        rateIndex == 3) {
      i++;
      continue;
    }
    final isV1 = version == 3;
    final rate = (isV1
        ? ratesV1
        : version == 2
        ? ratesV2
        : ratesV25)[rateIndex];
    final bitrate = (isV1 ? bitratesV1 : bitratesV2)[bitrateIndex] * 1000;
    final padding = (b2 >> 1) & 1;
    final length = isV1
        ? 144 * bitrate ~/ rate + padding
        : 72 * bitrate ~/ rate + padding;
    sampleRate ??= rate;
    samples = isV1 ? 1152 : 576;
    offsets.add(i);
    i += length;
  }
  if (offsets.length < 2 || sampleRate == null) return null;
  offsets.add(i > bytes.length ? bytes.length : i);
  return _FrameClip(bytes, offsets, samples / sampleRate, 'mp3');
}

MarketAudioClip? _parseAdts(Uint8List bytes) {
  const rates = [
    96000,
    88200,
    64000,
    48000,
    44100,
    32000,
    24000,
    22050,
    16000,
    12000,
    11025,
    8000,
    7350,
  ];
  final offsets = <int>[];
  int? sampleRate;
  var i = 0;
  while (i + 7 <= bytes.length) {
    if (bytes[i] != 0xFF || (bytes[i + 1] & 0xF6) != 0xF0) {
      i++;
      continue;
    }
    final rateIndex = (bytes[i + 2] >> 2) & 0xF;
    final length =
        ((bytes[i + 3] & 3) << 11) | (bytes[i + 4] << 3) | (bytes[i + 5] >> 5);
    if (rateIndex >= rates.length || length < 7) {
      i++;
      continue;
    }
    sampleRate ??= rates[rateIndex];
    offsets.add(i);
    i += length;
  }
  if (offsets.length < 2 || sampleRate == null) return null;
  offsets.add(i > bytes.length ? bytes.length : i);
  return _FrameClip(bytes, offsets, 1024 / sampleRate, 'aac');
}
