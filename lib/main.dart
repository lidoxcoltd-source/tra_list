import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/invoice/app_translations.dart';
import 'package:tra_list/invoice/language_controller.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/app_version_gate.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await GetStorage.init(); // Initialize GetStorage for language persistence
  if (FirebaseAuth.instance.currentUser != null) {
    try {
      await BusinessAccessService.initializeForCurrentUser();
    } on DisabledAccountException {
      await FirebaseAuth.instance.signOut();
      BusinessAccessService.clear();
    }
  }
  debugPrint('Storage bucket (runtime) = ${FirebaseStorage.instance.bucket}');
  runApp(MyApp());
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

class MyApp extends StatelessWidget {
  MyApp({super.key});

  // Initialize and register the LanguageController
  final langController = Get.put(LanguageController());

  @override
  Widget build(BuildContext context) {
    // Web deep links (e.g. /receipt/123) must skip the splash screen.
    final isDeepLink = kIsWeb && Uri.base.path.length > 1;
    final isDownloads =
        kIsWeb &&
        Uri.base.path.replaceAll(RegExp(r'/+$'), '') == AppRoutes.downloads;
    final String initialRoute = isDownloads
        ? AppRoutes.downloads
        : isDeepLink
        ? (FirebaseAuth.instance.currentUser != null
              ? AppRoutes.home
              : AppRoutes.login)
        : AppRoutes.splash;

    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mjasi POS',
      // Localization settings
      translations: AppTranslations(),
      locale: langController.locale, // Set initial locale from storage
      fallbackLocale: const Locale('en', 'US'), // Fallback language

      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          scrolledUnderElevation: 1,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        scrollbarTheme: ScrollbarThemeData(
          thickness: WidgetStateProperty.all(6),
          radius: const Radius.circular(8),
        ),
      ),
      initialRoute: initialRoute,
      getPages: AppRoutes.pages, // <-- wire routes
      scrollBehavior: const _AppScrollBehavior(),
      builder: (context, child) =>
          AppVersionGate(child: child ?? const SizedBox.shrink()),
      defaultTransition: kIsWeb ? Transition.fadeIn : Transition.rightToLeft,
      transitionDuration: const Duration(milliseconds: 300),
    );
  }
}
