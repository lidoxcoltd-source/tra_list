import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../routes.dart';

class _AdminItem {
  const _AdminItem(
    this.titleKey,
    this.descKey,
    this.icon,
    this.route,
    this.color,
  );

  final String titleKey;
  final String descKey;
  final IconData icon;
  final String route;
  final Color color;
}

class _AdminGroup {
  const _AdminGroup(this.titleKey, this.items);

  final String titleKey;
  final List<_AdminItem> items;
}

const _groups = <_AdminGroup>[
  _AdminGroup('hub_group_insights', [
    _AdminItem(
      'admin_manage_analytics',
      'hub_desc_analytics',
      Icons.insights_rounded,
      AppRoutes.adminAnalytics,
      Color(0xFF1565C0),
    ),
    _AdminItem(
      'analytics_advice_admin_title',
      'analytics_advice_admin_hub_desc',
      Icons.tips_and_updates_rounded,
      AppRoutes.adminAnalyticsAdvice,
      Color(0xFF7C3AED),
    ),
    _AdminItem(
      'admin_manage_subscriptions',
      'hub_desc_subscriptions',
      Icons.manage_accounts_rounded,
      AppRoutes.adminSubscriptions,
      Color(0xFF0F766E),
    ),
  ]),
  _AdminGroup('hub_group_distribution', [
    _AdminItem(
      'admin_manage_app_versions',
      'hub_desc_versions',
      Icons.system_update_alt_rounded,
      AppRoutes.adminAppVersions,
      Color(0xFFEA580C),
    ),
    _AdminItem(
      'admin_manage_downloads',
      'hub_desc_downloads',
      Icons.cloud_download_rounded,
      AppRoutes.adminDownloads,
      Color(0xFF0891B2),
    ),
    _AdminItem(
      'hub_view_downloads',
      'hub_desc_view_downloads',
      Icons.open_in_new_rounded,
      AppRoutes.downloads,
      Color(0xFF2563EB),
    ),
  ]),
  _AdminGroup('hub_group_communication', [
    _AdminItem(
      'support_admin_title',
      'support_admin_hub_desc',
      Icons.support_agent_rounded,
      AppRoutes.adminSupport,
      Color(0xFF0F766E),
    ),
    _AdminItem(
      'admin_manage_announcements',
      'hub_desc_announcements',
      Icons.campaign_rounded,
      AppRoutes.adminAnnouncements,
      Color(0xFF7C3AED),
    ),
    _AdminItem(
      'notif_title',
      'hub_desc_notifications',
      Icons.notifications_active_rounded,
      AppRoutes.notifications,
      Color(0xFFDB2777),
    ),
  ]),
  _AdminGroup('hub_group_records', [
    _AdminItem(
      'home_view_receipts',
      'hub_desc_receipts',
      Icons.receipt_rounded,
      AppRoutes.receiptsList,
      Color(0xFF16A34A),
    ),
    _AdminItem(
      'home_create_receipt',
      'hub_desc_create_receipt',
      Icons.add_business_rounded,
      AppRoutes.addReceipt,
      Color(0xFF4F46E5),
    ),
  ]),
  _AdminGroup('hub_group_market', [
    _AdminItem(
      'admin_market_verification_title',
      'admin_market_verification_hub_desc',
      Icons.verified_user_rounded,
      AppRoutes.adminMarketVerification,
      Color(0xFF0F766E),
    ),
    _AdminItem(
      'market_sound_admin_title',
      'market_sound_admin_desc',
      Icons.library_music_rounded,
      AppRoutes.adminMarketSounds,
      Color(0xFF7C3AED),
    ),
    _AdminItem(
      'market_report_admin_title',
      'market_report_admin_desc',
      Icons.flag_rounded,
      AppRoutes.adminMarketReports,
      Color(0xFFDC2626),
    ),
  ]),
];

class SuperAdminHubPage extends StatelessWidget {
  const SuperAdminHubPage({super.key});

  Widget _card(_AdminItem item) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Get.toNamed(item.route),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E9F2)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: item.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.titleKey.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.descKey.tr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(title: Text('hub_title'.tr)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0B1F4B), Color(0xFF1565C0)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'hub_title'.tr,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'hub_subtitle'.tr,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              for (final group in _groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
                  child: Text(
                    group.titleKey.tr,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                LayoutBuilder(
                  builder: (context, c) {
                    final cols = c.maxWidth >= 640 ? 2 : 1;
                    const gap = 10.0;
                    final width = (c.maxWidth - gap * (cols - 1)) / cols;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final item in group.items)
                          SizedBox(width: width, child: _card(item)),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
