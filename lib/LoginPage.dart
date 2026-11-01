import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'invoice/language_switcher.dart';
import 'routes.dart';
import 'services/account_mode_service.dart';
import 'services/auth_backdrop.dart';
import 'services/business_access_service.dart';
import 'services/desktop_google_auth_stub.dart'
    if (dart.library.io) 'services/desktop_google_auth_io.dart';
import 'services/personal_device_lock_service.dart';
import 'services/personal_finance_service.dart';
import 'services/staff_service.dart';

class LoginController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final emailController = TextEditingController();
  final shopNicknameController = TextEditingController();
  final passwordController = TextEditingController();

  final isLoading = false.obs;
  final hidePassword = true.obs;
  final isStaffLogin = false.obs;
  final selectedMode = AccountMode.business.obs;
  bool _googleInitialized = false;

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

  Future<bool> _personalProfileExists(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('personalUsers')
          .doc(uid)
          .get();
      return doc.exists;
    } on FirebaseException catch (error) {
      // Rules deny reads from a previous device session, which only exists
      // for accounts that are already Personal.
      if (error.code == 'permission-denied') return true;
      rethrow;
    }
  }

  /// Returns a translation key when the account belongs to the other type.
  Future<String?> _accountTypeConflict(
    User user,
    AccountMode mode,
    bool noBusinessYet,
  ) async {
    if (mode == AccountMode.business) {
      if (noBusinessYet && await _personalProfileExists(user.uid)) {
        return 'account_is_personal';
      }
      return null;
    }
    await BusinessAccessService.initializeForCurrentUser();
    final isBusiness = BusinessAccessService.availableBusinesses.isNotEmpty;
    BusinessAccessService.clear();
    return isBusiness ? 'account_is_business' : null;
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

  Future<void> loginWithGoogle() => login(google: true);

  Future<void> login({bool google = false}) async {
    final staffLogin = google ? false : isStaffLogin.value;
    if (!google &&
        (emailController.text.trim().isEmpty ||
            passwordController.text.isEmpty ||
            (staffLogin && shopNicknameController.text.trim().isEmpty))) {
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
      if (google) {
        final credential = await _googleCredential();
        if (credential == null) return;
        userCredential = credential;
      } else if (staffLogin) {
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
        final mode = selectedMode.value;
        var needsBusinessSetup = false;
        if (mode == AccountMode.business || staffLogin) {
          await BusinessAccessService.initializeForCurrentUser();
        } else {
          await BusinessAccessService.ensureCurrentAccountEnabled();
        }
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
        } else if (mode == AccountMode.business) {
          if (BusinessAccessService.hasBusinessAccess) {
            if (BusinessAccessService.isLegacyMembership.value &&
                !BusinessAccessService.isOwner.value) {
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
          } else {
            needsBusinessSetup = true;
          }
        }
        if (!staffLogin) {
          final conflict = await _accountTypeConflict(
            userCredential.user!,
            mode,
            needsBusinessSetup,
          );
          if (conflict != null) {
            await _auth.signOut();
            BusinessAccessService.clear();
            Get.snackbar(
              'Login Failed',
              conflict.tr,
              backgroundColor: Colors.red,
              colorText: Colors.white,
              snackPosition: SnackPosition.BOTTOM,
            );
            return;
          }
        }
        await AccountModeService.setForCurrentUser(mode);
        if (mode == AccountMode.personal) {
          BusinessAccessService.clear();
          await PersonalDeviceLockService.claim();
          if (!await _personalProfileExists(userCredential.user!.uid)) {
            await PersonalFinanceService.saveProfile({
              'displayName': userCredential.user!.displayName ?? '',
              'photoUrl': '',
              'currency': 'TZS',
              'dateFormat': 'dd/MM/yyyy',
              'notificationsEnabled': true,
            });
          }
        }
        final pendingWebRoute = needsBusinessSetup
            ? null
            : AppRoutes.takePendingWebRoute();
        Get.offAllNamed(
          needsBusinessSetup ? AppRoutes.businessSetup : AppRoutes.home,
        );
        if (pendingWebRoute != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_auth.currentUser != null) {
              unawaited(Get.toNamed(pendingWebRoute));
            }
          });
        }
        Get.snackbar(
          'Success',
          'Welcome back!',
          backgroundColor: Colors.green,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled &&
          e.code != GoogleSignInExceptionCode.interrupted) {
        Get.snackbar(
          'Login Failed',
          '${'google_login_failed'.tr}\n${e.code.name}: ${e.description ?? ''}',
          backgroundColor: Colors.red,
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
          case 'invalid-credential':
            errorMessage = 'login_invalid_credentials'.tr;
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
        google
            ? '${'google_login_failed'.tr}\n$e'
            : 'Could not finish signing in. Please try again.',
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

  void selectMode(AccountMode mode) {
    if (isLoading.value) return;
    selectedMode.value = mode;
    if (mode == AccountMode.personal) isStaffLogin.value = false;
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

class LoginPage extends StatefulWidget {
  LoginPage({super.key});

  final LoginController controller = Get.put(LoginController());

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const _blue = Color(0xFF0F66DF);
  static const _green = Color(0xFF0E9F6E);
  static const _personalBg = Color(0xFFF2FBF6);
  static const _businessBg = Color(0xFFF1F6FF);
  // Windows/Linux use a browser loopback flow that needs a desktop client ID.
  static bool get _googleSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      ((defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux) &&
          desktopGoogleConfigured);
  late final PageController _pageController;
  late final LoginController controller;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    controller = widget.controller;
    _pageController = PageController(initialPage: _currentPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    if (index == 0) {
      controller.selectMode(AccountMode.personal);
    } else if (index == 2) {
      controller.selectMode(AccountMode.business);
    }
  }

  Future<void> _goToPage(int index) => _pageController.animateToPage(
    index,
    duration: const Duration(milliseconds: 360),
    curve: Curves.easeInOutCubic,
  );

  @override
  Widget build(BuildContext context) {
    final bg = switch (_currentPage) {
      0 => _personalBg,
      2 => _businessBg,
      _ => const Color(0xFFEAF2FC),
    };
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: bg,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: _buildScaffold(bg),
    );
  }

  Widget _buildScaffold(Color bg) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: bg,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        foregroundColor: Colors.black87,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          const LanguageSwitcher(color: Colors.black87),
          const SizedBox(width: 8),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        children: [
          _buildModeLoginPage(isBusiness: false),
          _buildWelcomePage(),
          _buildModeLoginPage(isBusiness: true),
        ],
      ),
    );
  }

  Widget _buildWelcomePage() => Stack(
    children: [
      Positioned.fill(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFD5F2E3), Color(0xFFEAF2FC), Color(0xFFB9D0F5)],
            ),
          ),
        ),
      ),
      SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            // Scales down on short screens so nothing needs scrolling.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE500),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .25),
                              blurRadius: 22,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/mjas.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'MJASI POS',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF0B1F3A),
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'login_choose_type'.tr,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF0B1F3A),
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 22),
                    _welcomeModeCard(
                      icon: Icons.person_outline_rounded,
                      label: 'mode_personal'.tr,
                      description: 'login_personal_desc'.tr,
                      accent: _green,
                      arrowOnLeft: true,
                      onPressed: () => _goToPage(0),
                    ),
                    const SizedBox(height: 12),
                    _welcomeModeCard(
                      icon: Icons.storefront_outlined,
                      label: 'mode_business'.tr,
                      description: 'login_business_desc'.tr,
                      accent: _blue,
                      arrowOnLeft: false,
                      onPressed: () => _goToPage(2),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.swipe_rounded,
                          size: 16,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'login_swipe_both'.tr,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => Get.toNamed(AppRoutes.register),
                      style: TextButton.styleFrom(foregroundColor: _blue),
                      child: Text(
                        'login_create_account'.tr,
                        style: const TextStyle(fontWeight: FontWeight.w700),
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
  );

  Widget _welcomeModeCard({
    required IconData icon,
    required String label,
    required String description,
    required Color accent,
    required bool arrowOnLeft,
    required VoidCallback onPressed,
  }) {
    final arrow = Icon(
      arrowOnLeft
          ? Icons.arrow_back_ios_new_rounded
          : Icons.arrow_forward_ios_rounded,
      size: 16,
      color: accent,
    );
    return Material(
      color: Colors.white,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: .3),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (arrowOnLeft) ...[arrow, const SizedBox(width: 10)],
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFF0B1F3A),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (!arrowOnLeft) ...[const SizedBox(width: 10), arrow],
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(
    String label,
    IconData icon, {
    Color accent = _blue,
  }) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 20),
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: accent, width: 1.6),
    ),
  );

  Widget _buildModeLoginPage({required bool isBusiness}) {
    final mode = isBusiness ? AccountMode.business : AccountMode.personal;
    final accent = isBusiness ? _blue : _green;
    final form = Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        // Scales the form down on short screens so it never needs scrolling.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE500),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: .25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset('assets/mjas.png', fit: BoxFit.cover),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'MJASI POS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .6,
                    color: Color(0xFF0B1F3A),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isBusiness
                              ? Icons.storefront_outlined
                              : Icons.person_outline_rounded,
                          color: accent,
                          size: 17,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          isBusiness ? 'mode_business'.tr : 'mode_personal'.tr,
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isBusiness
                      ? 'login_business_desc'.tr
                      : 'login_personal_desc'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: Colors.black54,
                  ),
                ),
                if (isBusiness) ...[
                  const SizedBox(height: 14),
                  Obx(
                    () => SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text('login_as_owner'.tr),
                          icon: const Icon(Icons.business_outlined, size: 18),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('login_as_staff'.tr),
                          icon: const Icon(Icons.badge_outlined, size: 18),
                        ),
                      ],
                      selected: {controller.isStaffLogin.value},
                      onSelectionChanged: controller.isLoading.value
                          ? null
                          : (selection) =>
                                controller.setStaffLogin(selection.first),
                    ),
                  ),
                  Obx(
                    () => controller.isStaffLogin.value
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'staff_login_hint'.tr,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11.5,
                                height: 1.3,
                                color: Color(0xFF0E5962),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
                const SizedBox(height: 16),
                Obx(
                  () => TextFormField(
                    controller: controller.emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _fieldDecoration(
                      controller.isStaffLogin.value
                          ? 'staff_login_business_email'.tr
                          : 'login_email'.tr,
                      Icons.email_outlined,
                      accent: accent,
                    ),
                  ),
                ),
                Obx(() {
                  final staffLogin = controller.isStaffLogin.value;
                  return isBusiness && staffLogin
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: TextFormField(
                            controller: controller.shopNicknameController,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: _fieldDecoration(
                              'staff_shop_nickname'.tr,
                              Icons.storefront_outlined,
                              accent: accent,
                            ),
                          ),
                        )
                      : const SizedBox.shrink();
                }),
                const SizedBox(height: 12),
                Obx(
                  () => TextFormField(
                    controller: controller.passwordController,
                    obscureText: controller.hidePassword.value,
                    decoration:
                        _fieldDecoration(
                          'login_password'.tr,
                          Icons.lock_outline,
                          accent: accent,
                        ).copyWith(
                          suffixIcon: IconButton(
                            onPressed: controller.togglePasswordVisibility,
                            icon: Icon(
                              controller.hidePassword.value
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                            ),
                          ),
                        ),
                  ),
                ),
                Obx(() {
                  final hide = isBusiness && controller.isStaffLogin.value;
                  return Align(
                    alignment: Alignment.centerRight,
                    child: hide
                        ? const SizedBox(height: 12)
                        : TextButton(
                            onPressed: controller.isLoading.value
                                ? null
                                : controller.resetPassword,
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            child: Text('login_forgot_password'.tr),
                          ),
                  );
                }),
                Obx(
                  () => ElevatedButton(
                    onPressed: controller.isLoading.value
                        ? null
                        : () {
                            controller.selectMode(mode);
                            controller.login();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isBusiness
                          ? const Color(0xFFFFE500)
                          : _green,
                      foregroundColor: isBusiness
                          ? Colors.black87
                          : Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
                            isBusiness && controller.isStaffLogin.value
                                ? 'staff_login_button'.tr
                                : 'login_sign_in'.tr,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                Obx(() {
                  final hide = isBusiness && controller.isStaffLogin.value;
                  if (hide || !_googleSupported) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: TextButton.icon(
                      onPressed: controller.isLoading.value
                          ? null
                          : () {
                              controller.selectMode(mode);
                              controller.loginWithGoogle();
                            },
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
                  );
                }),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => Get.toNamed(AppRoutes.register),
                      child: Text('login_create_account'.tr),
                    ),
                    const Text('â€¢', style: TextStyle(color: Colors.black38)),
                    TextButton.icon(
                      onPressed: () => _goToPage(1),
                      icon: Icon(
                        isBusiness
                            ? Icons.swipe_left_rounded
                            : Icons.swipe_right_rounded,
                        size: 18,
                      ),
                      label: Text('login_change_mode'.tr),
                    ),
                  ],
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => Get.toNamed(AppRoutes.privacy),
                      child: Text(
                        'legal_privacy_link'.tr,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Get.toNamed(AppRoutes.terms),
                      child: Text(
                        'legal_terms_link'.tr,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Stack(
      children: [
        Positioned.fill(child: AuthBackdrop(isBusiness: isBusiness)),
        SafeArea(child: form),
      ],
    );
  }
}
