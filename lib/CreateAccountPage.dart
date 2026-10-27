import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/services/account_mode_service.dart';
import 'package:tra_list/services/account_mode_selector.dart';
import 'package:tra_list/services/auth_backdrop.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/convert_to_business.dart';
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
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;
  AccountMode _mode = AccountMode.personal;

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
      await user.updateDisplayName(_nameController.text.trim());
      await AccountModeService.setForCurrentUser(_mode);
      if (_mode == AccountMode.business) {
        await ProfileService.createForRegistration(
          ownerName: _nameController.text.trim(),
          businessName: _businessNameController.text.trim(),
          email: _emailController.text.trim(),
          phone: _phoneController.text.trim(),
        );
        await BusinessAccessService.initializeForCurrentUser();
      } else {
        BusinessAccessService.clear();
        await PersonalFinanceService.saveProfile({
          'displayName': _nameController.text.trim(),
          'photoUrl': '',
          'currency': 'TZS',
          'dateFormat': 'dd/MM/yyyy',
          'notificationsEnabled': true,
        });
      }
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
      if (mounted) {
        Get.snackbar(
          'Registration Failed'.tr,
          'account_profile_save_failed'.tr,
          backgroundColor: Colors.red,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
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
                    const SizedBox(height: 28),
                    Text(
                      'account_create_title'.tr,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'account_create_subtitle'.tr,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 32),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: AccountModeSelector(
                        mode: _mode,
                        onChanged: (mode) => setState(() => _mode = mode),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Card(
                        elevation: 8,
                        shadowColor: Colors.black.withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
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
                                    if (value == null || value.trim().isEmpty) {
                                      return 'account_full_name_required'.tr;
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 20),
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
                                  const SizedBox(height: 20),
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
                                const SizedBox(height: 20),
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.email],
                                  decoration: _inputDecoration(
                                    label: 'login_email'.tr,
                                    icon: Icons.email_outlined,
                                  ),
                                  validator: (value) {
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
                                const SizedBox(height: 20),
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
                                const SizedBox(height: 20),
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
                                    if (value == null || value.isEmpty) {
                                      return 'Please confirm your password'.tr;
                                    }
                                    if (value != _passwordController.text) {
                                      return 'Passwords do not match'.tr;
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 28),
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
                                      vertical: 16,
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
                                const SizedBox(height: 16),
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
