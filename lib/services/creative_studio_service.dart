import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:uuid/uuid.dart';

class CreativeBrandProfile {
  const CreativeBrandProfile({
    required this.id,
    required this.name,
    required this.colors,
    required this.typography,
    required this.slogan,
    required this.guidelines,
    required this.logoUrl,
  });

  final String id;
  final String name;
  final List<String> colors;
  final String typography;
  final String slogan;
  final String guidelines;
  final String logoUrl;

  Map<String, dynamic> toMap() => {
    'name': name.trim(),
    'colors': colors
        .map((color) => color.trim())
        .where((color) => color.isNotEmpty)
        .take(6)
        .toList(),
    'typography': typography.trim(),
    'slogan': slogan.trim(),
    'guidelines': guidelines.trim(),
    'logoUrl': logoUrl.trim(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  factory CreativeBrandProfile.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return CreativeBrandProfile(
      id: doc.id,
      name: data['name']?.toString() ?? '',
      colors: (data['colors'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(),
      typography: data['typography']?.toString() ?? '',
      slogan: data['slogan']?.toString() ?? '',
      guidelines: data['guidelines']?.toString() ?? '',
      logoUrl: data['logoUrl']?.toString() ?? '',
    );
  }
}

CollectionReference<Map<String, dynamic>> _creativeBrands() => FirebaseFirestore
    .instance
    .collection('users')
    .doc(BusinessAccessService.businessId)
    .collection('creativeStudioBrands');

Stream<List<CreativeBrandProfile>> watchCreativeBrands() => _creativeBrands()
    .orderBy('name')
    .snapshots()
    .map(
      (snapshot) =>
          snapshot.docs.map(CreativeBrandProfile.fromDocument).toList(),
    );

Future<String> saveCreativeBrand(CreativeBrandProfile profile) async {
  if (!BusinessAccessService.isOwner.value) {
    throw StateError('Only the business owner can manage brand profiles.');
  }
  if (profile.name.trim().isEmpty || profile.name.trim().length > 100) {
    throw ArgumentError('Brand name must be between 1 and 100 characters.');
  }
  final ref = _creativeBrands().doc(profile.id.isEmpty ? null : profile.id);
  final payload = profile.toMap();
  if (profile.id.isEmpty) payload['createdAt'] = FieldValue.serverTimestamp();
  await ref.set(payload, SetOptions(merge: true));
  return ref.id;
}

Future<void> deleteCreativeBrand(String id) async {
  if (!BusinessAccessService.isOwner.value) {
    throw StateError('Only the business owner can manage brand profiles.');
  }
  await _creativeBrands().doc(id).delete();
}

class CreativeDesignPlan {
  const CreativeDesignPlan({required this.values});

  final Map<String, dynamic> values;

  static const _labels = <String, String>{
    'objective': 'Design objective',
    'audience': 'Target audience',
    'hierarchy': 'Visual hierarchy',
    'palette': 'Color direction',
    'typography': 'Typography',
    'composition': 'Composition',
    'imagery': 'Image direction',
    'copyGuidance': 'Copy guidance',
    'printNotes': 'Production notes',
  };

  static const _swahiliLabels = <String, String>{
    'objective': 'Lengo la muundo',
    'audience': 'Walengwa',
    'hierarchy': 'Mpangilio wa taarifa',
    'palette': 'Mwelekeo wa rangi',
    'typography': 'Mtindo wa maandishi',
    'composition': 'Mpangilio wa picha',
    'imagery': 'Mwelekeo wa picha na vielelezo',
    'copyGuidance': 'Mwongozo wa ujumbe',
    'printNotes': 'Maelekezo ya uchapishaji',
  };

  static String labelFor(String key, {String language = 'en'}) =>
      (language == 'sw' ? _swahiliLabels[key] : null) ?? _labels[key] ?? key;

  static Future<CreativeDesignPlan> create({
    required String brief,
    required String category,
    required String size,
    required String language,
  }) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('planCreativeStudioDesign')
        .call({
          'businessUid': BusinessAccessService.businessId,
          'brief': brief,
          'category': category,
          'size': size,
          'language': language,
        });
    final data = Map<String, dynamic>.from(result.data as Map);
    return CreativeDesignPlan(
      values: Map<String, dynamic>.from(data['plan'] as Map),
    );
  }
}

class GeneratedDesignConcept {
  const GeneratedDesignConcept({
    required this.designId,
    required this.storagePath,
    required this.previewUrl,
    required this.width,
    required this.height,
    required this.format,
    this.copy = const {},
  });

  final String designId;
  final String storagePath;
  final String previewUrl;
  final int width;
  final int height;
  final String format;
  final Map<String, String> copy;
}

Future<GeneratedDesignConcept> generateDesignConcept({
  required String prompt,
  required String category,
  required String size,
  required String aspect,
  required String language,
  required String model,
  String? referencePath,
}) async {
  final result = await FirebaseFunctions.instance
      .httpsCallable(
        'generateCreativeStudioConcept',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
      )
      .call({
        'businessUid': BusinessAccessService.businessId,
        'prompt': prompt,
        'category': category,
        'size': size,
        'aspect': aspect,
        'language': language,
        'model': model,
        if (referencePath != null) 'referencePath': referencePath,
      });
  final data = Map<String, dynamic>.from(result.data as Map);
  return GeneratedDesignConcept(
    designId: data['designId'] as String,
    storagePath: data['storagePath'] as String,
    previewUrl: data['previewUrl'] as String,
    width: data['width'] as int,
    height: data['height'] as int,
    format: data['format'] as String,
    copy: Map<String, String>.from(data['copy'] as Map? ?? const {}),
  );
}

Future<Map<String, String>> generateCreativePosterCopy({
  required String brief,
  required String language,
  required String category,
}) async {
  final result = await FirebaseFunctions.instance
      .httpsCallable('generateCreativePosterCopy')
      .call({
        'businessUid': BusinessAccessService.businessId,
        'brief': brief,
        'language': language,
        'category': category,
      });
  final data = Map<String, dynamic>.from(result.data as Map);
  return {
    'headline': data['headline']?.toString() ?? '',
    'supportingText': data['supportingText']?.toString() ?? '',
    'callToAction': data['callToAction']?.toString() ?? '',
  };
}

class CreativeTextLayer {
  const CreativeTextLayer({
    required this.id,
    required this.text,
    required this.x,
    required this.y,
    required this.fontSize,
    required this.color,
    required this.bold,
    this.type = 'text',
    this.assetPath = '',
    this.imageWidth = .32,
    this.imageHeight = .24,
  });

  final String id;
  final String text;
  final double x;
  final double y;
  final double fontSize;
  final int color;
  final bool bold;
  final String type;
  final String assetPath;
  final double imageWidth;
  final double imageHeight;

  Map<String, dynamic> toMap() => {
    'id': id,
    'text': text,
    'x': x,
    'y': y,
    'fontSize': fontSize,
    'color': color,
    'bold': bold,
    'type': type,
    'assetPath': assetPath,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
  };

  factory CreativeTextLayer.fromMap(Map<String, dynamic> map) =>
      CreativeTextLayer(
        id: map['id'] as String,
        text: map['text'] as String,
        x: (map['x'] as num).toDouble(),
        y: (map['y'] as num).toDouble(),
        fontSize: (map['fontSize'] as num).toDouble(),
        color: map['color'] as int,
        bold: map['bold'] as bool? ?? false,
        type: map['type'] as String? ?? 'text',
        assetPath: map['assetPath'] as String? ?? '',
        imageWidth: (map['imageWidth'] as num?)?.toDouble() ?? .32,
        imageHeight: (map['imageHeight'] as num?)?.toDouble() ?? .24,
      );
}

class CreativeDesignProject {
  const CreativeDesignProject({
    required this.id,
    required this.title,
    required this.backgroundPath,
    required this.width,
    required this.height,
    required this.layers,
  });
  final String id;
  final String title;
  final String backgroundPath;
  final int width;
  final int height;
  final List<CreativeTextLayer> layers;

  factory CreativeDesignProject.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return CreativeDesignProject(
      id: doc.id,
      title: data['title']?.toString() ?? 'Untitled design',
      backgroundPath: data['backgroundPath']?.toString() ?? '',
      width: (data['width'] as num?)?.toInt() ?? 1024,
      height: (data['height'] as num?)?.toInt() ?? 1024,
      layers: (data['layers'] as List? ?? const [])
          .map(
            (entry) => CreativeTextLayer.fromMap(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList(),
    );
  }
}

CollectionReference<Map<String, dynamic>> _creativeProjects() =>
    FirebaseFirestore.instance
        .collection('users')
        .doc(BusinessAccessService.businessId)
        .collection('creativeStudioProjects');

Stream<List<CreativeDesignProject>> watchCreativeProjects() =>
    _creativeProjects()
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(CreativeDesignProject.fromDocument).toList(),
        );

Future<String> saveCreativeProject(CreativeDesignProject project) async {
  if (!BusinessAccessService.can('profile', 'edit')) {
    throw StateError(
      'Your account cannot save design projects for this business.',
    );
  }
  if (project.title.trim().isEmpty ||
      project.title.length > 120 ||
      project.layers.length > 40) {
    throw ArgumentError('Project title or number of layers is invalid.');
  }
  final ref = _creativeProjects().doc(project.id.isEmpty ? null : project.id);
  await ref.set({
    'title': project.title.trim(),
    'backgroundPath': project.backgroundPath,
    'width': project.width,
    'height': project.height,
    'layers': project.layers.map((layer) => layer.toMap()).toList(),
    'updatedAt': FieldValue.serverTimestamp(),
    if (project.id.isEmpty) 'createdAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
  return ref.id;
}

Future<void> deleteCreativeProject(String id) async {
  if (!BusinessAccessService.can('profile', 'edit')) {
    throw StateError(
      'Your account cannot delete design projects for this business.',
    );
  }
  await _creativeProjects().doc(id).delete();
}

Future<String> creativeProjectBackgroundUrl(
  CreativeDesignProject project,
) async {
  final result = await FirebaseFunctions.instance
      .httpsCallable('getCreativeStudioProjectImageUrl')
      .call({
        'businessUid': BusinessAccessService.businessId,
        'projectId': project.id,
      });
  return (result.data as Map)['url'] as String;
}

Future<String> uploadCreativeReference({
  required Uint8List bytes,
  required String extension,
}) async {
  final businessUid = BusinessAccessService.businessId;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) throw StateError('Sign in to upload a reference image.');
  final normalizedExtension = extension.toLowerCase() == 'jpeg'
      ? 'jpg'
      : extension.toLowerCase();
  final contentType = switch (normalizedExtension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'jpg' => 'image/jpeg',
    _ => throw ArgumentError('Choose a JPG, PNG or WebP image.'),
  };
  if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
    throw ArgumentError('Reference images must be under 8 MB.');
  }
  final fileName = '${const Uuid().v4()}.$normalizedExtension';
  final ref = FirebaseStorage.instance.ref(
    'creativeStudio/$businessUid/references/$uid/$fileName',
  );
  await ref.putData(bytes, SettableMetadata(contentType: contentType));
  return ref.fullPath;
}

Future<Map<String, dynamic>> analyzeCreativeReference({
  required String filePath,
  required String instructions,
  required String language,
}) async {
  final result = await FirebaseFunctions.instance
      .httpsCallable('analyzeCreativeStudioReference')
      .call({
        'businessUid': BusinessAccessService.businessId,
        'filePath': filePath,
        'instructions': instructions,
        'language': language,
      });
  final data = Map<String, dynamic>.from(result.data as Map);
  return Map<String, dynamic>.from(data['analysis'] as Map);
}

Future<void> deleteCreativeReference(String filePath) async {
  await FirebaseStorage.instance.ref(filePath).delete();
}

Future<String> uploadCreativeOverlay({
  required Uint8List bytes,
  required String extension,
}) async {
  if (!BusinessAccessService.can('profile', 'edit')) {
    throw StateError('Your account cannot edit design projects.');
  }
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) throw StateError('Sign in to add an image layer.');
  final normalized = extension.toLowerCase() == 'jpeg'
      ? 'jpg'
      : extension.toLowerCase();
  final contentType = switch (normalized) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'jpg' => 'image/jpeg',
    _ => throw ArgumentError('Choose a JPG, PNG or WebP image.'),
  };
  if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
    throw ArgumentError('Logo and overlay images must be under 5 MB.');
  }
  final fileName = '${const Uuid().v4()}.$normalized';
  final reference = FirebaseStorage.instance.ref(
    'creativeStudio/${BusinessAccessService.businessId}/assets/$uid/$fileName',
  );
  await reference.putData(bytes, SettableMetadata(contentType: contentType));
  return reference.fullPath;
}

Future<String> creativeOverlayDownloadUrl(String assetPath) =>
    FirebaseStorage.instance.ref(assetPath).getDownloadURL();
