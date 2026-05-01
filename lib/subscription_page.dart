import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/subscription_controller.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({Key? key}) : super(key: key);

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  final SubscriptionController _controller = Get.put(SubscriptionController());
  final TextEditingController _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Optionally prefill phone from user profile or Firestore
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Your Plan'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0E3A4C), Color(0xFF176B87), Color(0xFF64CCC5)],
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
              bottom: -90,
              right: -60,
              child: _buildGlowCircle(const Color(0x22FFFFFF), 220),
            ),
            SafeArea(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final contentWidth = constraints.maxWidth > 700
                        ? 620.0
                        : constraints.maxWidth;

                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      child: SizedBox(
                        width: contentWidth,
                        child: Card(
                          elevation: 14,
                          shadowColor: Colors.black.withOpacity(0.25),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFF176B87),
                                        Color(0xFF64CCC5),
                                      ],
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.workspace_premium_outlined,
                                    color: Colors.white,
                                    size: 34,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  'Upgrade to Premium',
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF10384A),
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Get full access to receipts, invoices, analytics, and advanced business tools in one plan.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: const Color(0xFF4E6471),
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3FAFC),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFFB5E3E6),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Tsh 20,000',
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                              color: const Color(0xFF0E3A4C),
                                            ),
                                      ),
                                      const SizedBox(width: 6),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        child: Text(
                                          '/ year',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: const Color(0xFF4E6471),
                                              ),
                                        ),
                                      ),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFD8F4E8),
                                          borderRadius: BorderRadius.circular(
                                            40,
                                          ),
                                        ),
                                        child: const Text(
                                          '7-day trial',
                                          style: TextStyle(
                                            color: Color(0xFF1C7C54),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: const [
                                    _FeatureTag(label: 'Unlimited Receipts'),
                                    _FeatureTag(label: 'Smart Invoicing'),
                                    _FeatureTag(label: 'Sales Analytics'),
                                    _FeatureTag(label: 'Cloud Backup'),
                                  ],
                                ),
                                const SizedBox(height: 22),
                                TextField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  decoration: InputDecoration(
                                    labelText: 'Phone Number',
                                    hintText: 'e.g. 07XXXXXXXX',
                                    prefixIcon: const Icon(
                                      Icons.phone_iphone_outlined,
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFF8FBFC),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF176B87),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Obx(
                                  () => Column(
                                    children: [
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFF176B87,
                                            ),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 16,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                          ),
                                          onPressed: _controller.loading.value
                                              ? null
                                              : () async {
                                                  final phone = _phoneController
                                                      .text
                                                      .trim();
                                                  if (phone.isEmpty) {
                                                    Get.snackbar(
                                                      'Missing Phone Number',
                                                      'Enter your phone number to continue with subscription.',
                                                      snackPosition:
                                                          SnackPosition.BOTTOM,
                                                      backgroundColor:
                                                          Colors.orange,
                                                      colorText: Colors.white,
                                                    );
                                                    return;
                                                  }
                                                  try {
                                                    await _controller
                                                        .subscribeUser(
                                                          phone: phone,
                                                        );
                                                    Get.snackbar(
                                                      'Success',
                                                      'Subscription activated successfully!',
                                                      snackPosition:
                                                          SnackPosition.BOTTOM,
                                                      backgroundColor:
                                                          Colors.green,
                                                      colorText: Colors.white,
                                                    );
                                                  } catch (e) {
                                                    Get.snackbar(
                                                      'Subscription Failed',
                                                      e.toString(),
                                                      snackPosition:
                                                          SnackPosition.BOTTOM,
                                                      backgroundColor:
                                                          Colors.red,
                                                      colorText: Colors.white,
                                                    );
                                                  }
                                                },
                                          icon: _controller.loading.value
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2.3,
                                                        color: Colors.white,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.lock_open_rounded,
                                                ),
                                          label: Text(
                                            _controller.loading.value
                                                ? 'Processing...'
                                                : 'Subscribe Now',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(
                                              color: Color(0xFF176B87),
                                              width: 1.4,
                                            ),
                                            foregroundColor: const Color(
                                              0xFF176B87,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 14,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                          ),
                                          onPressed: _controller.loading.value
                                              ? null
                                              : () async {
                                                  final user = FirebaseAuth
                                                      .instance
                                                      .currentUser;
                                                  if (user == null) {
                                                    Get.snackbar(
                                                      'Authentication Required',
                                                      'Please log in to start your free trial.',
                                                      snackPosition:
                                                          SnackPosition.BOTTOM,
                                                      backgroundColor:
                                                          Colors.orange,
                                                      colorText: Colors.white,
                                                    );
                                                    return;
                                                  }
                                                  await _controller
                                                      .startTrialIfNeeded(
                                                        user.uid,
                                                      );
                                                  Get.snackbar(
                                                    'Trial Started',
                                                    'Your 7-day free trial is now active.',
                                                    snackPosition:
                                                        SnackPosition.BOTTOM,
                                                    backgroundColor:
                                                        Colors.blue,
                                                    colorText: Colors.white,
                                                  );
                                                },
                                          icon: const Icon(
                                            Icons.auto_awesome_outlined,
                                          ),
                                          label: const Text(
                                            'Start 7-Day Free Trial',
                                            style: TextStyle(
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.verified_user_outlined,
                                      size: 16,
                                      color: Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Secure checkout. Cancel anytime.',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: Colors.grey.shade700,
                                            fontWeight: FontWeight.w500,
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
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlowCircle(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _FeatureTag extends StatelessWidget {
  final String label;

  const _FeatureTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7FA),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFB5E3E6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 16,
            color: Color(0xFF176B87),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF16566D),
            ),
          ),
        ],
      ),
    );
  }
}
