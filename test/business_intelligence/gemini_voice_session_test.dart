import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:tra_list/business_intelligence/ai_provider.dart';
import 'package:tra_list/business_intelligence/business_context.dart';
import 'package:tra_list/business_intelligence/gemini_voice_session.dart';
import 'package:tra_list/business_intelligence/retained_gemini_voice.dart';
import 'package:tra_list/services/business_access_service.dart';

class _DeniedRecorder implements AudioRecorder {
  _DeniedRecorder([this.permission]);

  final Future<bool>? permission;
  bool disposed = false;

  @override
  Future<bool> hasPermission({bool request = true}) async =>
      await (permission ?? Future.value(false));

  @override
  Future<String?> stop() async => null;

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StreamingRecorder implements AudioRecorder {
  StreamController<Uint8List>? audio;
  Completer<void>? startGate;
  int starts = 0;
  int stops = 0;
  bool disposed = false;

  @override
  Future<bool> hasPermission({bool request = true}) async => true;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    starts++;
    await startGate?.future;
    audio = StreamController<Uint8List>();
    return audio!.stream;
  }

  @override
  Future<String?> stop() async {
    stops++;
    await audio?.close();
    return null;
  }

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Socket implements WebSocket {
  final incoming = StreamController<dynamic>();
  final sent = <Map<String, dynamic>>[];
  bool closed = false;

  @override
  int? get closeCode => closed ? 1000 : null;

  @override
  void add(dynamic data) {
    final message = Map<String, dynamic>.from(
      jsonDecode(data as String) as Map,
    );
    sent.add(message);
    if (message.containsKey('setup')) {
      incoming.add(jsonEncode({'setupComplete': {}}));
    }
  }

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => incoming.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  Future close([int? code, String? reason]) async {
    closed = true;
    await incoming.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BusinessContext _business({String id = 'business', int month = 1}) =>
    BusinessContext(
      businessId: id,
      businessName: 'Duka',
      period: ReportingPeriod(DateTime(2026, month), DateTime(2026, month + 1)),
      updatedAt: DateTime(2026),
      income: 0,
      expenses: 0,
      transactionCount: 0,
      expenseCategories: const {},
      lowStock: null,
      receivable: null,
      payable: null,
      limitations: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Gemini speech indicator follows queued audio and interruption', (
    tester,
  ) async {
    final events = <bool>[];
    var now = DateTime(2026);
    final indicator = GeminiPlaybackIndicator(events.add, clock: () => now);
    indicator.addSamples(24000);
    expect(events, [true]);
    await tester.pump(const Duration(milliseconds: 300));
    now = now.add(const Duration(milliseconds: 300));
    indicator.addSamples(24000);
    expect(events, [true]);
    await tester.pump(const Duration(milliseconds: 800));
    expect(events, [true]);
    await tester.pump(const Duration(milliseconds: 900));
    expect(events, [true, false]);
    indicator.addSamples(24000);
    expect(events, [true, false, true]);
    indicator.stop();
    expect(events, [true, false, true, false]);
    await tester.pump(const Duration(seconds: 3));
    expect(events, [true, false, true, false]);
    indicator.addSamples(2400);
    await tester.pump(const Duration(milliseconds: 120));
    expect(events, [true, false, true, false, true, false]);
  });
  test(
    'Gemini tool responses preserve call ids and return actual data',
    () async {
      final result = await geminiToolResponses(
        [
          {
            'id': 'call-1',
            'name': 'get_business_summary',
            'args': {'period': 'yesterday'},
          },
        ],
        (name, args) async {
          expect(name, 'get_business_summary');
          expect(args['period'], 'yesterday');
          return {
            'summary': {
              'pos': {'total': 12345},
            },
          };
        },
      );
      expect(result, [
        {
          'id': 'call-1',
          'name': 'get_business_summary',
          'response': {
            'summary': {
              'pos': {'total': 12345},
            },
          },
        },
      ]);
      await expectLater(
        geminiToolResponses([
          {'name': 'missing-id'},
        ], null),
        throwsFormatException,
      );
    },
  );
  test(
    'denied microphone permission stops before requesting a voice grant',
    () async {
      final recorder = _DeniedRecorder();
      final session = GeminiVoiceSession(
        (_) {},
        (_) {},
        recorderFactory: () => recorder,
      );
      await expectLater(
        session.connect(
          endpoint: Uri(),
          snapshot: const AiSnapshot({}, 'snapshot'),
          businessId: 'business',
          language: 'sw',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Microphone permission denied',
          ),
        ),
      );
      await session.close();
      expect(recorder.disposed, isTrue);
    },
  );

  test(
    'closing during permission request does not request a voice grant',
    () async {
      final permission = Completer<bool>();
      final recorder = _DeniedRecorder(permission.future);
      final session = GeminiVoiceSession(
        (_) {},
        (_) {},
        recorderFactory: () => recorder,
      );
      final connection = session.connect(
        endpoint: Uri(),
        snapshot: const AiSnapshot({}, 'snapshot'),
        businessId: 'business',
        language: 'sw',
      );
      final expectation = expectLater(
        connection,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Voice session closed',
          ),
        ),
      );
      await session.close();
      permission.complete(true);
      await expectation;
      expect(recorder.disposed, isTrue);
    },
  );

  test('missing audio plugin fails before requesting a voice grant', () async {
    const channel = MethodChannel('flutter_pcm_sound/methods');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setup') {
            throw MissingPluginException('Audio plugin unavailable');
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final recorder = _DeniedRecorder(Future.value(true));
    final session = GeminiVoiceSession(
      (_) {},
      (_) {},
      recorderFactory: () => recorder,
    );
    await expectLater(
      session.connect(
        endpoint: Uri(),
        snapshot: const AiSnapshot({}, 'snapshot'),
        businessId: 'business',
        language: 'sw',
      ),
      throwsA(isA<MissingPluginException>()),
    );
    await session.close();
    expect(recorder.disposed, isTrue);
  });

  test('pause releases microphone and resumes without another grant', () async {
    const channel = MethodChannel('flutter_pcm_sound/methods');
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final recorder = _StreamingRecorder();
    final socket = _Socket();
    var grants = 0;
    final session = GeminiVoiceSession(
      (_) {},
      (_) {},
      recorderFactory: () => recorder,
      grantFactory: (_, __, ___) async {
        grants++;
        return {
          'token': 'grant',
          'model': 'model',
          'instruction': '',
          'minutes': 5,
        };
      },
      socketFactory: (_) async => socket,
    );
    await session.connect(
      endpoint: Uri(),
      snapshot: const AiSnapshot({}, 'snapshot'),
      businessId: 'business',
      language: 'sw',
    );
    expect(recorder.starts, 1);
    recorder.audio!.add(Uint8List.fromList([0, 0]));
    await Future<void>.delayed(Duration.zero);
    final audioBeforePause = socket.sent
        .where(
          (item) =>
              (item['realtimeInput'] as Map?)?.containsKey('audio') == true,
        )
        .length;
    expect(audioBeforePause, 1);
    await session.pause();
    expect(recorder.stops, 1);
    expect(socket.closed, isFalse);
    expect(calls, contains('release'));
    expect(await session.resume(() => true), isTrue);
    expect(grants, 1);
    expect(recorder.starts, 2);
    recorder.audio!.add(Uint8List.fromList([0, 0]));
    await Future<void>.delayed(Duration.zero);
    expect(
      socket.sent
          .where(
            (item) =>
                (item['realtimeInput'] as Map?)?.containsKey('audio') == true,
          )
          .length,
      2,
    );
    await session.close();
    expect(recorder.stops, 2);
    expect(recorder.disposed, isTrue);
    expect(socket.closed, isTrue);
  });

  test('cancelled resume stops microphone before transmitting', () async {
    const channel = MethodChannel('flutter_pcm_sound/methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final recorder = _StreamingRecorder();
    final socket = _Socket();
    final session = GeminiVoiceSession(
      (_) {},
      (_) {},
      recorderFactory: () => recorder,
      grantFactory: (_, __, ___) async => {
        'token': 'grant',
        'model': 'model',
        'instruction': '',
        'minutes': 5,
      },
      socketFactory: (_) async => socket,
    );
    await session.connect(
      endpoint: Uri(),
      snapshot: const AiSnapshot({}, 'snapshot'),
      businessId: 'business',
      language: 'sw',
    );
    await session.pause();
    recorder.startGate = Completer<void>();
    var allowed = true;
    final resuming = session.resume(() => allowed);
    while (recorder.starts < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    allowed = false;
    recorder.startGate!.complete();
    expect(await resuming, isFalse);
    expect(recorder.stops, 2);
    expect(
      socket.sent.where(
        (item) => (item['realtimeInput'] as Map?)?.containsKey('audio') == true,
      ),
      isEmpty,
    );
    await session.close();
  });

  test('provider disconnect while paused ends the retained session', () async {
    const channel = MethodChannel('flutter_pcm_sound/methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final recorder = _StreamingRecorder();
    final socket = _Socket();
    final ended = <String>[];
    final session = GeminiVoiceSession(
      ended.add,
      (_) {},
      recorderFactory: () => recorder,
      grantFactory: (_, __, ___) async => {
        'token': 'grant',
        'model': 'model',
        'instruction': '',
        'minutes': 5,
      },
      socketFactory: (_) async => socket,
    );
    await session.connect(
      endpoint: Uri(),
      snapshot: const AiSnapshot({}, 'snapshot'),
      businessId: 'business',
      language: 'sw',
    );
    await session.pause();
    await socket.incoming.close();
    expect(ended, ['bi_voice_connection_error']);
    await session.close();
  });

  test('closing during resume stops the restarted microphone', () async {
    const channel = MethodChannel('flutter_pcm_sound/methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final recorder = _StreamingRecorder();
    final socket = _Socket();
    final session = GeminiVoiceSession(
      (_) {},
      (_) {},
      recorderFactory: () => recorder,
      grantFactory: (_, __, ___) async => {
        'token': 'grant',
        'model': 'model',
        'instruction': '',
        'minutes': 5,
      },
      socketFactory: (_) async => socket,
    );
    await session.connect(
      endpoint: Uri(),
      snapshot: const AiSnapshot({}, 'snapshot'),
      businessId: 'business',
      language: 'sw',
    );
    await session.pause();
    recorder.startGate = Completer<void>();
    final resuming = session.resume(() => true);
    final expectation = expectLater(resuming, throwsStateError);
    while (recorder.starts < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    final closing = session.close();
    recorder.startGate!.complete();
    await expectation;
    await closing;
    expect(recorder.stops, 2);
    expect(recorder.disposed, isTrue);
    expect(socket.closed, isTrue);
    expect(
      socket.sent.where(
        (item) => (item['realtimeInput'] as Map?)?.containsKey('audio') == true,
      ),
      isEmpty,
    );
  });

  test(
    'retained session can be taken only by same account and period',
    () async {
      const channel = MethodChannel('flutter_pcm_sound/methods');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final auth = StreamController<String?>.broadcast();
      addTearDown(auth.close);
      final retention = GeminiVoiceRetention.testing(auth.stream);
      addTearDown(retention.discard);
      final recorder = _StreamingRecorder();
      final socket = _Socket();
      var grants = 0;
      var oldCallbacks = 0;
      final session = GeminiVoiceSession(
        (_) => oldCallbacks++,
        (_) => oldCallbacks++,
        recorderFactory: () => recorder,
        grantFactory: (_, __, ___) async {
          grants++;
          return {
            'token': 'grant',
            'model': 'model',
            'instruction': '',
            'minutes': 5,
          };
        },
        socketFactory: (_) async => socket,
      );
      await session.connect(
        endpoint: Uri(),
        snapshot: const AiSnapshot({}, 'snapshot'),
        businessId: 'business',
        language: 'sw',
      );
      oldCallbacks = 0;
      retention.retain(session, _business(), 'user', 'scope');
      final retained = retention.take(_business(), 'different-user');
      expect(retained, isNull);
      expect(retention.available(_business(month: 2), 'user'), isFalse);
      final resumed = retention.take(_business(), 'user');
      expect(resumed, isNotNull);
      await resumed!.pausing;
      expect(oldCallbacks, 0);
      expect(recorder.stops, 1);
      expect(await session.resume(() => true), isTrue);
      expect(grants, 1);
      expect(socket.closed, isFalse);
      await session.close();
    },
  );

  test('retained voice closes when business access changes', () async {
    const channel = MethodChannel('flutter_pcm_sound/methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final auth = StreamController<String?>.broadcast();
    addTearDown(auth.close);
    final retention = GeminiVoiceRetention.testing(auth.stream);
    addTearDown(retention.discard);
    final recorder = _StreamingRecorder();
    final socket = _Socket();
    final session = GeminiVoiceSession(
      (_) {},
      (_) {},
      recorderFactory: () => recorder,
      grantFactory: (_, __, ___) async => {
        'token': 'grant',
        'model': 'model',
        'instruction': '',
        'minutes': 5,
      },
      socketFactory: (_) async => socket,
    );
    await session.connect(
      endpoint: Uri(),
      snapshot: const AiSnapshot({}, 'snapshot'),
      businessId: 'business',
      language: 'sw',
    );
    retention.retain(session, _business(), 'user', 'scope');
    BusinessAccessService.businessUid.value = 'changed-business';
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(retention.available(_business(), 'user'), isFalse);
    expect(socket.closed, isTrue);
    expect(recorder.disposed, isTrue);
    BusinessAccessService.businessUid.value = '';
  });

  test('retained voice closes on account change', () async {
    const channel = MethodChannel('flutter_pcm_sound/methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final auth = StreamController<String?>.broadcast();
    addTearDown(auth.close);
    final retention = GeminiVoiceRetention.testing(auth.stream);
    addTearDown(retention.discard);
    final recorder = _StreamingRecorder();
    final socket = _Socket();
    final session = GeminiVoiceSession(
      (_) {},
      (_) {},
      recorderFactory: () => recorder,
      grantFactory: (_, __, ___) async => {
        'token': 'grant',
        'model': 'model',
        'instruction': '',
        'minutes': 5,
      },
      socketFactory: (_) async => socket,
    );
    await session.connect(
      endpoint: Uri(),
      snapshot: const AiSnapshot({}, 'snapshot'),
      businessId: 'business',
      language: 'sw',
    );
    retention.retain(session, _business(), 'user', 'scope');
    auth.add('another-user');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(retention.available(_business(), 'user'), isFalse);
    expect(socket.closed, isTrue);
    expect(recorder.disposed, isTrue);
  });
}
