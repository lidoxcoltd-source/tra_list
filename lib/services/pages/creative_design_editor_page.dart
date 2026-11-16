import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tra_list/services/creative_studio_service.dart';

class CreativeDesignEditorPage extends StatefulWidget {
  const CreativeDesignEditorPage({super.key, this.concept, this.project});
  final GeneratedDesignConcept? concept;
  final CreativeDesignProject? project;

  @override
  State<CreativeDesignEditorPage> createState() =>
      _CreativeDesignEditorPageState();
}

class _CreativeDesignEditorPageState extends State<CreativeDesignEditorPage> {
  static const _colors = <int>[
    0xFF10233F,
    0xFF315BE8,
    0xFFFFFFFF,
    0xFFFFB92E,
    0xFF202124,
    0xFFB52636,
  ];
  late final TextEditingController _title;
  late final String _backgroundPath;
  late final int _width;
  late final int _height;
  late List<CreativeTextLayer> _layers;
  final List<List<CreativeTextLayer>> _undo = [];
  final List<List<CreativeTextLayer>> _redo = [];
  final Map<String, Future<String>> _assetUrls = {};
  late final Future<String> _backgroundUrl;
  String _projectId = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final project = widget.project;
    final concept = widget.concept;
    _title = TextEditingController(text: project?.title ?? 'Untitled design');
    _projectId = project?.id ?? '';
    _backgroundPath = project?.backgroundPath ?? concept!.storagePath;
    _width = project?.width ?? concept!.width;
    _height = project?.height ?? concept!.height;
    _layers = [...?project?.layers];
    if (project == null && concept != null) {
      final copy = concept.copy;
      final headline = copy['headline']?.trim() ?? '';
      final supportingText = copy['supportingText']?.trim() ?? '';
      final callToAction = copy['callToAction']?.trim() ?? '';
      if (headline.isNotEmpty) {
        _layers.add(
          CreativeTextLayer(
            id: 'copy-headline',
            text: headline,
            x: .07,
            y: .12,
            fontSize: (_width * .058).clamp(24, 64).toDouble(),
            color: 0xFFFFFFFF,
            bold: true,
          ),
        );
      }
      if (supportingText.isNotEmpty) {
        _layers.add(
          CreativeTextLayer(
            id: 'copy-support',
            text: supportingText,
            x: .08,
            y: headline.isEmpty ? .2 : .27,
            fontSize: (_width * .032).clamp(16, 38).toDouble(),
            color: 0xFFFFFFFF,
            bold: false,
          ),
        );
      }
      if (callToAction.isNotEmpty) {
        _layers.add(
          CreativeTextLayer(
            id: 'copy-cta',
            text: callToAction,
            x: .08,
            y: .78,
            fontSize: (_width * .034).clamp(16, 40).toDouble(),
            color: 0xFFFFB92E,
            bold: true,
          ),
        );
      }
    }
    _backgroundUrl = project == null
        ? Future<String>.value(concept!.previewUrl)
        : creativeProjectBackgroundUrl(project);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _checkpoint() {
    _undo.add([..._layers]);
    if (_undo.length > 30) _undo.removeAt(0);
    _redo.clear();
  }

  void _undoChange() {
    if (_undo.isEmpty) return;
    _redo.add([..._layers]);
    setState(() => _layers = _undo.removeLast());
  }

  void _redoChange() {
    if (_redo.isEmpty) return;
    _undo.add([..._layers]);
    setState(() => _layers = _redo.removeLast());
  }

  Future<void> _editText([CreativeTextLayer? layer]) async {
    if (layer == null && _layers.length >= 40) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A design can have up to 40 layers.')),
      );
      return;
    }
    final controller = TextEditingController(
      text: layer?.text ?? 'Your headline',
    );
    var color = layer?.color ?? _colors.first;
    var size = layer?.fontSize ?? 34.0;
    var bold = layer?.bold ?? true;
    var deleteLayer = false;
    final result = await showDialog<CreativeTextLayer>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          scrollable: true,
          title: Text(layer == null ? 'Add text layer' : 'Edit text layer'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Text',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Text('Size'),
                    Expanded(
                      child: Slider(
                        value: size,
                        min: 16,
                        max: 64,
                        divisions: 24,
                        label: size.round().toString(),
                        onChanged: (value) =>
                            setDialogState(() => size = value),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final value in _colors)
                      InkWell(
                        onTap: () => setDialogState(() => color = value),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: Color(value),
                          child: color == value
                              ? Icon(
                                  Icons.check,
                                  size: 15,
                                  color: value == 0xFFFFFFFF
                                      ? Colors.black
                                      : Colors.white,
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bold'),
                  value: bold,
                  onChanged: (value) => setDialogState(() => bold = value),
                ),
              ],
            ),
          ),
          actions: [
            if (layer != null)
              TextButton.icon(
                onPressed: () {
                  deleteLayer = true;
                  Navigator.pop(dialogContext);
                },
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('Delete'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                Navigator.pop(
                  dialogContext,
                  CreativeTextLayer(
                    id:
                        layer?.id ??
                        DateTime.now().microsecondsSinceEpoch.toString(),
                    text: text,
                    x: layer?.x ?? .5,
                    y: layer?.y ?? .5,
                    fontSize: size,
                    color: color,
                    bold: bold,
                  ),
                );
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (!mounted) return;
    if (deleteLayer && layer != null) {
      _checkpoint();
      setState(() => _layers.removeWhere((item) => item.id == layer.id));
      return;
    }
    if (result == null) return;
    _checkpoint();
    setState(() {
      final index = _layers.indexWhere((item) => item.id == result.id);
      if (index < 0)
        _layers.add(result);
      else
        _layers[index] = result;
    });
  }

  Future<void> _addImageLayer() async {
    if (_layers.length >= 40) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A design can have up to 40 layers.')),
      );
      return;
    }
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
        maxWidth: 1800,
        maxHeight: 1800,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
        throw ArgumentError('Choose an image smaller than 5 MB.');
      }
      final assetPath = await uploadCreativeOverlay(
        bytes: bytes,
        extension: image.name.split('.').last,
      );
      if (!mounted) return;
      _checkpoint();
      setState(() {
        _layers.add(
          CreativeTextLayer(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            text: '',
            x: .34,
            y: .38,
            fontSize: 32,
            color: 0xFFFFFFFF,
            bold: false,
            type: 'image',
            assetPath: assetPath,
          ),
        );
        _assetUrls[assetPath] = creativeOverlayDownloadUrl(assetPath);
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not add image: $error')));
      }
    }
  }

  Future<void> _editImage(CreativeTextLayer layer) async {
    var width = layer.imageWidth;
    var height = layer.imageHeight;
    final deleteLayer = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Image or logo layer'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 58, child: Text('Width')),
                    Expanded(
                      child: Slider(
                        value: width.clamp(.12, .8),
                        min: .12,
                        max: .8,
                        onChanged: (value) =>
                            setDialogState(() => width = value),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const SizedBox(width: 58, child: Text('Height')),
                    Expanded(
                      child: Slider(
                        value: height.clamp(.08, .7),
                        min: .08,
                        max: .7,
                        onChanged: (value) =>
                            setDialogState(() => height = value),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text('Delete image'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, null),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (deleteLayer == true) {
      _checkpoint();
      setState(() => _layers.removeWhere((item) => item.id == layer.id));
    } else if (deleteLayer == null) {
      _checkpoint();
      setState(() {
        final index = _layers.indexWhere((item) => item.id == layer.id);
        if (index >= 0) {
          final current = _layers[index];
          _layers[index] = CreativeTextLayer(
            id: current.id,
            text: current.text,
            x: current.x,
            y: current.y,
            fontSize: current.fontSize,
            color: current.color,
            bold: current.bold,
            type: current.type,
            assetPath: current.assetPath,
            imageWidth: width,
            imageHeight: height,
          );
        }
      });
    }
  }

  void _moveLayerOrder(CreativeTextLayer layer, int offset) {
    final index = _layers.indexWhere((item) => item.id == layer.id);
    final next = index + offset;
    if (index < 0 || next < 0 || next >= _layers.length) return;
    _checkpoint();
    setState(() {
      final moved = _layers.removeAt(index);
      _layers.insert(next, moved);
    });
  }

  Future<void> _showLayers() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111A28),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .58,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 12, 8),
                child: Row(
                  children: [
                    const Icon(Icons.layers_outlined, color: Color(0xFF77D9ED)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Layers (${_layers.length})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white70,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFF34445A)),
              Expanded(
                child: _layers.isEmpty
                    ? const Center(
                        child: Text(
                          'Add text or a photo/logo to begin editing.',
                          style: TextStyle(color: Colors.white60),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _layers.length,
                        itemBuilder: (context, index) {
                          final layer = _layers[_layers.length - index - 1];
                          final isImage = layer.type == 'image';
                          return ListTile(
                            leading: Icon(
                              isImage ? Icons.image_outlined : Icons.title,
                              color: const Color(0xFF83CBE3),
                            ),
                            title: Text(
                              isImage
                                  ? 'Photo or logo'
                                  : layer.text.replaceAll('\n', ' '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              isImage ? 'Image layer' : 'Text layer',
                              style: const TextStyle(color: Colors.white54),
                            ),
                            trailing: Wrap(
                              spacing: 0,
                              children: [
                                IconButton(
                                  tooltip: 'Bring forward',
                                  onPressed: () => _moveLayerOrder(layer, 1),
                                  icon: const Icon(
                                    Icons.keyboard_arrow_up_rounded,
                                  ),
                                  color: Colors.white70,
                                ),
                                IconButton(
                                  tooltip: 'Send backward',
                                  onPressed: () => _moveLayerOrder(layer, -1),
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                  ),
                                  color: Colors.white70,
                                ),
                              ],
                            ),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              if (isImage) {
                                _editImage(layer);
                              } else {
                                _editText(layer);
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _moveLayer(
    CreativeTextLayer layer,
    DragUpdateDetails details,
    double canvasWidth,
    double canvasHeight,
  ) {
    final index = _layers.indexWhere((item) => item.id == layer.id);
    if (index < 0) return;
    final current = _layers[index];
    setState(() {
      _layers[index] = CreativeTextLayer(
        id: current.id,
        text: current.text,
        x: (current.x + details.delta.dx / canvasWidth).clamp(
          0,
          current.type == 'image' ? 1 - current.imageWidth : .9,
        ),
        y: (current.y + details.delta.dy / canvasHeight).clamp(
          0,
          current.type == 'image' ? 1 - current.imageHeight : .95,
        ),
        fontSize: current.fontSize,
        color: current.color,
        bold: current.bold,
        type: current.type,
        assetPath: current.assetPath,
        imageWidth: current.imageWidth,
        imageHeight: current.imageHeight,
      );
    });
  }

  Widget _textLayer(
    CreativeTextLayer layer,
    double canvasWidth,
    double canvasHeight,
  ) => GestureDetector(
    onTap: () => _editText(layer),
    onPanStart: (_) => _checkpoint(),
    onPanUpdate: (details) =>
        _moveLayer(layer, details, canvasWidth, canvasHeight),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .12),
        border: Border.all(color: Colors.white.withValues(alpha: .78)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        layer.text,
        style: TextStyle(
          color: Color(layer.color),
          fontSize: layer.fontSize,
          fontWeight: layer.bold ? FontWeight.w800 : FontWeight.w400,
          shadows: const [Shadow(color: Colors.black87, blurRadius: 6)],
        ),
      ),
    ),
  );

  Widget _imageLayer(
    CreativeTextLayer layer,
    double canvasWidth,
    double canvasHeight,
  ) {
    final future = _assetUrls.putIfAbsent(
      layer.assetPath,
      () => creativeOverlayDownloadUrl(layer.assetPath),
    );
    return GestureDetector(
      onTap: () => _editImage(layer),
      onPanStart: (_) => _checkpoint(),
      onPanUpdate: (details) =>
          _moveLayer(layer, details, canvasWidth, canvasHeight),
      child: Container(
        width: layer.imageWidth * canvasWidth,
        height: layer.imageHeight * canvasHeight,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white70),
          borderRadius: BorderRadius.circular(6),
          color: Colors.black.withValues(alpha: .08),
        ),
        child: FutureBuilder<String>(
          future: future,
          builder: (context, snapshot) => snapshot.hasData
              ? Image.network(
                  snapshot.data!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white,
                  ),
                )
              : snapshot.hasError
              ? const Icon(Icons.broken_image_outlined, color: Colors.white)
              : const Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _toolButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFE8F1FF),
        disabledForegroundColor: Colors.white30,
        side: const BorderSide(color: Color(0xFF40536D)),
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    ),
  );

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      _projectId = await saveCreativeProject(
        CreativeDesignProject(
          id: _projectId,
          title: _title.text.trim(),
          backgroundPath: _backgroundPath,
          width: _width,
          height: _height,
          layers: _layers,
        ),
      );
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Project saved.')));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save project: $error')),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0A0F19),
    appBar: AppBar(
      backgroundColor: const Color(0xFF101827),
      foregroundColor: Colors.white,
      title: SizedBox(
        width: math.min(260.0, MediaQuery.sizeOf(context).width * .34),
        child: TextField(
          controller: _title,
          decoration: const InputDecoration(
            hintText: 'Project name',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.white54),
          ),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Undo',
          onPressed: _undo.isEmpty ? null : _undoChange,
          icon: const Icon(Icons.undo_rounded),
        ),
        IconButton(
          tooltip: 'Redo',
          onPressed: _redo.isEmpty ? null : _redoChange,
          icon: const Icon(Icons.redo_rounded),
        ),
        IconButton.filledTonal(
          tooltip: 'Save design',
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final aspect = _width / _height;
            var canvasWidth = constraints.maxWidth;
            var canvasHeight = canvasWidth / aspect;
            if (canvasHeight > constraints.maxHeight) {
              canvasHeight = constraints.maxHeight;
              canvasWidth = canvasHeight * aspect;
            }
            return SizedBox(
              width: canvasWidth,
              height: canvasHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF151F30),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF3B4C63)),
                  boxShadow: const [
                    BoxShadow(color: Color(0x55000000), blurRadius: 24),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: FutureBuilder<String>(
                    future: _backgroundUrl,
                    builder: (context, snapshot) {
                      if (snapshot.hasError)
                        return const Center(
                          child: Text(
                            'Could not load this project background.',
                          ),
                        );
                      if (!snapshot.hasData)
                        return const Center(child: CircularProgressIndicator());
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(snapshot.data!, fit: BoxFit.cover),
                          for (final layer in _layers)
                            Positioned(
                              left: layer.x * canvasWidth,
                              top: layer.y * canvasHeight,
                              child: layer.type == 'image'
                                  ? _imageLayer(
                                      layer,
                                      canvasWidth,
                                      canvasHeight,
                                    )
                                  : _textLayer(
                                      layer,
                                      canvasWidth,
                                      canvasHeight,
                                    ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                _toolButton(
                  icon: Icons.undo_rounded,
                  label: 'Undo',
                  onPressed: _undo.isEmpty ? null : _undoChange,
                ),
                _toolButton(
                  icon: Icons.redo_rounded,
                  label: 'Redo',
                  onPressed: _redo.isEmpty ? null : _redoChange,
                ),
                _toolButton(
                  icon: Icons.title_rounded,
                  label: 'Add text',
                  onPressed: () => _editText(),
                ),
                _toolButton(
                  icon: Icons.add_photo_alternate_outlined,
                  label: 'Add photo or logo',
                  onPressed: _addImageLayer,
                ),
                _toolButton(
                  icon: Icons.layers_outlined,
                  label: 'Layers (${_layers.length})',
                  onPressed: _showLayers,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              'Tap text to edit · Drag to position · Background artwork stays flattened',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
}
