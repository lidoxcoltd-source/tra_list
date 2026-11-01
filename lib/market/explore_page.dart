import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'market_profile_page.dart';
import 'market_palette.dart';
import 'market_text_card.dart';
import '../theme/app_theme.dart';
import 'create_post_sheet.dart';
import 'market_audio.dart';
import 'market_video.dart';
import 'market_reels_page.dart';
import 'market_comments_sheet.dart';
import 'market_avatar.dart';
import 'market_hashtags.dart';
import 'market_models.dart';
import 'market_post_state.dart';
import 'market_order_dialog.dart';
import 'market_service.dart';
import 'status_stories_strip.dart';

enum MarketExploreTab { shops, posts, products }

enum MarketExploreFeedMode { forYou, following, reels }

class MarketExplorePage extends StatefulWidget {
  const MarketExplorePage({
    super.key,
    this.initialTab = MarketExploreTab.posts,
    this.showFeedModeTabs = false,
    this.showControls = true,
    this.searchAutofocus = false,
    this.initialHashtag = '',
  });

  final MarketExploreTab initialTab;
  final bool showFeedModeTabs;
  final bool showControls;
  final bool searchAutofocus;
  final String initialHashtag;

  @override
  State<MarketExplorePage> createState() => _MarketExplorePageState();
}

class _MarketExplorePageState extends State<MarketExplorePage> {
  final _searchController = TextEditingController();
  final _minPriceController = TextEditingController();
  final _maxPriceController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;
  late MarketExploreTab _tab;
  MarketExploreFeedMode _feedMode = MarketExploreFeedMode.forYou;
  String _hashtag = '';
  bool _loading = true;
  Object? _error;
  List<MarketProfile> _shops = const [];
  Map<String, MarketStatusGroup> _shopStatuses = const {};
  List<MarketPost> _posts = const [];
  QueryDocumentSnapshot<Map<String, dynamic>>? _postCursor;
  bool _hasMorePosts = true;
  bool _loadingMore = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _hashtag = widget.initialHashtag;
    _scrollController.addListener(_onFeedScroll);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _minPriceController.dispose();
    _maxPriceController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onFeedScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter < 700) {
      _loadMorePosts();
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _load() async {
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = _searchController.text;
      if (_tab == MarketExploreTab.shops) {
        final shops = await MarketService.searchProfiles(query);
        var groups = <String, MarketStatusGroup>{};
        try {
          groups = {
            for (final g in await MarketService.searchActiveStatuses())
              g.authorUid: g,
          };
        } catch (_) {
          // Statuses are optional; shops still load without them.
        }
        if (mounted && id == _requestId) {
          _shops = shops;
          _shopStatuses = groups;
        }
      } else {
        final page = await _fetchCurrentPostPage().timeout(
          const Duration(seconds: 25),
        );
        if (mounted && id == _requestId) {
          _posts = page.posts;
          _postCursor = page.lastDocument;
          _hasMorePosts = page.hasMore;
        }
      }
    } catch (error) {
      debugPrint('Market explore failed: $error');
      if (mounted && id == _requestId) _error = error;
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  Future<void> _loadMorePosts() async {
    final cursor = _postCursor;
    if (_loading || _loadingMore || !_hasMorePosts || cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetchCurrentPostPage(after: cursor);
      if (!mounted) return;
      final existingIds = _posts.map((post) => post.id).toSet();
      setState(() {
        _posts = [
          ..._posts,
          for (final post in page.posts)
            if (!existingIds.contains(post.id)) post,
        ];
        _postCursor = page.lastDocument;
        _hasMorePosts = page.hasMore;
      });
    } catch (error) {
      debugPrint('Market pagination failed: $error');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<MarketPostPage> _fetchCurrentPostPage({
    QueryDocumentSnapshot<Map<String, dynamic>>? after,
  }) {
    if (_feedMode == MarketExploreFeedMode.following) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Sign in to view followed accounts.');
      return MarketService.fetchFollowingPostsPage(uid: uid, after: after);
    }
    return MarketService.fetchPostsPage(
      query: _searchController.text,
      hashtag: _hashtag,
      minPrice: _tab == MarketExploreTab.products
          ? double.tryParse(_minPriceController.text.trim())
          : null,
      maxPrice: _tab == MarketExploreTab.products
          ? double.tryParse(_maxPriceController.text.trim())
          : null,
      productsOnly: _tab == MarketExploreTab.products,
      shuffleResults: widget.showFeedModeTabs,
      pageSize: widget.showFeedModeTabs ? 48 : 24,
      after: after,
    );
  }

  void _setFeedMode(MarketExploreFeedMode mode) {
    if (mode == _feedMode) return;
    setState(() {
      _feedMode = mode;
      _posts = const [];
      _postCursor = null;
      _hasMorePosts = true;
    });
    _load();
  }

  void _setTab(MarketExploreTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    _load();
  }

  void _setHashtag(String tag) {
    setState(() => _hashtag = _hashtag == tag ? '' : tag);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: MarketPalette.canvas,
      child: Column(
        children: [
          if (widget.showControls || widget.searchAutofocus)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MjasiSpacing.lg,
                MjasiSpacing.md,
                MjasiSpacing.lg,
                MjasiSpacing.sm,
              ),
              child: TextField(
                controller: _searchController,
                autofocus: widget.searchAutofocus,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'explore_search_hint'.tr,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchController.clear();
                            _load();
                          },
                        ),
                  filled: true,
                  fillColor: MarketPalette.surface,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MjasiRadius.pill),
                    borderSide: const BorderSide(color: MarketPalette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MjasiRadius.pill),
                    borderSide: const BorderSide(color: MarketPalette.border),
                  ),
                ),
              ),
            ),
          if (widget.showControls) _buildTabs(),
          if (widget.showControls && _tab == MarketExploreTab.products)
            _buildPriceFilter(),
          if ((widget.showControls || widget.searchAutofocus) &&
              (_tab == MarketExploreTab.posts ||
                  _tab == MarketExploreTab.products))
            _buildHashtags(),
          if (_hasFeedHeader && !_headerInList) _buildFeedHeader(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  bool get _hasFeedHeader =>
      widget.showFeedModeTabs ||
      (_tab == MarketExploreTab.posts &&
          _feedMode == MarketExploreFeedMode.forYou);

  // The header scrolls with the posts whenever the feed list is visible.
  bool get _headerInList =>
      _hasFeedHeader &&
      !widget.searchAutofocus &&
      !_loading &&
      _error == null &&
      _tab == MarketExploreTab.posts &&
      _posts.isNotEmpty;

  Widget _buildFeedHeader() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (widget.showFeedModeTabs) _buildFeedModeTabs(),
      if (_tab == MarketExploreTab.posts &&
          _feedMode == MarketExploreFeedMode.forYou)
        StatusStoriesStrip(
          onCreateStatus: () => _openPostComposer(initialType: 'status'),
        ),
    ],
  );

  Widget _segmentLabel(String text) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(text, maxLines: 1, softWrap: false),
  );

  Widget _buildFeedModeTabs() => Padding(
    padding: const EdgeInsets.fromLTRB(
      MjasiSpacing.lg,
      MjasiSpacing.sm,
      MjasiSpacing.lg,
      MjasiSpacing.xs,
    ),
    child: SizedBox(
      width: double.infinity,
      child: SegmentedButton<MarketExploreFeedMode>(
        showSelectedIcon: false,
        style: MarketPalette.feedModeButtonStyle,
        segments: [
          ButtonSegment(
            value: MarketExploreFeedMode.forYou,
            label: _segmentLabel('market_for_you'.tr),
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          ButtonSegment(
            value: MarketExploreFeedMode.following,
            label: _segmentLabel('market_following_count'.tr),
            icon: const Icon(Icons.people_outline_rounded),
          ),
          ButtonSegment(
            value: MarketExploreFeedMode.reels,
            label: _segmentLabel('Reels'),
            icon: const Icon(Icons.play_circle_outline_rounded),
          ),
        ],
        selected: {_feedMode},
        onSelectionChanged: (selection) {
          final mode = selection.first;
          if (mode == MarketExploreFeedMode.reels) {
            _openReels();
          } else {
            _setFeedMode(mode);
          }
        },
      ),
    ),
  );

  void _openReels() {
    final videos = [
      for (final p in _posts)
        if (p.hasVideo) p,
    ];
    if (videos.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('reels_empty'.tr)));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MarketReelsPage(posts: videos, initialIndex: 0),
      ),
    );
  }

  Future<void> _openPostComposer({String initialType = 'post'}) async {
    final published = await openMarketComposer(
      context,
      initialType: initialType,
    );
    if (published == true && mounted) await _load();
  }

  Widget _buildPriceFilter() {
    InputDecoration decoration(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: MarketPalette.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MjasiRadius.pill),
        borderSide: const BorderSide(color: MarketPalette.border),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MjasiSpacing.lg,
        MjasiSpacing.sm,
        MjasiSpacing.lg,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _minPriceController,
              keyboardType: TextInputType.number,
              onChanged: _onSearchChanged,
              decoration: decoration('market_price_min'.tr),
            ),
          ),
          const SizedBox(width: MjasiSpacing.sm),
          Expanded(
            child: TextField(
              controller: _maxPriceController,
              keyboardType: TextInputType.number,
              onChanged: _onSearchChanged,
              decoration: decoration('market_price_max'.tr),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    final labels = <MarketExploreTab, String>{
      MarketExploreTab.posts: 'explore_posts'.tr,
      MarketExploreTab.products: 'explore_products'.tr,
      MarketExploreTab.shops: 'explore_shops'.tr,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MjasiSpacing.lg),
      child: Wrap(
        spacing: MjasiSpacing.sm,
        runSpacing: MjasiSpacing.xs,
        children: [
          for (final tab in labels.keys)
            ChoiceChip(
              label: Text(labels[tab]!),
              selected: _tab == tab,
              onSelected: (_) => _setTab(tab),
              showCheckmark: false,
              selectedColor: MarketPalette.navy,
              backgroundColor: MarketPalette.surface,
              side: const BorderSide(color: MarketPalette.border),
              labelStyle: TextStyle(
                color: _tab == tab ? Colors.white : MarketPalette.text,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHashtags() {
    final counts = <String, int>{};
    for (final post in _posts) {
      for (final tag in post.hashtags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final popular = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final typed = normalizeHashtag(_searchController.text);
    final tags = <String>{
      if (_hashtag.isNotEmpty) _hashtag,
      ...popular.take(12),
      ...marketSuggestedHashtags,
    }.where((tag) => typed.isEmpty || tag.contains(typed)).toList();
    if (typed.length >= 2 && !tags.contains(typed)) tags.insert(0, typed);
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: MjasiSpacing.lg,
          vertical: MjasiSpacing.sm,
        ),
        itemCount: tags.length,
        separatorBuilder: (_, _) => const SizedBox(width: MjasiSpacing.sm),
        itemBuilder: (context, index) {
          final tag = tags[index];
          final selected = _hashtag == tag;
          return ChoiceChip(
            label: Text('#$tag'),
            selected: selected,
            onSelected: (_) => _setHashtag(tag),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            selectedColor: MarketPalette.blueSoft,
            backgroundColor: MarketPalette.surface,
            side: BorderSide(
              color: selected ? MarketPalette.blue : MarketPalette.border,
            ),
            labelStyle: TextStyle(
              fontSize: 12.5,
              color: selected ? MarketPalette.blue : MarketPalette.textMuted,
              fontWeight: FontWeight.w600,
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _message(
        Icons.cloud_off_rounded,
        _loadErrorMessage(),
        action: TextButton(onPressed: _load, child: Text('explore_retry'.tr)),
      );
    }
    if (_tab == MarketExploreTab.shops) {
      if (_shops.isEmpty) {
        return _message(Icons.storefront_outlined, 'explore_empty_shops'.tr);
      }
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.all(MjasiSpacing.lg),
          itemCount: _shops.length,
          separatorBuilder: (_, _) => const SizedBox(height: MjasiSpacing.sm),
          itemBuilder: (context, index) {
            final shop = _shops[index];
            return _ShopTile(
              shop: shop,
              status: _shopStatuses[shop.uid],
              onStatusClosed: _load,
            );
          },
        ),
      );
    }
    if (_posts.isEmpty) {
      return _message(
        _feedMode == MarketExploreFeedMode.following
            ? Icons.people_outline_rounded
            : Icons.image_search_rounded,
        _feedMode == MarketExploreFeedMode.following
            ? 'market_following_feed_empty'.tr
            : 'explore_empty_posts'.tr,
        action: _hasMorePosts
            ? TextButton(
                onPressed: _loadMorePosts,
                child: Text('market_load_more'.tr),
              )
            : null,
      );
    }
    if (_tab != MarketExploreTab.products) {
      final videoPosts = [
        for (final p in _posts)
          if (p.hasVideo) p,
      ];
      if (widget.searchAutofocus) {
        return RefreshIndicator(
          onRefresh: _load,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = (constraints.maxWidth / 140).floor().clamp(3, 6);
              return GridView.builder(
                controller: _scrollController,
                cacheExtent: 1200,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 4, bottom: 90),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                  childAspectRatio: .75,
                ),
                itemCount: _posts.length + (_hasMorePosts ? 1 : 0),
                itemBuilder: (context, index) => index >= _posts.length
                    ? const Center(child: CircularProgressIndicator())
                    : _GridPostTile(
                        key: ValueKey(_posts[index].id),
                        post: _posts[index],
                        videoPosts: videoPosts,
                      ),
              );
            },
          ),
        );
      }
      final header = _headerInList;
      final offset = header ? 1 : 0;
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          controller: _scrollController,
          cacheExtent: 1500,
          padding: const EdgeInsets.fromLTRB(0, 0, 0, MjasiSpacing.lg),
          itemCount: _posts.length + (_hasMorePosts ? 1 : 0) + offset,
          separatorBuilder: (_, _) => const SizedBox(height: MjasiSpacing.md),
          itemBuilder: (context, rawIndex) {
            if (header && rawIndex == 0) return _buildFeedHeader();
            final index = rawIndex - offset;
            return index >= _posts.length
                ? const Padding(
                    padding: EdgeInsets.all(MjasiSpacing.md),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : RepaintBoundary(
                    child: _FeedPostTile(
                      key: ValueKey(_posts[index].id),
                      post: _posts[index],
                      videoPosts: videoPosts,
                    ),
                  );
          },
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = (constraints.maxWidth / 220).floor().clamp(2, 6);
          return GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(MjasiSpacing.lg),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: MjasiSpacing.md,
              crossAxisSpacing: MjasiSpacing.md,
              childAspectRatio: .68,
            ),
            itemCount: _posts.length + (_hasMorePosts ? 1 : 0),
            itemBuilder: (context, index) => index >= _posts.length
                ? const Center(child: CircularProgressIndicator())
                : _PostTile(post: _posts[index]),
          );
        },
      ),
    );
  }

  Widget _message(IconData icon, String text, {Widget? action}) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 80),
      Icon(icon, size: 48, color: MarketPalette.textMuted),
      const SizedBox(height: MjasiSpacing.md),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: MarketPalette.textMuted, height: 1.4),
        ),
      ),
      if (action != null) Center(child: action),
    ],
  );

  String _loadErrorMessage() {
    final error = _error;
    if (error is FirebaseException) {
      final detail = switch (error.code) {
        'permission-denied' =>
          'Firestore denied access. Check that you are signed in and that the deployed rules allow market reads.',
        'unauthenticated' => 'Please sign in, then retry.',
        'failed-precondition' => error.message ?? error.code,
        'unavailable' || 'deadline-exceeded' =>
          'Firestore is unavailable. Check your connection and retry.',
        _ => 'Firestore error: ${error.code}',
      };
      return '${'explore_error'.tr}\n$detail';
    }
    return '${'explore_error'.tr}\n${error ?? ''}';
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<bool>(
      stream: MarketService.watchBusinessVerified(uid),
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        return const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Icon(
            Icons.verified_rounded,
            size: 16,
            color: MarketPalette.blue,
          ),
        );
      },
    );
  }
}

class _ShopTile extends StatelessWidget {
  const _ShopTile({required this.shop, this.status, this.onStatusClosed});

  final MarketProfile shop;
  final MarketStatusGroup? status;
  final VoidCallback? onStatusClosed;

  Widget _avatar(BuildContext context) {
    final avatar = MarketAvatar(uid: shop.uid, fallbackUrl: shop.photoUrl);
    final group = status;
    if (group == null) return avatar;
    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => MarketStatusViewer(group: group),
          ),
        );
        onStatusClosed?.call();
      },
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [MarketPalette.blue, MarketPalette.mint],
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: MarketPalette.surface,
          ),
          child: avatar,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (shop.category.isNotEmpty) 'market_cat_${shop.category}'.tr,
      if (shop.city.isNotEmpty) shop.city,
    ].join(' · ');
    return InkWell(
      onTap: () => Get.to(() => MarketProfilePage(uid: shop.uid)),
      borderRadius: BorderRadius.circular(MjasiRadius.md),
      child: Container(
        padding: const EdgeInsets.all(MjasiSpacing.md),
        decoration: BoxDecoration(
          color: MarketPalette.surface,
          borderRadius: BorderRadius.circular(MjasiRadius.md),
          border: Border.all(color: MarketPalette.border),
        ),
        child: Row(
          children: [
            _avatar(context),
            const SizedBox(width: MjasiSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          shop.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: MarketPalette.text,
                          ),
                        ),
                      ),
                      _VerifiedBadge(uid: shop.uid),
                    ],
                  ),
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: MarketPalette.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              '${shop.postsCount}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: MarketPalette.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _compactCount(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1).replaceAll('.0', '')} M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(value >= 100000 ? 0 : 1).replaceAll('.0', '')}K';
  }
  return '$value';
}

/// Instagram-style square-ish tile: media only, with the view count.
class _GridPostTile extends StatelessWidget {
  const _GridPostTile({
    super.key,
    required this.post,
    required this.videoPosts,
  });

  final MarketPost post;
  final List<MarketPost> videoPosts;

  void _open(BuildContext context) {
    if (post.hasVideo) {
      final start = videoPosts.indexWhere((p) => p.id == post.id);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MarketReelsPage(
            posts: videoPosts.isEmpty ? [post] : videoPosts,
            initialIndex: start < 0 ? 0 : start,
          ),
        ),
      );
      return;
    }
    unawaited(MarketService.recordView(post.id));
    Get.toNamed('/market/post/${post.id}');
  }

  @override
  Widget build(BuildContext context) {
    const placeholder = ColoredBox(color: MarketPalette.surfaceRaised);
    return GestureDetector(
      onTap: () => _open(context),
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (post.isTextOnly)
              MarketTextCard(
                text: post.caption,
                seed: post.id,
                bg: post.textBg,
                font: post.textFont,
                fontSize: 13,
                maxLines: 7,
              )
            else if (post.images.isEmpty && post.videoThumb.isEmpty)
              placeholder
            else
              CachedNetworkImage(
                imageUrl: post.images.isNotEmpty
                    ? post.images.first
                    : post.videoThumb,
                fit: BoxFit.cover,
                memCacheWidth: 400,
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) => placeholder,
              ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: [Color(0x99000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
            if (post.hasVideo)
              const Positioned(
                top: 6,
                right: 6,
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              )
            else if (post.images.length > 1)
              const Positioned(
                top: 6,
                right: 6,
                child: Icon(
                  Icons.collections_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            Positioned(
              left: 6,
              bottom: 5,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.remove_red_eye_outlined,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  ValueListenableBuilder<Map<String, int>>(
                    valueListenable: MarketService.viewBumps,
                    builder: (_, bumps, _) => Text(
                      _compactCount(post.viewsCount + (bumps[post.id] ?? 0)),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.post});

  final MarketPost post;

  @override
  Widget build(BuildContext context) {
    final title = post.isProduct && post.productName.isNotEmpty
        ? post.productName
        : post.caption;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: MarketPalette.surface,
        borderRadius: BorderRadius.circular(MjasiRadius.md),
        border: Border.all(color: MarketPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                post.isTextOnly
                    ? MarketTextCard(
                        text: post.caption,
                        seed: post.id,
                        bg: post.textBg,
                        font: post.textFont,
                        fontSize: 14,
                        maxLines: 6,
                      )
                    : post.images.isEmpty
                    ? const ColoredBox(color: MarketPalette.surfaceRaised)
                    : CachedNetworkImage(
                        imageUrl: post.images.first,
                        fit: BoxFit.cover,
                        memCacheWidth: 600,
                        errorWidget: (_, _, _) => const ColoredBox(
                          color: MarketPalette.surfaceRaised,
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: MarketPalette.textMuted,
                          ),
                        ),
                      ),
                if (post.price != null)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: MarketPalette.navy,
                        borderRadius: BorderRadius.circular(MjasiRadius.pill),
                      ),
                      child: Text(
                        '${post.currency} ${NumberFormat.decimalPattern().format(post.price)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(MjasiSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: MarketPalette.text,
                    ),
                  ),
                InkWell(
                  onTap: () =>
                      Get.to(() => MarketProfilePage(uid: post.authorUid)),
                  child: Text(
                    post.authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: MarketPalette.textMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _showBuy(context),
                      icon: const Icon(Icons.shopping_bag_outlined, size: 15),
                      label: Text('market_buy_button'.tr),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(62, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        visualDensity: VisualDensity.compact,
                        foregroundColor: MarketPalette.text,
                        side: const BorderSide(color: MarketPalette.border),
                        textStyle: const TextStyle(fontSize: 10.5),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openWhatsApp(context),
                      icon: const Icon(Icons.chat_outlined, size: 15),
                      label: Text('market_contact_whatsapp'.tr),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(62, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        visualDensity: VisualDensity.compact,
                        foregroundColor: MarketPalette.blue,
                        side: const BorderSide(color: MarketPalette.blue),
                        textStyle: const TextStyle(fontSize: 10.5),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => Get.toNamed('/market/post/${post.id}'),
                      icon: const Icon(Icons.info_outline, size: 15),
                      label: Text('market_product_details'.tr),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: 10.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showBuy(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => MarketBuyComingSoonDialog(post: post),
    );
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    final phone = await MarketService.getSellerWhatsApp(post);
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('market_seller_whatsapp_missing'.tr)),
      );
      return;
    }
    if (phone.length < 8 || phone.length > 15) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('market_whatsapp_invalid'.tr)));
      return;
    }
    try {
      await MarketService.recordWhatsAppClick(post);
    } catch (error) {
      debugPrint('Market contact click was not recorded: $error');
    }
    final message = buildMarketWhatsAppMessage(post);
    final uri = Uri.https('wa.me', '/$phone', {'text': message});
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('support_whatsapp_open_error'.tr)),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('support_whatsapp_open_error'.tr)),
        );
      }
    }
  }
}

class _FeedPostTile extends StatefulWidget {
  const _FeedPostTile({
    super.key,
    required this.post,
    this.videoPosts = const [],
  });

  final MarketPost post;
  final List<MarketPost> videoPosts;

  @override
  State<_FeedPostTile> createState() => _FeedPostTileState();
}

class _FeedPostTileState extends State<_FeedPostTile> {
  int _imageIndex = 0;
  bool _busy = false;
  bool _deleted = false;
  late final Stream<MarketPostLive> _live = watchMarketPostLive(widget.post);

  @override
  void initState() {
    super.initState();
    MarketUserSets.instance.ensureStarted();
  }

  MarketPost get post => widget.post;

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _comments() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: MarketPalette.surface,
    builder: (_) => MarketCommentsSheet(postId: post.id),
  );

  Future<void> _share() async {
    try {
      await MarketService.sharePost(post);
    } catch (error) {
      if (mounted) _message('$error');
    }
  }

  Future<void> _report() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('market_report_post'.tr),
        children: [
          for (final entry in <String, String>{
            'spam': 'market_report_spam'.tr,
            'unsafe': 'market_report_unsafe'.tr,
            'other': 'market_report_other'.tr,
          }.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, entry.key),
              child: Text(entry.value),
            ),
        ],
      ),
    );
    if (reason == null) return;
    try {
      await MarketService.reportPost(post.id, reason);
      if (mounted) _message('market_report_sent'.tr);
    } catch (error) {
      if (mounted) _message('$error');
    }
  }

  Future<void> _editCaption() async {
    final controller = TextEditingController(text: post.caption);
    final caption = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('market_edit_caption'.tr),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 5,
          maxLength: 2000,
          decoration: InputDecoration(
            labelText: 'market_caption'.tr,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text('save'.tr),
          ),
        ],
      ),
    );
    controller.dispose();
    if (caption == null) return;
    try {
      await MarketService.updateCaption(post, caption);
    } catch (error) {
      if (mounted) _message('$error');
    }
  }

  Future<void> _deletePost() async {
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
    if (confirmed != true) return;
    try {
      await MarketService.deletePost(post);
      if (mounted) setState(() => _deleted = true);
    } catch (error) {
      if (mounted) _message('$error');
    }
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
    final message = buildMarketWhatsAppMessage(post);
    final uri = Uri.https('wa.me', '/$phone', {'text': message});
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        _message('support_whatsapp_open_error'.tr);
      }
    } catch (_) {
      if (mounted) _message('support_whatsapp_open_error'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_deleted) return const SizedBox.shrink();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final canEdit = MarketService.canEditPost(post);
    final canDelete = MarketService.canDeletePost(post);
    return Container(
      color: MarketPalette.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                InkWell(
                  onTap: () =>
                      Get.to(() => MarketProfilePage(uid: post.authorUid)),
                  customBorder: const CircleBorder(),
                  child: MarketAvatar(
                    uid: post.authorUid,
                    fallbackUrl: post.authorPhotoUrl,
                    radius: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () =>
                        Get.to(() => MarketProfilePage(uid: post.authorUid)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                post.authorName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            _VerifiedBadge(uid: post.authorUid),
                          ],
                        ),
                        if (post.createdAt != null)
                          Text(
                            marketPostedAgo(post.createdAt),
                            style: const TextStyle(
                              color: MarketPalette.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        if (post.isProduct && post.price != null)
                          Text(
                            '${post.currency} ${NumberFormat.decimalPattern().format(post.price)}',
                            style: const TextStyle(
                              color: MarketPalette.blue,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (post.isProduct)
                  Text(
                    post.inStock
                        ? 'market_in_stock'.tr
                        : 'market_out_of_stock'.tr,
                    style: TextStyle(
                      color: post.inStock
                          ? MarketPalette.mint
                          : MarketPalette.red,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (uid != null && uid != post.authorUid)
                  ValueListenableBuilder<Set<String>>(
                    valueListenable: MarketUserSets.instance.following,
                    builder: (context, following, _) => TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() => _busy = true);
                              try {
                                await MarketService.toggleFollow(
                                  post.authorUid,
                                );
                              } catch (error) {
                                if (mounted) _message('$error');
                              } finally {
                                if (mounted) setState(() => _busy = false);
                              }
                            },
                      child: Text(
                        following.contains(post.authorUid)
                            ? 'market_following'.tr
                            : 'market_follow'.tr,
                      ),
                    ),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'market_post_options'.tr,
                  onSelected: (value) {
                    if (value == 'report') _report();
                    if (value == 'edit') _editCaption();
                    if (value == 'delete') _deletePost();
                    if (value == 'hide') {
                      MarketService.hidePost(post.id).then((_) {
                        if (mounted) _message('market_post_hidden'.tr);
                      });
                    }
                  },
                  itemBuilder: (_) => [
                    if (canEdit)
                      PopupMenuItem(
                        value: 'edit',
                        child: Text('market_edit_caption'.tr),
                      ),
                    if (canDelete)
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('market_delete_post'.tr),
                      ),
                    PopupMenuItem(
                      value: 'report',
                      child: Text('market_report_post'.tr),
                    ),
                    PopupMenuItem(
                      value: 'hide',
                      child: Text('market_hide_post'.tr),
                    ),
                  ],
                ),
              ],
            ),
          ),
          MarketPostAudio(
            post: post,
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (post.hasVideo)
                    MarketVideoView(
                      url: post.videoUrl,
                      visibilityKey: post.id,
                      onTap: () {
                        final list = widget.videoPosts.isEmpty
                            ? [post]
                            : widget.videoPosts;
                        final start = list.indexWhere((p) => p.id == post.id);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MarketReelsPage(
                              posts: list,
                              initialIndex: start < 0 ? 0 : start,
                            ),
                          ),
                        );
                      },
                      cover: post.images.isEmpty
                          ? null
                          : CachedNetworkImage(
                              imageUrl: post.images.first,
                              fit: BoxFit.cover,
                              memCacheWidth: 1000,
                            ),
                    )
                  else if (post.isTextOnly)
                    MarketTextCard(
                      text: post.caption,
                      seed: post.id,
                      bg: post.textBg,
                      font: post.textFont,
                      fontSize: 24,
                      maxLines: 9,
                    )
                  else
                    PageView.builder(
                      itemCount: post.images.length,
                      onPageChanged: (index) =>
                          setState(() => _imageIndex = index),
                      itemBuilder: (context, index) => CachedNetworkImage(
                        imageUrl: post.images[index],
                        fit: BoxFit.cover,
                        memCacheWidth: 1000,
                        errorWidget: (_, _, _) => const ColoredBox(
                          color: MarketPalette.surfaceRaised,
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  if (post.isProduct && post.price != null)
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: MarketPalette.navy,
                          borderRadius: BorderRadius.circular(MjasiRadius.sm),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          child: Text(
                            '${post.currency} ${NumberFormat.decimalPattern().format(post.price)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (post.images.length > 1 && !post.hasVideo)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(MjasiRadius.pill),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          child: Text(
                            '${_imageIndex + 1}/${post.images.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
            child: StreamBuilder<MarketPostLive>(
              stream: _live,
              builder: (context, postSnapshot) {
                final current = postSnapshot.data?.post ?? post;
                final liked = postSnapshot.data?.liked ?? false;
                final iconConstraints = const BoxConstraints(
                  minWidth: 48,
                  minHeight: 48,
                );
                final iconStyle = IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(48, 48),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
                return Row(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          constraints: iconConstraints,
                          style: iconStyle,
                          tooltip: liked
                              ? 'market_unlike'.tr
                              : 'market_like'.tr,
                          onPressed: _busy
                              ? null
                              : () async {
                                  setState(() => _busy = true);
                                  try {
                                    await MarketService.toggleLike(post.id);
                                  } catch (error) {
                                    if (mounted) _message('$error');
                                  } finally {
                                    if (mounted) {
                                      setState(() => _busy = false);
                                    }
                                  }
                                },
                          icon: Icon(
                            liked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        Text(
                          NumberFormat.compact().format(current.likesCount),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          constraints: iconConstraints,
                          style: iconStyle,
                          tooltip: 'market_comments'.tr,
                          onPressed: _comments,
                          icon: const Icon(
                            Icons.mode_comment_outlined,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        Text(
                          NumberFormat.compact().format(current.commentsCount),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      constraints: iconConstraints,
                      style: iconStyle,
                      tooltip: 'market_share'.tr,
                      onPressed: _share,
                      icon: const Icon(
                        Icons.send_outlined,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const Spacer(),
                    ValueListenableBuilder<Set<String>>(
                      valueListenable: MarketUserSets.instance.saved,
                      builder: (context, savedIds, _) {
                        final isSaved = savedIds.contains(post.id);
                        return IconButton(
                          constraints: iconConstraints,
                          style: iconStyle,
                          tooltip: isSaved
                              ? 'market_unsave'.tr
                              : 'market_save'.tr,
                          onPressed: () async {
                            try {
                              await MarketService.toggleSaved(post.id);
                            } catch (error) {
                              if (mounted) _message('$error');
                            }
                          },
                          icon: Icon(
                            isSaved
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post.isProduct && post.productName.isNotEmpty)
                  Text(
                    post.productName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                if (post.isProduct)
                  Text(
                    post.inStock
                        ? 'market_in_stock'.tr
                        : 'market_out_of_stock'.tr,
                    style: TextStyle(
                      color: post.inStock
                          ? MarketPalette.mint
                          : MarketPalette.red,
                      fontSize: 12,
                    ),
                  ),
                if (post.caption.isNotEmpty)
                  HashtagText(post.caption, collapsedLines: 3),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => MarketBuyComingSoonDialog(post: post),
                      ),
                      icon: const Icon(Icons.shopping_bag_outlined),
                      label: Text('market_buy_button'.tr),
                    ),
                    OutlinedButton.icon(
                      onPressed: _openWhatsApp,
                      icon: const Icon(Icons.chat_outlined),
                      label: Text('market_contact_whatsapp'.tr),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MarketPalette.blue,
                        side: const BorderSide(color: MarketPalette.blue),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => Get.toNamed('/market/post/${post.id}'),
                      icon: const Icon(Icons.info_outline),
                      label: Text('market_product_details'.tr),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
