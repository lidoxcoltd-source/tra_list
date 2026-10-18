import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Permanently deletes the signed-in account through the `deleteMyAccount`
/// Cloud Function after the user confirms and re-enters their password.
class AccountDeletionService {
  static Future<void> delete({required String password}) async {
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;
    if (user == null || user.email == null) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: user.email!, password: password),
    );
    await FirebaseFunctions.instance.httpsCallable('deleteMyAccount').call({
      'confirm': 'DELETE',
    });
    await auth.signOut();
  }

  /// Shows the confirmation dialog. Returns true when the account was deleted.
  static Future<bool> confirmAndDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DeleteAccountDialog(),
    );
    return result == true;
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String _message(Object error) {
    if (error is FirebaseAuthException &&
        (error.code == 'wrong-password' ||
            error.code == 'invalid-credential' ||
            error.code == 'invalid-password')) {
      return 'The password is incorrect.';
    }
    if (error is FirebaseFunctionsException && error.message != null) {
      return error.message!;
    }
    return 'Could not delete the account. Check your connection and try again.';
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AccountDeletionService.delete(password: _password.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _message(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready =
        !_busy && _confirm.text.trim() == 'DELETE' && _password.text.isNotEmpty;
    return AlertDialog(
      title: const Text('Delete account'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently deletes your login and, for business owners, '
              'all business records, staff accounts and uploaded files. '
              'This cannot be undone.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              obscureText: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Your password'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirm,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Type DELETE'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: ready ? _submit : null,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Delete permanently'),
        ),
      ],
    );
  }
}
