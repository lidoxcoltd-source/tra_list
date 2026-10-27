import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../market/market_models.dart';
import '../market/market_profile_page.dart';
import '../market/market_service.dart';
import 'notification_service.dart';
import '../tasks/task_detail_page.dart';

const _announceColor = Color(0xFF5BA2FF);
const _ink = Color(0xFFF2F6FC);
const _line = Color(0xFF283543);
const _canvas = Color(0xFF080D13);
const _surface = Color(0xFF111A24);
const _surfaceRaised = Color(0xFF1B2734);
const _muted = Color(0xFFA8B6C8);
const _accent = Color(0xFF5BA2FF);

String _relativeTime(DateTime? time) {
  if (time == null) return '';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'notif_now'.tr;
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return DateFormat('d MMM yyyy').format(time);
}

IconData _iconFor(String action) {
  switch (action) {
    case 'announcement':
      return Icons.campaign_rounded;
    case 'transaction':
      return Icons.payments_rounded;
    case 'invoice':
      return Icons.receipt_long_rounded;
    case 'quotation':
      return Icons.request_quote_rounded;
    case 'receipt':
      return Icons.receipt_rounded;
    case 'job':
      return Icons.work_rounded;
    case 'debt':
      return Icons.account_balance_wallet_rounded;
    case 'task':
      return Icons.task_alt_rounded;
    case 'verification':
      return Icons.verified_user_rounded;
    case 'market_like':
      return Icons.favorite_rounded;
    case 'market_comment':
      return Icons.mode_comment_rounded;
    case 'market_follow':
      return Icons.person_add_alt_1_rounded;
    default:
      return Icons.notifications_rounded;
  }
}

Color _colorFor(String action) {
  switch (action) {
    case 'announcement':
      return _announceColor;
    case 'transaction':
      return const Color(0xFF16A34A);
    case 'invoice':
      return const Color(0xFF1565C0);
    case 'quotation':
      return const Color(0xFFEA580C);
    case 'receipt':
      return const Color(0xFF0891B2);
    case 'job':
      return const Color(0xFF4F46E5);
    case 'debt':
      return const Color(0xFFDC2626);
    case 'task':
      return const Color(0xFF1E40AF);
    case 'verification':
      return const Color(0xFF0F766E);
    case 'market_like':
      return const Color(0xFFDC2626);
    case 'market_comment':
      return const Color(0xFF1565C0);
    case 'market_follow':
      return const Color(0xFF0F766E);
    default:
      return const Color(0xFF475569);
  }
}

/// Bell icon with an unread badge, for the app bar.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  DateTime _lastSeen = DateTime.now();
  late final Stream<List<AppNotification>> _activity;
  late final Stream<List<AppNotification>> _announcements;

  @override
  void initState() {
    super.initState();
    _activity = NotificationService.watchActivity().asBroadcastStream();
    _announcements = NotificationService.watchAnnouncements()
        .asBroadcastStream();
    NotificationService.lastSeenAnnouncements().then((value) {
      if (mounted) setState(() => _lastSeen = value);
    });
  }

  Future<void> _open() async {
    await Get.toNamed('/notifications');
    final seen = await NotificationService.lastSeenAnnouncements();
    if (mounted) setState(() => _lastSeen = seen);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppNotification>>(
      stream: _activity,
      builder: (context, activitySnap) {
        return StreamBuilder<List<AppNotification>>(
          stream: _announcements,
          builder: (context, announcementSnap) {
            final unreadActivity = (activitySnap.data ?? const [])
                .where((n) => !n.read)
                .length;
            final unreadAnnouncements = (announcementSnap.data ?? const [])
                .where((n) => n.createdAt?.isAfter(_lastSeen) ?? false)
                .length;
            final count = unreadActivity + unreadAnnouncements;
            return IconButton(
              tooltip: 'notif_title'.tr,
              onPressed: _open,
              icon: Badge(
                isLabelVisible: count > 0,
                label: Text(count > 99 ? '99+' : '$count'),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  color: Colors.white,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

enum _Filter { all, people, comments, professional, unread }

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final Set<String> _recorded = {};
  final Set<String> _hidden = {};
  final Set<String> _followBackBusy = {};
  final Map<String, Future<MarketProfile?>> _actorProfiles = {};
  final Map<String, Future<MarketPost?>> _postPreviews = {};
  late final Stream<List<AppNotification>> _activity;
  late final Stream<List<AppNotification>> _announcements;
  _Filter _filter = _Filter.all;
  DateTime _lastSeen = DateTime.now();

  @override
  void initState() {
    super.initState();
    _activity = NotificationService.watchActivity().asBroadcastStream();
    _announcements = NotificationService.watchAnnouncements()
        .asBroadcastStream();
    // Remember what was new when the page opened, then mark everything seen.
    NotificationService.lastSeenAnnouncements().then((value) {
      if (mounted) setState(() => _lastSeen = value);
      NotificationService.markAnnouncementsSeen();
    });
  }

  bool _isUnread(AppNotification n) =>
      n.isAnnouncement ? (n.createdAt?.isAfter(_lastSeen) ?? false) : !n.read;

  List<AppNotification> _apply(List<AppNotification> all) {
    switch (_filter) {
      case _Filter.all:
        return all;
      case _Filter.unread:
        return all.where(_isUnread).toList();
      case _Filter.people:
        return all
            .where(
              (n) =>
                  n.action == 'market_post' ||
                  n.action == 'market_status_reply',
            )
            .toList();
      case _Filter.comments:
        return all.where((n) => n.action == 'market_comment').toList();
      case _Filter.professional:
        return all
            .where((n) => n.isAnnouncement || !n.action.startsWith('market_'))
            .toList();
    }
  }

  String _groupLabel(DateTime? time) {
    if (time == null) return 'notif_earlier'.tr;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'notif_today'.tr;
    if (diff == 1) return 'notif_yesterday'.tr;
    if (diff < 7) return 'notif_this_week'.tr;
    return 'notif_earlier'.tr;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppNotification>>(
      stream: _activity,
      builder: (context, activitySnap) {
        return StreamBuilder<List<AppNotification>>(
          stream: _announcements,
          builder: (context, announcementSnap) {
            final announcements =
                (announcementSnap.data ?? const <AppNotification>[])
                    .where((n) => !_hidden.contains(n.id))
                    .toList();
            final ids = announcements.map((n) => n.id).toList();
            if (ids.any((id) => _recorded.add(id))) {
              NotificationService.recordAnnouncementReads(ids);
            }
            final activity = activitySnap.data ?? const <AppNotification>[];
            final all = <AppNotification>[...activity, ...announcements]
              ..sort(
                (a, b) => (b.createdAt ?? DateTime.now()).compareTo(
                  a.createdAt ?? DateTime.now(),
                ),
              );
            final loading =
                activitySnap.connectionState == ConnectionState.waiting &&
                announcementSnap.connectionState == ConnectionState.waiting;
            final items = _apply(all);

            return Scaffold(
              backgroundColor: _canvas,
              appBar: AppBar(
                backgroundColor: _canvas,
                foregroundColor: Colors.white,
                iconTheme: const IconThemeData(color: Colors.white),
                automaticallyImplyLeading: false,
                leading: IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                title: Text(
                  'notif_title'.tr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                actions: [
                  if (activity.any((n) => !n.read))
                    IconButton(
                      tooltip: 'notif_mark_all'.tr,
                      onPressed: () => NotificationService.markAllRead(all),
                      icon: const Icon(Icons.done_all_rounded),
                    ),
                  if (activity.isNotEmpty)
                    IconButton(
                      tooltip: 'notif_clear_all'.tr,
                      icon: const Icon(Icons.delete_sweep_outlined),
                      onPressed: () async {
                        if (await _confirm('notif_clear_all_q'.tr)) {
                          for (final n in activity) {
                            NotificationService.delete(n.id, inbox: n.isInbox);
                          }
                        }
                      },
                    ),
                ],
              ),
              body: LayoutBuilder(
                builder: (context, box) {
                  final listPane = loading
                      ? const Center(child: CircularProgressIndicator())
                      : items.isEmpty
                      ? _empty()
                      : _list(items);
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Column(
                        children: [
                          _filters(all, wide: box.maxWidth >= 900),
                          Expanded(child: listPane),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _filters(List<AppNotification> all, {bool wide = false}) {
    String label(_Filter f) {
      switch (f) {
        case _Filter.all:
          return 'notif_filter_all'.tr;
        case _Filter.people:
          return 'notif_filter_people'.tr;
        case _Filter.comments:
          return 'notif_filter_comments'.tr;
        case _Filter.professional:
          return 'notif_filter_professional'.tr;
        case _Filter.unread:
          return 'notif_filter_unread'.tr;
      }
    }

    Widget chip(_Filter f) => ChoiceChip(
      showCheckmark: false,
      selected: _filter == f,
      onSelected: (_) => setState(() => _filter = f),
      label: Text(label(f)),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: _filter == f ? _canvas : _ink,
      ),
      selectedColor: _ink,
      backgroundColor: _surfaceRaised,
      side: BorderSide(color: _filter == f ? _ink : _line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    if (wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final f in _Filter.values) chip(f)],
        ),
      );
    }

    return SizedBox(
      height: 54,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        children: [
          for (final f in _Filter.values)
            Padding(padding: const EdgeInsets.only(right: 8), child: chip(f)),
        ],
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: _surfaceRaised,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_off_outlined,
                size: 40,
                color: _muted,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'notif_empty'.tr,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: _ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'notif_empty_hint'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(List<AppNotification> items) {
    final children = <Widget>[];
    String? current;
    for (final n in items) {
      final group = _groupLabel(n.createdAt);
      if (group != current) {
        current = group;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
            child: Text(
              group,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
          ),
        );
      }
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: n.isAnnouncement
              ? Dismissible(
                  key: ValueKey('announcement_${n.id}'),
                  direction: DismissDirection.horizontal,
                  background: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(Icons.delete_outline_rounded, color: Colors.white),
                        Icon(Icons.delete_outline_rounded, color: Colors.white),
                      ],
                    ),
                  ),
                  onDismissed: (_) {
                    setState(() => _hidden.add(n.id));
                    NotificationService.hideAnnouncement(n.id);
                  },
                  child: _announcementCard(n),
                )
              : _activityCard(n),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      children: children,
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Future<bool> _confirm(String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          color: _ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(color: _muted, fontSize: 14),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
            ),
            child: Text('delete'.tr),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<MarketProfile?>? _actorProfileFor(AppNotification notification) {
    final uid = notification.actorUid;
    if (uid == null || uid.isEmpty) return null;
    return _actorProfiles.putIfAbsent(
      uid,
      () => MarketService.getPublicProfile(uid),
    );
  }

  Widget _actorAvatar(AppNotification notification, MarketProfile? profile) {
    final photo = profile?.photoUrl ?? '';
    final name = profile?.name.trim() ?? '';
    return CircleAvatar(
      radius: 24,
      backgroundColor: _surfaceRaised,
      foregroundImage: photo.startsWith('http') ? NetworkImage(photo) : null,
      child: photo.startsWith('http')
          ? null
          : name.isNotEmpty
          ? Text(
              name[0].toUpperCase(),
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w700),
            )
          : Icon(_iconFor(notification.action), color: _muted, size: 20),
    );
  }

  Widget _postThumbnail(String postId) {
    final future = _postPreviews.putIfAbsent(
      postId,
      () => MarketService.getPost(postId),
    );
    return FutureBuilder<MarketPost?>(
      future: future,
      builder: (context, snapshot) {
        final images = snapshot.data?.images ?? const <String>[];
        if (images.isEmpty) return const SizedBox.shrink();
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            images.first,
            width: 46,
            height: 52,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox(width: 46, height: 52),
          ),
        );
      },
    );
  }

  Widget _followBackButton(String uid) {
    return StreamBuilder<bool>(
      stream: MarketService.watchFollowing(uid),
      builder: (context, snapshot) {
        final following = snapshot.data == true;
        final busy = _followBackBusy.contains(uid);
        return SizedBox(
          height: 34,
          child: FilledButton(
            onPressed: following || busy
                ? null
                : () async {
                    setState(() => _followBackBusy.add(uid));
                    try {
                      await MarketService.toggleFollow(uid);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('market_follow_success'.tr)),
                        );
                      }
                    } catch (error) {
                      if (mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('$error')));
                      }
                    } finally {
                      if (mounted) setState(() => _followBackBusy.remove(uid));
                    }
                  },
            style: FilledButton.styleFrom(
              backgroundColor: following ? _surfaceRaised : _accent,
              foregroundColor: _ink,
              disabledBackgroundColor: _surfaceRaised,
              disabledForegroundColor: _muted,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(72, 34),
            ),
            child: Text(
              following ? 'market_following'.tr : 'notif_follow_back'.tr,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        );
      },
    );
  }

  Widget _activityCard(AppNotification n) {
    final unread = !n.read;
    final actorProfile = _actorProfileFor(n);
    return Dismissible(
      key: ValueKey('activity_${n.id}'),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFDC2626),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.white),
            Icon(Icons.delete_outline_rounded, color: Colors.white),
          ],
        ),
      ),
      onDismissed: (_) => NotificationService.delete(n.id, inbox: n.isInbox),
      child: FutureBuilder<MarketProfile?>(
        future: actorProfile,
        builder: (context, profileSnapshot) {
          final profile = profileSnapshot.data;
          final actorName = profile?.name.trim().isNotEmpty == true
              ? profile!.name
              : n.title;
          final body = n.action == 'market_follow' && actorName.isNotEmpty
              ? 'notif_market_follow_body'.trParams({'name': actorName})
              : n.body;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                if (unread)
                  NotificationService.markRead(n.id, inbox: n.isInbox);
                if (n.taskId != null) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TaskDetailPage(taskId: n.taskId!),
                    ),
                  );
                } else if (n.postId != null) {
                  Get.toNamed('/market/post/${n.postId}');
                } else if (n.actorUid != null) {
                  Get.to(() => MarketProfilePage(uid: n.actorUid!));
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: unread ? _accent.withValues(alpha: 0.35) : _line,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    _actorAvatar(n, profile),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            actorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: unread
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              fontSize: 14,
                              color: _ink,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            body,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: _muted,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _relativeTime(n.createdAt),
                            style: const TextStyle(fontSize: 11, color: _muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (n.action == 'market_follow' && n.actorUid != null)
                      _followBackButton(n.actorUid!)
                    else if (n.postId != null)
                      _postThumbnail(n.postId!),
                    InkResponse(
                      radius: 18,
                      onTap: () async {
                        if (await _confirm('notif_delete_one'.tr)) {
                          NotificationService.delete(n.id, inbox: n.isInbox);
                        }
                      },
                      child: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.more_horiz_rounded,
                          size: 20,
                          color: _muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _viewImage(String url) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox(
                  height: 200,
                  child: Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                color: Colors.white,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _announcementCard(AppNotification n) {
    final isNew = _isUnread(n);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isNew ? _announceColor.withValues(alpha: 0.4) : _line,
        ),
        boxShadow: [
          BoxShadow(
            color: _announceColor.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 4,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_announceColor, Color(0xFF55D6BE)],
              ),
            ),
          ),
          if (n.imageUrl != null)
            GestureDetector(
              onTap: () => _viewImage(n.imageUrl!),
              child: Image.network(
                n.imageUrl!,
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const SizedBox(
                        height: 180,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _badge('notif_announcement'.tr, _announceColor),
                    if (isNew) ...[
                      const SizedBox(width: 6),
                      _badge('notif_new'.tr, const Color(0xFFDB2777)),
                    ],
                    const Spacer(),
                    InkResponse(
                      radius: 16,
                      onTap: () async {
                        if (await _confirm('notif_delete_one'.tr)) {
                          setState(() => _hidden.add(n.id));
                          NotificationService.hideAnnouncement(n.id);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                          color: _muted,
                        ),
                      ),
                    ),
                    Text(
                      _relativeTime(n.createdAt),
                      style: TextStyle(fontSize: 11.5, color: _muted),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  n.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    height: 1.3,
                    color: _ink,
                  ),
                ),
                if (n.body.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    n.body,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: _muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
