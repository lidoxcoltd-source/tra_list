import 'package:flutter/foundation.dart';

enum MarketUploadStatus { uploading, publishing, completed, failed }

class MarketUploadProgressState {
  const MarketUploadProgressState({
    required this.id,
    required this.status,
    this.progress = 0,
    this.error,
  });

  final int id;
  final MarketUploadStatus status;
  final double progress;
  final String? error;
}

class MarketUploadProgress {
  MarketUploadProgress._();

  static final ValueNotifier<MarketUploadProgressState?> state = ValueNotifier(
    null,
  );
  static int _nextId = 0;

  static bool get isActive =>
      state.value?.status == MarketUploadStatus.uploading ||
      state.value?.status == MarketUploadStatus.publishing;

  static int start() {
    final id = ++_nextId;
    state.value = MarketUploadProgressState(
      id: id,
      status: MarketUploadStatus.uploading,
    );
    return id;
  }

  static void update(int id, double progress) {
    if (state.value?.id != id) return;
    final normalizedProgress = progress.clamp(0, 1).toDouble();
    state.value = MarketUploadProgressState(
      id: id,
      status: normalizedProgress >= 1
          ? MarketUploadStatus.publishing
          : MarketUploadStatus.uploading,
      progress: normalizedProgress,
    );
  }

  static void publishing(int id) {
    if (state.value?.id != id) return;
    state.value = MarketUploadProgressState(
      id: id,
      status: MarketUploadStatus.publishing,
      progress: 1,
    );
  }

  static void complete(int id) {
    if (state.value?.id != id) return;
    state.value = MarketUploadProgressState(
      id: id,
      status: MarketUploadStatus.completed,
      progress: 1,
    );
  }

  static void fail(int id, Object error) {
    if (state.value?.id != id) return;
    state.value = MarketUploadProgressState(
      id: id,
      status: MarketUploadStatus.failed,
      error: error.toString(),
    );
  }

  static void dismiss(int id) {
    if (state.value?.id == id) state.value = null;
  }
}
