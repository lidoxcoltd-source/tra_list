import 'dart:typed_data';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/account_mode_service.dart';
import 'package:tra_list/services/company_logo_service.dart';
import 'package:tra_list/services/profile_service.dart';

import 'market_audio.dart';
import 'market_video.dart';
import 'market_models.dart';

class MarketPostPage {
  const MarketPostPage({
    required this.posts,
    required this.lastDocument,
    required this.hasMore,
  });

  final List<MarketPost> posts;
  final QueryDocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;
}

class MarketService {
  MarketService._();

  static final _firestore = FirebaseFirestore.instance;

  static Future<void> publishPost({
    required String type,
    required String caption,
    required String category,
    required String productName,
    required String productId,
    required String productOwnerUid,
    required double price,
    required bool inStock,
    required List<Uint8List> imageBytes,
    required List<String> imageExtensions,
    MarketAudioSelection? audio,
    MarketVideoSelection? video,
    DateTime? publishAt,
    int textBg = -1,
    int textFont = 0,
    void Function(double progress)? onProgress,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to publish.');
    if (!{'post', 'status', 'product'}.contains(type)) {
      throw ArgumentError('Unsupported post type.');
    }
    final isProduct = type == 'product';
    final businessMode =
        AccountModeService.current == AccountMode.business &&
        BusinessAccessService.hasBusinessAccess;
    if (isProduct &&
        (!businessMode || !BusinessAccessService.can('stock', 'create'))) {
      throw StateError(
        'A business seller permission is required to publish products.',
      );
    }
    final textOnly = imageBytes.isEmpty && video == null;
    if ((textOnly && (isProduct || caption.trim().isEmpty)) ||
        imageBytes.length > 10 ||
        imageBytes.length != imageExtensions.length) {
      throw ArgumentError('Choose between 1 and 10 valid images.');
    }
    if (isProduct && price < 0) {
      throw ArgumentError('Price cannot be negative.');
    }
    if (video != null) {
      if (!businessMode || !BusinessAccessService.can('stock', 'create')) {
        throw StateError('market_video_business_only'.tr);
      }
      if (video.bytes.length > marketVideoMaxBytes) {
        throw ArgumentError('market_video_too_large'.tr);
      }
    }
    final isBusinessOwner = businessMode && BusinessAccessService.isOwner.value;
    final authorUid = isProduct || isBusinessOwner
        ? BusinessAccessService.businessId
        : user.uid;
    final contactUid = businessMode
        ? BusinessAccessService.businessId
        : authorUid;
    final whatsapp = await _resolveProfileWhatsApp(contactUid);
    if (whatsapp.length < 8 || whatsapp.length > 15) {
      throw StateError('market_seller_whatsapp_missing'.tr);
    }
    final postRef = _firestore.collection('marketPosts').doc();
    final uploadedRefs = <Reference>[];
    try {
      final imageUrls = <String>[];
      final totalBytes = imageBytes.fold<int>(
        0,
        (total, bytes) => total + bytes.length,
      );
      var completedBytes = 0;
      for (var index = 0; index < imageBytes.length; index++) {
        final extension = imageExtensions[index].toLowerCase();
        final contentType = switch (extension) {
          'jpg' || 'jpeg' => 'image/jpeg',
          'png' => 'image/png',
          'webp' => 'image/webp',
          _ => throw ArgumentError('Unsupported image format.'),
        };
        if (imageBytes[index].length > 5 * 1024 * 1024) {
          throw ArgumentError('Each image must be 5 MB or smaller.');
        }

        final imageRef = FirebaseStorage.instance.ref(
          'market/$authorUid/${postRef.id}_${index + 1}.$extension',
        );
        uploadedRefs.add(imageRef);
        final upload = imageRef.putData(
          imageBytes[index],
          SettableMetadata(contentType: contentType),
        );
        await for (final snapshot in upload.snapshotEvents) {
          if (totalBytes > 0) {
            onProgress?.call(
              (completedBytes + snapshot.bytesTransferred) / totalBytes,
            );
          }
        }
        completedBytes += imageBytes[index].length;
        imageUrls.add(await imageRef.getDownloadURL());
      }

      var audioUrl = audio?.url ?? '';
      var videoUrl = '';
      if (video != null) {
        final extension = video.extension.toLowerCase();
        if (!marketVideoExtensions.contains(extension)) {
          throw ArgumentError('Unsupported video format.');
        }
        final videoRef = FirebaseStorage.instance.ref(
          'market/$authorUid/video/${postRef.id}.$extension',
        );
        uploadedRefs.add(videoRef);
        await videoRef.putData(
          video.bytes,
          SettableMetadata(contentType: marketVideoContentType(extension)),
        );
        videoUrl = await videoRef.getDownloadURL();
      }
      final audioBytes = audio?.bytes;
      if (audio != null && audioBytes != null) {
        if (audioBytes.length > marketAudioMaxBytes) {
          throw ArgumentError('Sound must be 5 MB or smaller.');
        }
        final extension = audio.extension.toLowerCase();
        final audioRef = FirebaseStorage.instance.ref(
          'market/$authorUid/audio/${postRef.id}.$extension',
        );
        uploadedRefs.add(audioRef);
        await audioRef.putData(
          audioBytes,
          SettableMetadata(contentType: marketAudioContentType(extension)),
        );
        audioUrl = await audioRef.getDownloadURL();
      }

      final businessName = (isProduct || isBusinessOwner)
          ? BusinessAccessService.businessName.value.trim()
          : '';
      final userName = (user.displayName ?? '').trim();
      await postRef.set({
        'authorUid': authorUid,
        'authorName': (isProduct || isBusinessOwner) && businessName.isNotEmpty
            ? businessName
            : userName.isNotEmpty
            ? userName
            : (user.email ?? 'MJASI user'),
        'authorPhotoUrl': user.photoURL ?? '',
        'type': type,
        'caption': caption.trim(),
        'category': category,
        'images': imageUrls,
        'productId': productId,
        'productOwnerUid': productOwnerUid,
        'productName': productName.trim(),
        'price': price,
        'currency': 'TZS',
        'inStock': inStock,
        'whatsapp': whatsapp.replaceAll(RegExp(r'\D'), ''),
        'likesCount': 0,
        'commentsCount': 0,
        'hidden': false,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': null,
        if (videoUrl.isNotEmpty) 'videoUrl': videoUrl,
        if (textOnly && textBg >= 0) 'textBg': textBg,
        if (textOnly && textFont > 0) 'textFont': textFont,
        if (publishAt != null && type != 'status')
          'publishAt': Timestamp.fromDate(publishAt),
        if (audioUrl.isNotEmpty) 'audioUrl': audioUrl,
        if (audioUrl.isNotEmpty)
          'audioTitle': (audio?.title ?? '').trim().length > 80
              ? audio!.title.trim().substring(0, 80)
              : (audio?.title ?? '').trim(),
      });
    } catch (_) {
      for (final ref in uploadedRefs) {
        try {
          await ref.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Shops whose name starts with [query]; the alphabetical list when empty.
  static Future<List<MarketProfile>> searchProfiles(String query) async {
    final term = query.trim().toLowerCase();
    if (term.isEmpty) {
      final snapshot = await _firestore
          .collection('publicProfiles')
          .orderBy('nameLower')
          .limit(30)
          .get();
      return snapshot.docs.map(MarketProfile.fromDoc).toList();
    }
    final snapshot = await _firestore
        .collection('publicProfiles')
        .orderBy('nameLower')
        .limit(300)
        .get();
    return snapshot.docs
        .map(MarketProfile.fromDoc)
        .where(
          (shop) =>
              shop.name.toLowerCase().contains(term) ||
              shop.city.toLowerCase().contains(term),
        )
        .take(30)
        .toList();
  }

  static Future<MarketProfile?> getPublicProfile(
    String uid, {
    bool includeFollowCounts = false,
  }) async {
    final snapshot = await _firestore
        .collection('publicProfiles')
        .doc(uid)
        .get();
    final businessData = await _readBusinessProfileIfAvailable(uid);
    final counts = includeFollowCounts
        ? await getMarketFollowCounts(uid)
        : null;
    if (!snapshot.exists) {
      final user = FirebaseAuth.instance.currentUser;
      final isOwnUser = user?.uid == uid;
      final isSelectedBusiness =
          BusinessAccessService.hasBusinessAccess &&
          BusinessAccessService.businessId == uid;
      if (!isOwnUser && !isSelectedBusiness) return null;
      final businessName = (businessData?['name'] ?? '').toString().trim();
      final businessLogoUrl = businessData?['marketPhotoMode'] == 'custom'
          ? ''
          : _publicBusinessLogoUrl(businessData);
      final name = businessName.isNotEmpty
          ? businessName
          : isSelectedBusiness
          ? BusinessAccessService.businessName.value.trim()
          : user?.displayName?.trim() ?? '';
      return MarketProfile(
        uid: uid,
        name: name.isEmpty ? 'MJASI user' : name,
        photoUrl: businessLogoUrl.isNotEmpty
            ? businessLogoUrl
            : user?.photoURL ?? '',
        whatsapp: (businessData?['phone'] ?? '').toString(),
        followersCount: counts?.$1 ?? 0,
        followingCount: counts?.$2 ?? 0,
      );
    }
    final profile = MarketProfile.fromDoc(snapshot);
    final businessName = (businessData?['name'] ?? '').toString().trim();
    final businessPhone = (businessData?['phone'] ?? '').toString().trim();
    final businessLogoUrl = businessData?['marketPhotoMode'] == 'custom'
        ? ''
        : _publicBusinessLogoUrl(businessData);
    if (counts == null &&
        businessName.isEmpty &&
        businessPhone.isEmpty &&
        businessLogoUrl.isEmpty) {
      return profile;
    }
    return MarketProfile(
      uid: profile.uid,
      name: businessName.isNotEmpty ? businessName : profile.name,
      category: profile.category,
      bio: profile.bio,
      city: profile.city,
      photoUrl: businessLogoUrl.isNotEmpty ? businessLogoUrl : profile.photoUrl,
      whatsapp: businessPhone.isNotEmpty ? businessPhone : profile.whatsapp,
      followersCount: counts?.$1 ?? profile.followersCount,
      followingCount: counts?.$2 ?? profile.followingCount,
      postsCount: profile.postsCount,
    );
  }

  static String _publicBusinessLogoUrl(Map<String, dynamic>? businessData) {
    if (businessData == null ||
        businessData['logoSource']?.toString().toLowerCase() == 'local') {
      return '';
    }
    final url = businessData['logoUrl']?.toString().trim() ?? '';
    final uri = Uri.tryParse(url);
    return uri?.scheme == 'https' && uri!.host.isNotEmpty ? url : '';
  }

  static Future<({String url, Uint8List? bytes})?> loadBusinessProfilePhoto(
    String uid,
  ) async {
    final canEditBusiness =
        AccountModeService.current == AccountMode.business &&
        BusinessAccessService.hasBusinessAccess &&
        BusinessAccessService.businessId == uid &&
        BusinessAccessService.can('profile', 'edit');
    if (!canEditBusiness) {
      throw StateError('You cannot edit this business profile.');
    }

    final business = await ProfileService.loadOrCreate();
    if (business['logoSource']?.toString().toLowerCase() == 'local') {
      final bytes = BusinessAccessService.isOwner.value
          ? await CompanyLogoService.loadLocalLogoBytes()
          : null;
      return bytes == null ? null : (url: '', bytes: bytes);
    }
    final url = _publicBusinessLogoUrl(business);
    return url.isEmpty ? null : (url: url, bytes: null);
  }

  static Future<String> uploadMarketProfilePhoto({
    required String uid,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final isSelectedBusiness =
        AccountModeService.current == AccountMode.business &&
        BusinessAccessService.hasBusinessAccess &&
        BusinessAccessService.businessId == uid &&
        BusinessAccessService.can('profile', 'edit');
    if (user == null || (user.uid != uid && !isSelectedBusiness)) {
      throw StateError('You cannot edit this Market profile.');
    }
    if (bytes.isEmpty || bytes.length >= 5 * 1024 * 1024) {
      throw ArgumentError('Choose an image smaller than 5 MB.');
    }
    final extension = fileName.split('.').last.toLowerCase();
    final contentType = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => throw ArgumentError('Choose a JPG, PNG, or WebP image.'),
    };
    final storageRef = FirebaseStorage.instance.ref(
      'market/$uid/profile-images/${DateTime.now().millisecondsSinceEpoch}.$extension',
    );
    await storageRef.putData(bytes, SettableMetadata(contentType: contentType));
    return storageRef.getDownloadURL();
  }

  static Future<void> setMarketProfilePhoto({
    required String uid,
    required String source,
    required String photoUrl,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final isSelectedBusiness =
        AccountModeService.current == AccountMode.business &&
        BusinessAccessService.hasBusinessAccess &&
        BusinessAccessService.businessId == uid &&
        BusinessAccessService.can('profile', 'edit');
    final isOwnProfile = user?.uid == uid;
    if (user == null || (!isOwnProfile && !isSelectedBusiness)) {
      throw StateError('You cannot edit this Market profile.');
    }
    if (!{'business', 'custom'}.contains(source) ||
        (source == 'business' && !isSelectedBusiness)) {
      throw ArgumentError('Choose a valid Market profile image source.');
    }
    final uri = Uri.tryParse(photoUrl.trim());
    if (uri?.scheme != 'https' || uri!.host.isEmpty) {
      throw ArgumentError('The profile image URL is invalid.');
    }

    final ref = _firestore.collection('publicProfiles').doc(uid);
    final snapshot = await ref.get();
    final data = snapshot.data() ?? const <String, dynamic>{};
    final savedName = data['name']?.toString().trim() ?? '';
    final businessName = BusinessAccessService.businessName.value.trim();
    final name =
        (savedName.isNotEmpty
                ? savedName
                : businessName.isNotEmpty
                ? businessName
                : user.displayName?.trim() ?? '')
            .trim();
    if (name.isEmpty || name.length > 80) {
      throw StateError('Add a valid profile name before changing its image.');
    }

    final batch = _firestore.batch();
    if (isSelectedBusiness) {
      batch.set(_firestore.doc('users/$uid/profile/company'), {
        'marketPhotoMode': source,
        if (source == 'business') 'marketBusinessPhotoUrl': photoUrl.trim(),
      }, SetOptions(merge: true));
    }
    batch.set(ref, {
      'name': name,
      'nameLower': name.toLowerCase(),
      'category': data['category'] ?? '',
      'bio': data['bio'] ?? '',
      'city': data['city'] ?? '',
      'photoUrl': photoUrl.trim(),
      'whatsapp': data['whatsapp'] ?? '',
      'followersCount': data['followersCount'] ?? 0,
      'followingCount': data['followingCount'] ?? 0,
      'postsCount': data['postsCount'] ?? 0,
      if (!snapshot.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  static Future<Map<String, dynamic>?> _readBusinessProfileIfAvailable(
    String uid,
  ) async {
    final selectedBusiness =
        BusinessAccessService.hasBusinessAccess &&
        BusinessAccessService.businessId == uid &&
        BusinessAccessService.canReadBusinessProfile();
    final currentUser = FirebaseAuth.instance.currentUser;
    if (!selectedBusiness && currentUser?.uid != uid) return null;

    try {
      if (selectedBusiness) return await ProfileService.loadOrCreate();
      final snapshot = await _firestore.doc('users/$uid/profile/company').get();
      return snapshot.data();
    } catch (error) {
      debugPrint('Business profile unavailable for Market: $error');
      return null;
    }
  }

  static Future<(int, int)> getMarketFollowCounts(String uid) async {
    final counts = await Future.wait([
      _firestore
          .collectionGroup('following')
          .where('followingUid', isEqualTo: uid)
          .count()
          .get(),
      _firestore
          .collectionGroup('following')
          .where('followerUid', isEqualTo: uid)
          .count()
          .get(),
    ]);
    return (counts[0].count ?? 0, counts[1].count ?? 0);
  }

  static Stream<List<MarketBusinessDocument>> watchBusinessDocuments(
    String uid,
  ) => _firestore
      .collection('publicProfiles')
      .doc(uid)
      .collection('businessDocuments')
      .orderBy('uploadedAt')
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs.map(MarketBusinessDocument.fromDoc).toList(),
      );

  static Stream<bool> watchBusinessVerified(String uid) => _firestore
      .collection('marketBusinessVerifications')
      .doc(uid)
      .snapshots()
      .map((snapshot) => snapshot.data()?['verified'] == true);

  static Future<List<MarketBusinessReview>> loadBusinessReviews() async {
    // No orderBy: it would need a collection-group index. Sorted below.
    final submitted = await _firestore
        .collectionGroup('businessDocuments')
        .limit(500)
        .get();
    final grouped = <String, Map<String, MarketBusinessDocument>>{};
    for (final doc in submitted.docs) {
      final businessUid = doc.reference.parent.parent?.id;
      if (businessUid == null || businessUid.isEmpty) continue;
      grouped.putIfAbsent(businessUid, () => {})[doc.id] =
          MarketBusinessDocument.fromDoc(doc);
    }

    final reviews = await Future.wait(
      grouped.entries.map((entry) async {
        MarketProfile profile = MarketProfile(uid: entry.key, name: '');
        var verified = false;
        try {
          final snapshot = await _firestore
              .collection('publicProfiles')
              .doc(entry.key)
              .get();
          if (snapshot.exists) profile = MarketProfile.fromDoc(snapshot);
          final verification = await _firestore
              .collection('marketBusinessVerifications')
              .doc(entry.key)
              .get();
          verified = verification.data()?['verified'] == true;
        } catch (_) {
          // Keep the submission visible even if a lookup fails.
        }
        return MarketBusinessReview(
          profile: profile,
          documents: entry.value.values.toList(),
          verified: verified,
        );
      }),
    );
    reviews.sort((a, b) {
      if (a.verified != b.verified) return a.verified ? 1 : -1;
      final aTime = a.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return reviews;
  }

  static Future<void> setBusinessVerified({
    required String businessUid,
    required bool verified,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to review businesses.');
    await _firestore
        .collection('marketBusinessVerifications')
        .doc(businessUid)
        .set({
          'businessUid': businessUid,
          'verified': verified,
          'verifiedBy': uid,
          'verifiedAt': verified ? FieldValue.serverTimestamp() : null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  static Future<void> uploadBusinessDocument({
    required String uid,
    required String type,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final canEditBusiness =
        AccountModeService.current == AccountMode.business &&
        BusinessAccessService.hasBusinessAccess &&
        BusinessAccessService.businessId == uid &&
        BusinessAccessService.can('profile', 'edit');
    if (user == null || !canEditBusiness) {
      throw StateError('You cannot edit this business profile.');
    }
    if (!{'tin', 'tra', 'brela', 'other'}.contains(type)) {
      throw ArgumentError('Unsupported business document type.');
    }
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw ArgumentError('Choose a document smaller than 10 MB.');
    }
    final extension = fileName.split('.').last.toLowerCase();
    final contentType = switch (extension) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => throw ArgumentError('Choose PDF, JPG, PNG, or WebP.'),
    };
    final documentId = _firestore
        .collection('publicProfiles')
        .doc(uid)
        .collection('businessDocuments')
        .doc(type);
    final previous = await documentId.get();
    final previousPath = previous.data()?['storagePath']?.toString() ?? '';
    final storagePath =
        'market/$uid/business-documents/$type/'
        '${DateTime.now().millisecondsSinceEpoch}.$extension';
    final storageRef = FirebaseStorage.instance.ref(storagePath);
    await storageRef.putData(bytes, SettableMetadata(contentType: contentType));
    final url = await storageRef.getDownloadURL();
    try {
      await documentId.set({
        'type': type,
        'fileName': fileName,
        'url': url,
        'storagePath': storagePath,
        'contentType': contentType,
        'uploadedAt': FieldValue.serverTimestamp(),
        'uploadedBy': user.uid,
      });
    } catch (_) {
      await storageRef.delete().catchError((_) {});
      rethrow;
    }
    if (previousPath.isNotEmpty) {
      await FirebaseStorage.instance
          .ref(previousPath)
          .delete()
          .catchError((_) {});
    }
  }

  static Future<void> deleteBusinessDocument({
    required String uid,
    required MarketBusinessDocument document,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final canEditBusiness =
        AccountModeService.current == AccountMode.business &&
        BusinessAccessService.hasBusinessAccess &&
        BusinessAccessService.businessId == uid &&
        BusinessAccessService.can('profile', 'edit');
    if (user == null || !canEditBusiness) {
      throw StateError('You cannot edit this business profile.');
    }
    await _firestore
        .collection('publicProfiles')
        .doc(uid)
        .collection('businessDocuments')
        .doc(document.type)
        .delete();
    if (document.storagePath.isNotEmpty) {
      try {
        await FirebaseStorage.instance.ref(document.storagePath).delete();
      } catch (_) {}
    }
  }

  static Future<String> getSellerWhatsApp(MarketPost post) async {
    final postNumber = post.whatsapp.replaceAll(RegExp(r'\D'), '');
    if (postNumber.isNotEmpty) return postNumber;
    return _resolveProfileWhatsApp(post.authorUid);
  }

  static Future<String> _resolveProfileWhatsApp(String uid) async {
    final profile = await _firestore
        .collection('publicProfiles')
        .doc(uid)
        .get();
    final publicNumber = (profile.data()?['whatsapp'] ?? '')
        .toString()
        .replaceAll(RegExp(r'\D'), '');
    if (publicNumber.length >= 8 && publicNumber.length <= 15) {
      return publicNumber;
    }
    final businessData = await _readBusinessProfileIfAvailable(uid);
    final companyNumber = (businessData?['phone'] ?? '').toString().replaceAll(
      RegExp(r'\D'),
      '',
    );
    return companyNumber.length >= 8 && companyNumber.length <= 15
        ? companyNumber
        : publicNumber;
  }

  static Future<void> savePublicProfile({
    required String uid,
    required String name,
    required String bio,
    required String city,
    required String whatsapp,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final isOwnBusiness =
        AccountModeService.current == AccountMode.business &&
        BusinessAccessService.hasBusinessAccess &&
        BusinessAccessService.businessId == uid &&
        BusinessAccessService.can('profile', 'edit');
    if (user == null || (user.uid != uid && !isOwnBusiness)) {
      throw StateError('You cannot edit this Market profile.');
    }
    final cleanName = name.trim();
    final cleanBio = bio.trim();
    final cleanWhatsapp = whatsapp.replaceAll(RegExp(r'\D'), '');
    if (cleanName.isEmpty || cleanName.length > 80 || cleanBio.length > 500) {
      throw ArgumentError('Check the profile name and bio lengths.');
    }
    if (cleanWhatsapp.isNotEmpty &&
        (cleanWhatsapp.length < 8 || cleanWhatsapp.length > 15)) {
      throw ArgumentError('Enter a valid international phone number.');
    }

    if (isOwnBusiness) {
      final businessProfile = await ProfileService.loadOrCreate();
      await ProfileService.save({
        ...businessProfile,
        'name': cleanName,
        'phone': cleanWhatsapp,
      });
      BusinessAccessService.businessName.value = cleanName;
    }

    final ref = _firestore.collection('publicProfiles').doc(uid);
    final existing = await ref.get();
    await ref.set({
      'name': cleanName,
      'nameLower': cleanName.toLowerCase(),
      'category': existing.data()?['category'] ?? '',
      'bio': cleanBio,
      'city': city.trim(),
      'photoUrl': existing.data()?['photoUrl'] ?? user.photoURL ?? '',
      'whatsapp': cleanWhatsapp,
      'followersCount': existing.data()?['followersCount'] ?? 0,
      'followingCount': existing.data()?['followingCount'] ?? 0,
      'postsCount': existing.data()?['postsCount'] ?? 0,
      if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> syncBusinessLogoToPublicProfile({
    required String uid,
    required String photoUrl,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final canEditBusiness =
        AccountModeService.current == AccountMode.business &&
        BusinessAccessService.hasBusinessAccess &&
        BusinessAccessService.businessId == uid &&
        BusinessAccessService.can('profile', 'edit');
    if (user == null || !canEditBusiness) {
      throw StateError('You cannot edit this business profile.');
    }

    final companyRef = _firestore.doc('users/$uid/profile/company');
    final companyData = (await companyRef.get()).data() ?? const {};
    if (companyData['marketPhotoMode'] == 'custom') return;
    final trimmedUrl = photoUrl.trim();
    final uri = Uri.tryParse(trimmedUrl);
    final publicPhotoUrl = uri?.scheme == 'https' && uri!.host.isNotEmpty
        ? trimmedUrl
        : (companyData['marketBusinessPhotoUrl']?.toString() ?? '');
    if (publicPhotoUrl.isEmpty) return;
    final ref = _firestore.collection('publicProfiles').doc(uid);
    final snapshot = await ref.get();
    final data = snapshot.data() ?? const <String, dynamic>{};
    final savedName = data['name']?.toString().trim() ?? '';
    final businessName = BusinessAccessService.businessName.value.trim();
    final name = savedName.isNotEmpty
        ? savedName
        : businessName.isNotEmpty
        ? businessName
        : (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : 'MJASI user';

    await ref.set({
      'name': name,
      'nameLower': name.toLowerCase(),
      'category': data['category'] ?? '',
      'bio': data['bio'] ?? '',
      'city': data['city'] ?? '',
      'photoUrl': publicPhotoUrl,
      'whatsapp': data['whatsapp'] ?? '',
      'followersCount': data['followersCount'] ?? 0,
      'followingCount': data['followingCount'] ?? 0,
      'postsCount': data['postsCount'] ?? 0,
      if (!snapshot.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await companyRef.set({
      'marketPhotoMode': 'business',
      'marketBusinessPhotoUrl': publicPhotoUrl,
    }, SetOptions(merge: true));
  }

  static Future<List<MarketPost>> searchAuthorPosts(String uid) async {
    final snapshot = await _firestore
        .collection('marketPosts')
        .where('authorUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(60)
        .get();
    final viewerUid = FirebaseAuth.instance.currentUser?.uid;
    final hiddenIds = viewerUid == null
        ? const <String>{}
        : (await _firestore
                  .collection('marketHiddenPosts')
                  .doc(viewerUid)
                  .collection('items')
                  .get())
              .docs
              .map((doc) => doc.id)
              .toSet();
    final now = DateTime.now();
    return [
      for (final doc in snapshot.docs)
        if (!hiddenIds.contains(doc.id))
          if (doc.data()['hidden'] != true)
            if (MarketPost.fromDoc(doc).isStatus == false)
              if (!MarketPost.fromDoc(doc).isScheduled ||
                  MarketPost.fromDoc(doc).authorUid ==
                      FirebaseAuth.instance.currentUser?.uid)
                if (MarketPost.fromDoc(doc).expiresAt == null ||
                    MarketPost.fromDoc(doc).expiresAt!.isAfter(now))
                  MarketPost.fromDoc(doc),
    ];
  }

  static Future<List<MarketPost>> searchSavedPosts() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to view saved posts.');
    final saved = await _firestore
        .collection('marketSavedPosts')
        .doc(uid)
        .collection('items')
        .orderBy('savedAt', descending: true)
        .limit(100)
        .get();
    final posts = await Future.wait(
      saved.docs.map((doc) async {
        final post = await _firestore
            .collection('marketPosts')
            .doc(doc.id)
            .get();
        return post.exists ? MarketPost.fromDoc(post) : null;
      }),
    );
    return posts.whereType<MarketPost>().toList();
  }

  /// Latest public posts and products. Statuses, expired and hidden items are
  /// excluded. Hashtag and text filters run on the fetched page so no
  /// composite index is required.
  static Future<List<MarketPost>> searchPosts({
    String query = '',
    String hashtag = '',
    bool productsOnly = false,
  }) async {
    final page = await fetchPostsPage(
      query: query,
      hashtag: hashtag,
      productsOnly: productsOnly,
    );
    return page.posts;
  }

  static Future<MarketPostPage> fetchPostsPage({
    String query = '',
    String hashtag = '',
    bool productsOnly = false,
    bool shuffleResults = false,
    QueryDocumentSnapshot<Map<String, dynamic>>? after,
    int pageSize = 24,
    double? minPrice,
    double? maxPrice,
  }) async {
    Query<Map<String, dynamic>> request = _firestore
        .collection('marketPosts')
        .orderBy('createdAt', descending: true);
    if (after != null) request = request.startAfterDocument(after);
    final snapshot = await request.limit(pageSize + 1).get();
    final hasMore = snapshot.docs.length > pageSize;
    final pageDocs = snapshot.docs.take(pageSize).toList();
    final lastDocument = pageDocs.isEmpty ? null : pageDocs.last;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final hiddenIds = uid == null
        ? const <String>{}
        : (await _firestore
                  .collection('marketHiddenPosts')
                  .doc(uid)
                  .collection('items')
                  .get())
              .docs
              .map((doc) => doc.id)
              .toSet();
    final term = query.trim().toLowerCase();
    final now = DateTime.now();
    final posts = <MarketPost>[];
    for (final doc in pageDocs) {
      if (hiddenIds.contains(doc.id)) continue;
      if (doc.data()['hidden'] == true) continue;
      final post = MarketPost.fromDoc(doc);
      if (post.isStatus) continue;
      if (post.expiresAt != null && post.expiresAt!.isBefore(now)) continue;
      if (post.isScheduled) continue;
      if (productsOnly && !post.isProduct) continue;
      if (minPrice != null &&
          (!post.isProduct || (post.price ?? 0) < minPrice)) {
        continue;
      }
      if (maxPrice != null &&
          (!post.isProduct || (post.price ?? 0) > maxPrice)) {
        continue;
      }
      if (hashtag.isNotEmpty && !post.hashtags.contains(hashtag)) continue;
      if (term.isNotEmpty &&
          !(term.startsWith('#')
              ? post.hashtags.contains(normalizeHashtag(term))
              : post.caption.toLowerCase().contains(term)) &&
          !post.productName.toLowerCase().contains(term) &&
          !post.authorName.toLowerCase().contains(term)) {
        continue;
      }
      posts.add(post);
    }
    if (uid != null && posts.isNotEmpty && !shuffleResults) {
      final follows = await _firestore
          .collection('marketFollows')
          .doc(uid)
          .collection('following')
          .limit(100)
          .get();
      final followedIds = follows.docs
          .map((doc) => (doc.data()['followingUid'] ?? '').toString())
          .toSet();
      posts.sort((a, b) {
        final aFollowed = followedIds.contains(a.authorUid);
        final bFollowed = followedIds.contains(b.authorUid);
        if (aFollowed != bFollowed) return aFollowed ? -1 : 1;
        return (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
      });
    }
    if (shuffleResults) posts.shuffle(math.Random());
    return MarketPostPage(
      posts: posts,
      lastDocument: lastDocument,
      hasMore: hasMore,
    );
  }

  static Future<MarketPostPage> fetchFollowingPostsPage({
    required String uid,
    QueryDocumentSnapshot<Map<String, dynamic>>? after,
    int pageSize = 24,
  }) async {
    final follows = await _firestore
        .collection('marketFollows')
        .doc(uid)
        .collection('following')
        .limit(1000)
        .get();
    final followingUids = follows.docs.map((doc) => doc.id).toList();
    if (followingUids.isEmpty) {
      return const MarketPostPage(
        posts: [],
        lastDocument: null,
        hasMore: false,
      );
    }

    final requests = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    for (var start = 0; start < followingUids.length; start += 30) {
      final end = start + 30 < followingUids.length
          ? start + 30
          : followingUids.length;
      Query<Map<String, dynamic>> request = _firestore
          .collection('marketPosts')
          .where('authorUid', whereIn: followingUids.sublist(start, end))
          .orderBy('createdAt', descending: true);
      if (after != null) request = request.startAfterDocument(after);
      requests.add(request.limit(pageSize + 1).get());
    }
    final snapshots = await Future.wait(requests);

    final uniqueDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        uniqueDocs[doc.id] = doc;
      }
    }
    final candidates = uniqueDocs.values.toList()
      ..sort((a, b) {
        final aTime = (a.data()['createdAt'] as Timestamp?)?.toDate();
        final bTime = (b.data()['createdAt'] as Timestamp?)?.toDate();
        final order = (bTime ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(aTime ?? DateTime.fromMillisecondsSinceEpoch(0));
        return order == 0 ? b.id.compareTo(a.id) : order;
      });
    final hasMore = candidates.length > pageSize;
    final pageDocs = candidates.take(pageSize).toList();
    final lastDocument = pageDocs.isEmpty ? null : pageDocs.last;
    final hiddenDocs = await _firestore
        .collection('marketHiddenPosts')
        .doc(uid)
        .collection('items')
        .get();
    final hiddenIds = hiddenDocs.docs.map((doc) => doc.id).toSet();
    final now = DateTime.now();
    final posts = [
      for (final doc in pageDocs)
        if (!hiddenIds.contains(doc.id) && doc.data()['hidden'] != true)
          if (MarketPost.fromDoc(doc).isStatus == false)
            if (!MarketPost.fromDoc(doc).isScheduled)
              if (MarketPost.fromDoc(doc).expiresAt == null ||
                  MarketPost.fromDoc(doc).expiresAt!.isAfter(now))
                MarketPost.fromDoc(doc),
    ];
    return MarketPostPage(
      posts: posts,
      lastDocument: lastDocument,
      hasMore: hasMore,
    );
  }

  static Future<MarketPost?> getPost(String postId) async {
    final snapshot = await _firestore
        .collection('marketPosts')
        .doc(postId)
        .get();
    if (!snapshot.exists) return null;
    final post = MarketPost.fromDoc(snapshot);
    if (post.isStatus && !post.isActiveStatusAt(DateTime.now())) return null;
    if (post.expiresAt != null && !post.expiresAt!.isAfter(DateTime.now())) {
      return null;
    }
    return post;
  }

  static Stream<MarketPost?> watchPost(String postId) => _firestore
      .collection('marketPosts')
      .doc(postId)
      .snapshots()
      .map((snapshot) => snapshot.exists ? MarketPost.fromDoc(snapshot) : null);

  static Future<List<MarketStatusGroup>> searchActiveStatuses() async {
    final snapshot = await _firestore
        .collection('marketPosts')
        .where('type', isEqualTo: 'status')
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .orderBy('expiresAt')
        .limit(30)
        .get();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final hiddenIds = uid == null
        ? const <String>{}
        : (await _firestore
                  .collection('marketHiddenPosts')
                  .doc(uid)
                  .collection('items')
                  .get())
              .docs
              .map((doc) => doc.id)
              .toSet();
    final posts = [
      for (final doc in snapshot.docs)
        if (!hiddenIds.contains(doc.id) && doc.data()['hidden'] != true)
          MarketPost.fromDoc(doc),
    ];
    final grouped = <String, List<MarketPost>>{};
    for (final post in posts) {
      grouped.putIfAbsent(post.authorUid, () => []).add(post);
    }
    final groups = <MarketStatusGroup>[];
    for (final entry in grouped.entries) {
      final statuses = entry.value
        ..sort(
          (a, b) => (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
        );
      final latest = statuses.last;
      groups.add(
        MarketStatusGroup(
          authorUid: entry.key,
          authorName: latest.authorName,
          authorPhotoUrl: latest.authorPhotoUrl,
          statuses: statuses,
        ),
      );
    }
    groups.sort(
      (a, b) =>
          (b.statuses.last.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(
                a.statuses.last.createdAt ??
                    DateTime.fromMillisecondsSinceEpoch(0),
              ),
    );
    return groups;
  }

  static Future<void> recordStatusView(String postId) async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (user == null || uid == null) return;
    await _firestore
        .collection('marketPosts')
        .doc(postId)
        .collection('viewers')
        .doc(uid)
        .set({
          'viewerName': user.displayName?.trim().isNotEmpty == true
              ? user.displayName!.trim()
              : 'MJASI user',
          'viewerPhotoUrl': user.photoURL ?? '',
          'viewedAt': FieldValue.serverTimestamp(),
        });
  }

  static Stream<bool> watchStatusViewed(String postId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream<bool>.value(false);
    return _firestore
        .collection('marketPosts')
        .doc(postId)
        .collection('viewers')
        .doc(uid)
        .snapshots()
        .map((snapshot) => snapshot.exists);
  }

  static Stream<List<Map<String, dynamic>>> watchStatusViewers(String postId) =>
      _firestore
          .collection('marketPosts')
          .doc(postId)
          .collection('viewers')
          .orderBy('viewedAt', descending: true)
          .limit(100)
          .snapshots()
          .map(
            (snapshot) => [
              for (final doc in snapshot.docs) {'uid': doc.id, ...doc.data()},
            ],
          );

  static Stream<int> watchLikeCount(String postId) => _firestore
      .collection('marketPosts')
      .doc(postId)
      .collection('likes')
      .snapshots()
      .map((snapshot) => snapshot.size);

  static Stream<bool> watchLike(String postId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream<bool>.value(false);
    return _firestore
        .collection('marketPosts')
        .doc(postId)
        .collection('likes')
        .doc(uid)
        .snapshots()
        .map((snapshot) => snapshot.exists);
  }

  static Future<void> toggleLike(String postId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to like posts.');
    final postRef = _firestore.collection('marketPosts').doc(postId);
    final likeRef = postRef.collection('likes').doc(uid);
    await _firestore.runTransaction((transaction) async {
      final like = await transaction.get(likeRef);
      if (like.exists) {
        transaction.delete(likeRef);
      } else {
        transaction.set(likeRef, {
          'uid': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  static Stream<List<Map<String, dynamic>>> watchComments(String postId) =>
      _firestore
          .collection('marketPosts')
          .doc(postId)
          .collection('comments')
          .orderBy('createdAt')
          .limit(100)
          .snapshots()
          .map(
            (snapshot) => [
              for (final doc in snapshot.docs) {'id': doc.id, ...doc.data()},
            ],
          );

  static Future<void> addComment({
    required String postId,
    required String body,
    String? parentId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final text = body.trim();
    if (user == null) throw StateError('Sign in to comment.');
    if (text.isEmpty || text.length > 2000) {
      throw ArgumentError('Comment must contain 1 to 2000 characters.');
    }
    await _firestore
        .collection('marketPosts')
        .doc(postId)
        .collection('comments')
        .add({
          'authorUid': user.uid,
          'authorName': user.displayName?.trim().isNotEmpty == true
              ? user.displayName!.trim()
              : 'MJASI user',
          'body': text,
          'parentId': parentId,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  static Future<void> deleteComment(String postId, String commentId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to delete comments.');
    await _firestore
        .collection('marketPosts')
        .doc(postId)
        .collection('comments')
        .doc(commentId)
        .delete();
  }

  static Future<void> toggleSaved(String postId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to save posts.');
    final ref = _firestore
        .collection('marketSavedPosts')
        .doc(uid)
        .collection('items')
        .doc(postId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (snapshot.exists) {
        transaction.delete(ref);
      } else {
        transaction.set(ref, {
          'postId': postId,
          'savedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  static Stream<bool> watchSaved(String postId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream<bool>.value(false);
    return _firestore
        .collection('marketSavedPosts')
        .doc(uid)
        .collection('items')
        .doc(postId)
        .snapshots()
        .map((snapshot) => snapshot.exists);
  }

  static Stream<bool> watchFollowing(String targetUid) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid == targetUid) return Stream<bool>.value(false);
    return _firestore
        .collection('marketFollows')
        .doc(uid)
        .collection('following')
        .doc(targetUid)
        .snapshots()
        .map((snapshot) => snapshot.exists);
  }

  static Future<List<MarketProfile>> searchFollowProfiles({
    required String uid,
    required bool followers,
  }) async {
    final snapshot = await _firestore
        .collectionGroup('following')
        .where(followers ? 'followingUid' : 'followerUid', isEqualTo: uid)
        .limit(100)
        .get();
    final profileIds = snapshot.docs
        .map(
          (doc) =>
              (doc.data()[followers ? 'followerUid' : 'followingUid'] ?? '')
                  .toString(),
        )
        .where((id) => id.isNotEmpty)
        .toSet();
    final profiles = await Future.wait(profileIds.map(getPublicProfile));
    return profiles.whereType<MarketProfile>().toList();
  }

  static Future<bool> toggleFollow(String targetUid) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to follow shops.');
    if (uid == targetUid) throw ArgumentError('You cannot follow yourself.');
    final ref = _firestore
        .collection('marketFollows')
        .doc(uid)
        .collection('following')
        .doc(targetUid);
    return _firestore.runTransaction<bool>((transaction) async {
      final snapshot = await transaction.get(ref);
      if (snapshot.exists) {
        transaction.delete(ref);
        return false;
      } else {
        transaction.set(ref, {
          'followerUid': uid,
          'followingUid': targetUid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return true;
      }
    });
  }

  static Future<void> reportPost(String postId, String reason) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final cleanReason = reason.trim();
    if (uid == null) throw StateError('Sign in to report posts.');
    if (cleanReason.isEmpty || cleanReason.length > 500) {
      throw ArgumentError('Choose a report reason.');
    }
    final ref = _firestore.collection('marketReports').doc('${uid}_$postId');
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(ref);
      if (existing.exists) return;
      transaction.set(ref, {
        'postId': postId,
        'reporterUid': uid,
        'reason': cleanReason,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'open',
      });
    });
  }

  static Future<void> sendStatusReply(
    String postId, {
    String text = '',
    String emoji = '',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to reply.');
    final cleanText = text.trim();
    if (cleanText.isEmpty && emoji.isEmpty) return;
    final name = user.displayName?.trim() ?? '';
    await _firestore
        .collection('marketPosts')
        .doc(postId)
        .collection('statusReplies')
        .add({
          'senderUid': user.uid,
          'senderName': name.isEmpty
              ? 'MJASI user'
              : (name.length > 80 ? name.substring(0, 80) : name),
          'text': cleanText.length > 300
              ? cleanText.substring(0, 300)
              : cleanText,
          'emoji': emoji,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchStatusReplies(
    String postId,
  ) => _firestore
      .collection('marketPosts')
      .doc(postId)
      .collection('statusReplies')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchMarketReports() =>
      _firestore
          .collection('marketReports')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots();

  static Future<void> resolveMarketReport(
    String reportId, {
    required String status,
    String? deletePostId,
  }) async {
    if (deletePostId != null) {
      await _firestore.collection('marketPosts').doc(deletePostId).delete();
    }
    await _firestore.collection('marketReports').doc(reportId).update({
      'status': status,
    });
  }

  static Future<void> hidePost(String postId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to hide posts.');
    final ref = _firestore
        .collection('marketHiddenPosts')
        .doc(uid)
        .collection('items')
        .doc(postId);
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(ref);
      if (!existing.exists) {
        transaction.set(ref, {
          'postId': postId,
          'hiddenAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  static bool canEditPost(MarketPost post) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid != null &&
        (post.authorUid == uid ||
            (AccountModeService.current == AccountMode.business &&
                BusinessAccessService.hasBusinessAccess &&
                BusinessAccessService.businessId == post.authorUid &&
                BusinessAccessService.can('stock', 'edit')));
  }

  static bool canDeletePost(MarketPost post) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid != null &&
        (post.authorUid == uid ||
            (AccountModeService.current == AccountMode.business &&
                BusinessAccessService.hasBusinessAccess &&
                BusinessAccessService.businessId == post.authorUid &&
                BusinessAccessService.can('stock', 'delete')));
  }

  static Future<void> updateCaption(MarketPost post, String caption) async {
    final text = caption.trim();
    if (!canEditPost(post)) throw StateError('You cannot edit this post.');
    if (text.length > 2000) throw ArgumentError('Caption is too long.');
    await _firestore.collection('marketPosts').doc(post.id).update({
      'caption': text,
    });
  }

  static Future<void> deletePost(MarketPost post) async {
    if (!canDeletePost(post)) throw StateError('You cannot delete this post.');
    final exclusiveImages = <String>[];
    for (final url in post.images) {
      final references = await _firestore
          .collection('marketPosts')
          .where('images', arrayContains: url)
          .limit(2)
          .get();
      if (references.docs.length == 1 && references.docs.single.id == post.id) {
        exclusiveImages.add(url);
      }
    }
    await _firestore.collection('marketPosts').doc(post.id).delete();
    await _deleteVideoIfOrphan(post.videoUrl);
    for (final url in exclusiveImages) {
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {
        // Other media may still be referenced; cleanup can be retried safely.
      }
    }
  }

  static Future<void> recordWhatsAppClick(MarketPost post) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final hasLinkedProduct =
        post.isProduct || (post.isStatus && post.productId.isNotEmpty);
    if (uid == null || !hasLinkedProduct || post.whatsapp.isEmpty) {
      return;
    }
    await _firestore.collection('marketContactClicks').add({
      'postId': post.id,
      'sellerUid': post.authorUid,
      'buyerUid': uid,
      'channel': 'whatsapp',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> sharePost(MarketPost post) async {
    final link = 'https://mjasipos.web.app/#/market/post/${post.id}';
    await SharePlus.instance.share(
      ShareParams(
        text:
            '${post.productName.isNotEmpty ? post.productName : post.caption}\n$link',
      ),
    );
  }

  /// Publishes a fresh copy of [status] (new 24 h timer) and removes the old one.
  static Future<void> repostStatus(MarketPost status) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !status.isStatus || status.authorUid != uid) {
      throw StateError('Only the status owner can refresh it.');
    }
    final ref = _firestore.collection('marketPosts').doc();
    await ref.set({
      'authorUid': status.authorUid,
      'authorName': status.authorName,
      'authorPhotoUrl': status.authorPhotoUrl,
      'type': 'status',
      'caption': status.caption,
      'category': status.category,
      'images': status.images,
      'productId': status.productId,
      'productOwnerUid': status.productOwnerUid,
      'productName': status.productName,
      if (status.price != null) 'price': status.price,
      'currency': status.currency,
      'inStock': status.inStock,
      'whatsapp': status.whatsapp,
      'likesCount': 0,
      'commentsCount': 0,
      'hidden': false,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': null,
      if (status.audioUrl.isNotEmpty) 'audioUrl': status.audioUrl,
      if (status.videoUrl.isNotEmpty) 'videoUrl': status.videoUrl,
      if (status.audioUrl.isNotEmpty) 'audioTitle': status.audioTitle,
    });
    await deleteStatus(status);
  }

  static Future<void> setPostStock(MarketPost post, bool inStock) async {
    if (post.authorUid != FirebaseAuth.instance.currentUser?.uid) {
      throw StateError('You cannot edit this post.');
    }
    await _firestore.collection('marketPosts').doc(post.id).update({
      'inStock': inStock,
    });
  }

  static Future<void> deleteStatus(MarketPost status) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !status.isStatus || status.authorUid != uid) {
      throw StateError('Only the status owner can delete it.');
    }
    final exclusiveImages = <String>[];
    for (final url in status.images) {
      final references = await _firestore
          .collection('marketPosts')
          .where('images', arrayContains: url)
          .limit(2)
          .get();
      if (references.docs.length == 1 &&
          references.docs.single.id == status.id) {
        exclusiveImages.add(url);
      }
    }
    await _firestore.collection('marketPosts').doc(status.id).delete();
    await _deleteVideoIfOrphan(status.videoUrl);
    for (final url in exclusiveImages) {
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {
        // The status document is already removed; a missing image is harmless.
      }
    }
  }

  static Future<void> _deleteVideoIfOrphan(String url) async {
    if (url.isEmpty) return;
    try {
      final others = await _firestore
          .collection('marketPosts')
          .where('videoUrl', isEqualTo: url)
          .limit(1)
          .get();
      if (others.docs.isEmpty) {
        await FirebaseStorage.instance.refFromURL(url).delete();
      }
    } catch (_) {
      // Cleanup is best effort.
    }
  }
}
