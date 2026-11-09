import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/isher_greeting_voice.dart';
import 'package:tra_list/business_intelligence/isher_welcome_screen.dart';
import 'package:tra_list/invoice/app_translations.dart';

class FakeGreetingVoice implements IsherGreetingVoice {
  final spoken = <String>[];
  int stops = 0;
  bool fail = false;
  Completer<void>? waiting;

  @override
  Future<void> speak(
    String text,
    String language,
    bool Function() isCurrent, {
    required int greetingVariant,
  }) async {
    if (waiting != null) await waiting!.future;
    if (!isCurrent()) return;
    if (fail) throw StateError('unavailable');
    spoken.add('$language:$text');
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

void main() {
  testWidgets('shows three capabilities without speech controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: IsherWelcomeScreen(
          loading: false,
          ready: true,
          greetingReady: true,
          error: '',
          businessName: 'Duka',
          businessId: 'business',
          greetingVoice: FakeGreetingVoice()..fail = true,
          onRetry: () {},
          onChat: () {},
          onVoice: () {},
          onUsage: () {},
          onReport: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Isher AI'), findsOneWidget);
    expect(find.text('Msaidizi wako mahiri wa biashara'), findsOneWidget);
    expect(find.text('Chambua biashara'), findsOneWidget);
    expect(find.text('Andaa rasimu za hati'), findsOneWidget);
    expect(find.text('Rekodi miamala'), findsOneWidget);
    expect(find.text('Mipangilio ya sauti'), findsNothing);
    expect(find.byTooltip('Sikiliza salamu'), findsNothing);
  });

  testWidgets('greeting plays while the business report is still loading', (
    tester,
  ) async {
    final voice = FakeGreetingVoice();
    Widget screen(bool loading) => GetMaterialApp(
      translations: AppTranslations(),
      locale: const Locale('sw', 'TZ'),
      home: IsherWelcomeScreen(
        loading: loading,
        ready: !loading,
        greetingReady: true,
        error: '',
        businessName: 'Duka Asha',
        businessId: 'business',
        greetingVoice: voice,
        onRetry: () {},
        onChat: () {},
        onVoice: () {},
        onUsage: () {},
        onReport: () {},
      ),
    );
    await tester.pumpWidget(screen(true));
    await tester.pump();
    await tester.pump();
    expect(voice.spoken, hasLength(1));
    expect(voice.spoken.single, startsWith('sw:'));
    expect(voice.spoken.single, contains('Duka Asha'));
    expect(find.textContaining('Duka Asha'), findsNothing);
    expect(find.text('bi_tab_chat'.tr), findsNothing);
    await tester.pumpWidget(screen(false));
    await tester.pump();
    expect(voice.spoken, hasLength(1));
    expect(find.text('bi_tab_chat'.tr), findsOneWidget);
  });

  testWidgets('greets business once and stops on chat navigation', (
    tester,
  ) async {
    final voice = FakeGreetingVoice();
    var chats = 0;
    Widget screen({bool ready = true, String name = 'Duka Asha'}) =>
        GetMaterialApp(
          translations: AppTranslations(),
          locale: const Locale('sw', 'TZ'),
          home: IsherWelcomeScreen(
            loading: !ready,
            error: '',
            ready: ready,
            businessName: name,
            businessId: 'business',
            greetingReady: ready,
            greetingVoice: voice,
            onRetry: () {},
            onChat: () => chats++,
            onVoice: () {},
            onUsage: () {},
            onReport: () {},
          ),
        );
    await tester.pumpWidget(screen(ready: false));
    await tester.pump();
    expect(voice.spoken, isEmpty);
    await tester.pumpWidget(screen());
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Duka Asha'), findsNothing);
    expect(voice.spoken, hasLength(1));
    expect(voice.spoken.single, startsWith('sw:'));
    expect(voice.spoken.single, contains('Duka Asha'));
    await tester.pumpWidget(screen());
    await tester.pump();
    expect(voice.spoken, hasLength(1));
    await tester.ensureVisible(find.text('bi_tab_chat'.tr));
    await tester.tap(find.text('bi_tab_chat'.tr));
    expect(chats, 1);
    expect(voice.stops, greaterThanOrEqualTo(2));
  });

  testWidgets('uses a different greeting when entering Isher again', (
    tester,
  ) async {
    final voice = FakeGreetingVoice();
    Widget screen() => GetMaterialApp(
      translations: AppTranslations(),
      locale: const Locale('sw', 'TZ'),
      home: IsherWelcomeScreen(
        loading: false,
        ready: true,
        greetingReady: true,
        error: '',
        businessName: 'Duka Asha',
        businessId: 'business',
        greetingVoice: voice,
        onRetry: () {},
        onChat: () {},
        onVoice: () {},
        onUsage: () {},
        onReport: () {},
      ),
    );

    await tester.pumpWidget(screen());
    await tester.pump();
    await tester.pump();
    final firstGreeting = voice.spoken.single;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(screen());
    await tester.pump();
    await tester.pump();

    expect(voice.spoken, hasLength(2));
    expect(voice.spoken.last, isNot(firstGreeting));
  });

  testWidgets('shows an audio error without a business name', (tester) async {
    final voice = FakeGreetingVoice()..fail = true;
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: IsherWelcomeScreen(
          loading: false,
          error: '',
          ready: true,
          businessName: '',
          businessId: 'business',
          greetingReady: true,
          greetingVoice: voice,
          onRetry: () {},
          onChat: () {},
          onVoice: () {},
          onUsage: () {},
          onReport: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Habari! Naitwa Isher AI.'), findsNothing);
    expect(find.textContaining('Sauti haipatikani'), findsOneWidget);
  });

  testWidgets('a delayed greeting does not speak after leaving', (
    tester,
  ) async {
    final voice = FakeGreetingVoice()..waiting = Completer<void>();
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: IsherWelcomeScreen(
          loading: false,
          error: '',
          ready: true,
          businessName: 'Duka',
          businessId: 'business',
          greetingReady: true,
          greetingVoice: voice,
          onRetry: () {},
          onChat: () {},
          onVoice: () {},
          onUsage: () {},
          onReport: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(find.text('bi_tab_chat'.tr));
    await tester.tap(find.text('bi_tab_chat'.tr));
    voice.waiting!.complete();
    await tester.pump();
    expect(voice.spoken, isEmpty);
  });

  testWidgets('a delayed greeting does not speak after access is removed', (
    tester,
  ) async {
    final voice = FakeGreetingVoice()..waiting = Completer<void>();
    Widget screen(bool access) => GetMaterialApp(
      translations: AppTranslations(),
      locale: const Locale('sw', 'TZ'),
      home: IsherWelcomeScreen(
        loading: false,
        error: '',
        ready: access,
        greetingReady: access,
        businessName: 'Duka',
        businessId: access ? 'business' : null,
        greetingVoice: voice,
        onRetry: () {},
        onChat: () {},
        onVoice: () {},
        onUsage: () {},
        onReport: () {},
      ),
    );
    await tester.pumpWidget(screen(true));
    await tester.pump();
    await tester.pumpWidget(screen(false));
    voice.waiting!.complete();
    await tester.pump();
    expect(voice.spoken, isEmpty);
  });
}
