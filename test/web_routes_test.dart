import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/routes.dart';

void main() {
  group('AppRoutes.resolveWebLocation', () {
    test('resolves every registered route from a web hash URL', () {
      for (final page in AppRoutes.pages) {
        final route = page.name.replaceAllMapped(
          RegExp(r':([A-Za-z0-9_]+)'),
          (match) => switch (match.group(1)) {
            'section' => 'explore',
            'token' => 'share-token',
            _ => 'sample-id',
          },
        );
        final resolved = AppRoutes.resolveWebLocation(
          Uri.parse('https://mjasipos.web.app/#$route'),
        );
        expect(resolved, route, reason: 'Route ${page.name} did not resolve');
      }
    });

    test('resolves path URLs and keeps query parameters', () {
      expect(
        AppRoutes.resolveWebLocation(
          Uri.parse('https://mjasipos.web.app/receipt/abc123?source=email'),
        ),
        '/receipt/abc123?source=email',
      );
    });

    test('matches static routes without case sensitivity', () {
      expect(
        AppRoutes.resolveWebLocation(
          Uri.parse('https://mjasipos.web.app/#/addtransactionpage'),
        ),
        AppRoutes.addTransaction,
      );
    });

    test('rejects unknown routes and unsupported home sections', () {
      expect(
        AppRoutes.resolveWebLocation(
          Uri.parse('https://mjasipos.web.app/#/unknown-page'),
        ),
        isNull,
      );
      expect(
        AppRoutes.resolveWebLocation(
          Uri.parse('https://mjasipos.web.app/#/home/unknown'),
        ),
        isNull,
      );
    });

    test(
      'detects routes that require authentication from their middleware',
      () {
        expect(
          AppRoutes.webRouteRequiresAuthentication(AppRoutes.invoice),
          isTrue,
        );
        expect(
          AppRoutes.webRouteRequiresAuthentication(AppRoutes.sharedDocument),
          isFalse,
        );
      },
    );
  });
}
