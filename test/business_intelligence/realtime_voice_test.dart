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

  @override
  Future<AiSnapshot> prepare(BusinessContext context) async {
    preparations++;
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
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Kubali na uanze'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
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

  testWidgets('voice requires review and cancellation does not start session', (
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
    await tester.pump(const Duration(seconds: 1));
    expect(provider.preparations, 1);
    expect(find.text('Kagua na uanze mazungumzo ya sauti'), findsOneWidget);
    expect(find.textContaining('Jina la biashara'), findsOneWidget);
    expect(find.text('Kubali na uanze'), findsOneWidget);
    current.value = false;
    await tester.pump();
    expect(find.text('Kubali na uanze'), findsNothing);
    await tester.tap(find.text('cancel'.tr));
    await tester.pump(const Duration(milliseconds: 300));
    expect(sessionCreated, isFalse);
    expect(
      find.text('Kipaza sauti kiko wazi. Sauti yako inatumwa kwa OpenAI.'),
      findsNothing,
    );
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
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Kubali na uanze'));
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
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Kubali na uanze'));
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
