import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:tra_list/services/app_urls_service.dart';
import 'package:tra_list/theme/app_theme.dart';

class AppUrlsPage extends StatefulWidget {
  const AppUrlsPage({super.key});

  @override
  State<AppUrlsPage> createState() => _AppUrlsPageState();
}

class _AppUrlsPageState extends State<AppUrlsPage> {
  late final Future<AppUrls> _urls = AppUrlsService.load();

  bool get _isSw => Get.locale?.languageCode == 'sw';

  String _t(String en, String sw) => _isSw ? sw : en;

  Future<void> _copy(BuildContext context, String label, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(_t('$label copied', '$label imenakiliwa')),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MjasiColors.background,
      appBar: AppBar(title: Text(_t('App links', 'Viungo vya app'))),
      body: FutureBuilder<AppUrls>(
        future: _urls,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                _t(
                  'Could not load app links.',
                  'Imeshindwa kupakia viungo vya app.',
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final urls = snapshot.data!;
          final links = [
            (
              title: _t('Website', 'Tovuti'),
              subtitle: _t(
                'Visit the Mjasi POS website',
                'Tembelea tovuti ya Mjasi POS',
              ),
              url: urls.website,
              icon: Icons.language_rounded,
            ),
            (
              title: _t('Privacy Policy', 'Sera ya Faragha'),
              subtitle: _t(
                'How your information is handled',
                'Jinsi taarifa zako zinavyotumika',
              ),
              url: urls.privacyPolicy,
              icon: Icons.privacy_tip_outlined,
            ),
            (
              title: _t('Terms & Conditions', 'Vigezo na Masharti'),
              subtitle: _t(
                'Terms for using the app',
                'Masharti ya matumizi ya app',
              ),
              url: urls.termsOfService,
              icon: Icons.gavel_rounded,
            ),
          ];
          return ListView(
            padding: const EdgeInsets.all(MjasiSpacing.lg),
            children: [
              Text(
                _t(
                  'Copy an app link to share it.',
                  'Nakili kiungo cha app ili kukishiriki.',
                ),
                style: const TextStyle(
                  color: MjasiColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: MjasiSpacing.lg),
              for (final link in links) ...[
                _AppUrlCard(
                  title: link.title,
                  subtitle: link.subtitle,
                  url: link.url,
                  icon: link.icon,
                  copyLabel: _t('Copy link', 'Nakili kiungo'),
                  onCopy: () => _copy(context, link.title, link.url),
                ),
                const SizedBox(height: MjasiSpacing.md),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AppUrlCard extends StatelessWidget {
  const _AppUrlCard({
    required this.title,
    required this.subtitle,
    required this.url,
    required this.icon,
    required this.copyLabel,
    required this.onCopy,
  });

  final String title;
  final String subtitle;
  final String url;
  final IconData icon;
  final String copyLabel;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MjasiSpacing.lg),
      decoration: BoxDecoration(
        color: MjasiColors.surface,
        borderRadius: BorderRadius.circular(MjasiRadius.md),
        border: Border.all(color: MjasiColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: MjasiColors.lightBlue,
              borderRadius: BorderRadius.circular(MjasiRadius.sm),
            ),
            child: Icon(icon, color: MjasiColors.primaryBlue),
          ),
          const SizedBox(width: MjasiSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: MjasiColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: MjasiSpacing.xs),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: MjasiColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: MjasiSpacing.sm),
                SelectableText(
                  url,
                  style: const TextStyle(
                    color: MjasiColors.primaryBlue,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCopy,
            tooltip: copyLabel,
            icon: const Icon(Icons.copy_rounded),
            color: MjasiColors.primaryBlue,
          ),
        ],
      ),
    );
  }
}
