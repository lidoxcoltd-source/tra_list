import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/theme/app_theme.dart';

void showMjasiAboutDialog(BuildContext context) {
  final sw = Get.locale?.languageCode == 'sw';
  String t(String en, String swText) => sw ? swText : en;

  Widget link(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MjasiRadius.md),
      ),
      leading: Icon(icon, color: MjasiColors.primaryBlue, size: 22),
      title: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: MjasiColors.textPrimary,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: MjasiColors.textSecondary),
      onTap: onTap,
    );
  }

  void open(String route) {
    Get.back();
    Get.toNamed(route);
  }

  Get.dialog(
    Dialog(
      backgroundColor: MjasiColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [MjasiColors.primaryNavy, MjasiColors.primaryBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.storefront_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'MJASI POS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t(
                        'Manage income, expenses, invoices, receipts and jobs',
                        'Simamia mapato, matumizi, ankara, risiti na kazi',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                child: Column(
                  children: [
                    link(
                      Icons.privacy_tip_outlined,
                      t('Privacy Policy', 'Sera ya Faragha'),
                      () => open(AppRoutes.privacy),
                    ),
                    link(
                      Icons.gavel_outlined,
                      t('Terms & Conditions', 'Masharti na Vigezo'),
                      () => open(AppRoutes.terms),
                    ),
                    link(
                      Icons.link_rounded,
                      t('All app links', 'Viungo vyote vya app'),
                      () => open(AppRoutes.appUrls),
                    ),
                    link(
                      Icons.support_agent_outlined,
                      t('Help & Support', 'Msaada'),
                      () => open(AppRoutes.support),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  height: 46,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: MjasiColors.primaryBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(MjasiRadius.md),
                      ),
                    ),
                    onPressed: Get.back,
                    child: Text('close'.tr),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
