import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/home/models/home_models.dart';
import 'package:tra_list/theme/app_theme.dart';

class HomeBottomBar extends StatelessWidget {
  const HomeBottomBar({
    super.key,
    required this.canOpenReports,
    required this.canOpenChat,
    required this.canSell,
    required this.lightStyle,
    required this.activeDestination,
    required this.onSelectDestination,
    required this.onOpenMarket,
    required this.onOpenChat,
    required this.onOpenReports,
    required this.onShowQuickActions,
    required this.onScanSell,
  });

  final bool canOpenReports;
  final bool canOpenChat;
  final bool canSell;
  final bool lightStyle;
  final HomeDestination activeDestination;
  final ValueChanged<HomeDestination> onSelectDestination;
  final VoidCallback onOpenMarket;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenReports;
  final VoidCallback onShowQuickActions;
  final VoidCallback onScanSell;

  Widget _mobileNavigationItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    final color = lightStyle
        ? (selected ? const Color(0xFF0D6FEB) : const Color(0xFF52657D))
        : (selected
              ? const Color(0xFF8DBBFF)
              : Colors.white.withValues(alpha: .68));
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 62,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: selected && lightStyle
                    ? const Color(0xFFEAF2FF)
                    : selected
                    ? Colors.white.withValues(alpha: .09)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(lightStyle ? 24 : 14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: lightStyle
                          ? const Color(0xFF17263D)
                          : selected
                          ? Colors.white
                          : color,
                      fontSize: 9.5,
                      height: 1.1,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickNavigationAction() {
    return Semantics(
      button: true,
      label: canSell ? 'nav_scan'.tr : 'home_more'.tr,
      child: InkWell(
        onTap: canSell ? onScanSell : onShowQuickActions,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 70,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: lightStyle ? 46 : 38,
                height: lightStyle ? 46 : 34,
                decoration: BoxDecoration(
                  color: lightStyle
                      ? const Color(0xFF0D6FEB)
                      : MjasiColors.secondaryBlue,
                  borderRadius: BorderRadius.circular(lightStyle ? 23 : 12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x333B82F6),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  canSell ? Icons.qr_code_scanner_rounded : Icons.more_horiz,
                  color: Colors.white,
                  size: 25,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                canSell ? 'nav_scan'.tr : 'home_more'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: lightStyle
                      ? const Color(0xFF17263D)
                      : Colors.white.withValues(alpha: .9),
                  fontSize: 9,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final background = lightStyle ? Colors.white : MjasiColors.primaryNavy;

    return Container(
      margin: lightStyle
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: lightStyle
            ? BorderRadius.zero
            : BorderRadius.circular(MjasiRadius.md),
        border: lightStyle
            ? const Border(top: BorderSide(color: Color(0xFFE6ECF5)))
            : Border.all(color: Colors.white.withValues(alpha: .08)),
        boxShadow: lightStyle
            ? const []
            : const [
                BoxShadow(
                  color: Color(0x26071B3A),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: lightStyle
            ? BorderRadius.zero
            : BorderRadius.circular(MjasiRadius.md),
        child: BottomAppBar(
          color: background,
          elevation: 0,
          padding: EdgeInsets.symmetric(horizontal: lightStyle ? 4 : 10),
          child: SizedBox(
            height: lightStyle ? 76 : 72,
            child: Row(
              children: [
                Expanded(
                  child: _mobileNavigationItem(
                    icon: Icons.home_rounded,
                    label: 'nav_home'.tr,
                    onTap: () => onSelectDestination(HomeDestination.dashboard),
                    selected: activeDestination == HomeDestination.dashboard,
                  ),
                ),
                Expanded(
                  child: _mobileNavigationItem(
                    icon: Icons.explore_outlined,
                    label: 'nav_explore'.tr,
                    onTap: onOpenMarket,
                    selected: activeDestination == HomeDestination.explore,
                  ),
                ),
                SizedBox(
                  width: lightStyle ? 60 : 64,
                  child: _quickNavigationAction(),
                ),
                if (canOpenChat)
                  Expanded(
                    child: _mobileNavigationItem(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: 'chat_nav_label'.tr,
                      onTap: onOpenChat,
                      selected: activeDestination == HomeDestination.chat,
                    ),
                  ),
                if (canOpenReports && !canSell)
                  Expanded(
                    child: _mobileNavigationItem(
                      icon: Icons.insert_chart_outlined,
                      label: 'nav_reports'.tr,
                      onTap: onOpenReports,
                      selected: activeDestination == HomeDestination.reports,
                    ),
                  ),
                if (canSell)
                  Expanded(
                    child: _mobileNavigationItem(
                      icon: Icons.more_horiz_rounded,
                      label: 'home_more'.tr,
                      onTap: onShowQuickActions,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
