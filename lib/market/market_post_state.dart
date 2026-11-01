import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'market_models.dart';
import 'market_service.dart';

/// Saved posts and followed accounts of the signed-in user, listened to once
/// for the whole app instead of once per post tile.
class MarketUserSets {
  MarketUserSets._();

  static final MarketUserSets instance = MarketUserSets._();

  final ValueNotifier<Set<String>> saved = ValueNotifier(const {});
  final ValueNotifier<Set<String>> following = ValueNotifier(const {});

  String? _uid;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _savedSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _followingSub;

  void ensureStarted() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == _uid) return;
    unawaited(_savedSub?.cancel());
    unawaited(_followingSub?.cancel());
    _savedSub = null;
    _followingSub = null;
    _uid = uid;
    saved.value = const {};
    following.value = const {};
    if (uid == null) return;
    final db = FirebaseFirestore.instance;
    _savedSub = db
        .collection('marketSavedPosts')
        .doc(uid)
        .collection('items')
        .snapshots()
        .listen(
          (snapshot) => saved.value = {for (final d in snapshot.docs) d.id},
          onError: (_) {},
        );
    _followingSub = db
        .collection('marketFollows')
        .doc(uid)
        .collection('following')
        .snapshots()
        .listen(
          (snapshot) => following.value = {for (final d in snapshot.docs) d.id},
          onError: (_) {},
        );
  }
}

/// Live post document plus whether the current user liked it.
class MarketPostLive {
  const MarketPostLive({required this.post, this.liked = false});

  final MarketPost post;
  final bool liked;
}

/// One stream per post tile (post counters + like state) instead of two.
Stream<MarketPostLive> watchMarketPostLive(MarketPost initial) {
  late final StreamController<MarketPostLive> controller;
  StreamSubscription<MarketPost?>? postSub;
  StreamSubscription<bool>? likeSub;
  var live = MarketPostLive(post: initial);

  void emit(MarketPostLive next) {
    live = next;
    if (!controller.isClosed) controller.add(live);
  }

  controller = StreamController<MarketPostLive>(
    onListen: () {
      postSub = MarketService.watchPost(initial.id).listen(
        (post) =>
            emit(MarketPostLive(post: post ?? live.post, liked: live.liked)),
        onError: controller.addError,
      );
      likeSub = MarketService.watchLike(initial.id).listen(
        (liked) => emit(MarketPostLive(post: live.post, liked: liked)),
        onError: controller.addError,
      );
    },
    onCancel: () async {
      await postSub?.cancel();
      await likeSub?.cancel();
    },
  );
  return controller.stream;
}
