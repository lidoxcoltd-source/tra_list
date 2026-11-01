import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/services/account_mode_service.dart';
import 'package:tra_list/services/account_mode_selector.dart';
import 'package:tra_list/services/auth_backdrop.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/convert_to_business.dart';
import 'package:tra_list/services/desktop_google_auth_stub.dart'
    if (dart.library.io) 'services/desktop_google_auth_io.dart';
import 'package:tra_list/services/personal_finance_service.dart';
import 'package:tra_list/services/profile_service.dart';

class CreateAccountPage extends StatefulWidget {
  const CreateAccountPage({super.key});

  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends State<CreateAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _auth = FirebaseAuth.instance;

  bool _isLoading = false;
  bool _isGoogleSignUpAttempt = false;
  bool _googleInitialized = false;
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;
  AccountMode _mode = AccountMode.business;

  static bool get _googleSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      ((defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux) &&
          desktopGoogleConfigured);

  @override
  void dispose() {
    _nameController.dispose();
    _businessNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final user = credential.user;
      if (user == null) {
        throw StateError('Firebase did not return the newly registered user.');
      }
      await _initializeAccountProfile(
        user,
        displayName: _nameController.text.trim(),
        email: _emailController.text.trim(),
        photoUrl: '',
      );
      _showAccountCreated();
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'email-already-in-use' => 'An account with this email already exists',
        'invalid-email' => 'Invalid email format',
        'weak-password' => 'Password is too weak',
        _ => e.message ?? 'Registration failed',
      };

      if (mounted) {
        Get.snackbar(
          'Registration Failed'.tr,
          message.tr,
          backgroundColor: Colors.red,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 4),
        );
      }
    } catch (e) {
      debugPrint('Account profile initialization failed: $e');
      _showProfileSaveError();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<UserCredential?> _googleCredential() async {
    if (kIsWeb) return _auth.signInWithPopup(GoogleAuthProvider());
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      final token = await desktopGoogleIdToken();
      if (token == null) return null;
      return _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: token),
      );
    }

    final google = GoogleSignIn.instance;
    if (!_googleInitialized) {
      await google.initialize(
        serverClientId:
            '903048450592-iom8f9acml9g5e3e40d3rjaaj8iqua4i.apps.googleusercontent.com',
      );
      _googleInitialized = true;
    }
    final account = await google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'google-no-token',
        message: 'google_login_failed'.tr,
      );
    }
    return _auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
  }

  Future<void> _createAccountWithGoogle() async {
    _isGoogleSignUpAttempt = true;
    final isValid = _formKey.currentState!.validate();
    _isGoogleSignUpAttempt = false;
    if (!isValid) return;

    setState(() => _isLoading = true);
    try {
      final credential = await _googleCredential();
      if (credential == null) return;

      final user = credential.user;
      if (user == null) {
        throw StateError('Google sign-in did not return a user.');
      }
      if (credential.additionalUserInfo?.isNewUser != true) {
        await _auth.signOut();
        if (mounted) {
          Get.snackbar(
            'Registration Failed'.tr,
            'An account with this email already exists'.tr,
            backgroundColor: Colors.red,
            colorText: Colors.white,
            snackPosition: SnackPosition.BOTTOM,
          );
        }
        return;
      }

      final enteredName = _nameController.text.trim();
      final googleName = user.displayName?.trim();
      final displayName = enteredName.isNotEmpty
          ? enteredName
          : googleName != null && googleName.isNotEmpty
          ? googleName
          : user.email?.split('@').first ?? '';
      await _initializeAccountProfile(
        user,
        displayName: displayName,
        email: user.email ?? '',
        photoUrl: user.photoURL ?? '',
      );
      _showAccountCreated();
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled &&
          e.code != GoogleSignInExceptionCode.interrupted) {
        _showGoogleSignInError('${e.code.name}: ${e.description ?? ''}');
      }
    } on FirebaseAuthException catch (e) {
      _showGoogleSignInError(e.message);
    } catch (e) {
      debugPrint('Google account creation failed: $e');
      _showProfileSaveError();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _initializeAccountProfile(
    User user, {
    required String displayName,
    required String email,
    required String photoUrl,
  }) async {
    if (displayName.isNotEmpty && user.displayName != displayName) {
      await user.updateDisplayName(displayName);
    }
    await AccountModeService.setForCurrentUser(_mode);
    if (_mode == AccountMode.business) {
      await ProfileService.createForRegistration(
        ownerName: displayName,
        businessName: _businessNameController.text.trim(),
        email: email,
        phone: _phoneController.text.trim(),
      );
      await BusinessAccessService.initializeForCurrentUser();
    } else {
      BusinessAccessService.clear();
      await PersonalFinanceService.saveProfile({
        'displayName': displayName,
        'photoUrl': photoUrl,
        'currency': 'TZS',
        'dateFormat': 'dd/MM/yyyy',
        'notificationsEnabled': true,
      });
    }
  }

  void _showAccountCreated() {
    if (mounted) {
      Get.offAllNamed(AppRoutes.home);
      Get.snackbar(
        'Success'.tr,
        'account_created_success'.tr,
        backgroundColor: Colors.green,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void _showGoogleSignInError(String? details) {
    if (mounted) {
      Get.snackbar(
        'Registration Failed'.tr,
        details == null || details.isEmpty
            ? 'google_login_failed'.tr
            : '${'google_login_failed'.tr}\n$details',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void _showProfileSaveError() {
    if (mounted) {
      Get.snackbar(
        'Registration Failed'.tr,
        'account_profile_save_failed'.tr,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 760;
    final fieldGap = compact ? 8.0 : 14.0;
    final isBusiness = _mode == AccountMode.business;
    final accent = isBusiness
        ? AuthBackdrop.businessAccent
        : AuthBackdrop.personalAccent;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: isBusiness
          ? const Color(0xFFF1F6FF)
          : const Color(0xFFF2FBF6),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Get.back(),
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          tooltip: 'Back'.tr,
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: AuthBackdrop(isBusiness: isBusiness)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  compact ? 12 : 24,
                  compact ? 0 : 8,
                  compact ? 12 : 24,
                  compact ? 8 : 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!compact)
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE500),
                          borderRadius: BorderRadius.circular(48),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(48),
                          child: Image.asset(
                            'assets/mjas.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    SizedBox(height: compact ? 2 : 16),
                    Text(
                      'account_create_title'.tr,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: compact ? 22 : 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    if (!compact) const SizedBox(height: 8),
                    if (!compact)
                      Text(
                        'account_create_subtitle'.tr,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    SizedBox(height: compact ? 6 : 20),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: AccountModeSelector(
                        mode: _mode,
                        onChanged: (mode) => setState(() => _mode = mode),
                      ),
                    ),
                    SizedBox(height: compact ? 6 : 14),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Card(
                        elevation: 8,
                        shadowColor: Colors.black.withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(compact ? 12 : 24),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  controller: _nameController,
                                  textCapitalization: TextCapitalization.words,
                                  autofillHints: const [AutofillHints.name],
                                  decoration: _inputDecoration(
                                    label: 'account_full_name'.tr,
                                    icon: Icons.person_outline,
                                  ),
                                  validator: (value) {
                                    if (_isGoogleSignUpAttempt) return null;
                                    if (value == null || value.trim().isEmpty) {
                                      return 'account_full_name_required'.tr;
                                    }
                                    return null;
                                  },
                                ),
                                SizedBox(height: fieldGap),
                                if (_mode == AccountMode.business) ...[
                                  TextFormField(
                                    controller: _businessNameController,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    decoration: _inputDecoration(
                                      label: 'account_business_name'.tr,
                                      icon: Icons.storefront_outlined,
                                    ),
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'account_business_name_required'
                                            .tr;
                                      }
                                      return null;
                                    },
                                  ),
                                  SizedBox(height: fieldGap),
                                ],
                                TextFormField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  autofillHints: const [
                                    AutofillHints.telephoneNumber,
                                  ],
                                  decoration: _inputDecoration(
                                    label: _mode == AccountMode.business
                                        ? 'convert_business_phone'.tr
                                        : 'account_phone_optional'.tr,
                                    icon: _mode == AccountMode.business
                                        ? Icons.chat_outlined
                                        : Icons.phone_outlined,
                                  ),
                                  validator: (value) =>
                                      _mode == AccountMode.business
                                      ? validateBusinessWhatsapp(value)
                                      : null,
                                ),
                                SizedBox(height: fieldGap),
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.email],
                                  decoration: _inputDecoration(
                                    label: 'login_email'.tr,
                                    icon: Icons.email_outlined,
                                  ),
                                  validator: (value) {
                                    if (_isGoogleSignUpAttempt) return null;
                                    final email = value?.trim() ?? '';
                                    if (email.isEmpty) {
                                      return 'Please enter your email address'
                                          .tr;
                                    }
                                    if (!GetUtils.isEmail(email)) {
                                      return 'Invalid email format'.tr;
                                    }
                                    return null;
                                  },
                                ),
                                SizedBox(height: fieldGap),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _hidePassword,
                                  autofillHints: const [
                                    AutofillHints.newPassword,
                                  ],
                                  decoration: _inputDecoration(
                                    label: 'login_password'.tr,
                                    icon: Icons.lock_outline,
                                    suffix: IconButton(
                                      onPressed: () => setState(
                                        () => _hidePassword = !_hidePassword,
                                      ),
                                      icon: Icon(
                                        _hidePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                    ),
                                  ),
                                  validator: (value) {
                                    if (_isGoogleSignUpAttempt) return null;
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter a password'.tr;
                                    }
                                    if (value.length < 6) {
                                      return 'Password must be at least 6 characters'
                                          .tr;
                                    }
                                    return null;
                                  },
                                ),
                                SizedBox(height: fieldGap),
                                TextFormField(
                                  controller: _confirmPasswordController,
                                  obscureText: _hideConfirmPassword,
                                  decoration: _inputDecoration(
                                    label: 'account_confirm_password'.tr,
                                    icon: Icons.lock_outline,
                                    suffix: IconButton(
                                      onPressed: () => setState(
                                        () => _hideConfirmPassword =
                                            !_hideConfirmPassword,
                                      ),
                                      icon: Icon(
                                        _hideConfirmPassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                    ),
                                  ),
                                  validator: (value) {
                                    if (_isGoogleSignUpAttempt) return null;
                                    if (value == null || value.isEmpty) {
                                      return 'Please confirm your password'.tr;
                                    }
                                    if (value != _passwordController.text) {
                                      return 'Passwords do not match'.tr;
                                    }
                                    return null;
                                  },
                                ),
                                SizedBox(height: compact ? 8 : 20),
                                ElevatedButton(
                                  onPressed: _isLoading ? null : _createAccount,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isBusiness
                                        ? const Color(0xFFFFE500)
                                        : accent,
                                    foregroundColor: isBusiness
                                        ? Colors.black87
                                        : Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 2,
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.black87,
                                          ),
                                        )
                                      : Text(
                                          'account_create_button'.tr,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
                                if (_googleSupported) ...[
                                  SizedBox(height: compact ? 2 : 12),
                                  Row(
                                    children: [
                                      const Expanded(child: Divider()),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        child: Text('login_or'.tr),
                                      ),
                                      const Expanded(child: Divider()),
                                    ],
                                  ),
                                  TextButton.icon(
                                    onPressed: _isLoading
                                        ? null
                                        : _createAccountWithGoogle,
                                    icon: const Text(
                                      'G',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFFDB4437),
                                      ),
                                    ),
                                    label: Text(
                                      'login_google'.tr,
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                                SizedBox(height: compact ? 2 : 12),
                                TextButton(
                                  onPressed: () =>
                                      Get.offNamed(AppRoutes.login),
                                  child: Text('account_already_have'.tr),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    final accent = _mode == AccountMode.business
        ? AuthBackdrop.businessAccent
        : AuthBackdrop.personalAccent;
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accent, width: 2),
      ),
    );
  }
}
