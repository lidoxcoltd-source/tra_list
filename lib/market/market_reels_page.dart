import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'market_avatar.dart';
import 'market_comments_sheet.dart';
import 'market_models.dart';
import 'market_order_dialog.dart';
import 'market_palette.dart';
import 'market_post_page.dart';
import 'market_profile_page.dart';
import 'market_service.dart' hide MarketPostPage;

/// Full-screen, swipe-up video viewer (like reels).
class MarketReelsPage extends StatefulWidget {
  const MarketReelsPage({
    super.key,
    required this.posts,
    required this.initialIndex,
    this.embedded = false,
  });

  final List<MarketPost> posts;
  final int initialIndex;
  final bool embedded;

  @override
  State<MarketReelsPage> createState() => _MarketReelsPageState();
}

/// Reels as a bottom-nav tab: loads video posts from the feed.
class MarketReelsTab extends StatefulWidget {
  const MarketReelsTab({super.key});

  @override
  State<MarketReelsTab> createState() => _MarketReelsTabState();
}

class _MarketReelsTabState extends State<MarketReelsTab> {
  List<MarketPost>? _videos;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _videos = null;
      _failed = false;
    });
    try {
      final videos = <MarketPost>[];
      dynamic after;
      for (var i = 0; i < 4 && videos.length < 12; i++) {
        final page = await MarketService.fetchPostsPage(
          after: after,
          pageSize: 30,
        );
        videos.addAll(page.posts.where((p) => p.hasVideo));
        after = page.lastDocument;
        if (!page.hasMore || after == null) break;
      }
      if (mounted) setState(() => _videos = videos);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final videos = _videos;
    if (_failed || (videos != null && videos.isEmpty)) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'reels_empty'.tr,
              style: const TextStyle(color: Colors.white70),
            ),
            TextButton(onPressed: _load, child: const Text('Refresh')),
          ],
        ),
      );
    }
    if (videos == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    return MarketReelsPage(posts: videos, initialIndex: 0, embedded: true);
  }
}

class _MarketReelsPageState extends State<MarketReelsPage> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  int _readyIndex = -1;

  @override
  void initState() {
    super.initState();
    _prefetch(_index);
  }

  // Warms the disk cache for the next reels before they are reached.
  void _prefetch(int from) {
    if (kIsWeb) return;
    for (var i = from + 2; i <= from + 3 && i < widget.posts.length; i++) {
      unawaited(
        DefaultCacheManager()
            .downloadFile(widget.posts[i].videoUrl)
            .then((_) {}, onError: (_) {}),
      );
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            scrollDirection: Axis.vertical,
            itemCount: widget.posts.length,
            allowImplicitScrolling: true,
            onPageChanged: (value) {
              setState(() => _index = value);
              _prefetch(value);
            },
            itemBuilder: (context, index) => _ReelItem(
              key: ValueKey(widget.posts[index].id),
              post: widget.posts[index],
              active: index == _index,
              // On web the next reel loads only once the current one plays,
              // so the two downloads never compete for bandwidth.
              preload: kIsWeb
                  ? index == _index + 1 && _readyIndex == _index
                  : (index - _index).abs() == 1,
              onReady: () {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && index == _index && _readyIndex != index) {
                    setState(() => _readyIndex = index);
                  }
                });
              },
            ),
          ),
          if (!widget.embedded)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xB3000000), Color(0x00000000)],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: SizedBox(
                    height: 56,
                    child: Row(
                      children: [
                        const SizedBox(width: 10),
                        if (!widget.embedded) ...[
                          Material(
                            color: Colors.black38,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => Navigator.of(context).maybePop(),
                              child: const Padding(
                                padding: EdgeInsets.all(9),
                                child: Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        const Text(
                          'Reels',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const Spacer(),
                        if (widget.posts.length > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_index + 1}/${widget.posts.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        const SizedBox(width: 14),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReelItem extends StatefulWidget {
  const _ReelItem({
    super.key,
    required this.post,
    required this.active,
    this.preload = false,
    this.onReady,
  });

  final MarketPost post;
  final bool active;
  final bool preload;
  final VoidCallback? onReady;

  @override
  State<_ReelItem> createState() => _ReelItemState();
}

class _ReelItemState extends State<_ReelItem> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _muted = kIsWeb; // Browsers block unmuted autoplay.
  bool _expanded = false;
  bool _busy = false;
  bool _deleted = false;

  MarketPost get post => widget.post;

  @override
  void initState() {
    super.initState();
    if (widget.active) unawaited(MarketService.recordView(widget.post.id));
    if (widget.active || widget.preload) unawaited(_start());
  }

  @override
  void didUpdateWidget(_ReelItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      unawaited(MarketService.recordView(widget.post.id));
    }
    final needed = widget.active || widget.preload;
    if (!needed) {
      _release();
      return;
    }
    if (_controller == null) unawaited(_start());
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      final controller = _controller;
      if (controller != null && controller.value.isInitialized) {
        unawaited(controller.seekTo(Duration.zero));
        unawaited(controller.play());
        widget.onReady?.call();
      }
    } else {
      unawaited(_controller?.pause());
    }
  }

  // Frees decoders of reels that are two or more pages away.
  void _release() {
    final controller = _controller;
    if (controller == null) return;
    _controller = null;
    controller.removeListener(_loopGuard);
    unawaited(controller.dispose());
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    if (_controller != null || _failed) return;
    final url = widget.post.videoUrl;
    FileInfo? cached;
    if (!kIsWeb) {
      try {
        cached = await DefaultCacheManager().getFileFromCache(url);
      } catch (_) {}
    }
    if (!mounted || _controller != null) return;
    // Neighbouring reels are fully downloaded first so they start instantly.
    if (cached == null && !kIsWeb && !widget.active) {
      try {
        cached = await DefaultCacheManager().downloadFile(url);
      } catch (_) {}
      if (!mounted || _controller != null) return;
      if (!widget.active && !widget.preload) return;
    }
    final controller = cached != null
        ? VideoPlayerController.file(cached.file)
        : VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;
    try {
      await controller.initialize();
      if (cached == null && !kIsWeb) {
        unawaited(
          DefaultCacheManager().downloadFile(url).then((_) {}, onError: (_) {}),
        );
      }
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      controller.addListener(_loopGuard);
      if (!mounted) return;
      setState(() {});
      if (widget.active) {
        unawaited(controller.play());
        widget.onReady?.call();
      }
    } catch (error) {
      debugPrint('Reel video failed to load: $error');
      _controller = null;
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  // Some platforms ignore setLooping, so restart manually at the end.
  void _loopGuard() {
    final controller = _controller;
    if (controller == null || !widget.active || !mounted) return;
    final value = controller.value;
    if (!value.isInitialized || value.duration == Duration.zero) return;
    if (value.position >= value.duration && !value.isPlaying) {
      unawaited(controller.seekTo(Duration.zero));
      unawaited(controller.play());
    }
  }

  void _toggleSound() {
    setState(() => _muted = !_muted);
    unawaited(_controller?.setVolume(_muted ? 0 : 1));
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    unawaited(
      controller.value.isPlaying ? controller.pause() : controller.play(),
    );
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      _message('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _comments() async {
    unawaited(_controller?.pause());
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: MarketPalette.surface,
      builder: (_) => MarketCommentsSheet(postId: post.id),
    );
    if (mounted && widget.active) unawaited(_controller?.play());
  }

  Future<void> _more() async {
    final canDelete = MarketService.canDeletePost(post);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MarketPalette.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: Text('market_open_post'.tr),
              onTap: () => Navigator.pop(context, 'open'),
            ),
            if (canDelete)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: MarketPalette.red,
                ),
                title: Text(
                  'market_delete_post'.tr,
                  style: const TextStyle(color: MarketPalette.red),
                ),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'open') {
      await _openPost();
    } else if (choice == 'delete') {
      await _deletePost();
    }
  }

  Future<void> _deletePost() async {
    unawaited(_controller?.pause());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('market_delete_post'.tr),
        content: Text('market_delete_post_confirm'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('delete'.tr),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      if (widget.active) unawaited(_controller?.play());
      return;
    }
    try {
      await MarketService.deletePost(post);
      if (!mounted) return;
      _release();
      setState(() => _deleted = true);
    } catch (error) {
      _message('$error');
      if (widget.active) unawaited(_controller?.play());
    }
  }

  Future<void> _openPost() async {
    unawaited(_controller?.pause());
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => MarketPostPage(postId: post.id)));
    if (mounted && widget.active) unawaited(_controller?.play());
  }

  Future<void> _openWhatsApp() async {
    final phone = await MarketService.getSellerWhatsApp(post);
    if (phone.isEmpty) {
      _message('market_seller_whatsapp_missing'.tr);
      return;
    }
    if (phone.length < 8 || phone.length > 15) {
      _message('market_whatsapp_invalid'.tr);
      return;
    }
    try {
      await MarketService.recordWhatsAppClick(post);
    } catch (error) {
      debugPrint('Market contact click was not recorded: $error');
    }
    final uri = Uri.https('wa.me', '/$phone', {
      'text': buildMarketWhatsAppMessage(post),
    });
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _message('support_whatsapp_open_error'.tr);
      }
    } catch (_) {
      _message('support_whatsapp_open_error'.tr);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_loopGuard);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  Widget _action({
    required IconData icon,
    required VoidCallback? onTap,
    String? label,
    Color color = Colors.white,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 52,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: color,
                size: 30,
                shadows: const [Shadow(blurRadius: 6, color: Colors.black54)],
              ),
              if (label != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black87)],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionColumn() {
    final compact = NumberFormat.compact();
    return StreamBuilder<MarketPost?>(
      stream: MarketService.watchPost(post.id),
      builder: (context, postSnapshot) {
        final current = postSnapshot.data ?? post;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<bool>(
              stream: MarketService.watchLike(post.id),
              builder: (context, snapshot) {
                final liked = snapshot.data == true;
                return _action(
                  icon: liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: liked ? const Color(0xFFFF3B5C) : Colors.white,
                  label: compact.format(current.likesCount),
                  onTap: () =>
                      _guard(() async => MarketService.toggleLike(post.id)),
                );
              },
            ),
            _action(
              icon: Icons.mode_comment_outlined,
              label: compact.format(current.commentsCount),
              onTap: _comments,
            ),
            _action(
              icon: Icons.send_outlined,
              onTap: () => _guard(() => MarketService.sharePost(post)),
            ),
            StreamBuilder<bool>(
              stream: MarketService.watchSaved(post.id),
              builder: (context, snapshot) {
                final saved = snapshot.data == true;
                return _action(
                  icon: saved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  onTap: () =>
                      _guard(() async => MarketService.toggleSaved(post.id)),
                );
              },
            ),
            _action(
              icon: _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              onTap: _toggleSound,
            ),
            _action(icon: Icons.more_horiz_rounded, onTap: _more),
          ],
        );
      },
    );
  }

  Widget _authorRow() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Row(
      children: [
        GestureDetector(
          onTap: () => Get.to(() => MarketProfilePage(uid: post.authorUid)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MarketAvatar(
                uid: post.authorUid,
                fallbackUrl: post.authorPhotoUrl,
                radius: 18,
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  post.authorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (uid != null && uid != post.authorUid) ...[
          const SizedBox(width: 12),
          StreamBuilder<bool>(
            stream: MarketService.watchFollowing(post.authorUid),
            builder: (context, snapshot) {
              final following = snapshot.data == true;
              return GestureDetector(
                onTap: () => _guard(
                  () async => MarketService.toggleFollow(post.authorUid),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: following ? Colors.transparent : Colors.white24,
                    border: Border.all(color: Colors.white70),
                  ),
                  child: Text(
                    following ? 'market_following'.tr : 'market_follow'.tr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _pillButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_deleted) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Icon(
            Icons.delete_outline_rounded,
            color: Colors.white38,
            size: 56,
          ),
        ),
      );
    }
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    final title = post.isProduct && post.productName.isNotEmpty
        ? post.productName
        : '';
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePlay,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (post.images.isNotEmpty || post.videoThumb.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: post.images.isNotEmpty
                      ? post.images.first
                      : post.videoThumb,
                  fit: BoxFit.contain,
                  errorWidget: (_, _, _) => const SizedBox(),
                ),
              if (ready)
                Center(
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                ),
              if (!ready && !_failed)
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              if (_failed)
                const Center(
                  child: Icon(
                    Icons.error_outline_rounded,
                    color: Colors.white54,
                    size: 48,
                  ),
                ),
              if (ready)
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => value.isPlaying
                      ? const SizedBox.shrink()
                      : const Center(
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white70,
                            size: 84,
                          ),
                        ),
                ),
            ],
          ),
        ),
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 8,
          bottom: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: _actionColumn(),
            ),
          ),
        ),
        Positioned(
          left: 14,
          right: 70,
          bottom: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _authorRow(),
                  if (title.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  if (post.isProduct)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          if (post.price != null)
                            Text(
                              '${post.currency} ${NumberFormat.decimalPattern().format(post.price)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (post.price != null) const SizedBox(width: 10),
                          Text(
                            post.inStock
                                ? 'market_in_stock'.tr
                                : 'market_out_of_stock'.tr,
                            style: TextStyle(
                              color: post.inStock
                                  ? MarketPalette.mint
                                  : MarketPalette.red,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (post.caption.isNotEmpty)
                    GestureDetector(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          post.caption,
                          maxLines: _expanded ? 12 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (post.isProduct)
                          _pillButton(
                            icon: Icons.shopping_bag_outlined,
                            label: 'market_buy_button'.tr,
                            color: MarketPalette.blue,
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (_) =>
                                  MarketBuyComingSoonDialog(post: post),
                            ),
                          ),
                        _pillButton(
                          icon: Icons.chat_rounded,
                          label: 'WhatsApp',
                          color: const Color(0xFF25D366),
                          onTap: _openWhatsApp,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (ready)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              padding: EdgeInsets.zero,
              colors: const VideoProgressColors(
                playedColor: Colors.white,
                bufferedColor: Colors.white24,
                backgroundColor: Colors.white12,
              ),
            ),
          ),
      ],
    );
  }
}
