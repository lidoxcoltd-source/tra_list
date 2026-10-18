import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'invoice/language_switcher.dart';
import 'routes.dart';
import 'services/business_access_service.dart';
import 'services/staff_service.dart';

class LoginController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final emailController = TextEditingController();
  final shopNicknameController = TextEditingController();
  final passwordController = TextEditingController();

  final isLoading = false.obs;
  final hidePassword = true.obs;
  final isStaffLogin = false.obs;

  @override
  void onInit() {
    super.onInit();
    // Check if user is already logged in
    if (_auth.currentUser != null) {
      Get.offAllNamed(AppRoutes.home);
    }
  }

  Future<void> resetPassword() async {
    final email = emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      Get.snackbar(
        'Error',
        'Enter your account email above first',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-email' || e.code == 'network-request-failed') {
        Get.snackbar(
          'Error',
          e.code == 'invalid-email'
              ? 'That email address is not valid'
              : 'Check your internet connection and try again',
          backgroundColor: Colors.red,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }
    }
    // Same message for unknown emails so accounts cannot be probed.
    Get.snackbar(
      'Check your email',
      'If an account exists for $email, a password reset link has been sent.',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 6),
    );
  }

  Future<void> login() async {
    final staffLogin = isStaffLogin.value;
    if (emailController.text.trim().isEmpty ||
        passwordController.text.isEmpty ||
        (staffLogin && shopNicknameController.text.trim().isEmpty)) {
      Get.snackbar(
        'Error',
        staffLogin
            ? 'staff_login_credentials_required'.tr
            : 'Please enter both email and password',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    try {
      isLoading.value = true;

      final enteredEmail = emailController.text.trim();
      late final UserCredential userCredential;
      if (staffLogin) {
        try {
          userCredential = await _auth.signInWithEmailAndPassword(
            email: StaffService.staffAuthEmail(
              businessEmail: enteredEmail,
              password: passwordController.text,
            ),
            password: passwordController.text,
          );
        } on FirebaseAuthException catch (error) {
          if (error.code != 'user-not-found' &&
              error.code != 'invalid-credential') {
            rethrow;
          }
          userCredential = await _auth.signInWithEmailAndPassword(
            email: StaffService.legacyStaffAuthEmail(
              businessEmail: enteredEmail,
              username: shopNicknameController.text,
            ),
            password: passwordController.text,
          );
        }
      } else {
        userCredential = await _auth.signInWithEmailAndPassword(
          email: enteredEmail,
          password: passwordController.text,
        );
      }

      if (userCredential.user != null) {
        await BusinessAccessService.initializeForCurrentUser();
        if (staffLogin) {
          final membership = await FirebaseFirestore.instance
              .collection('employeeMemberships')
              .doc(userCredential.user!.uid)
              .get();
          final storedShopNickname =
              membership
                  .data()?['shopNickname']
                  ?.toString()
                  .trim()
                  .toLowerCase() ??
              '';
          final storedLegacyUsername =
              membership.data()?['username']?.toString().trim().toLowerCase() ??
              '';
          final enteredShopNickname = shopNicknameController.text
              .trim()
              .toLowerCase();
          final storedBusinessEmail =
              membership
                  .data()?['businessEmail']
                  ?.toString()
                  .trim()
                  .toLowerCase() ??
              '';
          final shopMatches =
              storedShopNickname == enteredShopNickname ||
              storedLegacyUsername == enteredShopNickname;
          if (!membership.exists ||
              BusinessAccessService.isOwner.value ||
              !BusinessAccessService.isActive.value ||
              enteredShopNickname.isEmpty ||
              !shopMatches ||
              (storedBusinessEmail.isNotEmpty &&
                  storedBusinessEmail != enteredEmail.toLowerCase())) {
            await _auth.signOut();
            BusinessAccessService.clear();
            Get.snackbar(
              'Login Failed',
              'staff_login_credentials_invalid'.tr,
              backgroundColor: Colors.red,
              colorText: Colors.white,
              snackPosition: SnackPosition.BOTTOM,
            );
            return;
          }
        } else if (!BusinessAccessService.isOwner.value) {
          await _auth.signOut();
          BusinessAccessService.clear();
          Get.snackbar(
            'Login Failed',
            'owner_login_staff_account'.tr,
            backgroundColor: Colors.red,
            colorText: Colors.white,
            snackPosition: SnackPosition.BOTTOM,
          );
          return;
        }
        Get.offAllNamed(AppRoutes.home);
        Get.snackbar(
          'Success',
          'Welcome back!',
          backgroundColor: Colors.green,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Login failed';

      if (staffLogin &&
          (e.code == 'user-not-found' ||
              e.code == 'wrong-password' ||
              e.code == 'invalid-credential')) {
        errorMessage = 'staff_login_credentials_invalid'.tr;
      } else {
        switch (e.code) {
          case 'user-not-found':
            errorMessage = 'No user found with this email';
            break;
          case 'wrong-password':
            errorMessage = 'Incorrect password';
            break;
          case 'invalid-email':
            errorMessage = 'Invalid email format';
            break;
          case 'user-disabled':
            errorMessage = 'This account has been disabled';
            break;
          case 'too-many-requests':
            errorMessage = 'Too many attempts. Please try again later';
            break;
          default:
            errorMessage = e.message ?? 'Login failed';
        }
      }

      Get.snackbar(
        'Login Failed',
        errorMessage,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
      );
    } on DisabledAccountException {
      await _auth.signOut();
      BusinessAccessService.clear();
      Get.snackbar(
        'Login Failed',
        'account_disabled_message'.tr,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } on FirebaseException catch (e, stackTrace) {
      debugPrint('Login initialization failed (${e.code}): $e');
      debugPrintStack(stackTrace: stackTrace);
      await _auth.signOut();
      BusinessAccessService.clear();

      final errorMessage = switch (e.code) {
        'permission-denied' =>
          'Could not load your business access. Firestore security rules may need to be deployed.',
        'unavailable' || 'network-request-failed' =>
          'Could not connect to Firebase. Check your internet connection and try again.',
        _ => e.message ?? 'Could not finish signing in. Please try again.',
      };
      Get.snackbar(
        'Login Failed',
        errorMessage,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
    } catch (e, stackTrace) {
      debugPrint('Unexpected login initialization error: $e');
      debugPrintStack(stackTrace: stackTrace);
      await _auth.signOut();
      BusinessAccessService.clear();
      Get.snackbar(
        'Error',
        'Could not finish signing in. Please try again.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoading.value = false;
    }
  }

  void togglePasswordVisibility() {
    hidePassword.value = !hidePassword.value;
  }

  void setStaffLogin(bool value) {
    isStaffLogin.value = value;
  }

  Future<void> signOut() async {
    await _auth.signOut();
    BusinessAccessService.clear();
    Get.offAllNamed(AppRoutes.login);
  }

  @override
  void onClose() {
    emailController.dispose();
    shopNicknameController.dispose();
    passwordController.dispose();
    super.onClose();
  }
}

class LoginPage extends StatelessWidget {
  LoginPage({super.key});

  final controller = Get.put(LoginController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        actions: const [LanguageSwitcher(), SizedBox(width: 8)],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo/Header
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE500),
                    borderRadius: BorderRadius.circular(60),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/mjas.png',
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Title
                const Text(
                  'MJASI POS',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'login_subtitle'.tr,
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),

                const SizedBox(height: 48),

                // Login Form
                Container(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Card(
                    elevation: 8,
                    shadowColor: Colors.black.withOpacity(0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Obx(
                            () => SegmentedButton<bool>(
                              segments: [
                                ButtonSegment(
                                  value: false,
                                  label: Text('login_as_owner'.tr),
                                  icon: const Icon(Icons.business_outlined),
                                ),
                                ButtonSegment(
                                  value: true,
                                  label: Text('login_as_staff'.tr),
                                  icon: const Icon(Icons.badge_outlined),
                                ),
                              ],
                              selected: {controller.isStaffLogin.value},
                              onSelectionChanged: controller.isLoading.value
                                  ? null
                                  : (selection) => controller.setStaffLogin(
                                      selection.first,
                                    ),
                            ),
                          ),
                          Obx(
                            () => controller.isStaffLogin.value
                                ? Container(
                                    margin: const EdgeInsets.only(top: 14),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEAF4F3),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          Icons.info_outline_rounded,
                                          size: 18,
                                          color: Color(0xFF0E5962),
                                        ),
                                        const SizedBox(width: 9),
                                        Expanded(
                                          child: Text(
                                            'staff_login_hint'.tr,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              height: 1.4,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 20),
                          // Staff use the business owner's email as their login identifier.
                          Obx(
                            () => TextFormField(
                              controller: controller.emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                labelText: controller.isStaffLogin.value
                                    ? 'staff_login_business_email'.tr
                                    : 'login_email'.tr,
                                prefixIcon: const Icon(Icons.email_outlined),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFFFE500),
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          Obx(
                            () => controller.isStaffLogin.value
                                ? Padding(
                                    padding: const EdgeInsets.only(bottom: 20),
                                    child: TextFormField(
                                      controller:
                                          controller.shopNicknameController,
                                      textCapitalization:
                                          TextCapitalization.none,
                                      autocorrect: false,
                                      enableSuggestions: false,
                                      decoration: InputDecoration(
                                        labelText: 'staff_shop_nickname'.tr,
                                        prefixIcon: const Icon(
                                          Icons.storefront_outlined,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: Colors.grey.shade300,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFFFE500),
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),

                          // Password Field
                          Obx(
                            () => TextFormField(
                              controller: controller.passwordController,
                              obscureText: controller.hidePassword.value,
                              decoration: InputDecoration(
                                labelText: 'login_password'.tr,
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  onPressed:
                                      controller.togglePasswordVisibility,
                                  icon: Icon(
                                    controller.hidePassword.value
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFFFE500),
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Login Button
                          Obx(
                            () => ElevatedButton(
                              onPressed: controller.isLoading.value
                                  ? null
                                  : controller.login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFE500),
                                foregroundColor: Colors.black87,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                              ),
                              child: controller.isLoading.value
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black87,
                                      ),
                                    )
                                  : Text(
                                      controller.isStaffLogin.value
                                          ? 'staff_login_button'.tr
                                          : 'login_sign_in'.tr,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          Obx(
                            () => controller.isStaffLogin.value
                                ? const SizedBox.shrink()
                                : Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: controller.isLoading.value
                                          ? null
                                          : controller.resetPassword,
                                      child: const Text('Forgot password?'),
                                    ),
                                  ),
                          ),

                          const SizedBox(height: 8),

                          // Register Button
                          Obx(
                            () => OutlinedButton(
                              onPressed: controller.isLoading.value
                                  ? null
                                  : () => Get.toNamed(AppRoutes.register),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: const BorderSide(
                                  color: Color(0xFFFFE500),
                                ),
                              ),
                              child: const Text(
                                'Create Account',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFFFE500),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Demo Credentials Info
              ],
            ),
          ),
        ),
      ),
    );
  }
}
