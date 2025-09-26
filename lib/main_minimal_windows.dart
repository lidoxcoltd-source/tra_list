import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Minimal Windows app for testing
/// No Firebase, no external dependencies, just basic functionality
void main() {
  runApp(const MinimalWindowsApp());
}

class MinimalWindowsApp extends StatelessWidget {
  const MinimalWindowsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'TRA Receipt System - Minimal Windows Test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFE500),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const MinimalHomePage(),
    );
  }
}

class MinimalHomePage extends StatelessWidget {
  const MinimalHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TRA Receipt System - Windows Test'),
        backgroundColor: const Color(0xFFFFE500),
        elevation: 0,
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 100, color: Color(0xFFFFE500)),
            SizedBox(height: 20),
            Text(
              'Windows App Test',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              'TRA Receipt System is running on Windows!',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 30),
            TestButtons(),
          ],
        ),
      ),
    );
  }
}

class TestButtons extends StatelessWidget {
  const TestButtons({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: () {
            Get.snackbar(
              'Test',
              'GetX is working on Windows!',
              backgroundColor: const Color(0xFFFFE500),
              colorText: Colors.black,
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFE500),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
          child: const Text('Test GetX Snackbar'),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Windows Test'),
                content: const Text(
                  'This dialog confirms that the Windows app is working correctly!',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
          child: const Text('Test Dialog'),
        ),
      ],
    );
  }
}
