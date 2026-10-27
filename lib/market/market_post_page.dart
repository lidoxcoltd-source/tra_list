import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import 'market_audio.dart';
import 'market_video.dart';
import 'market_hashtags.dart';
import 'market_models.dart';
import 'market_order_dialog.dart';
import 'market_service.dart';
import 'market_profile_page.dart';
import 'market_palette.dart';

class MarketPostPage extends StatefulWidget {
  const MarketPostPage({super.key, required this.postId});

  final String postId;

  @override
  State<MarketPostPage> createState() => _MarketPostPageState();
}

class _MarketPostPageState extends State<MarketPostPage> {
  late Future<MarketPost?> _post;

  @override
  void initState() {
    super.initState();
    _post = MarketService.getPost(widget.postId);
  }

  Future<void> _openWhatsApp(MarketPost post) async {
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
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        _message('support_whatsapp_open_error'.tr);
      }
    } catch (_) {
      if (mounted) _message('support_whatsapp_open_error'.tr);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: MarketPalette.darkTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: MarketPalette.canvas,
        appBar: AppBar(
          backgroundColor: MarketPalette.topBar,
          foregroundColor: Colors.white,
          title: Text('market_product_details'.tr),
        ),
        body: FutureBuilder<MarketPost?>(
          future: _post,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('explore_error'.tr));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final post = snapshot.data;
            if (post == null) {
              return Center(child: Text('market_post_unavailable'.tr));
            }
            return ListView(
              children: [
                if (post.images.isNotEmpty || post.hasVideo)
                  MarketPostAudio(
                    post: post,
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: post.hasVideo
                          ? MarketVideoView(
                              url: post.videoUrl,
                              visibilityKey: 'detail-${post.id}',
                              cover: post.images.isEmpty
                                  ? null
                                  : Image.network(
                                      post.images.first,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          const SizedBox(),
                                    ),
                            )
                          : PageView.builder(
                              itemCount: post.images.length,
                              itemBuilder: (_, index) => Image.network(
                                post.images[index],
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const ColoredBox(
                                  color: MarketPalette.surfaceRaised,
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(MjasiSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.isProduct ? post.productName : post.authorName,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (post.isProduct && post.price != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${post.currency} ${NumberFormat.decimalPattern().format(post.price)}',
                            style: const TextStyle(
                              color: MarketPalette.blue,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      const SizedBox(height: MjasiSpacing.md),
                      InkWell(
                        onTap: () => Get.to(
                          () => MarketProfilePage(uid: post.authorUid),
                        ),
                        child: Text(
                          post.authorName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (post.createdAt != null)
                        Text(
                          marketPostedAgo(post.createdAt),
                          style: const TextStyle(
                            color: MarketPalette.textMuted,
                            fontSize: 12,
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
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const SizedBox(height: MjasiSpacing.md),
                      if (post.price != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${post.currency} ${post.price!.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: MarketPalette.blue,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      HashtagText(post.caption),
                      if (post.price != null || post.whatsapp.isNotEmpty) ...[
                        const SizedBox(height: MjasiSpacing.lg),
                        Wrap(
                          spacing: MjasiSpacing.sm,
                          runSpacing: MjasiSpacing.sm,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) =>
                                    MarketBuyComingSoonDialog(post: post),
                              ),
                              icon: const Icon(Icons.shopping_bag_outlined),
                              label: Text('market_buy_button'.tr),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _openWhatsApp(post),
                              icon: const Icon(Icons.chat_outlined),
                              label: Text('market_contact_whatsapp'.tr),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: MarketPalette.blue,
                                side: const BorderSide(
                                  color: MarketPalette.blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
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
