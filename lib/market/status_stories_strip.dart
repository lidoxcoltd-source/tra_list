import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import 'market_order_dialog.dart';
import 'market_palette.dart';
import 'market_text_card.dart';
import 'market_models.dart';
import 'market_avatar.dart';
import 'market_audio.dart';
import 'market_video.dart';
import 'market_service.dart';

class StatusStoriesStrip extends StatefulWidget {
  const StatusStoriesStrip({super.key, required this.onCreateStatus});

  final VoidCallback onCreateStatus;

  @override
  State<StatusStoriesStrip> createState() => _StatusStoriesStripState();
}

class _StatusStoriesStripState extends State<StatusStoriesStrip> {
  late Future<List<MarketStatusGroup>> _statuses;

  /// Index of the first unseen status per author, so playback resumes there.
  Map<String, int> _startIndexes = {};

  Future<List<MarketStatusGroup>> _loadOrdered() async {
    final groups = await MarketService.searchActiveStatuses();
    final viewed = await Future.wait(
      groups.map(
        (group) => Future.wait(
          group.statuses.map(
            (post) => MarketService.watchStatusViewed(
              post.id,
            ).first.catchError((_) => false),
          ),
        ),
      ),
    );
    final starts = <String, int>{};
    final unseen = <MarketStatusGroup>[];
    final seen = <MarketStatusGroup>[];
    for (var i = 0; i < groups.length; i++) {
      final first = viewed[i].indexWhere((value) => !value);
      if (first < 0) {
        seen.add(groups[i]);
      } else {
        starts[groups[i].authorUid] = first;
        unseen.add(groups[i]);
      }
    }
    _startIndexes = starts;
    // Groups with new statuses first, fully seen ones last; each newest first.
    return [...unseen, ...seen];
  }

  @override
  void initState() {
    super.initState();
    _statuses = _loadOrdered();
  }

  Future<void> _reload() async {
    final next = _loadOrdered();
    setState(() {
      _statuses = next;
    });
    await next;
  }

  Future<void> _openStatus(List<MarketStatusGroup> statuses, int index) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MarketStatusViewer(
          group: statuses[index],
          nextGroups: statuses.sublist(index + 1),
          startIndexes: _startIndexes,
        ),
      ),
    );
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final ownName = (user?.displayName ?? '').trim();
    return SizedBox(
      height: 116,
      child: FutureBuilder<List<MarketStatusGroup>>(
        future: _statuses,
        builder: (context, snapshot) {
          final statuses = snapshot.data ?? const <MarketStatusGroup>[];
          return ListView.separated(
            padding: const EdgeInsets.symmetric(
              horizontal: MjasiSpacing.md,
              vertical: MjasiSpacing.sm,
            ),
            scrollDirection: Axis.horizontal,
            itemCount: statuses.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: MjasiSpacing.md),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _StoryAvatar(
                  name: ownName.isEmpty ? 'market_your_story'.tr : ownName,
                  uid: user?.uid ?? '',
                  imageUrl: user?.photoURL ?? '',
                  isOwn: true,
                  onTap: widget.onCreateStatus,
                );
              }
              final status = statuses[index - 1];
              return _StoryAvatar(
                name: status.authorName,
                uid: status.authorUid,
                imageUrl: status.authorPhotoUrl,
                isOwn: false,
                viewedStream: MarketService.watchStatusViewed(
                  status.statuses.last.id,
                ),
                onTap: () => _openStatus(statuses, index - 1),
              );
            },
          );
        },
      ),
    );
  }
}

class _StoryAvatar extends StatelessWidget {
  const _StoryAvatar({
    required this.name,
    required this.uid,
    required this.imageUrl,
    required this.isOwn,
    this.viewedStream,
    required this.onTap,
  });

  final String name;
  final String uid;
  final String imageUrl;
  final bool isOwn;
  final Stream<bool>? viewedStream;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 70,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MjasiRadius.md),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                StreamBuilder<bool>(
                  stream: viewedStream,
                  builder: (context, snapshot) => Container(
                    width: 62,
                    height: 62,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isOwn
                            ? MarketPalette.border
                            : snapshot.data == true
                            ? MarketPalette.border
                            : MarketPalette.blue,
                        width: 2,
                      ),
                    ),
                    child: SizedBox.expand(
                      child: MarketAvatar(
                        uid: uid,
                        fallbackUrl: imageUrl,
                        radius: 29,
                      ),
                    ),
                  ),
                ),
                if (isOwn)
                  const Positioned(
                    right: -1,
                    bottom: -1,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: MarketPalette.blue,
                      child: Icon(Icons.add, size: 15, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: MjasiSpacing.xs),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: MarketPalette.text, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class MarketStatusViewer extends StatefulWidget {
  const MarketStatusViewer({
    super.key,
    required this.group,
    this.nextGroups = const [],
    this.startIndexes = const {},
  });

  final MarketStatusGroup group;

  /// First unseen status index per author uid; missing means start at 0.
  final Map<String, int> startIndexes;

  /// Groups that play automatically after [group] finishes.
  final List<MarketStatusGroup> nextGroups;

  @override
  State<MarketStatusViewer> createState() => _MarketStatusViewerState();
}

class _MarketStatusViewerState extends State<MarketStatusViewer>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late final AnimationController _progress;
  late MarketStatusGroup _group;
  late List<MarketStatusGroup> _upcoming;
  final List<MarketStatusGroup> _history = [];
  bool _slideForward = true;
  late int _index;
  bool _captionExpanded = false;
  final ValueNotifier<bool> _videoHeld = ValueNotifier(false);

  void _setCaptionExpanded(bool value) {
    setState(() => _captionExpanded = value);
    if (value) {
      _pauseStatus();
    } else {
      _resumeStatus();
    }
  }

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _upcoming = List.of(widget.nextGroups);
    _index = _startFor(_group);
    _pageController = PageController(initialPage: _index);
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 35),
    )..addStatusListener(_onProgressStatus);
    _startStatus();
  }

  int _startFor(MarketStatusGroup group) {
    final start = widget.startIndexes[group.authorUid] ?? 0;
    return start >= 0 && start < group.statuses.length ? start : 0;
  }

  void _startStatus() {
    if (_group.statuses.isEmpty) return;
    unawaited(MarketService.recordStatusView(_group.statuses[_index].id));
    _progress.forward(from: 0);
    final status = _group.statuses[_index];
    final audioUrl = status.audioUrl;
    if (audioUrl.isNotEmpty) {
      unawaited(MarketAudioPlayer.instance.play(audioUrl));
    } else {
      unawaited(MarketAudioPlayer.instance.stop());
    }
  }

  void _onProgressStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    _next();
  }

  void _next() {
    if (_index + 1 >= _group.statuses.length) {
      if (_upcoming.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      _history.add(_group);
      _switchGroup(_upcoming.removeAt(0));
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  void _switchGroup(MarketStatusGroup group, {bool forward = true}) {
    final oldController = _pageController;
    setState(() {
      _slideForward = forward;
      _group = group;
      _index = forward ? _startFor(group) : 0;
      _captionExpanded = false;
      _pageController = PageController(initialPage: _index);
    });
    Future<void>.delayed(
      const Duration(milliseconds: 600),
      oldController.dispose,
    );
    _startStatus();
  }

  void _nextGroup() {
    if (_upcoming.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    _history.add(_group);
    _switchGroup(_upcoming.removeAt(0));
  }

  void _previousGroup() {
    if (_history.isEmpty) {
      _progress.forward(from: 0);
      return;
    }
    _upcoming.insert(0, _group);
    _switchGroup(_history.removeLast(), forward: false);
  }

  void _previous() {
    if (_index == 0) {
      if (_history.isEmpty) {
        _progress.forward(from: 0);
      } else {
        _upcoming.insert(0, _group);
        _switchGroup(_history.removeLast(), forward: false);
      }
    } else {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  void _pauseStatus() {
    _videoHeld.value = true;
    if (_progress.isAnimating) {
      _progress.stop(canceled: false);
      unawaited(MarketAudioPlayer.instance.pause());
    }
  }

  void _resumeStatus() {
    if (mounted) _videoHeld.value = false;
    if (!mounted || _progress.isAnimating || _progress.value >= 1) return;
    _progress.forward();
    unawaited(MarketAudioPlayer.instance.resume());
  }

  Future<void> _refreshStatus(MarketPost status) async {
    try {
      await MarketService.repostStatus(status);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('market_status_refreshed'.tr)));
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  final Map<String, bool> _stock = {};

  Future<void> _toggleStock(MarketPost status) async {
    final next = !(_stock[status.id] ?? status.inStock);
    try {
      await MarketService.setPostStock(status, next);
      if (mounted) setState(() => _stock[status.id] = next);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _deleteStatus(MarketPost status) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('market_delete_status'.tr),
        content: Text('market_delete_status_confirm'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('delete'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await MarketService.deleteStatus(status);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  String _postedAgo(DateTime? time) {
    if (time == null) return '';
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'market_just_now'.tr;
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours} h';
    return DateFormat('dd MMM, HH:mm').format(time);
  }

  String _viewedAgo(dynamic value) {
    if (value is! Timestamp) return '';
    final diff = DateTime.now().difference(value.toDate());
    if (diff.inMinutes < 1) return 'market_just_now'.tr;
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours} h';
    return DateFormat('dd MMM, HH:mm').format(value.toDate());
  }

  static const _reactionEmojis = ['❤️', '😂', '😮', '😢', '👏', '🔥'];

  Future<void> _openReplySheet(MarketPost status) async {
    _pauseStatus();
    final controller = TextEditingController();
    var sending = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: MarketPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> send({String text = '', String emoji = ''}) async {
            if (sending) return;
            setSheetState(() => sending = true);
            try {
              await MarketService.sendStatusReply(
                status.id,
                text: text,
                emoji: emoji,
              );
              if (sheetContext.mounted) Navigator.pop(sheetContext);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('market_status_reply_sent'.tr)),
                );
              }
            } catch (error) {
              setSheetState(() => sending = false);
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('$error')));
              }
            }
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final emoji in _reactionEmojis)
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: sending ? null : () => send(emoji: emoji),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 30),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        maxLength: 300,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (value) => send(text: value),
                        decoration: InputDecoration(
                          hintText: 'market_status_reply_hint'.tr,
                          counterText: '',
                          filled: true,
                          fillColor: MarketPalette.surfaceRaised,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(999),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: sending
                          ? null
                          : () => send(text: controller.text),
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    controller.dispose();
    _resumeStatus();
  }

  Future<void> _showReplies(MarketPost status) async {
    _pauseStatus();
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: MarketPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .55,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: MarketService.watchStatusReplies(status.id),
          builder: (context, snapshot) {
            final docs = snapshot.data?.docs ?? const [];
            if (docs.isEmpty) {
              return Center(
                child: Text(
                  'market_status_replies_empty'.tr,
                  style: const TextStyle(color: MarketPalette.textMuted),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final data = docs[index].data();
                final emoji = (data['emoji'] ?? '').toString();
                final text = (data['text'] ?? '').toString();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: emoji.isEmpty
                      ? const Icon(
                          Icons.chat_bubble_outline,
                          color: MarketPalette.textMuted,
                        )
                      : Text(emoji, style: const TextStyle(fontSize: 26)),
                  title: Text(
                    (data['senderName'] ?? '').toString(),
                    style: const TextStyle(
                      color: MarketPalette.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: text.isEmpty
                      ? null
                      : Text(
                          text,
                          style: const TextStyle(color: MarketPalette.text),
                        ),
                );
              },
            );
          },
        ),
      ),
    );
    _resumeStatus();
  }

  Future<void> _showViewers(MarketPost status) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: MarketPalette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .55,
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: MarketService.watchStatusViewers(status.id),
        builder: (context, snapshot) {
          final viewers = snapshot.data ?? const <Map<String, dynamic>>[];
          return Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: MarketPalette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.visibility_outlined,
                      color: MarketPalette.blue,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'market_status_viewers'.tr,
                        style: const TextStyle(
                          color: MarketPalette.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: MarketPalette.blueSoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${viewers.length}',
                        style: const TextStyle(
                          color: MarketPalette.blue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: MarketPalette.border),
              Expanded(
                child: !snapshot.hasData
                    ? const Center(child: CircularProgressIndicator())
                    : viewers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.visibility_off_outlined,
                              size: 40,
                              color: MarketPalette.textMuted,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'market_no_status_viewers'.tr,
                              style: const TextStyle(
                                color: MarketPalette.textMuted,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: viewers.length,
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          indent: 72,
                          color: MarketPalette.border,
                        ),
                        itemBuilder: (context, index) {
                          final viewer = viewers[index];
                          final name = (viewer['viewerName'] ?? '')
                              .toString()
                              .trim();
                          final ago = _viewedAgo(viewer['viewedAt']);
                          return ListTile(
                            leading: MarketAvatar(
                              uid: (viewer['uid'] ?? '').toString(),
                              fallbackUrl: (viewer['viewerPhotoUrl'] ?? '')
                                  .toString(),
                              radius: 20,
                            ),
                            title: Text(
                              name.isEmpty ? 'MJASI user' : name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: MarketPalette.text,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: ago.isEmpty
                                ? null
                                : Text(
                                    ago,
                                    style: const TextStyle(
                                      color: MarketPalette.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Future<void> _openLinkedProductWhatsApp(MarketPost status) async {
    final phone = await MarketService.getSellerWhatsApp(status);
    if (phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('market_seller_whatsapp_missing'.tr)),
        );
      }
      return;
    }
    if (phone.length < 8 || phone.length > 15) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('market_whatsapp_invalid'.tr)));
      }
      return;
    }
    try {
      try {
        await MarketService.recordWhatsAppClick(status);
      } catch (error) {
        debugPrint('Market contact click was not recorded: $error');
      }
      final uri = Uri.https('wa.me', '/$phone', {
        'text': buildMarketWhatsAppMessage(status),
      });
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('support_whatsapp_open_error'.tr)),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Widget _statPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(999),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildStats(MarketPost status, bool own) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    key: ValueKey('stats-${status.id}'),
    children: [
      StreamBuilder<bool>(
        stream: MarketService.watchLike(status.id),
        builder: (context, likedSnapshot) => StreamBuilder<int>(
          stream: MarketService.watchLikeCount(status.id),
          builder: (context, countSnapshot) {
            final liked = likedSnapshot.data ?? false;
            return _statPill(
              icon: liked ? Icons.favorite : Icons.favorite_border,
              color: liked ? MarketPalette.red : Colors.white,
              label: '${countSnapshot.data ?? 0}',
              onTap: () async {
                try {
                  await MarketService.toggleLike(status.id);
                } catch (error) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('$error')));
                  }
                }
              },
            );
          },
        ),
      ),
      if (own) ...[
        const SizedBox(width: 10),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: MarketService.watchStatusReplies(status.id),
          builder: (context, snapshot) => _statPill(
            icon: Icons.chat_bubble_outline,
            label: '${snapshot.data?.docs.length ?? 0}',
            onTap: () => _showReplies(status),
          ),
        ),
      ] else ...[
        const SizedBox(width: 10),
        _statPill(
          icon: Icons.chat_bubble_outline,
          label: 'market_status_reply'.tr,
          onTap: () => _openReplySheet(status),
        ),
      ],
      if (own) ...[
        const SizedBox(width: 10),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: MarketService.watchStatusViewers(status.id),
          builder: (context, snapshot) => _statPill(
            icon: Icons.visibility_outlined,
            label: '${snapshot.data?.length ?? 0}',
            onTap: () => _showViewers(status),
          ),
        ),
      ],
    ],
  );

  Widget _buildCaption(String caption) {
    const style = TextStyle(color: Colors.white, fontSize: 16, height: 1.35);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: caption, style: style),
          maxLines: 2,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth - 24);
        final overflows = painter.didExceedMaxLines;
        if (!overflows && !_captionExpanded) {
          return Text(caption, style: style);
        }
        return GestureDetector(
          onTap: () => _setCaptionExpanded(!_captionExpanded),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(
                  alpha: _captionExpanded ? 0.6 : 0.35,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_captionExpanded)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * .4,
                      ),
                      child: SingleChildScrollView(
                        child: Text(caption, style: style),
                      ),
                    )
                  else
                    Text(
                      caption,
                      style: style,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  Text(
                    _captionExpanded
                        ? 'market_show_less'.tr
                        : 'market_show_more'.tr,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    unawaited(MarketAudioPlayer.instance.stop());
    _progress
      ..removeStatusListener(_onProgressStatus)
      ..dispose();
    _pageController.dispose();
    _videoHeld.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final group = _group;
    final controller = _pageController;
    final current = _group.statuses[_index];
    final ownStatus =
        FirebaseAuth.instance.currentUser?.uid == current.authorUid;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => _pauseStatus(),
            onPointerUp: (_) => _resumeStatus(),
            onPointerCancel: (_) => _resumeStatus(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final width = MediaQuery.sizeOf(context).width;
                if (details.globalPosition.dx < width / 3) {
                  _previous();
                } else {
                  _next();
                }
              },
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity < -200) {
                  _nextGroup();
                } else if (velocity > 200) {
                  _previousGroup();
                }
              },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                switchInCurve: Curves.easeInOut,
                switchOutCurve: Curves.easeInOut,
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, if (current != null) current],
                ),
                transitionBuilder: (child, animation) {
                  final incoming = child.key == ValueKey(_group.authorUid);
                  final side = incoming == _slideForward ? 1.0 : -1.0;
                  return AnimatedBuilder(
                    animation: animation,
                    child: child,
                    builder: (context, child) {
                      final turn = 1 - animation.value;
                      final width = MediaQuery.sizeOf(context).width;
                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0012)
                          ..translate(side * turn * width, 0.0, 0.0)
                          ..rotateY(side * turn * 1.5708),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            child!,
                            IgnorePointer(
                              child: ColoredBox(
                                color: Colors.black.withValues(
                                  alpha: turn * 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
                child: PageView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  key: ValueKey(group.authorUid),
                  controller: controller,
                  itemCount: group.statuses.length,
                  onPageChanged: (index) {
                    setState(() {
                      _index = index;
                      _captionExpanded = false;
                    });
                    _startStatus();
                  },
                  itemBuilder: (context, index) =>
                      group.statuses[index].hasVideo
                      ? MarketVideoView(
                          url: group.statuses[index].videoUrl,
                          visibilityKey: 'status-${group.statuses[index].id}',
                          fit: BoxFit.contain,
                          paused: _videoHeld,
                          cover: group.statuses[index].images.isEmpty
                              ? null
                              : CachedNetworkImage(
                                  imageUrl: group.statuses[index].images.first,
                                  fit: BoxFit.contain,
                                ),
                        )
                      : group.statuses[index].images.isEmpty
                      ? MarketTextCard(
                          text: group.statuses[index].caption,
                          seed: group.statuses[index].id,
                          bg: group.statuses[index].textBg,
                          font: group.statuses[index].textFont,
                          fontSize: 28,
                          maxLines: 14,
                        )
                      : Center(
                          child: CachedNetworkImage(
                            imageUrl: group.statuses[index].images.first,
                            fit: BoxFit.contain,
                            errorWidget: (_, _, _) => const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white54,
                              size: 48,
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      for (
                        var index = 0;
                        index < _group.statuses.length;
                        index++
                      ) ...[
                        Expanded(
                          child: AnimatedBuilder(
                            animation: _progress,
                            builder: (context, _) => LinearProgressIndicator(
                              value: index < _index
                                  ? 1
                                  : index == _index
                                  ? _progress.value
                                  : 0,
                              minHeight: 2,
                              backgroundColor: Colors.white30,
                              valueColor: const AlwaysStoppedAnimation(
                                Colors.white,
                              ),
                            ),
                          ),
                        ),
                        if (index != _group.statuses.length - 1)
                          const SizedBox(width: 4),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (current.audioUrl.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: MarketSoundBadge(title: current.audioTitle),
                      ),
                    ),
                  Row(
                    children: [
                      const Icon(Icons.person, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _group.authorName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_postedAgo(current.createdAt).isNotEmpty)
                              Text(
                                _postedAgo(current.createdAt),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (ownStatus)
                        IconButton(
                          tooltip: 'market_status_viewers'.tr,
                          onPressed: () => _showViewers(current),
                          icon: const Icon(
                            Icons.visibility_outlined,
                            color: Colors.white,
                          ),
                        ),
                      if (ownStatus)
                        IconButton(
                          tooltip: 'market_status_refresh'.tr,
                          onPressed: () => _refreshStatus(current),
                          icon: const Icon(
                            Icons.refresh_rounded,
                            color: Colors.white,
                          ),
                        ),
                      if (ownStatus)
                        IconButton(
                          tooltip: (_stock[current.id] ?? current.inStock)
                              ? 'market_mark_out_of_stock'.tr
                              : 'market_mark_in_stock'.tr,
                          onPressed: () => _toggleStock(current),
                          icon: Icon(
                            (_stock[current.id] ?? current.inStock)
                                ? Icons.inventory_2_outlined
                                : Icons.remove_shopping_cart_outlined,
                            color: Colors.white,
                          ),
                        ),
                      if (ownStatus)
                        IconButton(
                          tooltip: 'market_delete_status'.tr,
                          onPressed: () => _deleteStatus(current),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.white,
                          ),
                        ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 80,
              height: double.infinity,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _previous,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 80,
              height: double.infinity,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _next,
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: MediaQuery.paddingOf(context).bottom + 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (current.caption.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildCaption(current.caption),
                    ),
                  ),
                if (!(_stock[current.id] ?? current.inStock))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: MarketPalette.red,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: Text(
                            'market_out_of_stock'.tr,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (current.price != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      '${current.currency} '
                      '${current.price!.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildStats(current, ownStatus),
                ),
                Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) =>
                              MarketBuyComingSoonDialog(post: current),
                        ),
                        icon: const Icon(Icons.shopping_bag_outlined),
                        label: Text('market_buy_on_app'.tr),
                        style: MarketPalette.statusActionButtonStyle,
                      ),
                      FilledButton.icon(
                        onPressed: () => _openLinkedProductWhatsApp(current),
                        icon: const Icon(Icons.chat_outlined),
                        label: Text('market_visit_whatsapp'.tr),
                        style: MarketPalette.statusActionButtonStyle,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
