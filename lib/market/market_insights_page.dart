import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/app_theme.dart';
import 'market_models.dart';
import 'market_palette.dart';
import 'market_service.dart';

class MarketInsightsPage extends StatefulWidget {
  const MarketInsightsPage({super.key, required this.uid});

  final String uid;

  @override
  State<MarketInsightsPage> createState() => _MarketInsightsPageState();
}

class _InsightsData {
  const _InsightsData({
    required this.posts,
    required this.likes,
    required this.comments,
    required this.clicks,
    required this.hours,
  });

  final List<MarketPost> posts;
  final int likes;
  final int comments;
  final int clicks;
  final List<int> hours;
}

class _MarketInsightsPageState extends State<MarketInsightsPage> {
  late Future<_InsightsData> _future = _load();

  Future<_InsightsData> _load() async {
    final posts = await MarketService.searchAuthorPosts(widget.uid);
    final clicks = await FirebaseFirestore.instance
        .collection('marketContactClicks')
        .where('sellerUid', isEqualTo: widget.uid)
        .limit(500)
        .get();
    final hours = List<int>.filled(24, 0);
    for (final doc in clicks.docs) {
      final at = (doc.data()['createdAt'] as Timestamp?)?.toDate();
      if (at != null) hours[at.hour]++;
    }
    return _InsightsData(
      posts: posts,
      likes: posts.fold(0, (sum, post) => sum + post.likesCount),
      comments: posts.fold(0, (sum, post) => sum + post.commentsCount),
      clicks: clicks.docs.length,
      hours: hours,
    );
  }

  String _hourLabel(int hour) {
    final next = (hour + 1) % 24;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(hour)}:00 - ${two(next)}:00';
  }

  Widget _tile(IconData icon, String label, int value) => Expanded(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: MarketPalette.surface,
        border: Border.all(color: MarketPalette.border),
        borderRadius: BorderRadius.circular(MjasiRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: MarketPalette.blue),
            const SizedBox(height: 6),
            Text(
              '$value',
              style: const TextStyle(
                color: MarketPalette.text,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MarketPalette.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: MarketPalette.darkTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: MarketPalette.canvas,
        appBar: AppBar(
          title: Text('market_insights'.tr),
          actions: [
            IconButton(
              onPressed: () => setState(() => _future = _load()),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<_InsightsData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || snapshot.data == null) {
              return Center(
                child: Text(
                  '${snapshot.error}',
                  style: const TextStyle(color: MarketPalette.textMuted),
                ),
              );
            }
            final data = snapshot.data!;
            final maxHour = data.hours.fold<int>(
              0,
              (max, value) => value > max ? value : max,
            );
            final peak = maxHour == 0 ? -1 : data.hours.indexOf(maxHour);
            final top = [...data.posts]
              ..sort((a, b) => b.likesCount.compareTo(a.likesCount));
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    _tile(
                      Icons.article_outlined,
                      'market_insights_posts'.tr,
                      data.posts.length,
                    ),
                    const SizedBox(width: 8),
                    _tile(
                      Icons.favorite_border,
                      'market_insights_likes'.tr,
                      data.likes,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _tile(
                      Icons.chat_bubble_outline,
                      'market_insights_comments'.tr,
                      data.comments,
                    ),
                    const SizedBox(width: 8),
                    _tile(
                      Icons.chat_outlined,
                      'market_insights_whatsapp'.tr,
                      data.clicks,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'market_insights_peak'.tr,
                  style: const TextStyle(
                    color: MarketPalette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  peak < 0 ? 'market_insights_no_data'.tr : _hourLabel(peak),
                  style: const TextStyle(color: MarketPalette.blue),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 90,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var h = 0; h < 24; h++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: FractionallySizedBox(
                              heightFactor: maxHour == 0
                                  ? 0.03
                                  : (data.hours[h] / maxHour).clamp(0.03, 1.0),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: h == peak
                                      ? MarketPalette.blue
                                      : MarketPalette.border,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'market_insights_top'.tr,
                  style: const TextStyle(
                    color: MarketPalette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                for (final post in top.take(5))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: post.images.isEmpty
                        ? null
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              post.images.first,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox(width: 48, height: 48),
                            ),
                          ),
                    title: Text(
                      post.productName.isNotEmpty
                          ? post.productName
                          : post.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: MarketPalette.text),
                    ),
                    subtitle: Text(
                      '♥ ${post.likesCount}   💬 ${post.commentsCount}',
                      style: const TextStyle(color: MarketPalette.textMuted),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
