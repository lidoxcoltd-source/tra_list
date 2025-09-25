import 'package:flutter/material.dart';
import 'package:get/get.dart';

class RouteTestPage extends StatelessWidget {
  const RouteTestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route Test'),
        backgroundColor: const Color(0xFFFFE500),
        foregroundColor: Colors.black87,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Route Testing',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current Route Information:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('Current Route: ${Get.currentRoute}'),
                    Text('Parameters: ${Get.parameters}'),
                    Text('Arguments: ${Get.arguments}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Test Receipt URLs:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Column(
              children: [
                _buildTestButton('Test Receipt ABC123', '/receipt/ABC123'),
                _buildTestButton('Test Receipt DEF456', '/receipt/DEF456'),
                _buildTestButton('Test Receipt GHI789', '/receipt/GHI789'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestButton(String label, String route) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () {
            print('Navigating to: $route');
            Get.toNamed(route);
          },
          child: Text(label),
        ),
      ),
    );
  }
}
