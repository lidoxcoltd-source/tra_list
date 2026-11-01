import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/invoice/app_translations.dart';
import 'package:tra_list/invoice/language_controller.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/account_mode_service.dart';
import 'package:tra_list/services/app_version_gate.dart';
import 'package:tra_list/services/offline_sync_coordinator.dart';
import 'package:tra_list/market/market_media_route_observer.dart';
import 'package:tra_list/theme/app_theme.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(
      webExperimentalAutoDetectLongPolling: true,
      persistenceEnabled: true,
    );
  }
  await GetStorage.init(); // Initialize GetStorage for language persistence
  if (FirebaseAuth.instance.currentUser != null) {
    try {
      if (AccountModeService.current == AccountMode.business) {
        await BusinessAccessService.initializeForCurrentUser();
      } else {
        await BusinessAccessService.ensureCurrentAccountEnabled();
        BusinessAccessService.clear();
      }
    } on DisabledAccountException {
      await FirebaseAuth.instance.signOut();
      BusinessAccessService.clear();
    } catch (error, stackTrace) {
      debugPrint('Could not restore business access: $error');
      debugPrintStack(stackTrace: stackTrace);
      BusinessAccessService.clear();
      BusinessAccessService.initializationError = error.toString();
    }
  }
  await OfflineSyncCoordinator.start();
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
    final webRoute = kIsWeb ? AppRoutes.resolveWebLocation(Uri.base) : null;
    final isDeepLink =
        webRoute != null && webRoute != AppRoutes.home && webRoute != AppRoutes.splash;
    final signedIn = FirebaseAuth.instance.currentUser != null;
    final requiresAuthentication =
        webRoute != null && AppRoutes.webRouteRequiresAuthentication(webRoute);
    final initialRoute = isDeepLink
        ? signedIn
              ? AppRoutes.home
              : AppRoutes.login
        : AppRoutes.splash;
    if (isDeepLink && !signedIn && requiresAuthentication) {
      AppRoutes.pendingWebRoute = webRoute;
    }
    final initialWebRoute = isDeepLink &&
            (signedIn || !requiresAuthentication) &&
            webRoute != AppRoutes.login
        ? webRoute
        : null;

    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mjasi POS',
      // Localization settings
      translations: AppTranslations(),
      locale: langController.locale, // Set initial locale from storage
      fallbackLocale: const Locale('en', 'US'), // Fallback language

      theme: MjasiTheme.light,
      initialRoute: initialRoute,
      getPages: AppRoutes.pages, // <-- wire routes
      navigatorObservers: [marketMediaRouteObserver],
      scrollBehavior: const _AppScrollBehavior(),
      defaultTransition: kIsWeb ? Transition.fadeIn : Transition.rightToLeft,
      transitionDuration: const Duration(milliseconds: 300),
      builder: (context, child) => _InitialWebRouteLauncher(
        route: initialWebRoute,
        child: AppVersionGate(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

class _InitialWebRouteLauncher extends StatefulWidget {
  const _InitialWebRouteLauncher({required this.route, required this.child});

  final String? route;
  final Widget child;

  @override
  State<_InitialWebRouteLauncher> createState() =>
      _InitialWebRouteLauncherState();
}

class _InitialWebRouteLauncherState extends State<_InitialWebRouteLauncher> {
  String? _launchedRoute;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = widget.route;
    if (!kIsWeb || route == null || route == _launchedRoute) return;
    _launchedRoute = route;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Get.toNamed(route);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
