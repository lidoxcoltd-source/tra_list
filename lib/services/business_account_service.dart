import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BusinessAccountService {
  BusinessAccountService._();

  static final _functions = FirebaseFunctions.instance;

  static Future<String> createBusiness({
    required String name,
    required String phone,
  }) async {
    final result = await _functions
        .httpsCallable('createBusiness')
        .call<Map<String, dynamic>>({
          'name': name.trim(),
          'phone': phone.trim(),
        });
    final businessUid = result.data['businessUid']?.toString() ?? '';
    if (businessUid.isEmpty) {
      throw StateError('The business setup response did not include an ID.');
    }
    return businessUid;
  }

  static Future<String> claimInvitation(String code) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in before joining a business.');
    if (user.email == null || user.email!.trim().isEmpty) {
      throw StateError('Add an email address to your account first.');
    }
    final result = await _functions
        .httpsCallable('claimBusinessInvitation')
        .call<Map<String, dynamic>>({'code': code.trim()});
    final businessUid = result.data['businessUid']?.toString() ?? '';
    if (businessUid.isEmpty) {
      throw StateError(
        'The invitation response did not include a business ID.',
      );
    }
    return businessUid;
  }
}
