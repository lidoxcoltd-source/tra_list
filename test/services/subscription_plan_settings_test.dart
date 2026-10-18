import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/services/super_admin_subscription_service.dart';

void main() {
  group('SubscriptionPlanSettings', () {
    test('uses the existing subscription defaults when no plan is saved', () {
      final plan = SubscriptionPlanSettings.fromMap(null);

      expect(plan.amount, 20000);
      expect(plan.durationDays, 365);
      expect(plan.version, 1);
    });

    test('loads the saved amount, duration, and version', () {
      final plan = SubscriptionPlanSettings.fromMap({
        'amount': 35000,
        'durationDays': 90,
        'version': 3,
      });

      expect(plan.amount, 35000);
      expect(plan.durationDays, 90);
      expect(plan.version, 3);
    });
  });
}
