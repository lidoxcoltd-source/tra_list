import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'notification_service.dart';

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
    default:
      return Icons.notifications_rounded;
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

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  @override
  void initState() {
    super.initState();
    NotificationService.markAnnouncementsSeen();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppNotification>>(
      stream: NotificationService.watchActivity(),
      builder: (context, activitySnap) {
        return StreamBuilder<List<AppNotification>>(
          stream: NotificationService.watchAnnouncements(),
          builder: (context, announcementSnap) {
            final activity = activitySnap.data ?? const <AppNotification>[];
            final items =
                <AppNotification>[
                  ...activity,
                  ...(announcementSnap.data ?? const <AppNotification>[]),
                ]..sort(
                  (a, b) => (b.createdAt ?? DateTime.now()).compareTo(
                    a.createdAt ?? DateTime.now(),
                  ),
                );
            final loading =
                activitySnap.connectionState == ConnectionState.waiting &&
                announcementSnap.connectionState == ConnectionState.waiting;
            return Scaffold(
              backgroundColor: const Color(0xFFF4F6FB),
              appBar: AppBar(
                title: Text('notif_title'.tr),
                actions: [
                  if (activity.any((n) => !n.read))
                    TextButton.icon(
                      onPressed: () => NotificationService.markAllRead(items),
                      icon: const Icon(Icons.done_all_rounded),
                      label: Text('notif_mark_all'.tr),
                    ),
                ],
              ),
              body: loading
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.notifications_off_outlined,
                            size: 56,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'notif_empty'.tr,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _tile(items[i]),
                        ),
                      ),
                    ),
            );
          },
        );
      },
    );
  }

  Widget _tile(AppNotification n) {
    final unread = !n.isAnnouncement && !n.read;
    final color = n.isAnnouncement
        ? const Color(0xFF7C3AED)
        : const Color(0xFF1565C0);
    final card = Material(
      color: unread ? const Color(0xFFEAF2FF) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: n.isAnnouncement || n.read
            ? null
            : () => NotificationService.markRead(n.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(_iconFor(n.action), color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.isAnnouncement ? n.title : '${n.title} • ${n.body}',
                      style: TextStyle(
                        fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    if (n.isAnnouncement && n.body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(n.body),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _relativeTime(n.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (!n.isAnnouncement)
                IconButton(
                  tooltip: 'delete'.tr,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => NotificationService.delete(n.id),
                ),
            ],
          ),
        ),
      ),
    );
    return card;
  }
}
