import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../theme/app_theme.dart';
import 'market_models.dart';
import 'market_palette.dart';

class MarketBuyComingSoonDialog extends StatelessWidget {
  const MarketBuyComingSoonDialog({super.key, required this.post});

  final MarketPost post;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: MarketPalette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: MarketPalette.border),
      ),
      iconColor: MarketPalette.blue,
      titleTextStyle: const TextStyle(
        color: MarketPalette.text,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: const TextStyle(
        color: MarketPalette.textMuted,
        fontSize: 14,
      ),
      icon: const Icon(
        Icons.shopping_bag_outlined,
        size: 34,
        color: MarketPalette.blue,
      ),
      title: Text('market_buy_button'.tr),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            post.productName.trim().isNotEmpty
                ? post.productName
                : post.caption,
            style: const TextStyle(
              color: MarketPalette.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (post.price != null) ...[
            const SizedBox(height: MjasiSpacing.xs),
            Text('${post.currency} ${post.price!.toStringAsFixed(0)}'),
          ],
          const SizedBox(height: MjasiSpacing.sm),
          Text('market_buy_coming_soon'.tr),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: MarketPalette.blue,
            foregroundColor: MarketPalette.canvas,
          ),
          child: Text('close'.tr),
        ),
      ],
    );
  }
}
