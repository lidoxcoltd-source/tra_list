import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/offline_service.dart';

class OfflineSyncCoordinator {
  OfflineSyncCoordinator._();

  static final Connectivity _connectivity = Connectivity();
  static StreamSubscription<List<ConnectivityResult>>?
  _connectivitySubscription;
  static StreamSubscription<User?>? _authSubscription;
  static Worker? _accessWorker;
  static Timer? _retryTimer;
  static bool _started = false;

  static Future<void> start() async {
    if (_started) return;
    _started = true;
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (results) {
        if (results.any((result) => result != ConnectivityResult.none)) {
          unawaited(syncIfReady());
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Offline sync connectivity listener failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    );
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      (user) {
        if (user != null) unawaited(syncIfReady());
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Offline sync auth listener failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    );
    _accessWorker = ever<bool>(BusinessAccessService.isReady, (ready) {
      if (ready) unawaited(syncIfReady());
    });
    _retryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(syncIfReady()),
    );
    await syncIfReady();
  }

  static Future<void> stop() async {
    await _connectivitySubscription?.cancel();
    await _authSubscription?.cancel();
    _accessWorker?.dispose();
    _retryTimer?.cancel();
    _connectivitySubscription = null;
    _authSubscription = null;
    _accessWorker = null;
    _retryTimer = null;
    _started = false;
  }

  static Future<void> syncIfReady() async {
    if (FirebaseAuth.instance.currentUser == null ||
        !BusinessAccessService.isReady.value ||
        !BusinessAccessService.isActive.value) {
      return;
    }

    try {
      final connections = await _connectivity.checkConnectivity();
      if (!connections.any((result) => result != ConnectivityResult.none)) {
        return;
      }
      final result = await OfflineService.syncPendingData();
      if (result.failureCount > 0) {
        debugPrint(
          'Offline sync left ${result.failureCount} item(s) pending: '
          '${result.errors.join('; ')}',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Offline sync attempt failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
