import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;

import 'market_palette.dart';

class _Normalized {
  const _Normalized(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;
}

_Normalized? _normalize(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final baked = img.bakeOrientation(decoded);
  return _Normalized(
    Uint8List.fromList(img.encodeJpg(baked, quality: 95)),
    baked.width,
    baked.height,
  );
}

class _EditJob {
  const _EditJob({
    required this.bytes,
    required this.turns,
    required this.flip,
    required this.crop,
    required this.brightness,
    required this.contrast,
    required this.saturation,
  });

  final Uint8List bytes;
  final int turns;
  final bool flip;
  final List<double> crop;
  final double brightness;
  final double contrast;
  final double saturation;
}

List<double> _colorMatrix(double b, double c, double s) {
  const lr = .2126, lg = .7152, lb = .0722;
  final i = 1 - s;
  final off = 128 * (1 - c) + b * 255;
  return [
    c * (lr * i + s), c * lg * i, c * lb * i, 0, off, //
    c * lr * i, c * (lg * i + s), c * lb * i, 0, off,
    c * lr * i, c * lg * i, c * (lb * i + s), 0, off,
    0, 0, 0, 1, 0,
  ];
}

Uint8List? _applyEdit(_EditJob job) {
  var image = img.decodeImage(job.bytes);
  if (image == null) return null;
  image = img.bakeOrientation(image);
  if (job.turns != 0) image = img.copyRotate(image, angle: job.turns * 90);
  if (job.flip)
    image = img.flip(image, direction: img.FlipDirection.horizontal);
  final w = image.width;
  final h = image.height;
  final x = (job.crop[0] * w).round().clamp(0, w - 1);
  final y = (job.crop[1] * h).round().clamp(0, h - 1);
  final cw = ((job.crop[2] - job.crop[0]) * w).round().clamp(1, w - x);
  final ch = ((job.crop[3] - job.crop[1]) * h).round().clamp(1, h - y);
  if (cw != w || ch != h) {
    image = img.copyCrop(image, x: x, y: y, width: cw, height: ch);
  }
  if (job.brightness != 0 || job.contrast != 1 || job.saturation != 1) {
    final m = _colorMatrix(job.brightness, job.contrast, job.saturation);
    for (final p in image) {
      final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
      p
        ..r = (m[0] * r + m[1] * g + m[2] * b + m[4]).clamp(0, 255)
        ..g = (m[5] * r + m[6] * g + m[7] * b + m[9]).clamp(0, 255)
        ..b = (m[10] * r + m[11] * g + m[12] * b + m[14]).clamp(0, 255);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 88));
}

class _Preset {
  const _Preset(this.key, this.brightness, this.contrast, this.saturation);

  final String key;
  final double brightness;
  final double contrast;
  final double saturation;
}

const _presets = [
  _Preset('img_filter_original', 0, 1, 1),
  _Preset('img_filter_vivid', .02, 1.12, 1.45),
  _Preset('img_filter_bw', 0, 1.1, 0),
  _Preset('img_filter_fade', .08, .85, .8),
  _Preset('img_filter_drama', -.04, 1.3, .9),
  _Preset('img_filter_bright', .12, 1.05, 1.1),
];

/// Crop / rotate / flip / adjust editor. Pops the edited JPEG bytes, or null
/// when cancelled or nothing changed.
class MarketImageEditorPage extends StatefulWidget {
  const MarketImageEditorPage({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<MarketImageEditorPage> createState() => _MarketImageEditorPageState();
}

class _MarketImageEditorPageState extends State<MarketImageEditorPage> {
  Uint8List? _source;
  int _width = 1;
  int _height = 1;
  bool _failed = false;
  bool _saving = false;

  int _tab = 0;
  int _turns = 0;
  bool _flip = false;
  Rect _crop = const Rect.fromLTWH(0, 0, 1, 1);
  double? _ratio;
  double _brightness = 0;
  double _contrast = 1;
  double _saturation = 1;

  static const _ratios = <String, double?>{
    'img_free': null,
    '1:1': 1,
    '4:5': 4 / 5,
    '3:4': 3 / 4,
    '16:9': 16 / 9,
    '9:16': 9 / 16,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await compute(_normalize, widget.bytes);
    if (!mounted) return;
    if (result == null) {
      setState(() => _failed = true);
      return;
    }
    setState(() {
      _source = result.bytes;
      _width = result.width;
      _height = result.height;
    });
  }

  double get _rotW => (_turns.isOdd ? _height : _width).toDouble();
  double get _rotH => (_turns.isOdd ? _width : _height).toDouble();

  Rect _fullRect(double? ratio) {
    if (ratio == null) return const Rect.fromLTWH(0, 0, 1, 1);
    final w = math.min(_rotW, _rotH * ratio);
    final h = w / ratio;
    final nw = w / _rotW, nh = h / _rotH;
    return Rect.fromLTWH((1 - nw) / 2, (1 - nh) / 2, nw, nh);
  }

  void _setRatio(double? ratio) => setState(() {
    _ratio = ratio;
    _crop = _fullRect(ratio);
  });

  void _rotate() => setState(() {
    _turns = (_turns + 1) % 4;
    _crop = _fullRect(_ratio);
  });

  void _toggleFlip() => setState(() {
    _flip = !_flip;
    _crop = _fullRect(_ratio);
  });

  void _applyPreset(_Preset preset) => setState(() {
    _brightness = preset.brightness;
    _contrast = preset.contrast;
    _saturation = preset.saturation;
  });

  void _reset() => setState(() {
    _turns = 0;
    _flip = false;
    _ratio = null;
    _crop = const Rect.fromLTWH(0, 0, 1, 1);
    _brightness = 0;
    _contrast = 1;
    _saturation = 1;
  });

  bool get _changed =>
      _turns != 0 ||
      _flip ||
      _crop != const Rect.fromLTWH(0, 0, 1, 1) ||
      _brightness != 0 ||
      _contrast != 1 ||
      _saturation != 1;

  Future<void> _done() async {
    final source = _source;
    if (source == null) return;
    if (!_changed) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    final result = await compute(
      _applyEdit,
      _EditJob(
        bytes: source,
        turns: _turns,
        flip: _flip,
        crop: [_crop.left, _crop.top, _crop.right, _crop.bottom],
        brightness: _brightness,
        contrast: _contrast,
        saturation: _saturation,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('market_invalid_photo'.tr)));
      return;
    }
    Navigator.of(context).pop(result);
  }

  Widget _preview(Uint8List source) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: AspectRatio(
          aspectRatio: _rotW / _rotH,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColorFiltered(
                colorFilter: ColorFilter.matrix(
                  _colorMatrix(_brightness, _contrast, _saturation),
                ),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.diagonal3Values(_flip ? -1 : 1, 1, 1),
                  child: RotatedBox(
                    quarterTurns: _turns,
                    child: Image.memory(
                      source,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
              if (_tab == 0)
                _CropOverlay(
                  crop: _crop,
                  ratio: _ratio,
                  onChanged: (rect) => setState(() => _crop = rect),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabButton(int index, IconData icon, String label) {
    final selected = _tab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: selected ? MarketPalette.blue : Colors.white70),
              const SizedBox(height: 2),
              Text(
                label.tr,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? MarketPalette.blue : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label.tr),
      selected: selected,
      onSelected: (_) => onTap(),
    ),
  );

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) => Row(
    children: [
      SizedBox(
        width: 84,
        child: Text(
          label.tr,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ),
      Expanded(
        child: Slider(value: value, min: min, max: max, onChanged: onChanged),
      ),
    ],
  );

  Widget _toolPanel() {
    switch (_tab) {
      case 0:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final entry in _ratios.entries)
                    _chip(
                      entry.key,
                      _ratio == entry.value,
                      () => _setRatio(entry.value),
                    ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _rotate,
                  icon: const Icon(Icons.rotate_right_rounded),
                  label: Text('img_rotate'.tr),
                ),
                TextButton.icon(
                  onPressed: _toggleFlip,
                  icon: const Icon(Icons.flip_rounded),
                  label: Text('img_flip'.tr),
                ),
              ],
            ),
          ],
        );
      case 1:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _slider(
                'img_brightness',
                _brightness,
                -.5,
                .5,
                (v) => setState(() => _brightness = v),
              ),
              _slider(
                'img_contrast',
                _contrast,
                .5,
                1.6,
                (v) => setState(() => _contrast = v),
              ),
              _slider(
                'img_saturation',
                _saturation,
                0,
                2,
                (v) => setState(() => _saturation = v),
              ),
            ],
          ),
        );
      default:
        return SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final preset in _presets)
                _chip(
                  preset.key,
                  _brightness == preset.brightness &&
                      _contrast == preset.contrast &&
                      _saturation == preset.saturation,
                  () => _applyPreset(preset),
                ),
            ],
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('img_edit_title'.tr),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _saving || source == null ? null : _reset,
            child: Text('img_reset'.tr),
          ),
          TextButton(
            onPressed: _saving || source == null ? null : _done,
            child: Text(
              'img_done'.tr,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: _failed
          ? Center(
              child: Text(
                'market_invalid_photo'.tr,
                style: const TextStyle(color: Colors.white),
              ),
            )
          : source == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Column(
                  children: [
                    Expanded(child: _preview(source)),
                    SafeArea(
                      top: false,
                      child: Theme(
                        data: ThemeData.dark(useMaterial3: true),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _toolPanel(),
                            Row(
                              children: [
                                _tabButton(
                                  0,
                                  Icons.crop_rounded,
                                  'img_tab_crop',
                                ),
                                _tabButton(
                                  1,
                                  Icons.tune_rounded,
                                  'img_tab_adjust',
                                ),
                                _tabButton(
                                  2,
                                  Icons.auto_awesome_rounded,
                                  'img_tab_filters',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (_saving)
                  const ColoredBox(
                    color: Colors.black54,
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    );
  }
}

class _CropOverlay extends StatefulWidget {
  const _CropOverlay({
    required this.crop,
    required this.ratio,
    required this.onChanged,
  });

  final Rect crop;
  final double? ratio;
  final ValueChanged<Rect> onChanged;

  @override
  State<_CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<_CropOverlay> {
  static const _minSize = 48.0;
  static const _hit = 36.0;
  // 0 = move, 1..4 = top-left, top-right, bottom-left, bottom-right.
  int _mode = -1;
  Size _size = Size.zero;

  Rect get _px => Rect.fromLTRB(
    widget.crop.left * _size.width,
    widget.crop.top * _size.height,
    widget.crop.right * _size.width,
    widget.crop.bottom * _size.height,
  );

  void _emit(Rect r) => widget.onChanged(
    Rect.fromLTRB(
      (r.left / _size.width).clamp(0, 1),
      (r.top / _size.height).clamp(0, 1),
      (r.right / _size.width).clamp(0, 1),
      (r.bottom / _size.height).clamp(0, 1),
    ),
  );

  void _start(DragStartDetails d) {
    final r = _px;
    final corners = [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight];
    _mode = -1;
    var best = _hit;
    for (var i = 0; i < corners.length; i++) {
      final dist = (corners[i] - d.localPosition).distance;
      if (dist < best) {
        best = dist;
        _mode = i + 1;
      }
    }
    if (_mode == -1 && r.contains(d.localPosition)) _mode = 0;
  }

  void _update(DragUpdateDetails d) {
    if (_mode < 0) return;
    final r = _px;
    if (_mode == 0) {
      final left = (r.left + d.delta.dx).clamp(0, _size.width - r.width);
      final top = (r.top + d.delta.dy).clamp(0, _size.height - r.height);
      _emit(Rect.fromLTWH(left.toDouble(), top.toDouble(), r.width, r.height));
      return;
    }
    final anchor = [
      r.bottomRight,
      r.bottomLeft,
      r.topRight,
      r.topLeft,
    ][_mode - 1];
    final p = Offset(
      d.localPosition.dx.clamp(0, _size.width),
      d.localPosition.dy.clamp(0, _size.height),
    );
    var dx = p.dx - anchor.dx;
    var dy = p.dy - anchor.dy;
    final sx = dx >= 0 ? 1.0 : -1.0;
    final sy = dy >= 0 ? 1.0 : -1.0;
    final ratio = widget.ratio;
    if (ratio == null) {
      dx = sx * math.max(dx.abs(), _minSize);
      dy = sy * math.max(dy.abs(), _minSize);
      final end = Offset(
        (anchor.dx + dx).clamp(0, _size.width),
        (anchor.dy + dy).clamp(0, _size.height),
      );
      _emit(Rect.fromPoints(anchor, end));
      return;
    }
    final availW = sx > 0 ? _size.width - anchor.dx : anchor.dx;
    final availH = sy > 0 ? _size.height - anchor.dy : anchor.dy;
    var w = math.max(dx.abs(), dy.abs() * ratio);
    w = math.min(w, math.min(availW, availH * ratio));
    w = math.max(w, math.min(_minSize, math.min(availW, availH * ratio)));
    final h = w / ratio;
    _emit(Rect.fromPoints(anchor, anchor + Offset(sx * w, sy * h)));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        _size = box.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _start,
          onPanUpdate: _update,
          onPanEnd: (_) => _mode = -1,
          child: CustomPaint(painter: _CropPainter(_px), size: _size),
        );
      },
    );
  }
}

class _CropPainter extends CustomPainter {
  const _CropPainter(this.rect);

  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = Colors.black54);

    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(rect, line);

    final grid = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3;
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
    }

    final handle = Paint()..color = Colors.white;
    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      canvas.drawCircle(corner, 8, handle);
    }
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) => oldDelegate.rect != rect;
}
