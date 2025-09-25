import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/routes.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TRA Receipt System',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1976D2),
        elevation: 4,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF5F5F5), Color(0xFFE8EAF6)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Section
              Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.receipt_long, size: 48, color: Colors.white),
                      const SizedBox(height: 12),
                      const Text(
                        'Tanzania Revenue Authority',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Receipt Management System',
                        style: TextStyle(fontSize: 16, color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // Menu Options
              Expanded(
                child: GridView.count(
                  crossAxisCount: MediaQuery.of(context).size.width > 600
                      ? 2
                      : 1,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 2,
                  children: [
                    // Create New Receipt
                    _buildMenuCard(
                      context,
                      icon: Icons.add_business,
                      title: 'Create New Receipt',
                      subtitle: 'Generate a new receipt with customer details',
                      color: const Color(0xFF4CAF50),
                      onTap: () {
                        Get.toNamed(AppRoutes.addReceipt);
                      },
                    ),

                    // View All Receipts
                    _buildMenuCard(
                      context,
                      icon: Icons.list_alt,
                      title: 'View All Receipts',
                      subtitle: 'Browse and manage existing receipts',
                      color: const Color(0xFF2196F3),
                      onTap: () {
                        Get.toNamed(AppRoutes.receiptsList);
                      },
                    ),

                    // Sample Receipt
                    _buildMenuCard(
                      context,
                      icon: Icons.preview,
                      title: 'Sample Receipt',
                      subtitle: 'View a sample receipt with demo data',
                      color: const Color(0xFFFF9800),
                      onTap: () {
                        Get.toNamed(AppRoutes.sampleReceipt);
                      },
                    ),

                    // Firebase Test
                    _buildMenuCard(
                      context,
                      icon: Icons.cloud_sync,
                      title: 'Firebase Connection Test',
                      subtitle: 'Test Firebase/Firestore connectivity',
                      color: const Color(0xFFF44336),
                      onTap: () {
                        Get.toNamed(AppRoutes.firebaseTest);
                      },
                    ),

                    // Route Test
                    _buildMenuCard(
                      context,
                      icon: Icons.route,
                      title: 'Route Test',
                      subtitle: 'Test GetX routing with receipt IDs',
                      color: const Color(0xFF607D8B),
                      onTap: () {
                        Get.toNamed(AppRoutes.routeTest);
                      },
                    ),

                    // Settings/Info
                    _buildMenuCard(
                      context,
                      icon: Icons.info_outline,
                      title: 'About',
                      subtitle: 'System information and help',
                      color: const Color(0xFF9C27B0),
                      onTap: () {
                        _showAboutDialog(context);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.info_outline, color: const Color(0xFF1976D2)),
              const SizedBox(width: 8),
              const Text('About TRA Receipt System'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TRA Receipt Management System',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'This application helps manage receipt generation and storage for Tanzania Revenue Authority compliance.',
              ),
              SizedBox(height: 16),
              Text('Features:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text('• Create and store receipts'),
              Text('• Generate PDF receipts'),
              Text('• Firebase cloud storage'),
              Text('• Mobile and web compatible'),
              SizedBox(height: 16),
              Text(
                'Version: 1.0.0',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}
