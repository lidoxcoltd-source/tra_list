import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tra_list/services/ai_early_access_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    TestFirebaseCoreHostApi.setUp(MockFirebaseApp());
    await Firebase.initializeApp();
  });

  testWidgets('early access fits mobile and links back to downloads', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      GetMaterialApp(
        getPages: [
          GetPage(
            name: '/downloads',
            page: () => const Scaffold(body: Text('Downloads destination')),
          ),
        ],
        home: const AiEarlyAccessPage(),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Nzuri.'), findsOneWidget);
    expect(find.text('DAYS'), findsOneWidget);
    expect(find.text('HRS'), findsOneWidget);
    expect(find.text('MIN'), findsOneWidget);
    expect(find.text('SEC'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    final downloads = find.text('Explore MJASI downloads');
    await tester.ensureVisible(downloads);
    await tester.tap(downloads);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('Downloads destination'), findsOneWidget);
  });
}
