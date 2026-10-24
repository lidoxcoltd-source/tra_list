import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/services/subscription_controller.dart';

void main() {
  group('SubscriptionController offline grace', () {
    final verifiedAt = DateTime.utc(2026, 10, 24, 9);

    test('allows offline access before the 24-hour limit', () {
      expect(
        SubscriptionController.isWithinOfflineGrace(
          verifiedAt,
          verifiedAt.add(const Duration(hours: 23, minutes: 59)),
        ),
        isTrue,
      );
    });

    test('expires offline access at the 24-hour limit', () {
      expect(
        SubscriptionController.isWithinOfflineGrace(
          verifiedAt,
          verifiedAt.add(const Duration(hours: 24)),
        ),
        isFalse,
      );
    });

    test('rejects a system clock earlier than the verification time', () {
      expect(
        SubscriptionController.isWithinOfflineGrace(
          verifiedAt,
          verifiedAt.subtract(const Duration(minutes: 1)),
        ),
        isFalse,
      );
    });

    test('does not extend offline access beyond the subscription expiry', () {
      expect(
        SubscriptionController.isCachedSubscriptionValid(
          verifiedAt: verifiedAt,
          validUntil: verifiedAt.add(const Duration(hours: 2)),
          now: verifiedAt.add(const Duration(hours: 3)),
        ),
        isFalse,
      );
    });
  });
}
