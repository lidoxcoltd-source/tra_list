import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'routes.dart';
import 'HomePage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase for Windows (optional - can be disabled for offline use)
  try {
    await Firebase.initializeApp();
    print('Firebase initialized for Windows');
  } catch (e) {
    print('Firebase initialization failed: $e');
    print('Running in offline mode...');
  }

  runApp(const WindowsTraApp());
}

class WindowsTraApp extends StatelessWidget {
  const WindowsTraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'TRA Receipt System - Windows',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFE500),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        // Windows-optimized theme
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'Segoe UI', // Windows default font
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFE500),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'Segoe UI',
      ),
      themeMode: ThemeMode.system, // Follow Windows theme
      home: const HomePage(),
      getPages: AppRoutes.routes,
      defaultTransition: Transition.fadeIn, // Smooth transitions for desktop
      transitionDuration: const Duration(milliseconds: 200),
    );
  }
}
