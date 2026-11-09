import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/ai_provider.dart';
import 'package:tra_list/business_intelligence/business_context.dart';
import 'package:tra_list/business_intelligence/realtime_voice.dart';
import 'package:tra_list/business_intelligence/voice_business_tools.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/invoice/app_translations.dart';

class _FirebaseCoreMock extends MockFirebaseApp {
  @override
  Future<List<CoreInitializeResponse>> initializeCore() async {
    final apps = await super.initializeCore();
    apps.single.options.projectId = 'tra-verify';
    return apps;
  }
}

class _Provider implements AIProvider {
  int preparations = 0;
  Completer<AiSnapshot>? nextPreparation;

  @override
  Future<AiSnapshot> prepare(BusinessContext context) async {
    preparations++;
    final pending = nextPreparation;
    nextPreparation = null;
    if (pending != null) return pending.future;
    return const AiSnapshot({'businessName': 'Duka'}, 'snapshot');
  }

  @override
  Future<String> respond({
    required BusinessContext context,
    required AiSnapshot snapshot,
    required List<Map<String, String>> messages,
    required String language,
    String? messageId,
  }) => throw UnimplementedError();
}

class _FakeVoiceSession implements VoiceSession {
  _FakeVoiceSession(this.onLevel, this.onSpeaking);
  final void Function(double?) onLevel;
  final void Function(bool) onSpeaking;
  bool muted = false;
  bool closed = false;

  @override
  Future<void> connect({
    required Uri endpoint,
    required AiSnapshot snapshot,
    required String businessId,
    required String language,
  }) async {}

  @override
  void setMuted(bool value) {
    muted = value;
    if (value) onLevel(0);
  }

  @override
  Future<void> close() async => closed = true;
}

BusinessContext _business() => BusinessContext(
  businessId: 'business',
  businessName: 'Duka',
  period: ReportingPeriod(DateTime(2024), DateTime(2024, 2)),
  updatedAt: DateTime(2024),
  income: 100,
  expenses: 10,
  transactionCount: 1,
  expenseCategories: const {},
  lowStock: null,
  receivable: null,
  payable: null,
  limitations: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    TestFirebaseCoreHostApi.setUp(_FirebaseCoreMock());
    await Firebase.initializeApp();
  });

  test(
    'voice endpoint is scoped to its Firebase project and can be overridden',
    () {
      expect(
        voiceServiceUrl('', 'tra-verify'),
        'wss://mjasi-ai-voice-903048450592.us-central1.run.app',
      );
      expect(voiceServiceUrl('', 'another-project'), isEmpty);
      expect(
        voiceServiceUrl('wss://custom.example', 'another-project'),
        'wss://custom.example',
      );
    },
  );

  test(
    'web voice uses browser-safe OpenAI signaling and supported engines',
    () {
      expect(voicePeerConfiguration(web: true)['iceServers'], [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]);
      expect(voicePeerConfiguration(web: false)['iceServers'], isEmpty);
      expect(voiceEnginesForPlatform(['gemini', 'openai'], web: true), [
        'openai',
      ]);
      expect(voiceEnginesForPlatform(['gemini', 'openai'], web: false), [
        'gemini',
        'openai',
      ]);
    },
  );

  test('microphone level uses only local audio source statistics', () {
    StatsReport report(String type, Map<String, dynamic> values) =>
        StatsReport('id', type, 0, values);
    expect(
      microphoneLevel([
        report('inbound-rtp', {'audioLevel': 0.9}),
      ]),
      isNull,
    );
    expect(
      microphoneLevel([
        report('media-source', {'kind': 'audio', 'audioLevel': 0.2}),
      ]),
      0.2,
    );
    expect(
      microphoneLevel([
        report('media-source', {'kind': 'audio', 'audioLevel': 2}),
      ]),
      1,
    );
    expect(
      microphoneLevel([
        report('media-source', {'kind': 'audio', 'audioLevel': double.nan}),
      ]),
      isNull,
    );
  });

  test('OpenAI output playback events identify AI speech', () {
    expect(openAiPlaybackState('output_audio_buffer.started'), isTrue);
    expect(openAiPlaybackState('output_audio_buffer.stopped'), isFalse);
    expect(openAiPlaybackState('output_audio_buffer.cleared'), isFalse);
    expect(openAiPlaybackState('response.done'), isNull);
  });

  test('voice summary includes business, selected period, and cash flow', () {
    final summary = voiceSummaryText({
      'businessName': 'Duka la Asha',
      'businessProfile': {
        'businessType': 'Retail',
        'businessDescription': 'Household goods',
      },
      'periodStart': '2024-01-01T00:00:00.000Z',
      'periodEndExclusive': '2024-02-01T00:00:00.000Z',
      'currency': 'TZS',
      'transactions': {'income': 120000, 'expenses': 30000, 'count': 8},
    }, language: 'sw');
    expect(summary, contains('Duka la Asha'));
    expect(summary, contains('Kipindi: 2024-01-01 hadi 2024-01-31'));
    expect(summary, contains('Mapato yaliyorekodiwa: TZS 120,000'));
    expect(summary, contains('Matumizi yaliyorekodiwa: TZS 30,000'));
    expect(summary, contains('Salio la fedha (si faida): TZS 90,000'));
  });

  test(
    'connection greeting explicitly requests audio in selected language',
    () {
      final sw = voiceConnectedGreeting('sw');
      final response = sw['response'] as Map<String, dynamic>;
      expect(sw['type'], 'response.create');
      expect(response['output_modalities'], ['audio']);
      expect(response['instructions'], contains('Kiswahili'));
      expect(
        (voiceConnectedGreeting('en')['response'] as Map)['instructions'],
        contains('English'),
      );
    },
  );

  testWidgets('orb follows microphone levels and resets on mute', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    late _FakeVoiceSession session;
    final current = true.obs;
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: Scaffold(
          body: BusinessRealtimeVoice(
            businessContext: _business(),
            isCurrent: () => current.value,
            provider: _Provider(),
            sessionFactory: (ended, level, speaking) =>
                session = _FakeVoiceSession(level, speaking),
          ),
        ),
      ),
    );
    Offset eyeOffset() {
      final matrix = tester
          .widget<Transform>(find.byKey(const ValueKey('voice_orb_eye')))
          .transform
          .storage;
      return Offset(matrix[12], matrix[13]);
    }

    final initialEye = eyeOffset();
    await tester.pump(const Duration(milliseconds: 600));
    expect(eyeOffset(), isNot(initialEye));
    await tester.tap(find.bySemanticsLabel('Anza sauti').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Kagua na uanze mazungumzo ya sauti'), findsNothing);
    double scale() => tester
        .widget<Transform>(find.byKey(const ValueKey('voice_orb_scale')))
        .transform
        .storage[0];
    Color orbColor() {
      final surface = tester.widget<Container>(
        find.byKey(const ValueKey('voice_orb_surface')),
      );
      final decoration = surface.decoration! as BoxDecoration;
      return (decoration.gradient! as RadialGradient).colors.first;
    }

    expect(scale(), 1);
    session.onLevel(0.25);
    await tester.pump();
    expect(scale(), closeTo(1.14, 0.001));
    session.onSpeaking(true);
    await tester.pump();
    expect(scale(), inInclusiveRange(1.02, 1.10));
    expect(orbColor(), const Color(0xFFB2FFF5));
    final speakingScale = scale();
    await tester.pump(const Duration(milliseconds: 120));
    expect(scale(), isNot(closeTo(speakingScale, 0.001)));
    session.onSpeaking(false);
    await tester.pump();
    expect(scale(), closeTo(1.14, 0.001));
    expect(orbColor(), const Color(0xFFB9A4FF));
    session.onLevel(null);
    await tester.pump();
    expect(
      find.text(
        'Kipimo cha sauti ya kipaza sauti hakipatikani kwenye kifaa hiki.',
      ),
      findsOneWidget,
    );
    expect(scale(), 1);
    session.onLevel(0.25);
    await tester.pump();
    await tester.ensureVisible(
      find.bySemanticsLabel('Zima kipaza sauti').first,
    );
    await tester.tap(find.bySemanticsLabel('Zima kipaza sauti').first);
    await tester.pump();
    expect(session.muted, isTrue);
    session.onSpeaking(true);
    await tester.pump();
    expect(orbColor(), const Color(0xFFB2FFF5));
    session.onSpeaking(false);
    await tester.pump();
    session.onLevel(0.3);
    await tester.pump();
    expect(scale(), lessThan(1.01));
    await tester.tap(find.bySemanticsLabel('Washa kipaza sauti').first);
    await tester.pump();
    expect(session.muted, isFalse);
    session.onLevel(0.1);
    await tester.pump();
    expect(scale(), closeTo(1.056, 0.001));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(session.closed, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('voice starts without a repeated privacy review dialog', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final provider = _Provider();
    final business = _business();
    final current = true.obs;
    var sessionCreated = false;
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: Scaffold(
          body: BusinessRealtimeVoice(
            businessContext: business,
            isCurrent: () => current.value,
            provider: provider,
            sessionFactory: (_, onLevel, onSpeaking) {
              sessionCreated = true;
              return _FakeVoiceSession(onLevel, onSpeaking);
            },
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Anza sauti').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(provider.preparations, 1);
    expect(find.text('Kagua na uanze mazungumzo ya sauti'), findsNothing);
    expect(find.text('Kubali na uanze'), findsNothing);
    expect(sessionCreated, isTrue);
    expect(find.text('Mazungumzo ya sauti'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('business summary lifts the orb and types the requested report', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    late VoiceToolHandler tools;
    final provider = _Provider();
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: Scaffold(
          body: BusinessRealtimeVoice(
            businessContext: _business(),
            isCurrent: () => true,
            provider: provider,
            sessionFactory: (_, level, speaking) =>
                _FakeVoiceSession(level, speaking),
            onToolsReady: (value) => tools = value,
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Anza sauti').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final orb = find.byKey(const ValueKey('voice_orb_surface'));
    final topBeforeSummary = tester.getTopLeft(orb).dy;

    final report = Completer<AiSnapshot>();
    provider.nextPreparation = report;
    final pending = tools('get_business_summary', {'period': 'selected'});
    await tester.pump();
    expect(
      find.text('Naendelea kuandaa ripoti ya biashara. Subiri kidogo.'),
      findsOneWidget,
    );
    report.complete(const AiSnapshot({'businessName': 'Duka'}, 'report-token'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Muhtasari wa biashara'), findsOneWidget);
    final typewriter = tester.widget<SelectableText>(
      find.descendant(
        of: find.byKey(const ValueKey('voice_summary_typewriter')),
        matching: find.byType(SelectableText),
      ),
    );
    expect(typewriter.data, isNot(contains('Duka')));
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.getTopLeft(orb).dy, lessThan(topBeforeSummary));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Duka'), findsOneWidget);
    await tester.tap(find.text('Funga'));
    await tester.pump(const Duration(milliseconds: 350));
    expect((await pending)['summary'], {'businessName': 'Duka'});
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'voice transaction review cancellation does not navigate or save',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      BusinessAccessService.businessUid.value = 'business';
      BusinessAccessService.isReady.value = true;
      BusinessAccessService.isActive.value = true;
      BusinessAccessService.isOwner.value = true;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        BusinessAccessService.businessUid.value = '';
        BusinessAccessService.isReady.value = false;
        BusinessAccessService.isActive.value = false;
        BusinessAccessService.isOwner.value = false;
      });
      late VoiceToolHandler tools;
      var navigated = false;
      final current = true.obs;
      await tester.pumpWidget(
        GetMaterialApp(
          translations: AppTranslations(),
          locale: const Locale('sw', 'TZ'),
          home: Scaffold(
            body: BusinessRealtimeVoice(
              businessContext: _business(),
              isCurrent: () => current.value,
              provider: _Provider(),
              sessionFactory: (_, level, speaking) =>
                  _FakeVoiceSession(level, speaking),
              onToolsReady: (value) => tools = value,
              onOpenTransaction: (_) => navigated = true,
            ),
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Anza sauti').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final pending = tools('review_transaction_draft', {
        'type': 'expense',
        'amount': 10000,
        'category': 'Kodi',
        'description': 'Kodi ya duka',
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Kagua rasimu ya muamala'), findsOneWidget);
      expect(find.textContaining('TZS 10000'), findsOneWidget);
      await tester.tap(find.text('cancel'.tr));
      await tester.pump(const Duration(milliseconds: 300));
      expect((await pending)['status'], contains('not saved'));
      expect(navigated, isFalse);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('voice page request asks for confirmation and respects cancel', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    late VoiceToolHandler tools;
    late _FakeVoiceSession session;
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: Scaffold(
          body: BusinessRealtimeVoice(
            businessContext: _business(),
            isCurrent: () => true,
            provider: _Provider(),
            sessionFactory: (_, level, speaking) =>
                session = _FakeVoiceSession(level, speaking),
            onToolsReady: (value) => tools = value,
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Anza sauti').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final pending = tools('open_app_page', {'destination': 'tasks'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Fungua ukurasa?'), findsOneWidget);
    expect(find.textContaining('Tasks'), findsOneWidget);
    await tester.tap(find.text('cancel'.tr));
    await tester.pump(const Duration(milliseconds: 300));
    expect((await pending)['status'], contains('cancelled'));
    expect(session.closed, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('orb respects reduced motion', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: BusinessRealtimeVoice(
              businessContext: _business(),
              isCurrent: () => true,
              provider: _Provider(),
              sessionFactory: (_, level, speaking) =>
                  _FakeVoiceSession(level, speaking),
            ),
          ),
        ),
      ),
    );
    final eye = find.byKey(const ValueKey('voice_orb_eye'));
    final initial = tester.widget<Transform>(eye).transform.storage.toList();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Transform>(eye).transform.storage, initial);
    debugDefaultTargetPlatformOverride = null;
  });
}
