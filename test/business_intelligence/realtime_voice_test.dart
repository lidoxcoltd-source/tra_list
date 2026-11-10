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
  _Provider({
    this.snapshot = const AiSnapshot({'businessName': 'Duka'}, 'snapshot'),
  });

  final AiSnapshot snapshot;
  int preparations = 0;
  ReportingPeriod? lastPreparedPeriod;
  Completer<AiSnapshot>? nextPreparation;

  @override
  Future<AiSnapshot> prepare(BusinessContext context) async {
    preparations++;
    lastPreparedPeriod = context.period;
    final pending = nextPreparation;
    nextPreparation = null;
    if (pending != null) return pending.future;
    return snapshot;
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
  final sentText = <String>[];
  void Function(String)? onTranscript;
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
  Future<void> sendText(String text) async {
    sentText.add(text);
  }

  @override
  void setTranscriptCallback(void Function(String text) callback) {
    onTranscript = callback;
  }

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
      'transactionDetails': {
        'total': 8,
        'truncated': true,
        'entries': [
          {
            'type': 'income',
            'amount': 120000,
            'description': 'Mauzo ya mchele',
          },
          {'type': 'expense', 'amount': 30000, 'description': 'Kodi'},
        ],
      },
    }, language: 'sw');
    expect(summary, contains('Duka la Asha'));
    expect(summary, contains('Kipindi: 2024-01-01 hadi 2024-01-31'));
    expect(summary, contains('Mapato yaliyorekodiwa: TZS 120,000'));
    expect(summary, contains('Matumizi yaliyorekodiwa: TZS 30,000'));
    expect(summary, contains('Salio la fedha (si faida): TZS 90,000'));
    expect(summary, contains('Mapato: Mauzo ya mchele - TZS 120,000'));
    expect(summary, contains('Inaonyesha miamala 2 kati ya 8'));
    final missingDetails = voiceSummaryText({
      'transactionDetails': {'total': 4, 'truncated': true, 'entries': []},
    }, language: 'sw');
    expect(missingDetails, contains('Maelezo ya miamala hayapatikani'));
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

  test('only plain business report requests use the selected period', () {
    for (final prompt in [
      'Nipe ripoti ya biashara yangu',
      'naomba riport',
      'Show me my business report',
    ]) {
      expect(isDefaultVoiceReportRequest(prompt), isTrue, reason: prompt);
    }
    for (final prompt in [
      'Nipe ripoti ya jana',
      'Nipe ripoti ya mauzo',
      'Nifundishe jinsi ya kutengeneza ripoti',
    ]) {
      expect(isDefaultVoiceReportRequest(prompt), isFalse, reason: prompt);
    }
    expect(
      voiceReportPeriod('Nipe muhtasari wa biashara yangu wa mwezi huu.'),
      'month',
    );
    expect(voiceReportPeriod('Nipe ripoti ya jana'), 'yesterday');
    expect(voiceReportPeriod('Nipe report za biashara za jana'), 'yesterday');
    expect(
      voiceReportArguments(
        'duka langu limefanya biashara gani leo?',
        DateTime(2026, 11, 10),
      ),
      {'period': 'today'},
    );
    expect(
      voiceReportArguments(
        'biashara yangu imefanya biashara gani jana?',
        DateTime(2026, 11, 10),
      ),
      {'period': 'yesterday'},
    );
    expect(
      voiceReportArguments(
        'duka langu linafanya biashara gani?',
        DateTime(2026, 11, 10),
      ),
      isNull,
    );
    expect(
      voiceReportArguments('za wiki nzima', DateTime(2026, 11, 10)),
      isNull,
    );
    expect(
      voiceReportArguments(
        'za wiki nzima',
        DateTime(2026, 11, 10),
        hasReportContext: true,
      ),
      {'period': 'seven'},
    );
    expect(
      voiceReportArguments(
        'na mwezi huu?',
        DateTime(2026, 11, 10),
        hasReportContext: true,
      ),
      {'period': 'month'},
    );
    expect(
      voiceReportArguments(
        'na jana?',
        DateTime(2026, 11, 10),
        hasReportContext: true,
      ),
      {'period': 'yesterday'},
    );
    expect(
      voiceReportArguments(
        'na tarehe 15/08/2024?',
        DateTime(2026, 11, 10),
        hasReportContext: true,
      ),
      {
        'period': 'custom',
        'start_date': '2024-08-15',
        'end_date': '2024-08-15',
      },
    );
    expect(
      voiceReportArguments('Nipe report ya wiki hii', DateTime(2026, 11, 10)),
      {
        'period': 'custom',
        'start_date': '2026-11-09',
        'end_date': '2026-11-10',
      },
    );
    expect(
      voiceReportArguments(
        'Nipe ripoti ya biashara ya tarehe 15/08/2024',
        DateTime(2026, 11, 10),
      ),
      {
        'period': 'custom',
        'start_date': '2024-08-15',
        'end_date': '2024-08-15',
      },
    );
    expect(
      voiceReportArguments(
        'Nipe ripoti ya biashara ya juzi',
        DateTime(2026, 11, 10),
      ),
      {
        'period': 'custom',
        'start_date': '2026-11-08',
        'end_date': '2026-11-08',
      },
    );
    expect(
      voiceReportArguments(
        'Nipe ripoti ya tarehe 2024-02-30',
        DateTime(2026, 11, 10),
      ),
      isNull,
    );
    expect(
      voiceReportArguments(
        'Nipe ripoti ya tarehe 2026-11-11',
        DateTime(2026, 11, 10),
      ),
      isNull,
    );
    expect(
      voiceReportArguments(
        'Nipe ripoti ya tarehe 15 agosti 2024',
        DateTime(2026, 11, 10),
      ),
      {
        'period': 'custom',
        'start_date': '2024-08-15',
        'end_date': '2024-08-15',
      },
    );
    expect(voiceReportPeriod('Nipe muhtasari wa mauzo ya mwezi huu'), isNull);
  });

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
    final screenAwakeStates = <bool>[];
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
            screenAwakeController: (enabled) async {
              screenAwakeStates.add(enabled);
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
    expect(screenAwakeStates, [true]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(screenAwakeStates, [true, false]);
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
    expect(find.text('Naandaa ripoti. Subiri kidogo.'), findsOneWidget);
    report.complete(const AiSnapshot({'businessName': 'Duka'}, 'report-token'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Muhtasari wa biashara'), findsOneWidget);
    expect(find.byKey(const ValueKey('voice_summary_dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice_summary_metrics')), findsNothing);
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

  testWidgets('summary dialog fits a compact screen with reduced motion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    });
    late VoiceToolHandler tools;
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 480),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: BusinessRealtimeVoice(
              businessContext: _business(),
              isCurrent: () => true,
              provider: _Provider(
                snapshot: const AiSnapshot({
                  'businessName': 'Duka',
                  'transactions': {'income': 120000, 'expenses': 30000},
                }, 'snapshot'),
              ),
              sessionFactory: (_, level, speaking) =>
                  _FakeVoiceSession(level, speaking),
              onToolsReady: (value) => tools = value,
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.bySemanticsLabel('Anza sauti').first);
    await tester.tap(find.bySemanticsLabel('Anza sauti').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final pending = tools('get_business_summary', {'period': 'selected'});
    await tester.pump();
    await tester.pump();
    final dialog = find.byKey(const ValueKey('voice_summary_dialog'));
    expect(dialog, findsOneWidget);
    expect(find.byKey(const ValueKey('voice_summary_metrics')), findsOneWidget);
    final text = tester.widget<SelectableText>(
      find.descendant(
        of: find.byKey(const ValueKey('voice_summary_typewriter')),
        matching: find.byType(SelectableText),
      ),
    );
    expect(text.data, contains('Duka'));
    expect(
      tester.getRect(dialog).contains(tester.getCenter(find.text('Funga'))),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Funga'));
    await tester.pump();
    expect((await pending)['summary'], isNotNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('voice transaction review only proceeds after confirmation', (
    tester,
  ) async {
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
    final confirmed = tools('review_transaction_draft', {
      'type': 'expense',
      'amount': 10000,
      'category': 'Kodi',
      'description': 'Kodi ya duka',
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Thibitisha na hifadhi'));
    await tester.pump(const Duration(milliseconds: 300));
    expect((await confirmed)['status'], contains('not saved'));
    expect(navigated, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

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

  testWidgets('voice guide button opens the localized help page', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
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
                _FakeVoiceSession(level, speaking),
          ),
        ),
      ),
    );
    final guideButton = find.byKey(const ValueKey('voice_guide_button'));
    await tester.ensureVisible(guideButton);
    await tester.tap(guideButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('Jinsi ya kuzungumza na Isher'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a typed business report opens the selected summary', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    late _FakeVoiceSession session;
    final provider = _Provider(
      snapshot: const AiSnapshot({
        'businessName': 'Duka',
        'periodStart': '2024-01-01T00:00:00.000Z',
        'periodEndExclusive': '2024-02-01T00:00:00.000Z',
        'transactions': {'income': 120000, 'expenses': 30000},
      }, 'snapshot'),
    );
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
                session = _FakeVoiceSession(level, speaking),
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Anza sauti').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byTooltip('Jaribu kwa maandishi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(
      find.byKey(const ValueKey('voice_text_prompt_input')),
      'Nipe ripoti ya biashara yangu',
    );
    final send = tester.widget<IconButton>(
      find.byKey(const ValueKey('voice_text_prompt_send')),
    );
    send.onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(provider.preparations, 2);
    expect(session.sentText.single, contains('Biashara: Duka'));
    expect(
      session.sentText.single,
      contains('Mapato yaliyorekodiwa: TZS 120,000'),
    );
    expect(
      session.sentText.single,
      contains('Matumizi yaliyorekodiwa: TZS 30,000'),
    );
    expect(session.sentText.single, contains('Answer directly'));
    expect(find.byKey(const ValueKey('voice_summary_metrics')), findsOneWidget);
    expect(find.text('TZS 120,000'), findsOneWidget);
    expect(find.text('TZS 30,000'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('voice_summary_typewriter')),
      findsOneWidget,
    );
    await tester.tap(find.text('close'.tr));
    await tester.pump(const Duration(milliseconds: 400));
    session.sentText.clear();
    final month = ReportingPeriod.fromKey('month', DateTime.now());
    provider.nextPreparation = Completer<AiSnapshot>()
      ..complete(
        AiSnapshot({
          'businessName': 'Duka',
          'periodStart': month.start.toIso8601String(),
          'periodEndExclusive': month.end.toIso8601String(),
          'transactions': {'income': 250000, 'expenses': 40000},
        }, 'snapshot'),
      );
    await tester.enterText(
      find.byKey(const ValueKey('voice_text_prompt_input')),
      'Nipe muhtasari wa biashara yangu wa mwezi huu.',
    );
    tester
        .widget<IconButton>(
          find.byKey(const ValueKey('voice_text_prompt_send')),
        )
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(provider.lastPreparedPeriod!.start, month.start);
    expect(provider.lastPreparedPeriod!.end, month.end);
    expect(session.sentText.single, contains('TZS 250,000'));
    expect(
      find.byKey(const ValueKey('voice_summary_typewriter')),
      findsOneWidget,
    );
    await tester.tap(find.text('close'.tr));
    await tester.pump(const Duration(milliseconds: 400));
    session.sentText.clear();
    for (final (question, period) in [
      (
        'Nipe report za biashara za jana',
        ReportingPeriod.fromKey('yesterday', DateTime.now()),
      ),
      ('za wiki nzima', ReportingPeriod.fromKey('seven', DateTime.now())),
      (
        'duka langu limefanya biashara gani leo?',
        ReportingPeriod.fromKey('today', DateTime.now()),
      ),
      (
        'Nipe ripoti ya biashara ya tarehe 15/08/2024',
        ReportingPeriod(DateTime(2024, 8, 15), DateTime(2024, 8, 16)),
      ),
    ]) {
      provider.nextPreparation = Completer<AiSnapshot>()
        ..complete(
          AiSnapshot({
            'businessName': 'Duka',
            'periodStart': period.start.toIso8601String(),
            'periodEndExclusive': period.end.toIso8601String(),
            'transactions': {'income': 75000, 'expenses': 10000},
            'transactionDetails': {
              'total': 1,
              'entries': [
                {
                  'type': 'income',
                  'amount': 75000,
                  'description': 'Mauzo ya mchele',
                },
              ],
            },
          }, 'snapshot'),
        );
      await tester.enterText(
        find.byKey(const ValueKey('voice_text_prompt_input')),
        question,
      );
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('voice_text_prompt_send')),
          )
          .onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(provider.lastPreparedPeriod!.start, period.start);
      expect(provider.lastPreparedPeriod!.end, period.end);
      expect(session.sentText.single, contains('TZS 75,000'));
      expect(session.sentText.single, contains(question));
      expect(session.sentText.single, contains('Mauzo ya mchele'));
      await tester.tap(find.text('close'.tr));
      await tester.pump(const Duration(milliseconds: 400));
      session.sentText.clear();
    }
    final unavailable = Completer<AiSnapshot>();
    provider.nextPreparation = unavailable;
    await tester.enterText(
      find.byKey(const ValueKey('voice_text_prompt_input')),
      'Nipe ripoti ya biashara yangu',
    );
    tester
        .widget<IconButton>(
          find.byKey(const ValueKey('voice_text_prompt_send')),
        )
        .onPressed!();
    await tester.pump();
    unavailable.completeError(StateError('Report unavailable'));
    await tester.pump();
    expect(session.sentText, isEmpty);
    expect(find.text('bi_voice_text_send_error'.tr), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('voice text test sends the question into the active call', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
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
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Anza sauti').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final orb = find.byKey(const ValueKey('voice_orb_surface'));
    final orbTopBefore = tester.getTopLeft(orb).dy;
    await tester.tap(find.byTooltip('Jaribu kwa maandishi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byKey(const ValueKey('voice_text_prompt_panel')),
      findsOneWidget,
    );
    expect(session.muted, isTrue);
    expect(
      tester
          .widget<SingleChildScrollView>(
            find.byType(SingleChildScrollView).first,
          )
          .physics,
      isA<NeverScrollableScrollPhysics>(),
    );
    expect(tester.getTopLeft(orb).dy, lessThan(orbTopBefore));
    expect(
      tester
          .widget<AnimatedScale>(
            find.byKey(const ValueKey('voice_orb_mode_scale')),
          )
          .scale,
      lessThan(1),
    );
    final input = find.byKey(const ValueKey('voice_text_prompt_input'));
    expect(
      find.descendant(
        of: input,
        matching: find.byKey(const ValueKey('voice_text_prompt_send')),
      ),
      findsOneWidget,
    );
    await tester.enterText(input, 'Nipe mapato ya mwezi huu');
    expect(
      tester.widget<TextField>(input).controller!.text,
      'Nipe mapato ya mwezi huu',
    );
    final sendButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('voice_text_prompt_send')),
    );
    expect(sendButton.onPressed, isNotNull);
    sendButton.onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(session.sentText, ['Nipe mapato ya mwezi huu']);
    session.onTranscript?.call('Mapato ya mwezi huu ni TZS 500,000.');
    await tester.pump();
    expect(find.text('Mapato ya mwezi huu ni TZS 500,000.'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('voice_transcript_feed'))).dy,
      greaterThan(tester.getTopLeft(input).dy),
    );
    expect(find.byKey(const ValueKey('voice_transcript_fade')), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('voice_text_prompt_panel')),
        matching: find.byTooltip('close'.tr),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(session.muted, isFalse);

    await tester.tap(find.bySemanticsLabel('Zima kipaza sauti').first);
    await tester.pump();
    expect(session.muted, isTrue);
    await tester.tap(find.byTooltip('Jaribu kwa maandishi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(session.muted, isTrue);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('voice_text_prompt_panel')),
        matching: find.byTooltip('close'.tr),
      ),
    );
    await tester.pump();
    expect(session.muted, isTrue);
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

  testWidgets('orb eyelid briefly closes then opens', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
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
                _FakeVoiceSession(level, speaking),
          ),
        ),
      ),
    );
    final eyelid = find.byKey(const ValueKey('voice_orb_blink'));
    double eyeHeightScale() =>
        tester.widget<Transform>(eyelid).transform.storage[5];

    expect(eyeHeightScale(), 1);
    await tester.pump(const Duration(milliseconds: 1801));
    await tester.pump(const Duration(milliseconds: 35));
    expect(eyeHeightScale(), lessThan(0.9));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(eyeHeightScale(), greaterThan(0.9));
    debugDefaultTargetPlatformOverride = null;
  });
}
