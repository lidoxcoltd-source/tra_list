import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tra_list/business_intelligence/business_context.dart';
import 'package:tra_list/business_intelligence/isher_greeting_voice.dart';
import 'package:tra_list/business_intelligence/isher_welcome_screen.dart';
import 'package:tra_list/invoice/app_translations.dart';
import 'package:tra_list/stock/daily_brief_weather_service.dart';

class FakeGreetingVoice implements IsherGreetingVoice {
  final spoken = <String>[];
  final spokenProviders = <String>[];
  int speakCalls = 0;
  int stops = 0;
  bool fail = false;
  Completer<void>? waiting;

  @override
  Future<void> speak(
    String text,
    String language,
    bool Function() isCurrent, {
    required int greetingVariant,
    required String provider,
  }) async {
    speakCalls++;
    if (waiting != null) await waiting!.future;
    if (!isCurrent()) return;
    if (fail) throw StateError('unavailable');
    spoken.add('$language:$text');
    spokenProviders.add(provider);
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

BusinessContext _businessContext() => BusinessContext(
  businessId: 'business',
  businessName: 'Duka Asha',
  period: ReportingPeriod(DateTime(2026, 11, 1), DateTime(2026, 12, 1)),
  updatedAt: DateTime.utc(2026, 11, 9),
  income: 120000,
  expenses: 30000,
  transactionCount: 8,
  expenseCategories: const {},
  lowStock: const ['Mchele (2 kg)'],
  receivable: 5000,
  payable: 0,
  limitations: const [],
);

Future<List<String>> _voiceProviders() async => ['gemini', 'openai'];

DailyBriefWeather _rainyWeather() => const DailyBriefWeather(
  temperatureC: 29,
  maxTemperatureC: 32,
  feelsLikeC: 31,
  precipitationChance: 70,
  weatherCode: 61,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('introduction is due on first use and after seven inactive days', () {
    final now = DateTime.utc(2026, 11, 9);
    expect(shouldIntroduceIsher(null, now), isTrue);
    expect(
      shouldIntroduceIsher(now.subtract(const Duration(days: 6)), now),
      isFalse,
    );
    expect(
      shouldIntroduceIsher(now.subtract(const Duration(days: 7)), now),
      isTrue,
    );
  });

  test(
    'welcome greeting uses Tanzania time and includes a business summary',
    () {
      final greeting = isherWelcomeGreeting(
        language: 'sw',
        name: 'Lidox',
        now: DateTime.utc(2026, 11, 9, 6),
        introduce: true,
        business: _businessContext(),
      );
      expect(greeting, contains('Habari Lidox, za asubuhi.'));
      expect(greeting, contains('Naitwa Isher AI'));
      expect(
        greeting,
        contains('Mapato yaliyorekodiwa ni shilingi laki moja na elfu ishirini.'),
      );
      expect(
        greeting,
        contains('Matumizi yaliyorekodiwa ni shilingi elfu thelathini.'),
      );
      expect(
        greeting,
        contains('Salio la fedha, si faida ni shilingi elfu tisini.'),
      );
      expect(greeting, contains('Bidhaa zenye akiba ndogo'));
    },
  );

  test('spoken summary includes local weather and practical actions', () {
    final greeting = isherWelcomeGreeting(
      language: 'sw',
      name: '',
      now: DateTime.utc(2026, 11, 9, 6),
      introduce: false,
      business: null,
      weather: _rainyWeather(),
    );

    expect(greeting, contains('Hali ya sasa katika eneo lako: Mvua.'));
    expect(greeting, contains('Uwezekano wa mvua leo ni 70%.'));
    expect(greeting, contains('Hatua za kuchukua:'));
    expect(greeting, contains('Beba mwamvuli'));
    expect(greeting, contains('kunywa maji ya kutosha'));
  });

  testWidgets('shows the listen-summary control with three capabilities', (
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
          voiceProvidersLoader: _voiceProviders,
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
    expect(find.text('Msaidizi wako Mahiri wa Biashara'), findsOneWidget);
    expect(find.text('Chambua biashara'), findsOneWidget);
    expect(find.text('Andaa rasimu za hati'), findsOneWidget);
    expect(find.text('Rekodi miamala'), findsOneWidget);
    expect(find.text('Mipangilio ya sauti'), findsNothing);
    expect(find.text('Sikiliza muhtasari'), findsOneWidget);
    expect(find.text('Modeli ya sauti ya muhtasari'), findsOneWidget);
    expect(find.text('Gemini'), findsOneWidget);
    expect(find.text('OpenAI'), findsOneWidget);
  });

  testWidgets('greeting remains paused until the summary is ready and played', (
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
        voiceProvidersLoader: _voiceProviders,
        greetingName: 'Lidox',
        businessContext: !loading ? _businessContext() : null,
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
    expect(voice.spoken, isEmpty);
    expect(find.textContaining('Duka Asha'), findsNothing);
    expect(find.text('bi_tab_chat'.tr), findsNothing);
    await tester.pumpWidget(screen(false));
    await tester.pump();
    await tester.pump();
    expect(voice.spoken, isEmpty);
    await tester.tap(find.text('Sikiliza muhtasari'));
    await tester.pump();
    await tester.pump();
    expect(voice.spoken, hasLength(1));
    expect(voice.spoken.single, contains('Habari Lidox, za'));
    expect(voice.spoken.single, contains('Muhtasari wa biashara yako'));
    expect(find.text('bi_tab_chat'.tr), findsOneWidget);
  });

  testWidgets('selected voice model is used when playback is requested', (
    tester,
  ) async {
    final voice = FakeGreetingVoice();
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
          voiceProvidersLoader: _voiceProviders,
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
    expect(voice.spoken, isEmpty);
    await tester.tap(find.text('OpenAI'));
    await tester.pump();
    await tester.tap(find.text('Sikiliza muhtasari'));
    await tester.pump();
    await tester.pump();

    expect(voice.spokenProviders, ['openai']);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('isher_greeting_provider__business'),
      'openai',
    );
  });

  testWidgets('loads local weather on play and speaks it in the summary', (
    tester,
  ) async {
    final voice = FakeGreetingVoice();
    var weatherRequests = 0;
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
          voiceProvidersLoader: _voiceProviders,
          weatherLoader: () async {
            weatherRequests++;
            return _rainyWeather();
          },
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
    expect(weatherRequests, 0);
    expect(voice.spoken, isEmpty);

    await tester.tap(find.text('Sikiliza muhtasari'));
    await tester.pump();
    await tester.pump();

    expect(weatherRequests, 1);
    expect(voice.spoken.single, contains('Hali ya sasa katika eneo lako: Mvua.'));
    expect(voice.spoken.single, contains('Beba mwamvuli'));
  });

  testWidgets('plays only on request and stops on chat navigation', (
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
            voiceProvidersLoader: _voiceProviders,
            greetingName: 'Lidox',
            businessContext: ready ? _businessContext() : null,
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
    expect(voice.spoken, isEmpty);
    await tester.tap(find.text('Sikiliza muhtasari'));
    await tester.pump();
    await tester.pump();
    expect(voice.spoken, hasLength(1));
    expect(voice.spoken.single, startsWith('sw:'));
    expect(voice.spoken.single, contains('Lidox'));
    expect(voice.spokenProviders, ['gemini']);
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
        voiceProvidersLoader: _voiceProviders,
        greetingName: 'Lidox',
        businessContext: _businessContext(),
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
    expect(voice.spoken, isEmpty);
    await tester.tap(find.text('Sikiliza muhtasari'));
    await tester.pump();
    await tester.pump();
    final firstGreeting = voice.spoken.single;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(screen());
    await tester.pump();
    await tester.pump();
    expect(voice.spoken, hasLength(1));
    await tester.tap(find.text('Sikiliza muhtasari'));
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
          voiceProvidersLoader: _voiceProviders,
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
    expect(voice.speakCalls, 0);
    await tester.tap(find.text('Sikiliza muhtasari'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Sauti ya AI haikuweza'), findsOneWidget);
  });

  testWidgets('listen button stops speech while playback is busy', (
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
          voiceProvidersLoader: _voiceProviders,
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
    expect(voice.speakCalls, 0);
    await tester.tap(find.text('Sikiliza muhtasari'));
    await tester.pump();
    expect(voice.speakCalls, 1);
    await tester.tap(find.text('Simamisha'));
    await tester.pump();
    expect(voice.stops, greaterThan(1));
    expect(find.text('Sikiliza muhtasari'), findsOneWidget);
    voice.waiting!.complete();
    await tester.pump();
    await tester.pump();
    expect(voice.spoken, isEmpty);
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
          greetingName: 'Lidox',
          greetingReady: true,
          voiceProvidersLoader: _voiceProviders,
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
    expect(voice.speakCalls, 0);
    await tester.tap(find.text('Sikiliza muhtasari'));
    await tester.pump();
    expect(voice.speakCalls, 1);
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
        voiceProvidersLoader: _voiceProviders,
        businessName: 'Duka',
        businessId: access ? 'business' : null,
        greetingName: 'Lidox',
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
    expect(voice.speakCalls, 0);
    await tester.tap(find.text('Sikiliza muhtasari'));
    await tester.pump();
    expect(voice.speakCalls, 1);
    await tester.pumpWidget(screen(false));
    voice.waiting!.complete();
    await tester.pump();
    expect(voice.spoken, isEmpty);
  });
}
