import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/services/app_version_service.dart';

void main() {
  group('AppVersionService.compareVersions', () {
    test('compares numeric components rather than string values', () {
      expect(
        AppVersionService.compareVersions('1.10.0', '1.9.0'),
        greaterThan(0),
      );
      expect(AppVersionService.compareVersions('2.0.0', '10.0.0'), lessThan(0));
    });

    test('treats omitted trailing zero components as equal', () {
      expect(AppVersionService.compareVersions('1.2', '1.2.0'), 0);
    });

    test('rejects non-numeric version components', () {
      expect(
        () => AppVersionService.compareVersions('1.2.beta', '1.2.0'),
        throwsFormatException,
      );
    });
  });

  group('AppVersionService.isUpdateRequired', () {
    const policy = PlatformVersionPolicy(
      enabled: true,
      minimumVersion: '1.2.0',
      minimumBuild: 4,
      updateUrl: 'https://example.com/update',
    );

    test('requires update for an older version', () {
      expect(
        AppVersionService.isUpdateRequired(
          installedVersion: '1.1.9',
          installedBuild: 100,
          policy: policy,
        ),
        isTrue,
      );
    });

    test('requires update for an older build of the minimum version', () {
      expect(
        AppVersionService.isUpdateRequired(
          installedVersion: '1.2.0',
          installedBuild: 3,
          policy: policy,
        ),
        isTrue,
      );
    });

    test('allows the minimum and newer versions', () {
      expect(
        AppVersionService.isUpdateRequired(
          installedVersion: '1.2.0',
          installedBuild: 4,
          policy: policy,
        ),
        isFalse,
      );
      expect(
        AppVersionService.isUpdateRequired(
          installedVersion: '1.3.0',
          installedBuild: 1,
          policy: policy,
        ),
        isFalse,
      );
    });

    test('does not enforce a disabled platform policy', () {
      expect(
        AppVersionService.isUpdateRequired(
          installedVersion: '0.1.0',
          installedBuild: 1,
          policy: const PlatformVersionPolicy(),
        ),
        isFalse,
      );
    });
  });
}
