import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'notification_service.dart';

class AdminAnnouncementsPage extends StatefulWidget {
  const AdminAnnouncementsPage({super.key});

  @override
  State<AdminAnnouncementsPage> createState() => _AdminAnnouncementsPageState();
}

class _AdminAnnouncementsPageState extends State<AdminAnnouncementsPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  int _expiryDays = 0;
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty) {
      Get.snackbar('error'.tr, 'announce_title_required'.tr);
      return;
    }
    setState(() => _sending = true);
    try {
      await NotificationService.sendAnnouncement(
        title: _title.text,
        body: _body.text,
        expiresAt: _expiryDays == 0
            ? null
            : DateTime.now().add(Duration(days: _expiryDays)),
      );
      _title.clear();
      _body.clear();
      Get.snackbar('success'.tr, 'announce_sent'.tr);
    } catch (error) {
      Get.snackbar('error'.tr, '$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(title: Text('admin_manage_announcements'.tr)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _title,
                        maxLength: 120,
                        decoration: InputDecoration(
                          labelText: 'announce_title'.tr,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _body,
                        maxLength: 1000,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: 'announce_body'.tr,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: _expiryDays,
                        decoration: InputDecoration(
                          labelText: 'announce_expiry'.tr,
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 0,
                            child: Text('announce_never'.tr),
                          ),
                          const DropdownMenuItem(
                            value: 1,
                            child: Text('1 day'),
                          ),
                          const DropdownMenuItem(
                            value: 7,
                            child: Text('7 days'),
                          ),
                          const DropdownMenuItem(
                            value: 30,
                            child: Text('30 days'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _expiryDays = v ?? 0),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _sending ? null : _send,
                        icon: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                        label: Text('announce_send'.tr),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'announce_history'.tr,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              StreamBuilder<List<AppNotification>>(
                stream: NotificationService.watchAnnouncements(),
                builder: (context, snap) {
                  final items = snap.data ?? const <AppNotification>[];
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(child: Text('notif_empty'.tr)),
                    );
                  }
                  return Column(
                    children: [
                      for (final n in items)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.campaign_rounded),
                            title: Text(n.title),
                            subtitle: Text(
                              '${n.body}\n${n.createdAt == null ? '' : DateFormat('d MMM yyyy, HH:mm').format(n.createdAt!)}',
                            ),
                            isThreeLine: true,
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () =>
                                  NotificationService.deleteAnnouncement(n.id),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
