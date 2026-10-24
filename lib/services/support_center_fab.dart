import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/theme/app_theme.dart';

class SupportCenterFabOverlay extends StatefulWidget {
  const SupportCenterFabOverlay({required this.child, super.key});

  final Widget child;

  @override
  State<SupportCenterFabOverlay> createState() =>
      _SupportCenterFabOverlayState();
}

class _SupportCenterFabOverlayState extends State<SupportCenterFabOverlay> {
  static const _expandedDuration = Duration(seconds: 4);
  Timer? _collapseTimer;
  String? _activeRoute;
  bool _isExpanded = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateRouteState();
  }

  @override
  void didUpdateWidget(covariant SupportCenterFabOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateRouteState();
  }

  void _updateRouteState() {
    final route = Get.currentRoute;
    if (_activeRoute == route) return;
    _activeRoute = route;
    _collapseTimer?.cancel();
    _isExpanded = true;
    if (_shouldShowFab) {
      _collapseTimer = Timer(_expandedDuration, () {
        if (mounted) setState(() => _isExpanded = false);
      });
    }
  }

  void _expandFab() {
    setState(() => _isExpanded = true);
    _collapseTimer?.cancel();
    _collapseTimer = Timer(_expandedDuration, () {
      if (mounted) setState(() => _isExpanded = false);
    });
  }

  void _onFabPressed() {
    if (!_isExpanded) {
      _expandFab();
      return;
    }
    _collapseTimer?.cancel();
    Get.toNamed(AppRoutes.support);
  }

  bool get _shouldShowFab => FirebaseAuth.instance.currentUser != null;

  @override
  void dispose() {
    _collapseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = Get.currentRoute;
    if (!_shouldShowFab) return widget.child;

    final isHome = route == AppRoutes.home;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final bottom = isHome ? safeBottom + 96.0 : safeBottom + 20.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned(
          right: 16,
          bottom: bottom,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Semantics(
              button: true,
              label: 'support_fab'.tr,
              child: _isExpanded
                  ? FloatingActionButton.extended(
                      key: const ValueKey('support_expanded'),
                      heroTag: null,
                      onPressed: _onFabPressed,
                      backgroundColor: MjasiColors.primaryBlue,
                      foregroundColor: Colors.white,
                      icon: const Icon(Icons.support_agent_rounded),
                      label: Text('support_fab'.tr),
                    )
                  : FloatingActionButton.small(
                      key: const ValueKey('support_collapsed'),
                      heroTag: null,
                      onPressed: _onFabPressed,
                      backgroundColor: MjasiColors.primaryBlue,
                      foregroundColor: Colors.white,
                      child: const Icon(Icons.arrow_forward_rounded),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
