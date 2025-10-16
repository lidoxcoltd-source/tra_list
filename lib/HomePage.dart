import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/jobs/controllers/job_controller.dart';
import 'package:tra_list/invoice/transactions_page.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/services/pages/ProfilePage.dart';
import 'LoginPage.dart';
import 'invoice/InvoicePage.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // Ensure JobController is available for the summary widget.
    // Get.put is safe to call multiple times; it won't create a new instance.
    final jobController = Get.put(JobController());
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'home_title'.tr,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: const Color(0xFF1976D2),
        elevation: 4,
        actions: [
          IconButton(
            tooltip: 'home_profile'.tr,
            icon: const Icon(Icons.person_outline),
            onPressed: () => Get.to(() => const ProfilePage()),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                final loginController = Get.find<LoginController>();
                loginController.signOut();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'logout',
                child: TextButton(
                  onPressed: () {
                    final loginController = Get.find<LoginController>();
                    loginController.signOut();
                  },
                  child: const Row(
                    children: [
                      Icon(Icons.logout, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Sign Out'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
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
              _buildJobsSummaryCard(context, jobController),
              const SizedBox(height: 20),

              // Menu Options
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    int crossAxisCount;
                    double childAspectRatio;

                    if (width > 1200) {
                      crossAxisCount = 4;
                      childAspectRatio = 1.8;
                    } else if (width > 800) {
                      crossAxisCount = 3;
                      childAspectRatio = 1.6;
                    } else if (width > 500) {
                      crossAxisCount = 2;
                      childAspectRatio = 1.8;
                    } else {
                      crossAxisCount = 1;
                      childAspectRatio = 2.5;
                    }

                    return GridView.count(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: childAspectRatio,
                      children: [
                        // Create New Receipt
                        _buildMenuCard(
                          context,
                          icon: Icons.add_business,
                          title: 'home_create_receipt'.tr,
                          subtitle: 'home_create_receipt_sub'.tr,
                          color: const Color(0xFF4CAF50),
                          onTap: () {
                            Get.toNamed(AppRoutes.addReceipt);
                          },
                        ),

                        // View All Receipts
                        _buildMenuCard(
                          context,
                          icon: Icons.list_alt,
                          title: 'home_view_receipts'.tr,
                          subtitle: 'home_view_receipts_sub'.tr,
                          color: const Color(0xFF2196F3),
                          onTap: () {
                            Get.toNamed(AppRoutes.receiptsList);
                          },
                        ),

                        // View Invoices
                        _buildMenuCard(
                          context,
                          icon: Icons.receipt_long,
                          title: 'home_view_invoices'.tr,
                          subtitle: 'home_view_invoices_sub'.tr,
                          color: const Color(0xFF3F51B5),
                          onTap: () => Get.toNamed(AppRoutes.invoicesList),
                        ),

                        // Generate Invoice
                        _buildMenuCard(
                          context,
                          icon: Icons.receipt,
                          title: 'home_generate_invoice'.tr,
                          subtitle: 'home_generate_invoice_sub'.tr,
                          color: const Color(0xFF8D6E63),
                          onTap: () {
                            Get.toNamed(AppRoutes.invoice); // use named route
                          },
                        ),

                        // Expense & Income Tracker
                        _buildMenuCard(
                          context,
                          icon: Icons.track_changes,
                          title: 'home_finance_tracker'.tr,
                          subtitle: 'home_finance_tracker_sub'.tr,
                          color: const Color(0xFFFFA000),
                          onTap: () => Get.toNamed(AppRoutes.transactions),
                        ),

                        // Manage Jobs
                        _buildMenuCard(
                          context,
                          icon: Icons.work_history_outlined,
                          title: 'home_manage_jobs'.tr,
                          subtitle: 'home_manage_jobs_sub'.tr,
                          color: const Color(0xFF795548),
                          onTap: () {
                            Get.toNamed(AppRoutes.jobs);
                          },
                        ),
                        // Analytics & Insights
                        _buildMenuCard(
                          context,
                          icon: Icons.analytics_outlined,
                          title: 'home_analytics'.tr,
                          subtitle: 'home_analytics_sub'.tr,
                          color: const Color(0xFF00897B), // Teal color
                          onTap: () {
                            Get.toNamed(AppRoutes.analytics);
                          },
                        ),

                        // Manage Categories
                        _buildMenuCard(
                          context,
                          icon: Icons.category_outlined,
                          title: 'home_manage_categories'.tr,
                          subtitle: 'home_manage_categories_sub'.tr,
                          color: const Color(0xFF673AB7),
                          onTap: () => Get.toNamed(AppRoutes.categories),
                        ),

                        // Settings/Info
                        _buildMenuCard(
                          context,
                          icon: Icons.info_outline,
                          title: 'home_about'.tr,
                          subtitle: 'home_about_sub'.tr,
                          color: const Color(0xFF9C27B0),
                          onTap: () {
                            _showAboutDialog(context);
                          },
                        ),
                      ],
                    );
                  },
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

  Widget _buildJobsSummaryCard(BuildContext context, JobController controller) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => Get.toNamed(AppRoutes.jobs),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [
                const Color(0xFF795548).withOpacity(0.8),
                const Color(0xFF5D4037).withOpacity(0.9),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Obx(
            () => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.work_history_outlined,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'home_jobs_overview'.tr,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white,
                      size: 16,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildSummaryStat(
                          'home_active_jobs'.tr,
                          controller.active.length.toString(),
                        ),
                        _buildSummaryStat(
                          'home_completed_jobs'.tr,
                          controller.completed.length.toString(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildSummaryStat(
                          'home_overdue_jobs'.tr,
                          '0',
                          highlight: false,
                        ),
                        _buildSummaryStat(
                          'home_important_jobs'.tr,
                          controller.important.length.toString(),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryStat(
    String label,
    String value, {
    bool highlight = false,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: highlight ? Colors.amber.shade300 : Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8)),
        ),
      ],
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
