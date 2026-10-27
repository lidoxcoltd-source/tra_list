import 'package:firebase_auth/firebase_auth.dart';
import 'package:get_storage/get_storage.dart';

enum AccountMode { personal, business }

class AccountModeService {
  AccountModeService._();

  static const _keyPrefix = 'account_mode_';
  static final _storage = GetStorage();

  static AccountMode get current {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return AccountMode.business;
    return _parse(_storage.read<String>('$_keyPrefix$uid'));
  }

  static AccountMode forUser(String uid) =>
      _parse(_storage.read<String>('$_keyPrefix$uid'));

  static Future<void> setForCurrentUser(AccountMode mode) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to save your account mode.');
    await _storage.write('$_keyPrefix$uid', mode.name);
  }

  static AccountMode _parse(String? value) => switch (value) {
    'personal' => AccountMode.personal,
    _ => AccountMode.business,
  };
}
