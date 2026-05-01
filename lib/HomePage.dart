import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/jobs/controllers/job_controller.dart';
import 'package:tra_list/invoice/transactions_page.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/services/pages/ProfilePage.dart';
import 'package:tra_list/services/profile_service.dart';
import 'LoginPage.dart';
import 'invoice/InvoicePage.dart';
import 'services/subscription_controller.dart';
import 'subscription_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const Color _brandDeep = Color(0xFF0E3A4C);
  static const Color _brandPrimary = Color(0xFF176B87);
  static const Color _brandAccent = Color(0xFF64CCC5);

  final SubscriptionController subscriptionController = Get.put(
    SubscriptionController(),
  );
  String subscriptionBadge = '';
  bool isSubscribed = false;
  bool isTrial = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadSubscriptionStatus();
  }

  Future<void> _loadSubscriptionStatus() async {
    final badge = await subscriptionController.getUserSubscriptionBadge();
    final subscribed = await subscriptionController.isSubscribed();
    final trial = await subscriptionController.isUserInTrial();
    setState(() {
      subscriptionBadge = badge;
      isSubscribed = subscribed;
      isTrial = trial;
    });
  }

  final jobController = Get.put(JobController());
  String userRole = 'user';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    try {
      final profile = await ProfileService.loadOrCreate();
      setState(() {
        userRole = profile['role']?.toString() ?? 'user';
        loading = false;
      });
    } catch (e) {
      setState(() {
        userRole = 'user';
        loading = false;
      });
    }
  }

  bool get _hasAccess =>
      isSubscribed ||
      isTrial ||
      userRole == 'superadmin' ||
      userRole == 'admin';

  void _handleRestrictedTap(VoidCallback action) {
    if (_hasAccess) {
      action();
    } else {
      _showSubscriptionRequiredDialog();
    }
  }

  void _showSubscriptionRequiredDialog() {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.lock_outline, color: _brandPrimary),
            SizedBox(width: 8),
            Text('Unahitaji Kujiunga'),
          ],
        ),
        content: const Text(
          'Huduma Hii inapatikana kwa watumiaji waliyojisajili. Jiandikishe sasa au anza jaribio la bure ili kuendelea.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Maybe Later'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Get.back();
              Get.toNamed(
                AppRoutes.subscription,
              )?.then((_) => _loadSubscriptionStatus());
            },
            icon: const Icon(Icons.verified_user),
            label: const Text('JIUNGE SASA'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
      barrierDismissible: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _brandDeep,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            Text(
              'home_title'.tr,
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 12),
            if (subscriptionBadge.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isSubscribed
                      ? const Color(0xFF1C7C54)
                      : isTrial
                      ? const Color(0xFFD68B1A)
                      : const Color(0xFF5F7280),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  subscriptionBadge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
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
            colors: [_brandDeep, _brandPrimary, _brandAccent],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -120,
              left: -80,
              child: _buildGlowCircle(const Color(0x33FFFFFF), 260),
            ),
            Positioned(
              bottom: -80,
              right: -50,
              child: _buildGlowCircle(const Color(0x22FFFFFF), 220),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildJobsSummaryCard(context, jobController),
                    const SizedBox(height: 20),
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
                            childAspectRatio = 1.55;
                          } else if (width > 500) {
                            crossAxisCount = 2;
                            childAspectRatio = 1.75;
                          } else {
                            crossAxisCount = 1;
                            childAspectRatio = 2.35;
                          }

                          final List<Widget> menuCards = [];
                          if (userRole == 'superadmin') {
                            menuCards.addAll([
                              _buildMenuCard(
                                context,
                                icon: Icons.add_business,
                                title: 'home_create_receipt'.tr,
                                subtitle: 'home_create_receipt_sub'.tr,
                                color: const Color(0xFF1C7C54),
                                onTap: () {
                                  _handleRestrictedTap(() {
                                    Get.toNamed(AppRoutes.addReceipt);
                                  });
                                },
                              ),
                              _buildMenuCard(
                                context,
                                icon: Icons.list_alt,
                                title: 'home_view_receipts'.tr,
                                subtitle: 'home_view_receipts_sub'.tr,
                                color: const Color(0xFF1C6EA4),
                                onTap: () {
                                  _handleRestrictedTap(() {
                                    Get.toNamed(AppRoutes.receiptsList);
                                  });
                                },
                              ),
                            ]);
                          }

                          menuCards.add(
                            _buildMenuCard(
                              context,
                              icon: Icons.verified_user,
                              title: isSubscribed
                                  ? 'Subscription Active'
                                  : isTrial
                                  ? 'Trial Active'
                                  : 'Subscribe for 1 Year',
                              subtitle: isSubscribed
                                  ? 'Thank you for subscribing!'
                                  : isTrial
                                  ? 'Trial period in progress'
                                  : 'Activate your annual subscription or start a free trial',
                              color: isSubscribed
                                  ? const Color(0xFF1C7C54)
                                  : isTrial
                                  ? const Color(0xFFD68B1A)
                                  : _brandPrimary,
                              onTap: () {
                                Get.toNamed(
                                  AppRoutes.subscription,
                                )?.then((_) => _loadSubscriptionStatus());
                              },
                            ),
                          );

                          menuCards.addAll([
                            _buildMenuCard(
                              context,
                              icon: Icons.receipt_long,
                              title: 'home_view_invoices'.tr,
                              subtitle: 'home_view_invoices_sub'.tr,
                              color: const Color(0xFF2F5FA3),
                              onTap: () => _handleRestrictedTap(
                                () => Get.toNamed(AppRoutes.invoicesList),
                              ),
                            ),
                            _buildMenuCard(
                              context,
                              icon: Icons.receipt,
                              title: 'home_generate_invoice'.tr,
                              subtitle: 'home_generate_invoice_sub'.tr,
                              color: const Color(0xFF4C8AA7),
                              onTap: () {
                                _handleRestrictedTap(() {
                                  Get.toNamed(AppRoutes.invoice);
                                });
                              },
                            ),
                            _buildMenuCard(
                              context,
                              icon: Icons.track_changes,
                              title: 'home_finance_tracker'.tr,
                              subtitle: 'home_finance_tracker_sub'.tr,
                              color: const Color(0xFFDB8B28),
                              onTap: () => _handleRestrictedTap(
                                () => Get.toNamed(AppRoutes.transactions),
                              ),
                            ),
                            _buildMenuCard(
                              context,
                              icon: Icons.work_history_outlined,
                              title: 'home_manage_jobs'.tr,
                              subtitle: 'home_manage_jobs_sub'.tr,
                              color: const Color(0xFF455F71),
                              onTap: () {
                                _handleRestrictedTap(() {
                                  Get.toNamed(AppRoutes.jobs);
                                });
                              },
                            ),
                            _buildMenuCard(
                              context,
                              icon: Icons.analytics_outlined,
                              title: 'home_analytics'.tr,
                              subtitle: 'home_analytics_sub'.tr,
                              color: const Color(0xFF1A7A7C),
                              onTap: () {
                                _handleRestrictedTap(() {
                                  Get.toNamed(AppRoutes.analytics);
                                });
                              },
                            ),
                            _buildMenuCard(
                              context,
                              icon: Icons.category_outlined,
                              title: 'home_manage_categories'.tr,
                              subtitle: 'home_manage_categories_sub'.tr,
                              color: const Color(0xFF2E6A8D),
                              onTap: () => _handleRestrictedTap(
                                () => Get.toNamed(AppRoutes.categories),
                              ),
                            ),
                            _buildMenuCard(
                              context,
                              icon: Icons.info_outline,
                              title: 'home_about'.tr,
                              subtitle: 'home_about_sub'.tr,
                              color: const Color(0xFF366488),
                              onTap: () {
                                _showAboutDialog(context);
                              },
                            ),
                          ]);

                          return GridView.count(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: childAspectRatio,
                            children: menuCards,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.2),
      color: Colors.white.withOpacity(0.96),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [color.withOpacity(0.16), color.withOpacity(0.06)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 32, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.blueGrey.shade700,
                  height: 1.3,
                ),
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
      elevation: 10,
      shadowColor: Colors.black.withOpacity(0.25),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: () => _handleRestrictedTap(() => Get.toNamed(AppRoutes.jobs)),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [_brandDeep, _brandPrimary],
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

  Widget _buildGlowCircle(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
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
              const Text('About Mjasi POS'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mjasi POS',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Mjasi POS is a powerful point of sale system designed to help businesses manage their sales, inventory, and customer data efficiently. With an intuitive interface and robust features, Mjasi POS is the perfect solution for businesses of all sizes.',
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
