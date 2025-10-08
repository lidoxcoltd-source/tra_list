import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../utils/image_utils.dart';

class ProfileService {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static DocumentReference<Map<String, dynamic>> _docRef(String uid) =>
      _db.collection('users').doc(uid).collection('profile').doc('company');

  static String _uidOrThrow() {
    final u = _auth.currentUser;
    if (u == null) throw StateError('Not signed in');
    return u.uid;
  }

  static Future<Map<String, dynamic>> loadOrCreate() async {
    final uid = _uidOrThrow();
    final ref = _docRef(uid);
    final snap = await ref.get();
    if (snap.exists) {
      final d = snap.data() ?? {};
      return {
        'name': d['name']?.toString() ?? '',
        'address': d['address']?.toString() ?? '',
        'phone': d['phone']?.toString() ?? '',
        'email': d['email']?.toString() ?? '',
        'website': d['website']?.toString() ?? '',
        'taxId': d['taxId']?.toString() ?? '',
        'handle': d['handle']?.toString() ?? '',
        'logoUrl': d['logoUrl']?.toString() ?? '',
        // Payment details
        'beneficiary': d['beneficiary']?.toString() ?? '',
        'bank': d['bank']?.toString() ?? '',
        'account': d['account']?.toString() ?? '',
        'swift': d['swift']?.toString() ?? '',
        'paymentMethod': d['paymentMethod']?.toString() ?? '',
        // Theming
        'colors': {
          'brand': (d['colors']?['brand'] as int?) ?? 0xFFF15A24,
          'footer': (d['colors']?['footer'] as int?) ?? 0xFF424242,
          'accent': (d['colors']?['accent'] as int?) ?? 0xFF1976D2,
        },
      };
    }
    final init = {
      'name': '',
      'address': '',
      'email': '',
      'phone': '',
      'website': '',
      'taxId': '',
      'handle': '',
      'logoUrl': '',
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
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await ref.set(init);
    return init;
  }

  static Future<void> save(Map<String, dynamic> data) async {
    final uid = _uidOrThrow();
    final payload = Map<String, dynamic>.from(data);
    payload['updatedAt'] = FieldValue.serverTimestamp();
    await _docRef(uid).set(payload, SetOptions(merge: true));
  }

  // Back-compat alias
  static Future<String> uploadCompressedLogoFromBytes(Uint8List original) =>
      uploadCompressedLogo(original);

  /// Compress + upload to users/<uid>/logo_<ts>.(png|jpg), store logoUrl, return URL.
  static Future<String> uploadCompressedLogo(Uint8List original) async {
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

  /// Parse googleapis URL to object path.
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

  /// Find newest logo in users/<uid>/ by timestamp.
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

  /// Repair Firestore logoUrl for current user.
  /// Strategy A: rebuild from stored url. Strategy B: newest under users/<uid>/.
  static Future<String?> repairLogoUrlForCurrentUser() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;

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
