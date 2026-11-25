import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/creative_studio_service.dart';
import 'package:tra_list/services/pages/creative_design_editor_page.dart';

/// Creative Studio dashboard and design-intelligence planning workflow.
class CreativeStudioPage extends StatefulWidget {
  const CreativeStudioPage({
    super.key,
    this.initialBrief = '',
    this.initialReferenceBytes,
    this.initialReferenceName = '',
  });

  final String initialBrief;
  final Uint8List? initialReferenceBytes;
  final String initialReferenceName;

  @override
  State<CreativeStudioPage> createState() => _CreativeStudioPageState();
}

class _CreativeStudioPageState extends State<CreativeStudioPage> {
  static const _navy = Color(0xFF080D1B);
  static const _blue = Color(0xFF5577FF);
  static const _ink = Color(0xFFF4F7FF);
  static const _muted = Color(0xFF8995B0);
  static const _canvas = Color(0xFF080D1B);
  static const _surface = Color(0xFF111A2D);
  static const _surface2 = Color(0xFF17233A);
  static const _border = Color(0xFF263653);
  static const _cyan = Color(0xFF57D7FF);
  static const _violet = Color(0xFF9572FF);
  final _briefController = TextEditingController();
  final _customWidthController = TextEditingController(text: '30');
  final _customHeightController = TextEditingController(text: '40');
  String _selectedCategory = 'Poster';
  String _selectedSize = 'Instagram post';
  String _customUnit = 'cm';
  String _selectedLanguage = 'sw';
  String _selectedModel = 'gpt-image-2.5-sunburst';
  bool _planning = false;
  bool _generating = false;
  CreativeDesignPlan? _plan;
  GeneratedDesignConcept? _concept;
  Uint8List? _referenceBytes;
  String _referenceName = '';
  String? _referencePath;
  Map<String, dynamic>? _referenceAnalysis;
  bool _analyzingReference = false;
  CreativeBrandProfile? _selectedBrand;

  static const _categories = <({String title, String caption, IconData icon})>[
    (
      title: 'Poster',
      caption: 'Promotions, events and launches',
      icon: Icons.campaign_outlined,
    ),
    (
      title: 'Logo',
      caption: 'Marks and brand identities',
      icon: Icons.auto_awesome_outlined,
    ),
    (
      title: 'Flyer',
      caption: 'Flyers and brochures',
      icon: Icons.description_outlined,
    ),
    (
      title: 'Print',
      caption: 'Banners, cards and labels',
      icon: Icons.print_outlined,
    ),
    (
      title: 'Social',
      caption: 'Posts, stories and thumbnails',
      icon: Icons.phone_iphone_rounded,
    ),
  ];

  static const _imageModels = <String>[
    'gpt-image-2.5-sunburst',
    'gpt-image-2.5-flare',
  ];
  static const _imageModelLabels = <String, String>{
    'gpt-image-2.5-sunburst': 'GPT Image 2.5 · Detailed',
    'gpt-image-2.5-flare': 'GPT Image 2.5 · Fast',
  };

  @override
  void initState() {
    super.initState();
    _briefController.text = widget.initialBrief;
    _referenceBytes = widget.initialReferenceBytes;
    _referenceName = widget.initialReferenceName;
  }

  @override
  void dispose() {
    _briefController.dispose();
    _customWidthController.dispose();
    _customHeightController.dispose();
    super.dispose();
  }

  double? get _customWidthCm {
    final value = double.tryParse(_customWidthController.text.trim());
    if (value == null || value <= 0) return null;
    return _customUnit == 'm' ? value * 100 : value;
  }

  double? get _customHeightCm {
    final value = double.tryParse(_customHeightController.text.trim());
    if (value == null || value <= 0) return null;
    return _customUnit == 'm' ? value * 100 : value;
  }

  String get _effectiveSize {
    if (_selectedSize != 'Custom size') return _selectedSize;
    final width = _customWidthCm;
    final height = _customHeightCm;
    if (width == null || height == null) return 'Custom size';
    return 'Custom size: ${_formatCm(width)} × ${_formatCm(height)} cm';
  }

  String get _effectiveAspect {
    if (_selectedSize != 'Custom size') {
      return _selectedSize.toLowerCase().contains('story') ||
              _selectedSize.toLowerCase().contains('a4')
          ? 'portrait'
          : 'square';
    }
    final width = _customWidthCm;
    final height = _customHeightCm;
    if (width == null || height == null) return 'square';
    final ratio = width / height;
    if (ratio > 1.12) return 'landscape';
    if (ratio < .88) return 'portrait';
    return 'square';
  }

  String _formatCm(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  bool _customSizeIsValid() {
    if (_selectedSize != 'Custom size') return true;
    final width = _customWidthCm;
    final height = _customHeightCm;
    return width != null &&
        height != null &&
        width >= 1 &&
        height >= 1 &&
        width <= 1000 &&
        height <= 1000;
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This feature will be available in a later phase.'),
      ),
    );
  }

  Future<void> _createPlan() async {
    final brief = _briefController.text.trim();
    if (!_customSizeIsValid()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedLanguage == 'sw'
                ? 'Weka upana na urefu kati ya 1 na 1000 cm.'
                : 'Enter a width and height between 1 and 1000 cm.',
          ),
        ),
      );
      return;
    }
    if (_referenceBytes != null && _referenceAnalysis == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedLanguage == 'sw'
                ? 'Chambua picha ya bidhaa kabla ya kupanga poster.'
                : 'Analyze your product photo before planning the poster.',
          ),
        ),
      );
      return;
    }
    if (brief.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Describe your design in a little more detail.'),
        ),
      );
      return;
    }
    if (!BusinessAccessService.hasBusinessAccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Open Creative Studio from your business account to plan a design.',
          ),
        ),
      );
      return;
    }
    setState(() => _planning = true);
    try {
      final referenceNotes = _referenceAnalysis == null
          ? ''
          : [
              'Overview: ${_referenceAnalysis!['summary'] ?? ''}',
              'Layout: ${_referenceAnalysis!['layout'] ?? ''}',
              'Palette: ${_referenceAnalysis!['palette'] ?? ''}',
              'Typography: ${_referenceAnalysis!['typography'] ?? ''}',
              'Keep: ${_referenceAnalysis!['preserveElements'] ?? ''}',
              'Improve: ${_referenceAnalysis!['improvements'] ?? ''}',
            ].join('\n');
      final plan = await CreativeDesignPlan.create(
        brief: _withBrandGuidance(
          _referenceAnalysis == null
              ? brief
              : '$brief\n\nReference insights:\n$referenceNotes',
        ),
        category: _selectedCategory,
        size: _effectiveSize,
        language: _selectedLanguage,
      );
      if (mounted) setState(() => _plan = plan);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create a design plan: $error')),
      );
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  String _withBrandGuidance(String brief) {
    final brand = _selectedBrand;
    if (brand == null) return brief;
    final details = [
      'Brand: ${brand.name}',
      if (brand.colors.isNotEmpty) 'Brand colors: ${brand.colors.join(', ')}',
      if (brand.typography.isNotEmpty) 'Typography: ${brand.typography}',
      if (brand.slogan.isNotEmpty) 'Slogan: ${brand.slogan}',
      if (brand.guidelines.isNotEmpty) 'Guidelines: ${brand.guidelines}',
      if (brand.logoUrl.isNotEmpty) 'Logo asset URL: ${brand.logoUrl}',
    ].join('\n');
    final combined = '$brief\n\nSelected brand identity:\n$details';
    return combined.length <= 1950 ? combined : combined.substring(0, 1950);
  }

  Future<void> _chooseBrand() async {
    if (!BusinessAccessService.isOwner.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the business owner can manage brand profiles.'),
        ),
      );
      return;
    }
    final selected = await showModalBottomSheet<CreativeBrandProfile>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _BrandPickerSheet(selectedId: _selectedBrand?.id),
    );
    if (selected != null && mounted) {
      setState(() {
        _selectedBrand = selected;
        _plan = null;
        _concept = null;
      });
    }
  }

  Future<void> _openEditor(GeneratedDesignConcept concept) async {
    Map<String, String> copy = concept.copy;
    if (copy.isEmpty) {
      try {
        copy = await generateCreativePosterCopy(
          brief: _briefController.text.trim(),
          language: _selectedLanguage,
          category: _selectedCategory,
        );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _selectedLanguage == 'sw'
                  ? 'Maandishi hayakupatikana. Unaweza kuyaandika kwenye editor: $error'
                  : 'Poster text could not be generated. You can add it in the editor: $error',
            ),
          ),
        );
      }
    }
    final preparedConcept = GeneratedDesignConcept(
      designId: concept.designId,
      storagePath: concept.storagePath,
      previewUrl: concept.previewUrl,
      width: concept.width,
      height: concept.height,
      format: concept.format,
      copy: copy,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreativeDesignEditorPage(concept: preparedConcept),
      ),
    );
  }

  Future<void> _showMyDesigns() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .65,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'My saved designs',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<CreativeDesignProject>>(
                  stream: watchCreativeProjects(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Could not load projects: ${snapshot.error}',
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.data!.isEmpty) {
                      return const Center(
                        child: Text('Saved projects will appear here.'),
                      );
                    }
                    return ListView(
                      children: [
                        for (final project in snapshot.data!)
                          ListTile(
                            leading: const Icon(Icons.design_services_outlined),
                            title: Text(project.title),
                            subtitle: Text(
                              '${project.layers.length} editable text layer(s) · ${project.width} × ${project.height}px',
                            ),
                            trailing: IconButton(
                              tooltip: 'Delete project',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                try {
                                  await deleteCreativeProject(project.id);
                                } catch (error) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Could not delete project: $error',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                            onTap: () async {
                              Navigator.pop(sheetContext);
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => CreativeDesignEditorPage(
                                    project: project,
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
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

  Future<void> _generateConcept() async {
    if (_plan == null) return;
    if (!_customSizeIsValid()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedLanguage == 'sw'
                ? 'Weka upana na urefu sahihi kabla ya kutengeneza design.'
                : 'Enter valid width and height before generating the design.',
          ),
        ),
      );
      return;
    }
    setState(() => _generating = true);
    try {
      final aspect = _effectiveAspect;
      final brief = _withBrandGuidance(_briefController.text.trim());
      final copy = await generateCreativePosterCopy(
        brief: brief,
        language: _selectedLanguage,
        category: _selectedCategory,
      );
      final headline = (copy['headline'] ?? '').trim();
      if (headline.isNotEmpty) {
        final briefHeadline = headline.toLowerCase();
        copy['headline'] =
            briefHeadline[0].toUpperCase() + briefHeadline.substring(1);
      }
      if (copy.values.every((text) => text.trim().isEmpty)) {
        throw StateError(
          _selectedLanguage == 'sw'
              ? 'AI haikuweza kuandaa maandishi. Ongeza ujumbe kwenye maelezo yako ujaribu tena.'
              : 'No poster copy was prepared. Add the message you want to your brief and try again.',
        );
      }
      final copyForImage = [
        if (copy['headline']?.isNotEmpty == true)
          'Headline: ${copy['headline']}',
        if (copy['supportingText']?.isNotEmpty == true)
          'Supporting text: ${copy['supportingText']}',
        if (copy['callToAction']?.isNotEmpty == true)
          'Call to action: ${copy['callToAction']}',
      ].join('\n');
      final concept = await generateDesignConcept(
        prompt:
            '$brief\nApproved poster text to typeset exactly as written:\n$copyForImage\nArt direction: ${_plan!.values}',
        category: _selectedCategory,
        size: _effectiveSize,
        aspect: aspect,
        language: _selectedLanguage,
        model: _selectedModel,
        referencePath: _referencePath,
      );
      if (mounted) {
        setState(
          () => _concept = GeneratedDesignConcept(
            designId: concept.designId,
            storagePath: concept.storagePath,
            previewUrl: concept.previewUrl,
            width: concept.width,
            height: concept.height,
            format: concept.format,
            copy: copy,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      final quotaReached =
          error is FirebaseFunctionsException &&
          error.code == 'resource-exhausted' &&
          error.message?.contains('Daily visual concept limit reached') == true;
      final message = quotaReached
          ? 'creative_daily_image_limit'.tr
          : _selectedLanguage == 'sw'
          ? 'Picha ya poster haikuweza kutengenezwa sasa. Jaribu tena baadaye.'
          : 'The poster image could not be generated right now. Please try again later.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _startVoicePosterGuide() async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _CreativePosterVoiceGuide(
        language: _selectedLanguage,
        onPhotoRequested: (fromCamera) async {
          await _pickReference(fromCamera: fromCamera);
        },
      ),
    );
    if (result == null || result.trim().isEmpty || !mounted) return;
    setState(() {
      _briefController.text = result;
      _plan = null;
      _concept = null;
      _referenceAnalysis = null;
    });
    if (_referenceBytes != null) await _analyzeReference();
    await _createPlan();
    if (mounted && _plan != null) await _generateConcept();
  }

  Future<void> _pickReference({required bool fromCamera}) async {
    try {
      final picker = ImagePicker();
      XFile? photo;
      try {
        photo = await picker.pickImage(
          source: fromCamera ? ImageSource.camera : ImageSource.gallery,
          imageQuality: 90,
          maxWidth: 2400,
          maxHeight: 2400,
        );
      } on PlatformException catch (error) {
        if (!fromCamera || error.code != 'no_available_camera') rethrow;
        photo = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 90,
          maxWidth: 2400,
          maxHeight: 2400,
        );
      }
      if (photo == null) return;
      final imageBytes = await photo.readAsBytes();
      final name = photo.name;
      final extension = name.split('.').last.toLowerCase();
      if (!{'jpg', 'jpeg', 'png', 'webp'}.contains(extension)) {
        throw ArgumentError('Choose a JPG, PNG or WebP image.');
      }
      if (imageBytes.length > 8 * 1024 * 1024) {
        throw ArgumentError('Product images must be under 8 MB.');
      }
      final oldPath = _referencePath;
      setState(() {
        _referenceBytes = imageBytes;
        _referenceName = name;
        _referencePath = null;
        _referenceAnalysis = null;
        _plan = null;
        _concept = null;
      });
      if (oldPath != null) {
        try {
          await deleteCreativeReference(oldPath);
        } catch (_) {
          // The old reference may already have expired or been removed.
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add this product photo: $error')),
        );
      }
    }
  }

  Future<void> _analyzeReference() async {
    final bytes = _referenceBytes;
    if (bytes == null || _analyzingReference) return;
    setState(() => _analyzingReference = true);
    try {
      final existingPath = _referencePath;
      late final String path;
      if (existingPath == null) {
        final extension = _referenceName.split('.').last.toLowerCase();
        path = await uploadCreativeReference(
          bytes: bytes,
          extension: extension,
        );
        if (mounted) setState(() => _referencePath = path);
      } else {
        path = existingPath;
      }
      final analysis = await analyzeCreativeReference(
        filePath: path,
        instructions:
            'This is the exact product that must appear in the finished poster. Identify visible product shape, packaging, colors, label, logo, and distinctive details. Do not guess hidden facts. User brief: ${_briefController.text.trim()}',
        language: _selectedLanguage,
      );
      if (mounted) setState(() => _referenceAnalysis = analysis);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not analyze the reference: $error')),
      );
    } finally {
      if (mounted) setState(() => _analyzingReference = false);
    }
  }

  Future<void> _removeReference() async {
    final path = _referencePath;
    setState(() {
      _referenceBytes = null;
      _referenceName = '';
      _referencePath = null;
      _referenceAnalysis = null;
      _plan = null;
      _concept = null;
    });
    if (path != null) {
      try {
        await deleteCreativeReference(path);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Reference removed from the editor; cloud cleanup may complete later.',
              ),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1000
        ? 5
        : width >= 650
        ? 3
        : 2;

    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        backgroundColor: _canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(colors: [_blue, _violet]),
                boxShadow: [
                  BoxShadow(
                    color: _blue.withValues(alpha: .32),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 11),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ISHER',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'CREATIVE STUDIO',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 2,
                    color: _cyan,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _showMyDesigns,
            tooltip: 'My designs',
            icon: const Icon(Icons.grid_view_rounded),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
            children: [
              _entranceMotion(_hero()),
              const SizedBox(height: 14),
              _entranceMotion(
                _CreativePosterCarousel(
                  language: _selectedLanguage,
                  concept: _concept,
                  onUseIdea: _useInspiration,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _selectedLanguage == 'sw'
                        ? 'Anza ubunifu'
                        : 'Create something',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Icon(Icons.tune_rounded, color: _muted, size: 20),
                ],
              ),
              const SizedBox(height: 14),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _categories.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: 76,
                ),
                itemBuilder: (context, index) =>
                    _categoryTile(_categories[index]),
              ),
              const SizedBox(height: 20),
              _briefCard(),
              if (_referenceBytes != null) ...[
                const SizedBox(height: 14),
                _referenceCard(),
              ],
              if (_referenceAnalysis != null) ...[
                const SizedBox(height: 14),
                _referenceAnalysisCard(_referenceAnalysis!),
              ],
              if (_plan != null) ...[
                const SizedBox(height: 20),
                _planCard(_plan!),
              ],
              if (_concept != null) ...[
                const SizedBox(height: 16),
                _posterCopyCard(_concept!),
                const SizedBox(height: 12),
                _conceptCard(_concept!),
              ],
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _selectedLanguage == 'sw'
                        ? 'Miundo ya hivi karibuni'
                        : 'Recent creations',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextButton(
                    onPressed: _showMyDesigns,
                    child: const Text(
                      'View all',
                      style: TextStyle(color: _cyan),
                    ),
                  ),
                ],
              ),
              _emptyHistory(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF182B59), Color(0xFF20245A), Color(0xFF101A32)],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: .09)),
      boxShadow: [
        BoxShadow(
          color: _blue.withValues(alpha: .16),
          blurRadius: 35,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: Stack(
      children: [
        Positioned(
          right: -10,
          top: -20,
          child: Icon(
            Icons.auto_awesome,
            size: 130,
            color: Colors.white.withValues(alpha: .045),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.circle,
                        color: Color(0xFF4DFFBC),
                        size: 8,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        _selectedLanguage == 'sw'
                            ? 'ISHER AI STUDIO'
                            : 'AI CREATIVE ENGINE',
                        style: const TextStyle(
                          color: _cyan,
                          fontSize: 10,
                          letterSpacing: 1.8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _selectedLanguage == 'sw'
                        ? 'Wazo lako.\nUbunifu wa ISHER.'
                        : 'Imagine it.\nCreate it.',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 29,
                      height: 1.12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _selectedLanguage == 'sw'
                        ? 'Anza kuunda kitu cha kipekee.'
                        : 'Turn your ideas into stunning designs.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .65),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    _blue.withValues(alpha: .3),
                    _violet.withValues(alpha: .15),
                  ],
                ),
                border: Border.all(color: _cyan.withValues(alpha: .3)),
                boxShadow: [
                  BoxShadow(color: _blue.withValues(alpha: .3), blurRadius: 30),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 36,
                color: _cyan,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  void _useInspiration(_PosterSample sample) {
    setState(() {
      _selectedCategory = sample.category;
      _briefController.value = TextEditingValue(
        text: _selectedLanguage == 'sw' ? sample.swahiliPrompt : sample.prompt,
        selection: TextSelection.collapsed(
          offset:
              (_selectedLanguage == 'sw' ? sample.swahiliPrompt : sample.prompt)
                  .length,
        ),
      );
      _plan = null;
      _concept = null;
      _referenceAnalysis = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _selectedLanguage == 'sw'
              ? 'Wazo limejazwa kwenye maelezo ya design. Unaweza kulibadilisha.'
              : 'Idea added to your design brief. You can customize it.',
        ),
      ),
    );
  }

  Widget _entranceMotion(Widget child) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 850),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (context, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(-22 * (1 - value), 0),
        child: child,
      ),
    ),
  );

  Widget _categoryTile(
    ({String title, String caption, IconData icon}) category,
  ) {
    final selected = _selectedCategory == category.title;

    return InkWell(
      borderRadius: BorderRadius.circular(17),
      onTap: () {
        setState(() {
          _selectedCategory = category.title;
          _plan = null;
          _concept = null;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1D3260) : _surface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected ? _blue : _border,
            width: selected ? 1.4 : .8,
          ),
          boxShadow: selected
              ? [BoxShadow(color: _blue.withValues(alpha: .17), blurRadius: 16)]
              : null,
        ),
        child: Row(
          children: [
            Icon(category.icon, color: selected ? _cyan : _muted, size: 22),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                _categoryName(category.title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFFC3CBE0),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: _cyan, size: 15),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeading({
    required String step,
    required String title,
    required String subtitle,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (step.isNotEmpty) ...[
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFE7ECFF),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            step,
            style: const TextStyle(
              color: _blue,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(width: 11),
      ],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: _ink,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -.2,
              ),
            ),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
          ],
        ),
      ),
    ],
  );

  String _categoryCaption(String category) {
    if (_selectedLanguage != 'sw') {
      return _categories.firstWhere((item) => item.title == category).caption;
    }
    return switch (category) {
      'Poster' => 'Matangazo na ofa',
      'Logo' => 'Utambulisho wa biashara',
      'Flyer' => 'Vipeperushi vya biashara',
      'Print' => 'Bango, kadi na lebo',
      _ => 'Mitandao ya kijamii',
    };
  }

  String _categoryName(String category) {
    if (_selectedLanguage != 'sw') return category;
    return switch (category) {
      'Poster' => 'Poster',
      'Logo' => 'Nembo',
      'Flyer' => 'Kipeperushi',
      'Print' => 'Chapisho',
      _ => 'Mitandao',
    };
  }

  Widget _briefCard() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading(
          step: '02',
          title: _selectedLanguage == 'sw'
              ? 'Eleza unachohitaji'
              : 'Describe what you need',
          subtitle: _selectedLanguage == 'sw'
              ? 'Andika tu kwa maneno yako. Kiswahili kinakaribishwa.'
              : 'Write it in your own words. Simple is perfect.',
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _briefController,
          minLines: 3,
          maxLines: 5,
          maxLength: 1100,
          onChanged: (_) {
            if (_plan != null ||
                _concept != null ||
                _referenceAnalysis != null) {
              setState(() {
                _plan = null;
                _concept = null;
                _referenceAnalysis = null;
              });
            }
          },
          decoration: InputDecoration(
            hintText: _selectedLanguage == 'sw'
                ? 'Mfano: Tengeneza bango la ofa ya wikendi kwa mgahawa wangu. Tumia rangi zinazovutia; usibuni bei au namba ya simu.'
                : 'Example: Create a clean weekend offer poster for my cafe. Use warm colors; do not invent a price or phone number.',
            filled: true,
            fillColor: const Color(0xFFF8F9FC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE4E9F2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE4E9F2)),
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _generating || _planning ? null : _startVoicePosterGuide,
            icon: const Icon(Icons.mic_rounded, size: 19),
            label: Text(
              _selectedLanguage == 'sw'
                  ? 'Tengeneza poster kwa sauti — ISHER akuongoze'
                  : 'Create poster by voice — guided by ISHER',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _cyan,
              side: const BorderSide(color: _cyan),
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _surface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.shopping_bag_outlined,
                    color: _blue,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedLanguage == 'sw'
                          ? 'Una bidhaa ya kuweka kwenye poster?'
                          : 'Have a product to feature?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    _selectedLanguage == 'sw' ? 'HIARI' : 'OPTIONAL',
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w800,
                      fontSize: 9,
                      letterSpacing: .7,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _selectedLanguage == 'sw'
                    ? 'Piga picha au chagua iliyopo. ISHER itatumia bidhaa yako kwenye muundo.'
                    : 'Take a photo or choose one. ISHER will build the design around it.',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 9,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _pickReference(fromCamera: true),
                    icon: const Icon(Icons.camera_alt_outlined, size: 18),
                    label: Text(
                      _selectedLanguage == 'sw' ? 'Piga picha' : 'Use camera',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickReference(fromCamera: false),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: Text(
                      _selectedLanguage == 'sw'
                          ? 'Chagua picha'
                          : 'Choose photo',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            leading: const Icon(Icons.tune_rounded, color: _muted, size: 19),
            title: Text(
              _selectedLanguage == 'sw'
                  ? 'Mipangilio mingine'
                  : 'More settings',
              style: const TextStyle(
                color: _muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              _selectedLanguage == 'sw'
                  ? 'Ukubwa, modeli, lugha na chapa'
                  : 'Size, model, language and brand',
              style: const TextStyle(color: _muted, fontSize: 10),
            ),
            children: [
              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  _selector(
                    _selectedLanguage == 'sw' ? 'Lugha' : 'Language',
                    _selectedLanguage,
                    const ['sw', 'en'],
                    (value) => setState(() {
                      _selectedLanguage = value;
                      _plan = null;
                      _concept = null;
                      _referenceAnalysis = null;
                    }),
                    displayLabels: const {'sw': 'Kiswahili', 'en': 'English'},
                  ),
                  _selector(
                    _selectedLanguage == 'sw' ? 'Modeli' : 'Image model',
                    _selectedModel,
                    _imageModels,
                    (value) => setState(() => _selectedModel = value),
                    displayLabels: _imageModelLabels,
                  ),
                  _selector(
                    _selectedLanguage == 'sw' ? 'Ukubwa' : 'Size',
                    _selectedSize,
                    const [
                      'Instagram post',
                      'Instagram story',
                      'Facebook post',
                      'A4 print',
                      'Custom size',
                    ],
                    (value) => setState(() {
                      _selectedSize = value;
                      _plan = null;
                      _concept = null;
                    }),
                    displayLabels: _selectedLanguage == 'sw'
                        ? const {
                            'Instagram post': 'Chapisho la Instagram',
                            'Instagram story': 'Story ya Instagram',
                            'Facebook post': 'Chapisho la Facebook',
                            'A4 print': 'Chapisho la A4',
                            'Custom size': 'Ukubwa maalum',
                          }
                        : const {},
                  ),
                  OutlinedButton.icon(
                    onPressed: _chooseBrand,
                    icon: const Icon(Icons.storefront_outlined, size: 18),
                    label: Text(
                      _selectedBrand?.name ??
                          (_selectedLanguage == 'sw'
                              ? 'Chagua chapa'
                              : 'Choose brand'),
                    ),
                  ),
                ],
              ),
              if (_selectedSize == 'Custom size') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _customDimensionField(
                        _selectedLanguage == 'sw' ? 'Upana' : 'Width',
                        _customWidthController,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _customDimensionField(
                        _selectedLanguage == 'sw' ? 'Urefu' : 'Length',
                        _customHeightController,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 82,
                      child: DropdownButtonFormField<String>(
                        initialValue: _customUnit,
                        decoration: InputDecoration(
                          labelText: _selectedLanguage == 'sw'
                              ? 'Kipimo'
                              : 'Unit',
                          filled: true,
                          fillColor: const Color(0xFF0B1322),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        dropdownColor: const Color(0xFF17233A),
                        items: const [
                          DropdownMenuItem(value: 'cm', child: Text('cm')),
                          DropdownMenuItem(value: 'm', child: Text('m')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            final factor = _customUnit == 'cm' ? .01 : 100.0;
                            for (final controller in [
                              _customWidthController,
                              _customHeightController,
                            ]) {
                              final current = double.tryParse(
                                controller.text.trim(),
                              );
                              if (current != null) {
                                final converted = current * factor;
                                controller.value = TextEditingValue(
                                  text: _formatCm(converted),
                                  selection: TextSelection.collapsed(
                                    offset: _formatCm(converted).length,
                                  ),
                                );
                              }
                            }
                            _customUnit = value;
                            _plan = null;
                            _concept = null;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _selectedLanguage == 'sw'
                      ? 'Uwiano wa muundo: ${_effectiveAspect == 'square'
                            ? 'mraba'
                            : _effectiveAspect == 'portrait'
                            ? 'wima'
                            : 'mlalo'}. Vipimo vinaongoza muundo; resolution ya picha huamuliwa na AI.'
                      : 'Design orientation: $_effectiveAspect. Dimensions guide the layout; the AI model sets image resolution.',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 10,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _planning ? null : _createPlan,
            icon: _planning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _surface,
                    ),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(
              _planning
                  ? (_selectedLanguage == 'sw'
                        ? 'Inapanga muundo...'
                        : 'Planning your design...')
                  : (_selectedLanguage == 'sw' ? 'Endelea' : 'Continue'),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _blue,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            _selectedLanguage == 'sw'
                ? 'Hatua inayofuata: tengeneza poster yako.'
                : 'Next, ISHER will prepare your design direction.',
            style: const TextStyle(fontSize: 11, color: _muted),
          ),
        ),
      ],
    ),
  );

  Widget _customDimensionField(
    String label,
    TextEditingController controller,
  ) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
    style: const TextStyle(color: _ink, fontSize: 13),
    decoration: InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFF0B1322),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    onChanged: (_) => setState(() {
      _plan = null;
      _concept = null;
    }),
  );

  Widget _selector(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> onSelected, {
    Map<String, String> displayLabels = const {},
  }) => PopupMenuButton<String>(
    onSelected: onSelected,
    itemBuilder: (context) => options
        .map(
          (option) => PopupMenuItem(
            value: option,
            child: Text(displayLabels[option] ?? option),
          ),
        )
        .toList(),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE4E9F2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(color: Color(0xFF738096))),
          Text(
            displayLabels[value] ?? value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 5),
          const Icon(Icons.expand_more_rounded, size: 18),
        ],
      ),
    ),
  );

  Widget _emptyHistory() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _border),
    ),
    child: const Column(
      children: [
        Icon(Icons.collections_outlined, size: 30, color: Color(0xFF9AA5B8)),
        SizedBox(height: 8),
        Text(
          'Your saved designs will appear here.',
          style: TextStyle(color: Color(0xFF738096)),
        ),
      ],
    ),
  );

  Widget _planCard(CreativeDesignPlan plan) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading(
          step: '03',
          title: _selectedLanguage == 'sw'
              ? 'Muundo umeandaliwa'
              : 'Your design direction',
          subtitle: _selectedLanguage == 'sw'
              ? 'Sasa tengeneza picha ya mwisho.'
              : 'Review the direction, then create your visual.',
        ),
        const SizedBox(height: 12),
        for (final entry in plan.values.entries) ...[
          Text(
            CreativeDesignPlan.labelFor(entry.key, language: _selectedLanguage),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            entry.value is List
                ? (entry.value as List).join(' • ')
                : entry.value.toString(),
            style: const TextStyle(color: Color(0xFF536178), height: 1.45),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _generating ? null : _generateConcept,
            icon: _generating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _surface,
                    ),
                  )
                : const Icon(Icons.image_search_rounded),
            label: Text(
              _generating
                  ? (_selectedLanguage == 'sw'
                        ? 'Inatengeneza poster...'
                        : 'Creating your design...')
                  : _selectedLanguage == 'sw'
                  ? (_referenceBytes == null
                        ? 'Tengeneza picha ya mfano'
                        : 'Tengeneza poster ya bidhaa')
                  : (_referenceBytes == null
                        ? 'Generate visual concept'
                        : 'Generate poster from product'),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _blue,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _selectedLanguage == 'sw'
              ? 'Unaweza kuhariri maandishi na kuweka nembo baada ya picha kutengenezwa.'
              : 'You can add editable text and a logo after the image is created.',
          style: const TextStyle(color: _muted, fontSize: 11),
        ),
      ],
    ),
  );

  Widget _conceptCard(GeneratedDesignConcept concept) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _selectedLanguage == 'sw' ? 'Muundo wako' : 'Your design preview',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${concept.width} × ${concept.height} px · ${concept.format.toUpperCase()} · Preview link expires in 1 hour',
          style: const TextStyle(color: Color(0xFF738096), fontSize: 12),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            concept.previewUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const SizedBox(
                    height: 260,
                    child: Center(child: CircularProgressIndicator()),
                  ),
            errorBuilder: (context, error, stack) => const SizedBox(
              height: 220,
              child: Center(
                child: Text(
                  'Preview link has expired. Generate a new concept.',
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _openEditor(concept),
            icon: const Icon(Icons.layers_outlined),
            label: Text(
              _selectedLanguage == 'sw' ? 'Hariri muundo' : 'Edit this design',
            ),
          ),
        ),
      ],
    ),
  );

  Widget _posterCopyCard(GeneratedDesignConcept concept) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.text_fields_rounded, color: _cyan, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _selectedLanguage == 'sw'
                    ? 'Maandishi yatakayowekwa kwenye poster'
                    : 'Text for your poster',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => _editPosterCopy(concept),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(_selectedLanguage == 'sw' ? 'Badili' : 'Customize'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final entry in const [
          ('headline', 'Kichwa', 'Headline'),
          ('supportingText', 'Maelezo', 'Supporting text'),
          ('callToAction', 'Mwito wa hatua', 'Call to action'),
        ])
          if ((concept.copy[entry.$1] ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 112,
                    child: Text(
                      _selectedLanguage == 'sw' ? entry.$2 : entry.$3,
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      concept.copy[entry.$1]!,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
      ],
    ),
  );

  Future<void> _editPosterCopy(GeneratedDesignConcept concept) async {
    final fields = <String, TextEditingController>{
      'headline': TextEditingController(text: concept.copy['headline'] ?? ''),
      'supportingText': TextEditingController(
        text: concept.copy['supportingText'] ?? '',
      ),
      'callToAction': TextEditingController(
        text: concept.copy['callToAction'] ?? '',
      ),
    };
    final labels = _selectedLanguage == 'sw'
        ? const {
            'headline': 'Kichwa cha poster',
            'supportingText': 'Maelezo mafupi',
            'callToAction': 'Mwito wa kuchukua hatua',
          }
        : const {
            'headline': 'Poster headline',
            'supportingText': 'Supporting text',
            'callToAction': 'Call to action',
          };
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _selectedLanguage == 'sw'
              ? 'Badili maandishi ya poster'
              : 'Customize poster text',
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in fields.entries) ...[
                TextField(
                  controller: entry.value,
                  maxLength: entry.key == 'headline'
                      ? 100
                      : entry.key == 'supportingText'
                      ? 160
                      : 70,
                  maxLines: entry.key == 'supportingText' ? 2 : 1,
                  decoration: InputDecoration(
                    labelText: labels[entry.key],
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_selectedLanguage == 'sw' ? 'Ghairi' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, {
              for (final entry in fields.entries)
                entry.key: entry.value.text.trim(),
            }),
            child: Text(_selectedLanguage == 'sw' ? 'Tumia' : 'Apply'),
          ),
        ],
      ),
    );
    for (final controller in fields.values) {
      controller.dispose();
    }
    if (result == null || !mounted) return;
    setState(
      () => _concept = GeneratedDesignConcept(
        designId: concept.designId,
        storagePath: concept.storagePath,
        previewUrl: concept.previewUrl,
        width: concept.width,
        height: concept.height,
        format: concept.format,
        copy: result,
      ),
    );
  }

  Widget _referenceCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Product photo',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Remove product photo',
              onPressed: _analyzingReference ? null : _removeReference,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        Text(
          _referenceName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF738096), fontSize: 12),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(
            _referenceBytes!,
            height: 240,
            width: double.infinity,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _analyzingReference ? null : _analyzeReference,
            icon: _analyzingReference
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _surface,
                    ),
                  )
                : const Icon(Icons.manage_search_rounded),
            label: Text(
              _analyzingReference
                  ? 'Analyzing reference…'
                  : (_selectedLanguage == 'sw'
                        ? 'Chambua picha ya bidhaa'
                        : 'Analyze product photo'),
            ),
            style: FilledButton.styleFrom(backgroundColor: _blue),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'ISHER will use this photo as the product source and keep its visible details in the poster.',
          style: TextStyle(color: Color(0xFF7A869A), fontSize: 11),
        ),
      ],
    ),
  );

  Widget _referenceAnalysisCard(Map<String, dynamic> analysis) {
    const labels = <String, String>{
      'summary': 'Overview',
      'layout': 'Layout and hierarchy',
      'palette': 'Palette',
      'typography': 'Typography',
      'strengths': 'What works',
      'improvements': 'Suggested improvements',
      'preserveElements': 'Elements to retain',
      'adaptationPrompt': 'Direction for a new design',
    };
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.visibility_outlined, color: _blue),
              SizedBox(width: 9),
              Text(
                'Reference analysis',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final entry in analysis.entries)
            if (entry.value != null &&
                entry.value.toString().trim().isNotEmpty) ...[
              Text(
                labels[entry.key] ?? entry.key,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                entry.value is List
                    ? (entry.value as List).join(' • ')
                    : entry.value.toString(),
                style: const TextStyle(color: Color(0xFF536178), height: 1.45),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _BrandPickerSheet extends StatelessWidget {
  const _BrandPickerSheet({required this.selectedId});
  final String? selectedId;

  Future<void> _editBrand(
    BuildContext context, [
    CreativeBrandProfile? brand,
  ]) async {
    final name = TextEditingController(text: brand?.name ?? '');
    final colors = TextEditingController(text: brand?.colors.join(', ') ?? '');
    final typography = TextEditingController(text: brand?.typography ?? '');
    final slogan = TextEditingController(text: brand?.slogan ?? '');
    final guidelines = TextEditingController(text: brand?.guidelines ?? '');
    final logoUrl = TextEditingController(text: brand?.logoUrl ?? '');
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<CreativeBrandProfile>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          brand == null ? 'Create brand profile' : 'Edit ${brand.name}',
        ),
        content: SizedBox(
          width: 460,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Business / brand name',
                    ),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Enter a brand name'
                        : null,
                  ),
                  TextFormField(
                    controller: colors,
                    decoration: const InputDecoration(
                      labelText: 'Brand colors (comma separated)',
                      hintText: '#10233F, #315BE8',
                    ),
                  ),
                  TextFormField(
                    controller: typography,
                    maxLength: 160,
                    decoration: const InputDecoration(
                      labelText: 'Preferred typography',
                    ),
                  ),
                  TextFormField(
                    controller: slogan,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: 'Slogan'),
                  ),
                  TextFormField(
                    controller: logoUrl,
                    maxLength: 2048,
                    decoration: const InputDecoration(
                      labelText: 'Logo image URL (optional)',
                    ),
                  ),
                  TextFormField(
                    controller: guidelines,
                    maxLength: 1000,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Brand guidelines',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(
                dialogContext,
                CreativeBrandProfile(
                  id: brand?.id ?? '',
                  name: name.text.trim(),
                  colors: colors.text
                      .split(',')
                      .map((value) => value.trim())
                      .where((value) => value.isNotEmpty)
                      .take(6)
                      .toList(),
                  typography: typography.text.trim(),
                  slogan: slogan.text.trim(),
                  guidelines: guidelines.text.trim(),
                  logoUrl: logoUrl.text.trim(),
                ),
              );
            },
            child: const Text('Save brand'),
          ),
        ],
      ),
    );
    name.dispose();
    colors.dispose();
    typography.dispose();
    slogan.dispose();
    guidelines.dispose();
    logoUrl.dispose();
    if (result == null || !context.mounted) return;
    try {
      final id = await saveCreativeBrand(result);
      if (context.mounted) {
        Navigator.pop(
          context,
          CreativeBrandProfile(
            id: id,
            name: result.name,
            colors: result.colors,
            typography: result.typography,
            slogan: result.slogan,
            guidelines: result.guidelines,
            logoUrl: result.logoUrl,
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save brand: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .62,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Brand identity',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Text(
              'Save multiple brand profiles and apply one to each design.',
              style: TextStyle(color: Color(0xFF738096)),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<CreativeBrandProfile>>(
                stream: watchCreativeBrands(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Could not load brand profiles: ${snapshot.error}',
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final brands = snapshot.data!;
                  if (brands.isEmpty) {
                    return const Center(
                      child: Text('No saved brands yet. Create one to start.'),
                    );
                  }
                  return ListView.builder(
                    itemCount: brands.length,
                    itemBuilder: (context, index) {
                      final brand = brands[index];
                      final colors = brand.colors
                          .map(
                            (value) => int.tryParse(
                              value.replaceFirst('#', ''),
                              radix: 16,
                            ),
                          )
                          .whereType<int>()
                          .toList();
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: colors.isEmpty
                              ? const Color(0xFF315BE8)
                              : Color(0xFF000000 | colors.first),
                        ),
                        title: Text(brand.name),
                        subtitle: Text(
                          [
                            brand.colors.join(', '),
                            brand.typography,
                          ].where((value) => value.isNotEmpty).join(' · '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Edit brand',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editBrand(context, brand),
                            ),
                            IconButton(
                              tooltip: 'Delete brand',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                try {
                                  await deleteCreativeBrand(brand.id);
                                } catch (error) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Could not delete brand: $error',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, brand),
                              child: Text(
                                brand.id == selectedId ? 'Selected' : 'Use',
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _editBrand(context),
                icon: const Icon(Icons.add),
                label: const Text('Create brand profile'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CreativePosterCarousel extends StatefulWidget {
  const _CreativePosterCarousel({
    required this.language,
    required this.onUseIdea,
    this.concept,
  });

  final String language;
  final ValueChanged<_PosterSample> onUseIdea;
  final GeneratedDesignConcept? concept;

  @override
  State<_CreativePosterCarousel> createState() =>
      _CreativePosterCarouselState();
}

class _CreativePosterCarouselState extends State<_CreativePosterCarousel> {
  static const _samples = <_PosterSample>[
    _PosterSample(
      title: 'Kahawa ya Asili',
      subtitle: 'Ladha ya nyumbani',
      icon: Icons.coffee_rounded,
      colors: [Color(0xFF4B291E), Color(0xFFE4A449)],
      category: 'Poster',
      swahiliPrompt:
          'Tengeneza poster ya kahawa ya asili kwa biashara ya Tanzania iitwayo Kahawa ya Asili. Tumia rangi za kahawia na dhahabu, onyesha kikombe cha kahawa ya kienyeji yenye mvuke, weka kichwa kinachoonekana vizuri, maelezo mafupi na mwito wa kuagiza. Acha nafasi safi ya kuweka namba ya simu; usibuni namba.',
      prompt:
          'Create a premium Kiswahili coffee poster for Kahawa ya Asili. Use a rich brown and warm gold palette, show a steaming cup of locally roasted coffee, bold readable headline, short supporting copy, and a clear order call to action. Leave clean space for a phone number; do not invent one.',
    ),
    _PosterSample(
      title: 'Furaha ya Ladha',
      subtitle: 'Fresh kila siku',
      icon: Icons.local_pizza_rounded,
      colors: [Color(0xFF7E2340), Color(0xFFFF9B63)],
      category: 'Poster',
      swahiliPrompt:
          'Tengeneza poster ya ofa ya chakula kwa Furaha ya Ladha. Onyesha pizza mpya na viungo vyake kwa muonekano unaovutia, tumia rangi nyekundu na machungwa, kichwa kifupi kinachoonekana, maelezo mafupi ya ofa na mwito wa kuagiza. Usibuni bei wala mawasiliano.',
      prompt:
          'Design a vibrant food promotion poster for Furaha ya Ladha. Feature fresh pizza and appetizing ingredients, warm red and orange colors, strong headline, concise offer details, and a clear order call to action. Do not invent prices or contact details.',
    ),
    _PosterSample(
      title: 'Ubunifu wa Soko',
      subtitle: 'Chagua kilicho bora',
      icon: Icons.shopping_bag_rounded,
      colors: [Color(0xFF174D5C), Color(0xFF4CC9B0)],
      category: 'Social',
      swahiliPrompt:
          'Tengeneza chapisho safi la mitandao ya kijamii kwa duka la Tanzania liitwalo Ubunifu wa Soko. Onyesha bidhaa mpya zilizopangwa vizuri, tumia rangi za kijani bahari na krimu, weka kichwa kinachoeleweka kwa Kiswahili, maelezo mafupi na mwito wa kutembelea duka. Usibuni anwani wala bei.',
      prompt:
          'Create a clean, modern social poster for a Tanzanian market shop called Ubunifu wa Soko. Feature a neat arrangement of fresh everyday products, teal and cream colors, readable Swahili headline, brief supporting line, and a visit-us call to action. Do not invent an address or prices.',
    ),
  ];

  late final PageController _controller;
  Timer? _timer;
  int _activePage = 0;
  double _viewportFraction = .72;
  final Map<String, Future<String>> _imageUrls = {};

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: _viewportFraction);
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.nextPage(
        duration: const Duration(milliseconds: 1050),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextFraction = MediaQuery.sizeOf(context).width > 700 ? .34 : .72;
    if (nextFraction != _viewportFraction) {
      _viewportFraction = nextFraction;
      _controller.dispose();
      _controller = PageController(
        viewportFraction: _viewportFraction,
        initialPage: _activePage,
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<List<CreativeDesignProject>>(
    stream: watchCreativeProjects(),
    builder: (context, snapshot) {
      final entries = <_PosterEntry>[];
      final concept = widget.concept;
      if (concept != null) {
        entries.add(
          _PosterEntry(
            title: widget.language == 'sw'
                ? 'Poster yako mpya'
                : 'Your new poster',
            previewUrl: concept.previewUrl,
          ),
        );
      }
      for (final project in snapshot.data ?? const <CreativeDesignProject>[]) {
        entries.add(_PosterEntry(title: project.title, project: project));
      }
      final hasRealDesigns = entries.isNotEmpty;
      for (var i = 0; entries.length < 3; i++) {
        entries.add(_PosterEntry(sample: _samples[i % _samples.length]));
      }
      if (entries.length > 9) entries.removeRange(9, entries.length);

      final title = widget.language == 'sw'
          ? (hasRealDesigns ? 'POSTER ZAKO' : 'MIFANO YA UBUNIFU')
          : (hasRealDesigns ? 'YOUR DESIGNS' : 'DESIGN INSPIRATION');
      final subtitle = widget.language == 'sw'
          ? (hasRealDesigns
                ? 'Kazi zako za hivi karibuni'
                : 'Telezesha uone mawazo ya biashara')
          : (hasRealDesigns
                ? 'Your latest creative work'
                : 'Swipe through ideas for your business');

      return Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF111A2D),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF263653)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x291A6AFF),
              blurRadius: 28,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFF5577FF).withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Color(0xFF57D7FF),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFFF4F7FF),
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF8995B0),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.swipe_rounded,
                  color: Color(0xFF8995B0),
                  size: 19,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 205,
              child: PageView.builder(
                controller: _controller,
                itemCount: entries.length,
                onPageChanged: (index) => setState(() => _activePage = index),
                itemBuilder: (context, index) => AnimatedBuilder(
                  animation: _controller,
                  child: _posterCard(entries[index]),
                  builder: (context, child) {
                    var page = _activePage.toDouble();
                    if (_controller.hasClients &&
                        _controller.position.haveDimensions) {
                      page = _controller.page ?? _activePage.toDouble();
                    }
                    final distance = (page - index).abs().clamp(0.0, 1.0);
                    return Transform.scale(
                      scale: 1 - distance * .055,
                      child: Opacity(opacity: 1 - distance * .22, child: child),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(entries.length, (index) {
                final selected = index == _activePage % entries.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: selected ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF57D7FF)
                        : const Color(0xFF40506B),
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              }),
            ),
          ],
        ),
      );
    },
  );

  Widget _posterCard(_PosterEntry entry) {
    Widget image;
    if (entry.sample != null) {
      image = _samplePoster(entry.sample!);
    } else if (entry.previewUrl != null) {
      image = CachedNetworkImage(
        imageUrl: entry.previewUrl!,
        fit: BoxFit.cover,
        memCacheWidth: 720,
        maxWidthDiskCache: 720,
        fadeInDuration: const Duration(milliseconds: 120),
        placeholder: (_, _) => _posterFallback(entry.title, loading: true),
        errorWidget: (_, _, _) => _posterFallback(entry.title),
      );
    } else if (entry.project != null &&
        entry.project!.backgroundPath.isNotEmpty) {
      final project = entry.project!;
      final future = _imageUrls.putIfAbsent(
        project.id,
        () => creativeProjectBackgroundUrl(project),
      );
      image = FutureBuilder<String>(
        future: future,
        builder: (context, snapshot) => snapshot.hasData
            ? CachedNetworkImage(
                imageUrl: snapshot.data!,
                fit: BoxFit.cover,
                memCacheWidth: 720,
                maxWidthDiskCache: 720,
                fadeInDuration: const Duration(milliseconds: 120),
                placeholder: (_, _) =>
                    _posterFallback(entry.title, loading: true),
                errorWidget: (_, _, _) => _posterFallback(entry.title),
              )
            : _posterFallback(entry.title, loading: !snapshot.hasError),
      );
    } else {
      image = _posterFallback(entry.title);
    }
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC080D1B)],
                  stops: [0.38, 1],
                ),
              ),
            ),
            if (entry.sample case final sample?)
              Positioned(
                top: 7,
                right: 7,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filledTonal(
                      tooltip: widget.language == 'sw'
                          ? 'Tumia wazo hili na ujaze fomu'
                          : 'Use this idea and fill the form',
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xCC080D1B),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => widget.onUseIdea(sample),
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                    ),
                    IconButton.filledTonal(
                      tooltip: widget.language == 'sw'
                          ? 'Nakili prompt'
                          : 'Copy prompt',
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xCC080D1B),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        final prompt = widget.language == 'sw'
                            ? sample.swahiliPrompt
                            : sample.prompt;
                        await Clipboard.setData(ClipboardData(text: prompt));
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              widget.language == 'sw'
                                  ? 'Prompt imenakiliwa.'
                                  : 'Prompt copied.',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.content_copy_rounded, size: 16),
                    ),
                  ],
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (entry.sample != null)
                    const Text(
                      'INSPIRATION',
                      style: TextStyle(
                        color: Color(0xFF57D7FF),
                        fontSize: 8,
                        letterSpacing: .8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _samplePoster(_PosterSample sample) => Stack(
    fit: StackFit.expand,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: sample.colors,
          ),
        ),
      ),
      Positioned(
        right: -26,
        top: -28,
        child: Container(
          width: 130,
          height: 130,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: .10),
          ),
        ),
      ),
      Positioned(
        right: 26,
        top: 30,
        child: Icon(
          sample.icon,
          size: 82,
          color: Colors.white.withValues(alpha: .22),
        ),
      ),
      Positioned(
        left: 18,
        top: 22,
        child: Container(
          width: 30,
          height: 3,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .78),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
      Positioned(
        left: 18,
        bottom: 43,
        right: 18,
        child: Text(
          sample.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -.6,
          ),
        ),
      ),
      Positioned(
        left: 19,
        bottom: 25,
        child: Text(
          sample.subtitle.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: .8),
            fontSize: 8,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      Positioned(
        right: 18,
        bottom: 20,
        child: Icon(
          Icons.arrow_outward_rounded,
          size: 18,
          color: Colors.white.withValues(alpha: .85),
        ),
      ),
    ],
  );

  Widget _posterFallback(String title, {bool loading = false}) => Container(
    color: const Color(0xFF17233A),
    child: Center(
      child: loading
          ? const CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF57D7FF),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.image_not_supported_outlined,
                  color: Color(0xFF8995B0),
                  size: 28,
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFB7C2D9),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
    ),
  );
}

class _PosterEntry {
  const _PosterEntry({
    this.title = 'Design inspiration',
    this.previewUrl,
    this.project,
    this.sample,
  });

  final String title;
  final String? previewUrl;
  final CreativeDesignProject? project;
  final _PosterSample? sample;
}

class _PosterSample {
  const _PosterSample({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.category,
    required this.swahiliPrompt,
    required this.prompt,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final String category;
  final String swahiliPrompt;
  final String prompt;
}

class _CreativePosterVoiceGuide extends StatefulWidget {
  const _CreativePosterVoiceGuide({
    required this.language,
    required this.onPhotoRequested,
  });

  final String language;
  final Future<void> Function(bool fromCamera) onPhotoRequested;

  @override
  State<_CreativePosterVoiceGuide> createState() =>
      _CreativePosterVoiceGuideState();
}

class _CreativePosterVoiceGuideState extends State<_CreativePosterVoiceGuide> {
  final _speech = SpeechToText();
  final _tts = FlutterTts();
  final _typedAnswer = TextEditingController();
  final List<String> _answers = [];
  bool _speechAvailable = false;
  bool _listening = false;
  bool _working = false;
  bool _handlingAnswer = false;
  bool _autoListen = false;
  int _step = 0;
  String _transcript = '';
  String _status = '';
  String? _localeId;

  bool get _swahili => widget.language == 'sw';

  List<String> get _questions => _swahili
      ? const [
          'Tuanzie kwenye bidhaa au biashara yako. Unauza nini, na poster hii inatangaza nini?',
          'Kuna ofa, bei, au taarifa maalum unayotaka ionekane? Kama hakuna, sema hakuna.',
          'Unalenga wateja gani, na unapendelea rangi au mtindo gani wa muundo?',
          'Unataka mteja afanye nini baada ya kuona poster? Taja namba au eneo tu kama unataka liwekwe.',
        ]
      : const [
          'Let us start with your product or business. What do you sell, and what should the poster promote?',
          'Is there an offer, price, or important detail to show? Say none if there is not.',
          'Who are your target customers, and what colors or visual style do you prefer?',
          'What should customers do after seeing the poster? Say any phone number or location only if you want it printed.',
        ];

  @override
  void initState() {
    super.initState();
    _status = _swahili
        ? 'ISHER inajiandaa kusikiliza…'
        : 'ISHER is getting ready to listen…';
    _initializeVoice();
  }

  Future<void> _initializeVoice() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          setState(() => _listening = status == SpeechToText.listeningStatus);
        },
        onError: (SpeechRecognitionError error) {
          if (!mounted) return;
          setState(() {
            _listening = false;
            _status = _swahili
                ? 'Sauti haikupatikana. Unaweza kuandika jibu hapa chini.'
                : 'Voice input is unavailable. You can type your answer below.';
          });
        },
      );
      if (!mounted) return;
      String languageCode = _swahili ? 'sw' : 'en';
      final locales = available ? await _speech.locales() : <dynamic>[];
      for (final locale in locales) {
        if (locale.localeId.toString().toLowerCase().startsWith(languageCode)) {
          _localeId = locale.localeId.toString();
          break;
        }
      }
      _speechAvailable = available;
      _autoListen = available;
      try {
        await _tts.setLanguage(_swahili ? 'sw-TZ' : 'en-US');
        await _tts.setSpeechRate(.48);
        _tts.setCompletionHandler(() {
          if (_autoListen) unawaited(_listen());
        });
      } catch (_) {
        // Speech input and typed answers still work when device TTS is absent.
      }
      if (!mounted) return;
      setState(() {
        _status = available
            ? (_swahili
                  ? 'Jibu kwa sauti au andika.'
                  : 'Answer by voice or type.')
            : (_swahili
                  ? 'Sauti haipatikani kwenye kifaa hiki. Andika jibu hapa chini.'
                  : 'Voice is unavailable on this device. Type your answer below.');
      });
      await _askCurrentQuestion();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _speechAvailable = false;
        _autoListen = false;
        _status = _swahili
            ? 'Tumia sehemu ya kuandika kujibu maswali ya ISHER.'
            : 'Type your answers to ISHER’s questions below.';
      });
    }
  }

  Future<void> _askCurrentQuestion() async {
    if (_step >= _questions.length || !mounted) return;
    _autoListen = _speechAvailable;
    try {
      await _tts.speak(_questions[_step]);
    } catch (_) {
      if (_speechAvailable) await _listen();
    }
  }

  Future<void> _listen() async {
    if (!mounted || !_speechAvailable || _listening || _working) return;
    _transcript = '';
    setState(() {
      _listening = true;
      _status = _swahili ? 'Ninasikiliza…' : 'Listening…';
    });
    try {
      await _speech.listen(
        onResult: _onSpeechResult,
        localeId: _localeId,
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 35),
          pauseFor: const Duration(seconds: 4),
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _listening = false;
        _status = _swahili
            ? 'Gusa kipaza sauti ujaribu tena.'
            : 'Tap the microphone to try again.';
      });
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    setState(() => _transcript = result.recognizedWords.trim());
    if (result.finalResult && _transcript.isNotEmpty) {
      unawaited(_submitAnswer(_transcript));
    }
  }

  bool _isPhotoRequest(String text) {
    final value = text.toLowerCase();
    return value.contains('piga picha') ||
        value.contains('fungua kamera') ||
        value.contains('tumia kamera') ||
        value.contains('chukua picha') ||
        value.contains('camera') ||
        value.contains('kamera') ||
        value.contains('gallery') ||
        value.contains('galeri') ||
        value.contains('picha zilizopo') ||
        value.contains('take a photo') ||
        value.contains('open gallery') ||
        value.contains('open camera') ||
        value.contains('select from gallery') ||
        value.contains('choose photo') ||
        value.contains('select photo');
  }

  Future<void> _requestPhoto(bool fromCamera) async {
    _autoListen = false;
    await _speech.stop();
    await _tts.stop();
    if (!mounted) return;
    setState(() {
      _working = true;
      _listening = false;
      _status = _swahili ? 'Fungua picha ya bidhaa…' : 'Opening product photo…';
    });
    try {
      await widget.onPhotoRequested(fromCamera);
    } finally {
      if (!mounted) return;
      setState(() {
        _working = false;
        _status = _swahili
            ? 'Tuendelee na maelezo ya poster yako.'
            : 'Let us continue with your poster details.';
      });
      await _askCurrentQuestion();
    }
  }

  Future<void> _submitAnswer([String? voiceText]) async {
    if (_working || _handlingAnswer || _step >= _questions.length) return;
    final answer = (voiceText ?? _typedAnswer.text).trim();
    if (answer.isEmpty) return;
    _handlingAnswer = true;
    _autoListen = false;
    await _speech.stop();
    await _tts.stop();
    if (_isPhotoRequest(answer)) {
      _typedAnswer.clear();
      _transcript = '';
      _handlingAnswer = false;
      final normalized = answer.toLowerCase();
      final fromCamera =
          normalized.contains('camera') ||
          normalized.contains('kamera') ||
          normalized.contains('piga picha') ||
          normalized.contains('take a photo') ||
          normalized.contains('chukua picha') ||
          normalized.contains('fungua kamera') ||
          normalized.contains('open camera') ||
          normalized.contains('tumia kamera');
      await _requestPhoto(fromCamera);
      return;
    }
    _answers.add('${_questions[_step]}\n$answer');
    _typedAnswer.clear();
    _transcript = '';
    if (!mounted) return;
    setState(() {
      _step++;
      _listening = false;
      _status = _step < _questions.length
          ? (_swahili
                ? 'Jibu limehifadhiwa. Swali linalofuata…'
                : 'Answer saved. Next question…')
          : (_swahili
                ? 'Brief yako iko tayari kukaguliwa.'
                : 'Your brief is ready to review.');
    });
    _handlingAnswer = false;
    if (_step < _questions.length) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await _askCurrentQuestion();
    } else {
      try {
        await _tts.speak(
          _swahili
              ? 'Asante. Brief yako iko tayari. Kagua majibu kisha bonyeza tengeneza poster.'
              : 'Thank you. Your brief is ready. Review your answers and create the poster.',
        );
      } catch (_) {}
    }
  }

  String _buildBrief() => [
    if (_swahili)
      'Tengeneza poster nzuri ya biashara kwa Kiswahili cha Tanzania.'
    else
      'Create a professional business poster in English.',
    ..._answers,
    'Usibuni bei, punguzo, tarehe, anwani au namba ya simu ambazo sijataja.',
  ].join('\n\n');

  @override
  void dispose() {
    _autoListen = false;
    _speech.stop();
    _tts.stop();
    _typedAnswer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final complete = _step >= _questions.length;
    final question = complete
        ? (_swahili ? 'Brief yako tayari' : 'Your brief is ready')
        : _questions[_step];
    return Dialog(
      backgroundColor: const Color(0xFF111A2D),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFF263653)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 690),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF5577FF).withValues(alpha: .2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.graphic_eq_rounded,
                      color: Color(0xFF57D7FF),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _swahili
                              ? 'ISHER · MWONGOZO WA POSTER'
                              : 'ISHER · POSTER GUIDE',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _swahili
                              ? 'Hatua ${(_step + 1).clamp(1, _questions.length)} kati ya ${_questions.length}'
                              : 'Step ${(_step + 1).clamp(1, _questions.length)} of ${_questions.length}',
                          style: const TextStyle(
                            color: Color(0xFF8995B0),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _working ? null : () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF8995B0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: complete ? 1 : _step / _questions.length,
                  minHeight: 5,
                  backgroundColor: const Color(0xFF263653),
                  color: const Color(0xFF57D7FF),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                question,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (complete) ...[
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      _answers
                          .map((answer) => answer.split('\n').last)
                          .join('\n\n'),
                      style: const TextStyle(
                        color: Color(0xFFB7C2D9),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 92),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF17233A),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF263653)),
                  ),
                  child: Text(
                    _transcript.isEmpty
                        ? (_swahili
                              ? 'Jibu lako litaonekana hapa…'
                              : 'Your answer will appear here…')
                        : _transcript,
                    style: TextStyle(
                      color: _transcript.isEmpty
                          ? const Color(0xFF8995B0)
                          : Colors.white,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _status,
                  style: const TextStyle(
                    color: Color(0xFF8995B0),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _typedAnswer,
                  enabled: !_working,
                  onTap: () {
                    _autoListen = false;
                    _tts.stop();
                    if (_listening) {
                      _speech.stop();
                      setState(() => _listening = false);
                    }
                  },
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submitAnswer(),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: _swahili
                        ? 'Au andika jibu hapa…'
                        : 'Or type your answer…',
                    hintStyle: const TextStyle(color: Color(0xFF8995B0)),
                    filled: true,
                    fillColor: const Color(0xFF080D1B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: const BorderSide(color: Color(0xFF263653)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: const BorderSide(color: Color(0xFF263653)),
                    ),
                    suffixIcon: IconButton(
                      tooltip: _swahili ? 'Tuma jibu' : 'Submit answer',
                      onPressed: _working ? null : () => _submitAnswer(),
                      icon: const Icon(
                        Icons.send_rounded,
                        color: Color(0xFF57D7FF),
                        size: 19,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!complete)
                    FilledButton.tonalIcon(
                      onPressed: _working || !_speechAvailable
                          ? null
                          : () async {
                              if (_listening) {
                                final words = _transcript;
                                await _speech.stop();
                                if (mounted) setState(() => _listening = false);
                                if (words.isNotEmpty) {
                                  await _submitAnswer(words);
                                }
                              } else {
                                await _listen();
                              }
                            },
                      icon: Icon(
                        _listening ? Icons.stop_rounded : Icons.mic_rounded,
                      ),
                      label: Text(
                        _listening
                            ? (_swahili ? 'Simamisha' : 'Stop')
                            : (_swahili ? 'Jibu kwa sauti' : 'Answer by voice'),
                      ),
                    ),
                  if (!complete)
                    OutlinedButton.icon(
                      onPressed: _working ? null : () => _requestPhoto(true),
                      icon: const Icon(Icons.camera_alt_outlined, size: 17),
                      label: Text(_swahili ? 'Piga picha' : 'Camera'),
                    ),
                  if (!complete)
                    OutlinedButton.icon(
                      onPressed: _working ? null : () => _requestPhoto(false),
                      icon: const Icon(Icons.photo_library_outlined, size: 17),
                      label: Text(_swahili ? 'Gallery' : 'Gallery'),
                    ),
                  if (complete)
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(context, _buildBrief()),
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: Text(
                        _swahili ? 'Tengeneza poster' : 'Create poster',
                      ),
                    ),
                ],
              ),
              if (!complete) ...[
                const SizedBox(height: 10),
                Text(
                  _swahili
                      ? 'Unaweza pia kusema “piga picha” au “fungua gallery” ili kuongeza picha ya bidhaa.'
                      : 'You can also say “take a photo” or “open gallery” to add a product image.',
                  style: const TextStyle(
                    color: Color(0xFF738096),
                    fontSize: 10,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
