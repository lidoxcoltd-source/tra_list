import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'routes.dart';
import 'HomePage.dart';

/// Lightweight Windows app without Firebase
/// For faster builds and offline operation
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('Starting TRA Receipt System - Windows (Offline Mode)');

  runApp(const WindowsTraAppLight());
}

class WindowsTraAppLight extends StatelessWidget {
  const WindowsTraAppLight({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'TRA Receipt System - Windows (Offline)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFE500),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'Segoe UI',
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
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
      themeMode: ThemeMode.system,
      home: const HomePage(),
      getPages: AppRoutes.routes,
      defaultTransition: Transition.fadeIn,
      transitionDuration: const Duration(milliseconds: 150),
    );
  }
}
