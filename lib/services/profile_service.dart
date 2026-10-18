import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../utils/image_utils.dart';
import 'package:tra_list/invoice/language_controller.dart';
import 'business_access_service.dart';

class ProfileService {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static DocumentReference<Map<String, dynamic>> _docRef(String uid) =>
      _db.collection('users').doc(uid).collection('profile').doc('company');

  static String _uidOrThrow() {
    if (_auth.currentUser == null) throw StateError('Not signed in');
    return BusinessAccessService.businessId;
  }

  static Future<void> createForRegistration({
    required String ownerName,
    required String businessName,
    required String email,
    required String phone,
  }) async {
    final user = _auth.currentUser;
    if (user == null ||
        !BusinessAccessService.isReady.value ||
        !BusinessAccessService.isOwner.value ||
        BusinessAccessService.businessId != user.uid) {
      throw StateError(
        'Only a newly registered business owner can create this profile.',
      );
    }

    final now = FieldValue.serverTimestamp();
    await _docRef(user.uid).set({
      'name': businessName.isNotEmpty ? businessName : ownerName,
      'shopNickname': '',
      'ownerName': ownerName,
      'email': email,
      'phone': phone,
      'address': '',
      'website': '',
      'taxId': '',
      'role': 'user',
      'handle': '',
      'logoUrl': '',
      'logoSource': 'firebase',
      'language': 'en',
      'beneficiary': '',
      'bank': '',
      'account': '',
      'swift': '',
      'paymentMethod': 'Bank Transfer',
      'colors': {
        'brand': 0xFFF15A24,
        'footer': 0xFF424242,
        'accent': 0xFF1976D2,
      },
      'createdAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));
  }

  static Future<Map<String, dynamic>> loadOrCreate() async {
    if (!BusinessAccessService.canReadBusinessProfile()) {
      throw StateError(
        'You do not have permission to view the business profile.',
      );
    }
    final uid = _uidOrThrow();
    final ref = _docRef(uid);
    final snap = await ref.get();
    if (snap.exists) {
      final d = snap.data() ?? {};
      final storedEmail = d['email']?.toString().trim() ?? '';
      final currentUser = BusinessAccessService.isOwner.value
          ? _auth.currentUser
          : null;
      final accountEmail = currentUser?.email?.trim() ?? '';
      final storedOwnerName = d['ownerName']?.toString().trim() ?? '';
      final accountOwnerName = currentUser?.displayName?.trim() ?? '';
      final profileUpdates = <String, dynamic>{};
      if (storedEmail.isEmpty && accountEmail.isNotEmpty) {
        profileUpdates['email'] = accountEmail;
      }
      if (storedOwnerName.isEmpty && accountOwnerName.isNotEmpty) {
        profileUpdates['ownerName'] = accountOwnerName;
      }
      if (profileUpdates.isNotEmpty) {
        profileUpdates['updatedAt'] = FieldValue.serverTimestamp();
        await ref.set(profileUpdates, SetOptions(merge: true));
      }
      return {
        'name': d['name']?.toString() ?? '',
        'shopNickname': d['shopNickname']?.toString() ?? '',
        'ownerName': storedOwnerName.isNotEmpty
            ? storedOwnerName
            : accountOwnerName,
        'address': d['address']?.toString() ?? '',
        'phone': d['phone']?.toString() ?? '',
        'email': storedEmail.isNotEmpty ? storedEmail : accountEmail,
        'website': d['website']?.toString() ?? '',
        'taxId': d['taxId']?.toString() ?? '',
        'role': d['role']?.toString() ?? 'user',
        'handle': d['handle']?.toString() ?? '',
        'logoUrl': d['logoUrl']?.toString() ?? '',
        'logoSource': d['logoSource']?.toString() ?? 'firebase',
        'language': d['language']?.toString() ?? '',
        // Payment details
        'beneficiary': d['beneficiary']?.toString() ?? '',
        'bank': d['bank']?.toString() ?? '',
        'account': d['account']?.toString() ?? '',
        'swift': d['swift']?.toString() ?? '',
        'paymentMethod': d['paymentMethod']?.toString() ?? '',
        'documentTermsVersions':
            (d['documentTermsVersions'] as List? ?? const [])
                .whereType<Map>()
                .map((version) => Map<String, dynamic>.from(version))
                .toList(),
        'selectedDocumentTerms': Map<String, dynamic>.from(
          d['selectedDocumentTerms'] as Map? ?? const {},
        ),
        'documentDesigns': Map<String, dynamic>.from(
          d['documentDesigns'] as Map? ?? const {},
        ),
        // Theming
        'colors': {
          'brand': (d['colors']?['brand'] as int?) ?? 0xFFF15A24,
          'footer': (d['colors']?['footer'] as int?) ?? 0xFF424242,
          'accent': (d['colors']?['accent'] as int?) ?? 0xFF1976D2,
        },
      };
    }
    final currentUser = BusinessAccessService.isOwner.value
        ? _auth.currentUser
        : null;
    final accountOwnerName = currentUser?.displayName?.trim() ?? '';
    final init = {
      'name': accountOwnerName,
      'shopNickname': '',
      'ownerName': accountOwnerName,
      'address': '',
      'email': currentUser?.email?.trim() ?? '',
      'phone': '',
      'website': '',
      'taxId': '',
      'role': 'user',
      'handle': '',
      'logoUrl': '',
      'logoSource': 'firebase',
      'language': 'en',
      'beneficiary': '',
      'bank': '',
      'account': '',
      'swift': '',
      'paymentMethod': 'Bank Transfer',
      'documentTermsVersions': <Map<String, dynamic>>[],
      'selectedDocumentTerms': <String, String>{},
      'documentDesigns': <String, dynamic>{},
      'colors': {
        'brand': 0xFFF15A24,
        'footer': 0xFF424242,
        'accent': 0xFF1976D2,
      },
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (BusinessAccessService.can('profile', 'edit')) {
      await ref.set(init);
    }
    return init;
  }

  static Future<void> save(Map<String, dynamic> data) async {
    if (!BusinessAccessService.can('profile', 'edit')) {
      throw StateError(
        'You do not have permission to edit the business profile.',
      );
    }
    final uid = _uidOrThrow();
    final payload = Map<String, dynamic>.from(data);
    payload['updatedAt'] = FieldValue.serverTimestamp();
    await _docRef(uid).set(payload, SetOptions(merge: true));
  }

  /// Loads the user's language preference from their profile and sets it globally.
  /// This should be called once after the user signs in.
  static Future<void> loadAndSetLanguage() async {
    try {
      if (!BusinessAccessService.canReadBusinessProfile()) return;
      final uid = _uidOrThrow();
      final ref = _docRef(uid);
      final snap = await ref.get();

      if (snap.exists && snap.data()!.containsKey('language')) {
        final langCode = snap.data()!['language']?.toString();
        if (langCode != null) {
          final langController = Get.isRegistered<LanguageController>()
              ? Get.find<LanguageController>()
              : Get.put(LanguageController());
          langController.changeLanguage(
            langCode,
            langCode == 'sw' ? 'TZ' : 'US',
          );
        }
      }
    } catch (e) {
      // Silently fail, as default language will be used.
      debugPrint('Could not load language preference: $e');
    }
  }

  // Back-compat alias
  static Future<String> uploadCompressedLogoFromBytes(Uint8List original) =>
      uploadCompressedLogo(original);

  /// Compresses and uploads a logo for the current user and stores the resulting URL.
  static Future<String> uploadCompressedLogo(Uint8List original) async {
    if (!BusinessAccessService.can('profile', 'edit')) {
      throw StateError(
        'You do not have permission to change the business logo.',
      );
    }
    final uid = _uidOrThrow();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final comp = await compressLogoBytes(original, maxSide: 640);
    final path = 'users/$uid/logo_$ts.${comp.ext}';
    final ref = FirebaseStorage.instance.ref().child(path);

    final task = ref.putData(
      comp.bytes,
      SettableMetadata(
        contentType: comp.contentType,
        cacheControl: 'public, max-age=604800',
      ),
    );

    final snap = await task;
    if (snap.state != TaskState.success) {
      throw Exception('Upload failed with state ${snap.state}');
    }

    final url = await ref.getDownloadURL();

    await _docRef(uid).set({
      'logoUrl': url,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return url;
  }

  /// Parses a Firebase Storage URL to its object path.
  static String? _extractObjectPath(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final segs = uri.pathSegments; // [v0,b,<bucket>,o,<encodedPath>]
    final oIndex = segs.indexOf('o');
    if (oIndex != -1 && oIndex + 1 < segs.length) {
      return Uri.decodeFull(segs[oIndex + 1]);
    }
    return null;
  }

  /// Finds the newest stored logo for the given user ID by timestamp.
  static Future<String?> findLatestLogoUrl(String uid) async {
    final dir = FirebaseStorage.instance.ref().child('users/$uid');
    final listing = await dir.listAll();
    if (listing.items.isEmpty) return null;

    int ts(Reference r) {
      final m = RegExp(r'logo_(\d+)\.').firstMatch(r.name);
      return m != null ? int.tryParse(m.group(1)!) ?? -1 : -1;
    }

    listing.items.sort((a, b) => ts(b).compareTo(ts(a)));
    return listing.items.first.getDownloadURL();
  }

  /// Repairs the current user's stored logo URL.
  /// Strategy A rebuilds it from the stored URL; strategy B falls back to the newest logo in the user folder.
  static Future<String?> repairLogoUrlForCurrentUser() async {
    if (_auth.currentUser == null ||
        !BusinessAccessService.can('profile', 'edit')) {
      return null;
    }
    final uid = BusinessAccessService.businessId;

    final ref = _docRef(uid);
    final snap = await ref.get();
    final current = snap.data()?['logoUrl']?.toString().trim() ?? '';

    if (current.isNotEmpty) {
      final path = _extractObjectPath(current);
      if (path != null && path.isNotEmpty) {
        try {
          final fresh = await FirebaseStorage.instance
              .ref()
              .child(path)
              .getDownloadURL();
          await ref.set({
            'logoUrl': fresh,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          return fresh;
        } catch (_) {
          /* fallback */
        }
      }
    }

    final latest = await findLatestLogoUrl(uid);
    if (latest == null) return null;
    await ref.set({
      'logoUrl': latest,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return latest;
  }
}
