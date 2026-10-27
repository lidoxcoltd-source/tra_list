import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'market_models.dart';
import 'market_service.dart';
import 'market_palette.dart';

class MarketSavedPostsPage extends StatefulWidget {
  const MarketSavedPostsPage({super.key});

  @override
  State<MarketSavedPostsPage> createState() => _MarketSavedPostsPageState();
}

class _MarketSavedPostsPageState extends State<MarketSavedPostsPage> {
  late Future<List<MarketPost>> _posts;

  @override
  void initState() {
    super.initState();
    _posts = MarketService.searchSavedPosts();
  }

  Future<void> _refresh() async {
    final next = MarketService.searchSavedPosts();
    setState(() => _posts = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: MarketPalette.darkTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: MarketPalette.canvas,
        appBar: AppBar(
          title: Text('market_saved_posts'.tr),
          backgroundColor: MarketPalette.topBar,
          foregroundColor: Colors.white,
        ),
        body: FutureBuilder<List<MarketPost>>(
          future: _posts,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('explore_error'.tr));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final posts = snapshot.data!;
            if (posts.isEmpty) {
              return Center(child: Text('market_saved_empty'.tr));
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: GridView.builder(
                padding: const EdgeInsets.all(2),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
                itemCount: posts.length,
                itemBuilder: (context, index) => _SavedPostTile(
                  post: posts[index],
                  onUnsave: () async {
                    await MarketService.toggleSaved(posts[index].id);
                    await _refresh();
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SavedPostTile extends StatelessWidget {
  const _SavedPostTile({required this.post, required this.onUnsave});

  final MarketPost post;
  final VoidCallback onUnsave;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (post.images.isNotEmpty)
        Image.network(
          post.images.first,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const ColoredBox(
            color: MarketPalette.surfaceRaised,
            child: Icon(Icons.broken_image_outlined),
          ),
        )
      else
        const ColoredBox(color: MarketPalette.surfaceRaised),
      Align(
        alignment: Alignment.topRight,
        child: IconButton.filledTonal(
          tooltip: 'market_unsave'.tr,
          onPressed: onUnsave,
          icon: const Icon(Icons.bookmark_remove_outlined, size: 18),
        ),
      ),
    ],
  );
}
