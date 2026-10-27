import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/market/market_models.dart';

void main() {
  group('MarketPost', () {
    test('serializes and deserializes post fields', () {
      final createdAt = DateTime.utc(2026, 1, 2, 3, 4);
      final expiresAt = createdAt.add(const Duration(hours: 24));
      final post = MarketPost(
        id: 'post-1',
        authorUid: 'seller-1',
        authorName: 'Shop',
        type: 'product',
        images: const ['https://example.com/item.jpg'],
        productName: 'Item',
        productId: 'inventory-1',
        price: 1500,
        currency: 'TZS',
        purchaseMethod: 'whatsapp',
        whatsapp: '255712345678',
        createdAt: createdAt,
        expiresAt: expiresAt,
      );

      final restored = MarketPost.fromData('post-1', post.toMap());

      expect(restored.authorUid, post.authorUid);
      expect(restored.productId, 'inventory-1');
      expect(restored.images, post.images);
      expect(restored.price, 1500);
      expect(restored.purchaseMethod, 'whatsapp');
      expect(restored.whatsapp, '255712345678');
      expect(restored.createdAt?.toUtc(), createdAt.toUtc());
      expect(restored.expiresAt?.toUtc(), expiresAt.toUtc());
    });

    test('status is active only before its expiry', () {
      final now = DateTime.utc(2026, 1, 2);
      final status = MarketPost(
        id: 'status-1',
        authorUid: 'user-1',
        authorName: 'User',
        type: 'status',
        images: const ['https://example.com/status.jpg'],
        expiresAt: now.add(const Duration(hours: 24)),
      );

      expect(status.isActiveStatusAt(now), isTrue);
      expect(
        status.isActiveStatusAt(now.add(const Duration(hours: 24))),
        isFalse,
      );
    });

    test(
      'builds WhatsApp contact text with product, seller, price, and reference',
      () {
        final post = MarketPost(
          id: 'product-42',
          authorUid: 'seller-1',
          authorName: 'Kariakoo Shop',
          type: 'product',
          images: const ['https://example.com/item.jpg'],
          productName: 'Rice',
          caption: 'Premium local rice',
          category: 'food',
          price: 2500,
        );

        final message = buildMarketWhatsAppMessage(post, quantity: 2);

        expect(message, contains('Rice'));
        expect(message, contains('Kariakoo Shop'));
        expect(message, contains('2500'));
        expect(message, contains('product-42'));
        expect(message, contains('Premium local rice'));
        expect(message, contains('food'));
        expect(
          message,
          contains('https://mjasipos.web.app/#/market/post/product-42'),
        );
        expect(message, contains('Quantity: 2'));
      },
    );
  });
}
