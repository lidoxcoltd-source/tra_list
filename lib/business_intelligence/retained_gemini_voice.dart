import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/business_context.dart';
import 'package:tra_list/business_intelligence/gemini_voice_session.dart';
import 'package:tra_list/services/business_access_service.dart';

class RetainedGeminiVoice {
  RetainedGeminiVoice({
    required this.session,
    required this.business,
    required this.uid,
    required this.scope,
    required this.pausing,
  });

  final GeminiVoiceSession session;
  final BusinessContext business;
  final String uid;
  final String scope;
  final Future<void> pausing;

  bool matches(BusinessContext other, String? currentUid) =>
      uid == currentUid &&
      business.businessId == other.businessId &&
      business.period.start == other.period.start &&
      business.period.end == other.period.end;
}

class GeminiVoiceRetention {
  GeminiVoiceRetention._()
    : _authChanges = (() =>
          FirebaseAuth.instance.authStateChanges().map((user) => user?.uid));

  @visibleForTesting
  GeminiVoiceRetention.testing(Stream<String?> authChanges)
    : _authChanges = (() => authChanges);

  static final instance = GeminiVoiceRetention._();
  final Stream<String?> Function() _authChanges;
  RetainedGeminiVoice? _retained;
  Worker? _accessWorker;
  StreamSubscription<String?>? _authSubscription;

  bool available(BusinessContext business, String? uid) =>
      _retained?.matches(business, uid) ?? false;

  void retain(
    GeminiVoiceSession session,
    BusinessContext business,
    String uid,
    String scope,
  ) {
    discard();
    session.setCallbacks(
      onEnded: (_) => discard(),
      onMicrophoneLevel: (_) {},
      onAiSpeaking: (_) {},
    );
    final pausing = session.pause();
    final retained = RetainedGeminiVoice(
      session: session,
      business: business,
      uid: uid,
      scope: scope,
      pausing: pausing,
    );
    _retained = retained;
    _accessWorker = everAll([
      BusinessAccessService.businessUid,
      BusinessAccessService.isActive,
      BusinessAccessService.isReady,
      BusinessAccessService.isOwner,
      BusinessAccessService.shopNickname,
      BusinessAccessService.permissions,
    ], (_) => discard());
    _authSubscription = _authChanges().listen(
      (currentUid) {
        if (currentUid != uid) discard();
      },
      onError: (Object error, StackTrace stack) {
        debugPrint('Retained voice auth check failed: ${error.runtimeType}');
        debugPrintStack(stackTrace: stack);
        discard();
      },
    );
    unawaited(
      pausing.catchError((Object error, StackTrace stack) {
        debugPrint('Retained voice pause failed: ${error.runtimeType}');
        debugPrintStack(stackTrace: stack);
        if (identical(_retained, retained)) discard();
      }),
    );
  }

  RetainedGeminiVoice? take(BusinessContext business, String? uid) {
    final retained = _retained;
    if (retained == null || !retained.matches(business, uid)) return null;
    _retained = null;
    _clearObservers();
    return retained;
  }

  void discard() {
    final retained = _retained;
    _retained = null;
    _clearObservers();
    if (retained != null) unawaited(retained.session.close());
  }

  void _clearObservers() {
    _accessWorker?.dispose();
    _accessWorker = null;
    unawaited(_authSubscription?.cancel());
    _authSubscription = null;
  }
}
