import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/document_design_service.dart';
import 'package:tra_list/services/pages/document_terms_page.dart';
import 'package:tra_list/services/profile_service.dart';

class DocumentDesignPage extends StatefulWidget {
  const DocumentDesignPage({super.key});

  @override
  State<DocumentDesignPage> createState() => _DocumentDesignPageState();
}

class _DocumentDesignPageState extends State<DocumentDesignPage> {
  static const _ink = Color(0xFF19313A);
  static const _muted = Color(0xFF75838A);
  static const _canvas = Color(0xFFF5F7F8);
  static const _line = Color(0xFFE5EAEC);
  static const _accentUi = Color(0xFF0E5962);

  final Map<String, Map<String, dynamic>> _designs = {};
  final List<Map<String, dynamic>> _termVersions = [];
  final Map<String, String> _selectedTerms = {};
  String _type = 'invoice';
  bool _applyToAll = false;
  bool _loading = true;
  bool _saving = false;
  bool get _canEdit => BusinessAccessService.can('profile', 'edit');
  Map<String, dynamic> get _design => _designs[_type]!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await ProfileService.loadOrCreate();
      for (final type in DocumentDesignService.documentTypes.keys) {
        _designs[type] = DocumentDesignService.selectedFor(profile, type);
      }
      _readTerms(profile);
    } catch (error) {
      for (final type in DocumentDesignService.documentTypes.keys) {
        _designs[type] = DocumentDesignService.selectedFor({}, type);
      }
      Get.snackbar('Error', 'Could not load document designs: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _readTerms(Map<String, dynamic> profile) {
    _termVersions
      ..clear()
      ..addAll(
        (profile['documentTermsVersions'] as List? ?? const [])
            .whereType<Map>()
            .map((v) => Map<String, dynamic>.from(v)),
      );
    final selected = profile['selectedDocumentTerms'] as Map? ?? const {};
    _selectedTerms
      ..clear()
      ..addAll({
        for (final type in DocumentDesignService.documentTypes.keys)
          type: selected[type]?.toString() ?? '',
      });
    _selectedTerms.updateAll(
      (_, id) => _termVersions.any((v) => v['id']?.toString() == id) ? id : '',
    );
  }

  Future<void> _openTermsEditor() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DocumentTermsPage()));
    try {
      final profile = await ProfileService.loadOrCreate();
      if (mounted) setState(() => _readTerms(profile));
    } catch (_) {}
  }

  void _update(String key, Object value) {
    if (!_canEdit) return;
    setState(() => _design[key] = value);
  }

  void _resetColors() {
    if (!_canEdit) return;
    setState(() {
      _design['brand'] = DocumentDesignService.defaultBrand;
      _design['accent'] = DocumentDesignService.defaultAccent;
      _design['footer'] = DocumentDesignService.defaultFooter;
    });
  }

  Future<void> _save() async {
    if (!_canEdit || _saving) return;
    setState(() => _saving = true);
    try {
      final types = _applyToAll
          ? DocumentDesignService.documentTypes.keys
          : [_type];
      final payload = {
        'selectedDocumentTerms': Map<String, String>.from(_selectedTerms),
        'documentDesigns': {
          for (final type in types) type: Map<String, dynamic>.from(_design),
        },
      };
      await ProfileService.save(payload);
      if (_applyToAll) {
        for (final type in types) {
          _designs[type] = Map<String, dynamic>.from(_design);
        }
      }
      Get.snackbar(
        'Saved',
        _applyToAll
            ? 'Design applied to all documents.'
            : 'Design saved for ${DocumentDesignService.documentTypes[_type]}.',
      );
    } catch (error) {
      Get.snackbar('Error', 'Could not save design: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        title: const Text('Document design'),
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: _line),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  final controls = _buildControls();
                  final preview = _buildPreviewCard();
                  return SingleChildScrollView(
                    padding: EdgeInsets.all(wide ? 28 : 14),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 6, child: controls),
                                  const SizedBox(width: 24),
                                  Expanded(flex: 5, child: preview),
                                ],
                              )
                            : Column(
                                children: [
                                  preview,
                                  const SizedBox(height: 14),
                                  controls,
                                ],
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _card({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _ink,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_canEdit)
          _card(
            title: 'View only',
            subtitle: 'You do not have permission to change document designs.',
            child: const SizedBox.shrink(),
          ),
        _card(
          title: 'Document',
          subtitle: 'Each document type keeps its own design.',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: DocumentDesignService.documentTypes.entries
                .map(
                  (entry) => ChoiceChip(
                    label: Text(entry.value),
                    selected: _type == entry.key,
                    selectedColor: _accentUi.withValues(alpha: 0.14),
                    onSelected: (_) => setState(() => _type = entry.key),
                  ),
                )
                .toList(),
          ),
        ),
        _card(
          title: 'Layout',
          subtitle: 'Choose how the document is arranged.',
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 460 ? 2 : 1;
              const spacing = 10.0;
              final width =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: DocumentDesignService.styles
                    .map(
                      (style) =>
                          SizedBox(width: width, child: _styleTile(style)),
                    )
                    .toList(),
              );
            },
          ),
        ),
        _card(
          title: 'Terms and conditions',
          subtitle:
              'Choose which saved wording ${DocumentDesignService.documentTypes[_type]} uses.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('terms-$_type-${_selectedTerms[_type]}'),
                initialValue: _selectedTerms[_type] ?? '',
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Built-in default'),
                  ),
                  for (final v in _termVersions)
                    DropdownMenuItem(
                      value: v['id']?.toString() ?? '',
                      child: Text(
                        v['name']?.toString() ?? 'Version',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _canEdit
                    ? (value) =>
                          setState(() => _selectedTerms[_type] = value ?? '')
                    : null,
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: _openTermsEditor,
                icon: const Icon(Icons.edit_note_rounded, size: 20),
                label: Text(_canEdit ? 'Edit or add terms' : 'View terms'),
              ),
            ],
          ),
        ),
        _card(
          title: 'Colors',
          subtitle: 'Pick a swatch or type a hex code such as #1976D2.',
          child: Column(
            children: [
              _ColorPicker(
                label: 'Main color',
                value: _design['brand'] as int,
                enabled: _canEdit,
                onChanged: (v) => _update('brand', v),
              ),
              _ColorPicker(
                label: 'Accent color',
                value: _design['accent'] as int,
                enabled: _canEdit,
                onChanged: (v) => _update('accent', v),
              ),
              _ColorPicker(
                label: 'Footer color',
                value: _design['footer'] as int,
                enabled: _canEdit,
                onChanged: (v) => _update('footer', v),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _canEdit ? _resetColors : null,
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('Reset colors'),
                ),
              ),
            ],
          ),
        ),
        if (_canEdit) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Apply to all document types'),
            value: _applyToAll,
            activeThumbColor: _accentUi,
            onChanged: (v) => setState(() => _applyToAll = v),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: const Text('Save design'),
              style: FilledButton.styleFrom(
                backgroundColor: _accentUi,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _styleTile(DocumentDesignStyle style) {
    final selected = _design['style'] == style.id;
    return Material(
      color: selected ? _accentUi.withValues(alpha: 0.07) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _canEdit ? () => _update('style', style.id) : null,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? _accentUi : _line,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: _DesignPreview(
                  style: style.id,
                  brand: Color(_design['brand'] as int),
                  footer: Color(_design['footer'] as int),
                  compact: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          style.label,
                          style: const TextStyle(
                            color: _ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.check_circle,
                            size: 16,
                            color: _accentUi,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      style.description,
                      style: const TextStyle(color: _muted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard() {
    return _card(
      title: 'Preview',
      subtitle: DocumentDesignService.documentTypes[_type],
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: _DesignPreview(
            style: _design['style'] as String,
            brand: Color(_design['brand'] as int),
            accent: Color(_design['accent'] as int),
            footer: Color(_design['footer'] as int),
            title: DocumentDesignService.documentTypes[_type]!.toUpperCase(),
          ),
        ),
      ),
    );
  }
}

class _ColorPicker extends StatefulWidget {
  const _ColorPicker({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  State<_ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<_ColorPicker> {
  late final TextEditingController _hex = TextEditingController(
    text: _format(widget.value),
  );

  static String _format(int value) =>
      '#${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  void didUpdateWidget(covariant _ColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _parse(_hex.text) != widget.value) {
      _hex.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  static int? _parse(String text) {
    final clean = text.trim().replaceFirst('#', '');
    if (clean.length != 6) return null;
    final parsed = int.tryParse(clean, radix: 16);
    return parsed == null ? null : 0xFF000000 | parsed;
  }

  Future<void> _openPicker() async {
    var hsv = HSVColor.fromColor(Color(widget.value));
    final picked = await showDialog<int>(
      context: context,
      builder: (context) =>
          StatefulBuilder(
            builder: (context, setLocal) {
              final color = hsv.toColor();
              Widget slider(
                String label,
                double value,
                double max,
                ValueChanged<double> onChanged,
                List<Color> track,
              ) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 12)),
                    Container(
                      height: 10,
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        gradient: LinearGradient(colors: track),
                      ),
                    ),
                    Slider(
                      value: value.clamp(0, max),
                      max: max,
                      onChanged: onChanged,
                    ),
                  ],
                );
              }

              return AlertDialog(
                title: Text(widget.label),
                content: SizedBox(
                  width: 340,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: 56,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _format(color.toARGB32()),
                            style: TextStyle(
                              color: color.computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        slider(
                          'Color',
                          hsv.hue,
                          360,
                          (v) => setLocal(() => hsv = hsv.withHue(v)),
                          [
                            for (var h = 0; h <= 360; h += 60)
                              HSVColor.fromAHSV(
                                1,
                                h.toDouble() % 360,
                                1,
                                1,
                              ).toColor(),
                          ],
                        ),
                        slider(
                          'Saturation',
                          hsv.saturation,
                          1,
                          (v) => setLocal(() => hsv = hsv.withSaturation(v)),
                          [
                            hsv.withSaturation(0).toColor(),
                            hsv.withSaturation(1).toColor(),
                          ],
                        ),
                        slider(
                          'Brightness',
                          hsv.value,
                          1,
                          (v) => setLocal(() => hsv = hsv.withValue(v)),
                          [Colors.black, hsv.withValue(1).toColor()],
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, color.toARGB32()),
                    child: const Text('Use color'),
                  ),
                ],
              );
            },
          ),
    );
    if (picked != null) widget.onChanged(0xFF000000 | (picked & 0xFFFFFF));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: const TextStyle(
              color: Color(0xFF19313A),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GestureDetector(
                onTap: widget.enabled ? _openPicker : null,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        Colors.red,
                        Colors.yellow,
                        Colors.green,
                        Colors.cyan,
                        Colors.blue,
                        Colors.purple,
                        Colors.red,
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.colorize,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
              ),
              for (final swatch in DocumentDesignService.palette)
                GestureDetector(
                  onTap: widget.enabled ? () => widget.onChanged(swatch) : null,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Color(swatch),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.value == swatch
                            ? const Color(0xFF19313A)
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: widget.value == swatch
                        ? const Icon(Icons.check, size: 15, color: Colors.white)
                        : null,
                  ),
                ),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _hex,
                  enabled: widget.enabled,
                  maxLength: 7,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    counterText: '',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                  ),
                  onChanged: (text) {
                    final parsed = _parse(text);
                    if (parsed != null) widget.onChanged(parsed);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small on-screen mock of how a document looks with the chosen design.
class _DesignPreview extends StatelessWidget {
  const _DesignPreview({
    required this.style,
    required this.brand,
    required this.footer,
    this.accent,
    this.title = '',
    this.compact = false,
  });

  final String style;
  final Color brand;
  final Color? accent;
  final Color footer;
  final String title;
  final bool compact;

  Color _mix(Color color, double amount) => Color.lerp(
    color,
    amount >= 0 ? Colors.white : Colors.black,
    amount.abs(),
  )!;

  Widget _bar(double height, {Color? color, double? width, double radius = 2}) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: color ?? const Color(0xFFD5DBDE),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = compact ? 5.0 : 18.0;
    final gap = compact ? 3.0 : 9.0;
    final unit = compact ? 3.0 : 7.0;

    Widget header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _bar(unit * 3.5, width: unit * 6, color: _mix(brand, 0.5)),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (compact)
              _bar(unit * 1.4, width: unit * 7, color: brand)
            else
              Text(
                title,
                style: TextStyle(
                  color: brand,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            SizedBox(height: gap / 2),
            _bar(unit * 0.8, width: unit * 8),
            SizedBox(height: gap / 3),
            _bar(unit * 0.8, width: unit * 6),
          ],
        ),
      ],
    );

    switch (style) {
      case 'modern':
        header = Container(
          padding: EdgeInsets.only(bottom: gap),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: brand, width: 3)),
          ),
          child: header,
        );
      case 'minimal':
        header = Container(
          padding: EdgeInsets.only(bottom: gap),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFBDBDBD))),
          ),
          child: header,
        );
      case 'elegant':
        header = Container(
          padding: EdgeInsets.all(gap),
          decoration: BoxDecoration(
            color: _mix(brand, 0.9),
            borderRadius: BorderRadius.circular(compact ? 3 : 8),
          ),
          child: header,
        );
    }

    BoxDecoration tableHead;
    switch (style) {
      case 'modern':
        tableHead = BoxDecoration(color: brand);
      case 'minimal':
        tableHead = BoxDecoration(
          border: Border(bottom: BorderSide(color: brand, width: 1.5)),
        );
      case 'corner':
        tableHead = const BoxDecoration(
          border: Border.symmetric(
            horizontal: BorderSide(color: Color(0xFF212121), width: 0.8),
          ),
        );
      case 'ledger':
        tableHead = BoxDecoration(color: brand);
      case 'elegant':
        tableHead = BoxDecoration(
          color: _mix(brand, -0.45),
          borderRadius: BorderRadius.circular(3),
        );
      default:
        tableHead = BoxDecoration(
          color: brand,
          borderRadius: BorderRadius.circular(compact ? 3 : 8),
        );
    }
    final headLight = style == 'minimal' || style == 'corner';

    Widget row(int i) => Container(
      padding: EdgeInsets.symmetric(vertical: gap / 2, horizontal: gap / 2),
      decoration: style == 'ledger'
          ? BoxDecoration(
              border: Border.all(color: _mix(brand, 0.45), width: 0.6),
            )
          : style == 'modern'
          ? const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
            )
          : style == 'elegant'
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: _mix(brand, 0.7))),
            )
          : null,
      child: Row(
        children: [
          Expanded(flex: 5, child: _bar(unit * 0.9)),
          SizedBox(width: gap),
          Expanded(flex: 2, child: _bar(unit * 0.9)),
          SizedBox(width: gap),
          Expanded(
            flex: 2,
            child: _bar(unit * 0.9, color: const Color(0xFF9AA5AA)),
          ),
        ],
      ),
    );

    return AspectRatio(
      aspectRatio: compact ? 0.75 : 0.707,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(compact ? 4 : 6),
          border: Border.all(color: const Color(0xFFDDE3E5)),
          boxShadow: compact
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: _TexturePainter(style, brand, accent ?? brand, footer),
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(pad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      SizedBox(height: gap * 1.6),
                      Row(
                        children: [
                          _bar(unit, width: unit * 7, color: accent ?? brand),
                          const Spacer(),
                          _bar(unit, width: unit * 7),
                        ],
                      ),
                      SizedBox(height: gap * 1.6),
                      Container(
                        padding: EdgeInsets.symmetric(
                          vertical: gap / 1.5,
                          horizontal: gap / 2,
                        ),
                        decoration: tableHead,
                        child: Row(
                          children: [
                            Expanded(
                              flex: 5,
                              child: _bar(
                                unit * 0.9,
                                color: headLight ? brand : Colors.white,
                              ),
                            ),
                            SizedBox(width: gap),
                            Expanded(
                              flex: 2,
                              child: _bar(
                                unit * 0.9,
                                color: headLight ? brand : Colors.white,
                              ),
                            ),
                            SizedBox(width: gap),
                            Expanded(
                              flex: 2,
                              child: _bar(
                                unit * 0.9,
                                color: headLight ? brand : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      row(0),
                      row(1),
                      row(2),
                      const Spacer(),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _bar(unit * 1.3, width: unit * 10, color: brand),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                height: compact ? 6 : 22,
                color: footer,
                padding: EdgeInsets.symmetric(horizontal: pad),
                child: compact
                    ? null
                    : Row(
                        children: [
                          for (var i = 0; i < 3; i++) ...[
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.white70,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          const SizedBox(width: 2),
                          _bar(4, width: 50, color: Colors.white70),
                          const Spacer(),
                          _bar(4, width: 40, color: Colors.white70),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TexturePainter extends CustomPainter {
  _TexturePainter(this.style, this.brand, this.accent, this.footer);

  final String style;
  final Color brand;
  final Color accent;
  final Color footer;

  Color _tint(double amount) => Color.lerp(brand, Colors.white, amount)!;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final scale = w / 595;
    final fill = Paint();
    if (style != 'band' &&
        const {'tinted', 'dots', 'stripes', 'grid'}.contains(style)) {
      fill.color = _tint(style == 'tinted' ? 0.9 : 0.95);
      canvas.drawRect(Offset.zero & size, fill);
    }
    switch (style) {
      case 'dots':
        fill.color = _tint(0.75);
        final step = 16 * scale;
        for (var y = 10 * scale; y < h; y += step) {
          for (var x = 10 * scale; x < w; x += step) {
            canvas.drawCircle(Offset(x, y), 1.2 * scale + 0.3, fill);
          }
        }
      case 'stripes':
        canvas.save();
        canvas.clipRect(Offset.zero & size);
        final line = Paint()
          ..color = _tint(0.85)
          ..strokeWidth = 7 * scale;
        for (var x = -h; x < w; x += 24 * scale) {
          canvas.drawLine(Offset(x, h), Offset(x + h, 0), line);
        }
        canvas.restore();
      case 'grid':
        final line = Paint()
          ..color = _tint(0.8)
          ..strokeWidth = 0.5;
        for (var x = 0.0; x < w; x += 18 * scale) {
          canvas.drawLine(Offset(x, 0), Offset(x, h), line);
        }
        for (var y = 0.0; y < h; y += 18 * scale) {
          canvas.drawLine(Offset(0, y), Offset(w, y), line);
        }
      case 'ledger':
        canvas.drawRect(
          Rect.fromLTWH(0, 0, w, h),
          Paint()..color = _tint(0.93),
        );
        canvas.drawRect(
          Rect.fromLTWH(0, 0, w, 8 * scale + 1),
          Paint()..color = brand,
        );
      case 'corner':
        canvas.drawRect(
          Rect.fromLTWH(0, 0, 9 * scale + 1, h),
          Paint()..color = footer,
        );
        final p = Paint()..color = brand;
        final cw = 26 * scale + 2;
        canvas.drawPath(
          Path()
            ..moveTo(w, 0)
            ..lineTo(w - cw, 0)
            ..lineTo(w - cw, 120 * scale)
            ..lineTo(w, 160 * scale)
            ..close(),
          p,
        );
        canvas.drawPath(
          Path()
            ..moveTo(9 * scale, h)
            ..lineTo(9 * scale + cw, h)
            ..lineTo(9 * scale + cw, h - 120 * scale)
            ..lineTo(9 * scale, h - 160 * scale)
            ..close(),
          p,
        );
      case 'band':
        canvas.drawRect(
          Rect.fromLTWH(0, 0, w, 14 * scale + 2),
          Paint()..color = brand,
        );
        canvas.drawRect(
          Rect.fromLTWH(0, 14 * scale + 2, 8 * scale + 1, h),
          Paint()..color = accent,
        );
    }
  }

  @override
  bool shouldRepaint(_TexturePainter old) =>
      old.style != style ||
      old.brand != brand ||
      old.accent != accent ||
      old.footer != footer;
}
