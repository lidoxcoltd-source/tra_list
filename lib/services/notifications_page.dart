import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'notification_service.dart';
import '../tasks/task_detail_page.dart';

const _announceColor = Color(0xFF7C3AED);
const _ink = Color(0xFF0F172A);
const _line = Color(0xFFE5E9F2);

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

enum _Filter { all, unread, activity, announcements }

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final Set<String> _recorded = {};
  final Set<String> _hidden = {};
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
      case _Filter.activity:
        return all.where((n) => !n.isAnnouncement).toList();
      case _Filter.announcements:
        return all.where((n) => n.isAnnouncement).toList();
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
            final unreadCount = all.where(_isUnread).length;
            final loading =
                activitySnap.connectionState == ConnectionState.waiting &&
                announcementSnap.connectionState == ConnectionState.waiting;
            final items = _apply(all);

            return Scaffold(
              backgroundColor: const Color(0xFFF4F6FB),
              appBar: AppBar(
                title: Text('notif_title'.tr),
                actions: [
                  if (activity.any((n) => !n.read))
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => NotificationService.markAllRead(all),
                      icon: const Icon(Icons.done_all_rounded, size: 20),
                      label: Text('notif_mark_all'.tr),
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
                  if (box.maxWidth >= 900) {
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 340,
                              child: Column(
                                children: [
                                  _summary(unreadCount, all.length),
                                  _filters(all, wide: true),
                                ],
                              ),
                            ),
                            Expanded(child: listPane),
                          ],
                        ),
                      ),
                    );
                  }
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        children: [
                          _summary(unreadCount, all.length),
                          _filters(all),
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

  Widget _summary(int unread, int total) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A3F46), Color(0xFF0E5962), Color(0xFF17808B)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unread > 0
                      ? 'notif_unread_count'.trParams({'n': '$unread'})
                      : 'notif_all_caught_up'.tr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'notif_total_count'.trParams({'n': '$total'}),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters(List<AppNotification> all, {bool wide = false}) {
    int count(_Filter f) {
      switch (f) {
        case _Filter.all:
          return all.length;
        case _Filter.unread:
          return all.where(_isUnread).length;
        case _Filter.activity:
          return all.where((n) => !n.isAnnouncement).length;
        case _Filter.announcements:
          return all.where((n) => n.isAnnouncement).length;
      }
    }

    String label(_Filter f) {
      switch (f) {
        case _Filter.all:
          return 'notif_filter_all'.tr;
        case _Filter.unread:
          return 'notif_filter_unread'.tr;
        case _Filter.activity:
          return 'notif_filter_activity'.tr;
        case _Filter.announcements:
          return 'notif_filter_announcements'.tr;
      }
    }

    Widget chip(_Filter f) => ChoiceChip(
      showCheckmark: false,
      selected: _filter == f,
      onSelected: (_) => setState(() => _filter = f),
      label: Text('${label(f)} · ${count(f)}'),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: _filter == f ? Colors.white : _ink,
      ),
      selectedColor: const Color(0xFF0E5962),
      backgroundColor: Colors.white,
      side: BorderSide(color: _filter == f ? const Color(0xFF0E5962) : _line),
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
                color: const Color(0xFF0E5962).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_off_outlined,
                size: 40,
                color: Color(0xFF0E5962),
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
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
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
              group.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: Colors.grey.shade600,
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

  Widget _activityCard(AppNotification n) {
    final unread = !n.read;
    final color = _colorFor(n.action);
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
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (unread) NotificationService.markRead(n.id, inbox: n.isInbox);
            if (n.taskId != null) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TaskDetailPage(taskId: n.taskId!),
                ),
              );
            }
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: unread ? color.withValues(alpha: 0.35) : _line,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(_iconFor(n.action), color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              n.title,
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
                          ),
                          Text(
                            _relativeTime(n.createdAt),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        n.body,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                if (unread)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 6),
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                InkResponse(
                  radius: 18,
                  onTap: () async {
                    if (await _confirm('notif_delete_one'.tr)) {
                      NotificationService.delete(n.id, inbox: n.isInbox);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6, top: 2),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
                colors: [_announceColor, Color(0xFFDB2777)],
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
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                    Text(
                      _relativeTime(n.createdAt),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ),
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
                      color: Colors.grey.shade800,
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
