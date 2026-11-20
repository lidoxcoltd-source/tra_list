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
  const CreateAccountPage({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends State<CreateAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameKey = GlobalKey<FormFieldState<String>>();
  final _businessNameKey = GlobalKey<FormFieldState<String>>();
  final _phoneKey = GlobalKey<FormFieldState<String>>();
  final _emailKey = GlobalKey<FormFieldState<String>>();
  final _passwordKey = GlobalKey<FormFieldState<String>>();
  final _confirmPasswordKey = GlobalKey<FormFieldState<String>>();
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
  int _step = 0;

  static const _stepCount = 5;

  bool _validateCurrentStep() {
    final keys = switch (_step) {
      0 => [_nameKey],
      1 => _mode == AccountMode.business
          ? [_businessNameKey, _phoneKey]
          : [_phoneKey],
      2 => [_emailKey],
      3 => [_passwordKey],
      _ => [_confirmPasswordKey],
    };
    var valid = true;
    for (final key in keys) {
      if (!(key.currentState?.validate() ?? false)) valid = false;
    }
    return valid;
  }

  void _nextStep() {
    if (!_validateCurrentStep()) return;
    if (_step < _stepCount - 1) setState(() => _step++);
  }

  void _previousStep() {
    if (_step > 0) setState(() => _step--);
  }

  Widget _buildStepFields(double fieldGap) {
    switch (_step) {
      case 0:
        return TextFormField(
          key: _nameKey,
          controller: _nameController,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w400),
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          decoration: _inputDecoration(
            label: 'account_full_name'.tr,
            icon: Icons.person_outline,
          ),
          validator: (value) => _isGoogleSignUpAttempt
              ? null
              : value == null || value.trim().isEmpty
                  ? 'account_full_name_required'.tr
                  : null,
        );
      case 1:
        return Column(
          key: const ValueKey('account-step-business'),
          children: [
            if (_mode == AccountMode.business) ...[
              TextFormField(
                key: _businessNameKey,
                controller: _businessNameController,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w400),
                textCapitalization: TextCapitalization.words,
                decoration: _inputDecoration(
                  label: 'account_business_name'.tr,
                  icon: Icons.storefront_outlined,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'account_business_name_required'.tr
                    : null,
              ),
              SizedBox(height: fieldGap),
            ],
            TextFormField(
              key: _phoneKey,
              controller: _phoneController,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w400),
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: _inputDecoration(
                label: _mode == AccountMode.business
                    ? 'convert_business_phone'.tr
                    : 'account_phone_optional'.tr,
                icon: _mode == AccountMode.business
                    ? Icons.chat_outlined
                    : Icons.phone_outlined,
              ),
              validator: (value) => _mode == AccountMode.business
                  ? validateBusinessWhatsapp(value)
                  : null,
            ),
          ],
        );
      case 2:
        return TextFormField(
          key: _emailKey,
          controller: _emailController,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w400),
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: _inputDecoration(
            label: 'login_email'.tr,
            icon: Icons.email_outlined,
          ),
          validator: (value) {
            if (_isGoogleSignUpAttempt) return null;
            final email = value?.trim() ?? '';
            if (email.isEmpty) return 'Please enter your email address'.tr;
            if (!GetUtils.isEmail(email)) return 'Invalid email format'.tr;
            return null;
          },
        );
      case 3:
        return TextFormField(
          key: _passwordKey,
          controller: _passwordController,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w400),
          obscureText: _hidePassword,
          autofillHints: const [AutofillHints.newPassword],
          decoration: _inputDecoration(
            label: 'login_password'.tr,
            icon: Icons.lock_outline,
            suffix: IconButton(
              onPressed: () => setState(() => _hidePassword = !_hidePassword),
              icon: Icon(_hidePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
            ),
          ),
          validator: (value) {
            if (_isGoogleSignUpAttempt) return null;
            if (value == null || value.isEmpty) return 'Please enter a password'.tr;
            if (value.length < 6) return 'Password must be at least 6 characters'.tr;
            return null;
          },
        );
      default:
        return TextFormField(
          key: _confirmPasswordKey,
          controller: _confirmPasswordController,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w400),
          obscureText: _hideConfirmPassword,
          decoration: _inputDecoration(
            label: 'account_confirm_password'.tr,
            icon: Icons.lock_outline,
            suffix: IconButton(
              onPressed: () => setState(
                () => _hideConfirmPassword = !_hideConfirmPassword,
              ),
              icon: Icon(_hideConfirmPassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
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
        );
    }
  }

  Widget _buildStepProgress(Color accent) => Column(
    children: [
      Row(
        children: List.generate(_stepCount, (index) {
          final active = index <= _step;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              height: 4,
              margin: EdgeInsets.only(right: index == _stepCount - 1 ? 0 : 7),
              decoration: BoxDecoration(
                color: active ? accent : Colors.white.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }),
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(_stepCount, (index) {
          final active = index <= _step;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? accent : const Color(0xFF102C50),
              border: Border.all(
                color: active ? accent : Colors.white.withValues(alpha: .3),
              ),
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: active ? const Color(0xFF06152E) : const Color(0xFFC0D7EA),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          );
        }),
      ),
    ],
  );

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail?.trim() ?? '';
  }

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
    final height = MediaQuery.sizeOf(context).height;
    final compact = height < 860;
    final tight = height < 720;
    final fieldGap = tight ? 5.0 : (compact ? 7.0 : 12.0);
    final isBusiness = _mode == AccountMode.business;
    final accent = isBusiness
        ? AuthBackdrop.businessAccent
        : AuthBackdrop.personalAccent;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: isBusiness
          ? const Color(0xFF06152E)
          : const Color(0xFF071B2A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: _step > 0 ? _previousStep : () => Get.back(),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          tooltip: 'Back'.tr,
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: AuthBackdrop(isBusiness: isBusiness)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: MediaQuery.viewInsetsOf(context).bottom > 0
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 12 : 24,
                    vertical: tight ? 2 : (compact ? 8 : 24),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!compact)
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: const Color(0xFF102C50),
                              borderRadius: BorderRadius.circular(48),
                              border: Border.all(color: accent, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withValues(alpha: .28),
                                  blurRadius: 24,
                                  spreadRadius: 2,
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
                        if (compact && !tight)
                          Container(
                            width: 40,
                            height: 40,
                            margin: const EdgeInsets.only(bottom: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF102C50),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: accent, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withValues(alpha: .26),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.asset(
                                'assets/mjas.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        SizedBox(height: tight ? 1 : (compact ? 2 : 14)),
                        Text(
                          'account_create_title'.tr,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: tight ? 19 : (compact ? 21 : 27),
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        if (!compact) const SizedBox(height: 8),
                        if (!compact || !tight)
                          Text(
                            'account_create_subtitle'.tr,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: compact ? 12 : 16,
                              color: const Color(0xFFC0D7EA),
                            ),
                          ),
                        SizedBox(height: tight ? 3 : (compact ? 5 : 16)),
                        Container(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              segmentedButtonTheme: SegmentedButtonThemeData(
                                style: ButtonStyle(
                                  foregroundColor: WidgetStateProperty.resolveWith(
                                    (states) => states.contains(WidgetState.selected)
                                        ? const Color(0xFF06152E)
                                        : const Color(0xFFE2F0FF),
                                  ),
                                  backgroundColor: WidgetStateProperty.resolveWith(
                                    (states) => states.contains(WidgetState.selected)
                                        ? accent
                                        : const Color(0xFF102C50),
                                  ),
                                  side: WidgetStateProperty.all(
                                    BorderSide(color: accent.withValues(alpha: .45)),
                                  ),
                                ),
                              ),
                            ),
                            child: AccountModeSelector(
                              mode: _mode,
                              onChanged: (mode) => setState(() {
                                _mode = mode;
                                _step = 0;
                              }),
                            ),
                          ),
                        ),
                        SizedBox(height: tight ? 3 : (compact ? 5 : 12)),
                        Container(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: Card(
                            elevation: 12,
                            color: const Color(0xFF0D2747).withValues(alpha: .97),
                            shadowColor: Colors.black.withValues(alpha: .4),
                            surfaceTintColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(
                              tight ? 14 : (compact ? 20 : 28),
                              ),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: compact ? 330 : 430,
                                ),
                                child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    _buildStepProgress(accent),
                                    const SizedBox(height: 18),
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 460),
                                      reverseDuration: const Duration(milliseconds: 360),
                                      transitionBuilder: (child, animation) => FadeTransition(
                                        opacity: animation,
                                        child: SlideTransition(
                                          position: Tween<Offset>(
                                            begin: const Offset(.035, 0),
                                            end: Offset.zero,
                                          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic)),
                                          child: child,
                                        ),
                                      ),
                                      child: Column(
                                        key: ValueKey('registration-step-$_step-$_mode'),
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                            'Step ${_step + 1} of $_stepCount',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 1.1),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            switch (_step) {
                                              0 => 'account_full_name'.tr,
                                              1 => _mode == AccountMode.business ? 'account_business_name'.tr : 'account_phone_optional'.tr,
                                              2 => 'login_email'.tr,
                                              3 => 'login_password'.tr,
                                              _ => 'account_confirm_password'.tr,
                                            },
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w500),
                                          ),
                                            const SizedBox(height: 24),
                                            Center(
                                              child: ConstrainedBox(
                                                constraints: const BoxConstraints(maxWidth: 340),
                                                child: _buildStepFields(fieldGap),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(height: compact ? 14 : 22),
                                    Row(
                                      children: [
                                        if (_step > 0)
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: _isLoading ? null : _previousStep,
                                              icon: const Icon(Icons.arrow_back_rounded, size: 18),
                                              label: Text('Back'.tr),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.white,
                                                side: BorderSide(color: Colors.white.withValues(alpha: .3)),
                                                minimumSize: Size.fromHeight(compact ? 42 : 48),
                                              ),
                                            ),
                                          ),
                                        if (_step > 0) const SizedBox(width: 10),
                                        Expanded(
                                          flex: 2,
                                          child: ElevatedButton.icon(
                                            onPressed: _isLoading
                                                ? null
                                                : _step == _stepCount - 1
                                                    ? _createAccount
                                                    : _nextStep,
                                            icon: Icon(_step == _stepCount - 1 ? Icons.check_circle_outline_rounded : Icons.arrow_forward_rounded, size: 19),
                                            label: _isLoading
                                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                                : Text(_step == _stepCount - 1 ? 'account_create_button'.tr : 'Continue'.tr, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: accent,
                                              foregroundColor: const Color(0xFF06152E),
                                              minimumSize: Size.fromHeight(compact ? 42 : 48),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                              elevation: 4,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_step == _stepCount - 1 && _googleSupported) ...[
                                      SizedBox(height: compact ? 4 : 12),
                                      Row(
                                        children: [
                                          Expanded(child: Divider(color: Colors.white.withValues(alpha: .2))),
                                          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('login_or'.tr, style: const TextStyle(color: Color(0xFFC0D7EA)))),
                                          Expanded(child: Divider(color: Colors.white.withValues(alpha: .2))),
                                        ],
                                      ),
                                      TextButton.icon(
                                        onPressed: _isLoading ? null : _createAccountWithGoogle,
                                        icon: const Text('G', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFFDB4437))),
                                        label: Text('login_google'.tr, style: const TextStyle(color: Color(0xFFE2F0FF), fontWeight: FontWeight.w600)),
                                      ),
                                    ],
                                    SizedBox(height: compact ? 2 : 8),
                                    TextButton(
                                      onPressed: () => Get.offNamed(AppRoutes.login),
                                      child: Text('account_already_have'.tr),
                                    ),
                                  ],
                                ),
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
    final height = MediaQuery.sizeOf(context).height;
    final compact = height < 860;
    final tight = height < 720;
    final accent = _mode == AccountMode.business
        ? AuthBackdrop.businessAccent
        : AuthBackdrop.personalAccent;
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF9FC7E8)),
      suffixIcon: suffix,
      prefixIconConstraints: BoxConstraints(
        minWidth: compact ? 38 : 48,
        minHeight: compact ? 42 : 48,
      ),
      suffixIconConstraints: BoxConstraints(
        minWidth: compact ? 38 : 48,
        minHeight: compact ? 42 : 48,
      ),
      isDense: true,
      filled: true,
      fillColor: const Color(0xFF102C50),
      labelStyle: TextStyle(
        fontSize: compact ? 13 : 14,
        color: const Color(0xFFC0D7EA),
      ),
      floatingLabelStyle: TextStyle(color: accent),
      hintStyle: const TextStyle(color: Color(0xFF9FB6CA)),
      helperStyle: const TextStyle(color: Color(0xFFC0D7EA)),
      errorStyle: const TextStyle(color: Color(0xFFFFA6A6)),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: tight ? 6 : (compact ? 8 : 10),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .18)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accent, width: 2),
      ),
    );
  }
}
