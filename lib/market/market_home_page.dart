import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';

import '../routes.dart';
import '../services/business_access_service.dart';
import '../services/account_mode_service.dart';
import '../services/push_service.dart';
import '../services/notifications_page.dart';
import '../services/notification_service.dart';
import 'market_avatar.dart';
import 'create_post_sheet.dart';
import 'explore_page.dart';
import 'market_profile_page.dart';
import 'market_palette.dart';
import 'market_reels_page.dart';
import 'market_upload_progress.dart';

enum _MarketDestination { home, market, search, profile }

class MarketHomePage extends StatefulWidget {
  const MarketHomePage({super.key});

  @override
  State<MarketHomePage> createState() => _MarketHomePageState();
}

class _MarketHomePageState extends State<MarketHomePage> {
  _MarketDestination _destination = _MarketDestination.home;
  int _feedKey = 0;
  late final Stream<List<AppNotification>> _activity;
  late final Stream<List<AppNotification>> _announcements;
  int? _lastCompletedUploadId;

  @override
  void initState() {
    super.initState();
    _activity = NotificationService.watchActivity().asBroadcastStream();
    _announcements = NotificationService.watchAnnouncements()
        .asBroadcastStream();
  }

  bool _appBarHidden = false;
  double? _lastScrollPixels;
  double _scrollDelta = 0;

  static const _headerScrollThreshold = 18.0;

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: MarketPalette.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: MarketPalette.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: MarketPalette.red.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    color: MarketPalette.red,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'home_sign_out'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MarketPalette.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'market_sign_out_confirm'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MarketPalette.textMuted,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: MarketPalette.text,
                          side: const BorderSide(color: MarketPalette.border),
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text('cancel'.tr),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: MarketPalette.red,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text('home_sign_out'.tr),
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
    if (confirmed != true) return;
    await PushService.unregister();
    await FirebaseAuth.instance.signOut();
    BusinessAccessService.clear();
    Get.offAllNamed(AppRoutes.login);
  }

  Future<void> _openComposer() async {
    await openMarketComposer(context);
  }

  Widget _uploadProgressBanner() {
    return ValueListenableBuilder<MarketUploadProgressState?>(
      valueListenable: MarketUploadProgress.state,
      builder: (context, progress, _) {
        if (progress == null) return const SizedBox.shrink();
        if (progress.status == MarketUploadStatus.completed &&
            _lastCompletedUploadId != progress.id) {
          _lastCompletedUploadId = progress.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _feedKey++);
          });
        }
        final active =
            progress.status == MarketUploadStatus.uploading ||
            progress.status == MarketUploadStatus.publishing;
        final failed = progress.status == MarketUploadStatus.failed;
        final message = switch (progress.status) {
          MarketUploadStatus.uploading =>
            '${'market_uploading'.tr} ${(progress.progress * 100).round()}%',
          MarketUploadStatus.publishing => 'market_saving_post'.tr,
          MarketUploadStatus.completed => 'market_published'.tr,
          MarketUploadStatus.failed =>
            '${'market_publish_failed'.tr} ${progress.error ?? ''}',
        };
        return Material(
          color: MarketPalette.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (active)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        failed
                            ? Icons.error_outline_rounded
                            : Icons.check_circle_outline_rounded,
                        color: failed ? MarketPalette.red : MarketPalette.mint,
                        size: 20,
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message,
                        maxLines: failed ? 3 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MarketPalette.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (!active)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'close'.tr,
                        onPressed: () =>
                            MarketUploadProgress.dismiss(progress.id),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                  ],
                ),
                if (active) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress.status == MarketUploadStatus.publishing
                        ? null
                        : progress.progress,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _select(_MarketDestination destination) {
    setState(() {
      _destination = destination;
      _appBarHidden = false;
      _lastScrollPixels = null;
      _scrollDelta = 0;
    });
  }

  Widget _buildContent() => switch (_destination) {
    _MarketDestination.home => MarketExplorePage(
      key: ValueKey('feed-$_feedKey'),
      initialTab: MarketExploreTab.posts,
      showFeedModeTabs: true,
      showControls: false,
    ),
    _MarketDestination.market => const MarketReelsTab(),
    _MarketDestination.search => const MarketExplorePage(
      initialTab: MarketExploreTab.posts,
      searchAutofocus: true,
    ),
    _MarketDestination.profile => MarketProfilePage(
      uid: _profileUid,
      embedded: true,
    ),
  };

  String get _profileUid {
    if (AccountModeService.current == AccountMode.business &&
        BusinessAccessService.hasBusinessAccess) {
      return BusinessAccessService.businessId;
    }
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final reels = _destination == _MarketDestination.market;
    final barHidden = _appBarHidden && !reels;
    return Theme(
      data: MarketPalette.darkTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: MarketPalette.canvas,
        extendBodyBehindAppBar: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: AnimatedSlide(
            offset: barHidden ? const Offset(0, -1) : Offset.zero,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeInOutCubic,
            child: AnimatedOpacity(
              opacity: barHidden ? 0 : 1,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeInOutCubic,
              child: AppBar(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                elevation: 0,
                scrolledUnderElevation: 0,
                surfaceTintColor: Colors.transparent,
                centerTitle: true,
                flexibleSpace: reels
                    ? const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xB3000000), Color(0x00000000)],
                          ),
                        ),
                      )
                    : null,
                title: Text(
                  reels ? 'Reels' : 'MJASI MARKET',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                leading: IconButton(
                  tooltip: 'market_create_post'.tr,
                  onPressed: _openComposer,
                  icon: const Icon(Icons.add_rounded),
                ),
                actions: [
                  const NotificationBell(),
                  PopupMenuButton<String>(
                    tooltip: '',
                    icon: const Icon(Icons.more_vert_rounded),
                    color: MarketPalette.surfaceRaised,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    onSelected: (value) {
                      if (value == 'pos') {
                        Get.offAllNamed(AppRoutes.home);
                      } else if (value == 'logout') {
                        _confirmSignOut();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'pos',
                        child: Row(
                          children: [
                            const Icon(
                              Icons.point_of_sale_rounded,
                              color: MarketPalette.blue,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'market_back_to_pos'.tr,
                              style: const TextStyle(color: MarketPalette.text),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'logout',
                        child: Row(
                          children: [
                            const Icon(
                              Icons.logout_rounded,
                              color: MarketPalette.red,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'home_sign_out'.tr,
                              style: const TextStyle(color: MarketPalette.red),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        body: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (reels || notification.metrics.axis != Axis.vertical) {
              return false;
            }
            if (notification is ScrollStartNotification) {
              _lastScrollPixels = notification.metrics.pixels;
              _scrollDelta = 0;
            } else if (notification is OverscrollNotification) {
              _lastScrollPixels = notification.metrics.pixels;
              _scrollDelta = 0;
            } else if (notification is ScrollUpdateNotification) {
              final pixels = notification.metrics.pixels;
              final previousPixels = _lastScrollPixels;
              _lastScrollPixels = pixels;
              if (notification.metrics.outOfRange) {
                _scrollDelta = 0;
                return false;
              }
              _scrollDelta +=
                  notification.scrollDelta ??
                  (previousPixels == null ? 0 : pixels - previousPixels);
              if (_scrollDelta.abs() >= _headerScrollThreshold) {
                final shouldHide = _scrollDelta > 0;
                _scrollDelta = 0;
                if (shouldHide != _appBarHidden) {
                  setState(() => _appBarHidden = shouldHide);
                }
              }
            } else if (notification is ScrollEndNotification) {
              _lastScrollPixels = null;
              _scrollDelta = 0;
            }
            return false;
          },
          child: Stack(
            children: [
              SafeArea(
                top: false,
                bottom: false,
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeInOutCubic,
                  padding: EdgeInsets.only(
                    top: reels
                        ? 0
                        : MediaQuery.paddingOf(context).top +
                              (_appBarHidden ? 0 : kToolbarHeight),
                  ),
                  child: _buildContent(),
                ),
              ),
              Positioned(
                top:
                    MediaQuery.paddingOf(context).top +
                    (_appBarHidden ? 8 : kToolbarHeight + 8),
                left: 16,
                right: 16,
                child: _uploadProgressBanner(),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomNavigation(),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        child: Container(
          height: 62,
          decoration: BoxDecoration(
            color: const Color(0xF20A0B0E),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 18,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _navItem(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
                label: 'market_home'.tr,
                destination: _MarketDestination.home,
              ),
              _navItem(
                icon: Icons.movie_outlined,
                selectedIcon: Icons.movie_rounded,
                label: 'Reels',
                destination: _MarketDestination.market,
              ),
              _createNavItem(),
              _navItem(
                icon: Icons.search_rounded,
                label: 'market_search'.tr,
                destination: _MarketDestination.search,
              ),
              _navItem(
                icon: Icons.person_outline_rounded,
                selectedIcon: Icons.person_rounded,
                label: 'market_profile'.tr,
                destination: _MarketDestination.profile,
                isProfile: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _createNavItem() => SizedBox(
    width: 54,
    height: 54,
    child: IconButton(
      tooltip: 'market_create_post'.tr,
      onPressed: _openComposer,
      icon: const Icon(Icons.add_rounded),
      color: Colors.white,
      iconSize: 27,
    ),
  );

  Widget _navItem({
    required IconData icon,
    IconData? selectedIcon,
    required String label,
    required _MarketDestination destination,
    bool isProfile = false,
  }) {
    final selected = _destination == destination;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Center(
          child: InkWell(
            onTap: () => _select(destination),
            borderRadius: BorderRadius.circular(26),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 52,
              height: 48,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF3B3D42) : Colors.transparent,
                borderRadius: BorderRadius.circular(26),
              ),
              alignment: Alignment.center,
              child: isProfile
                  ? _profileAvatar(selected)
                  : Icon(
                      selected ? (selectedIcon ?? icon) : icon,
                      color: selected ? Colors.white : const Color(0xFFD2D5DA),
                      size: 25,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileAvatar(bool selected) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.white : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: MarketAvatar(
            uid: _profileUid,
            fallbackUrl: FirebaseAuth.instance.currentUser?.photoURL ?? '',
            radius: 13,
          ),
        ),
        Positioned(
          right: -1,
          top: -1,
          child: StreamBuilder<List<AppNotification>>(
            stream: _activity,
            builder: (context, snapshot) {
              final hasUnread = (snapshot.data ?? const []).any((n) => !n.read);
              return ValueListenableBuilder<int>(
                valueListenable: NotificationService.announcementsSeenTick,
                builder: (context, _, _) => FutureBuilder<DateTime>(
                  future: NotificationService.lastSeenAnnouncements(),
                  builder: (context, seenSnapshot) =>
                      StreamBuilder<List<AppNotification>>(
                        stream: _announcements,
                        builder: (context, announcementSnapshot) {
                          final seen = seenSnapshot.data;
                          final hasNewAnnouncement =
                              seen != null &&
                              (announcementSnapshot.data ?? const []).any(
                                (n) => n.createdAt?.isAfter(seen) ?? false,
                              );
                          if (!hasUnread && !hasNewAnnouncement) {
                            return const SizedBox.shrink();
                          }
                          return Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xF20A0B0E),
                                width: 1.5,
                              ),
                            ),
                          );
                        },
                      ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
