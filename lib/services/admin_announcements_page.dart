import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'notification_service.dart';

const _brand = Color(0xFF7C3AED);

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
  double? _progress;
  Uint8List? _imageBytes;
  String _imageName = '';
  late final Stream<List<AppNotification>> _history;
  late final Future<int> _audience;

  @override
  void initState() {
    super.initState();
    _history = NotificationService.watchAnnouncements().asBroadcastStream();
    _audience = NotificationService.totalActiveUsers();
    _title.addListener(_refresh);
    _body.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null || file.bytes == null) return;
    if (file.bytes!.length > 5 * 1024 * 1024) {
      Get.snackbar('error'.tr, 'announce_image_too_big'.tr);
      return;
    }
    setState(() {
      _imageBytes = file.bytes;
      _imageName = file.name;
    });
  }

  Future<String?> _uploadImage() async {
    final bytes = _imageBytes;
    if (bytes == null) return null;
    final ext = _imageName.contains('.')
        ? _imageName.split('.').last.toLowerCase()
        : 'jpg';
    final type = ext == 'png'
        ? 'image/png'
        : ext == 'webp'
        ? 'image/webp'
        : 'image/jpeg';
    final ref = FirebaseStorage.instance.ref(
      'announcements/${DateTime.now().millisecondsSinceEpoch}.$ext',
    );
    final task = ref.putData(bytes, SettableMetadata(contentType: type));
    task.snapshotEvents.listen((s) {
      if (s.totalBytes > 0 && mounted) {
        setState(() => _progress = s.bytesTransferred / s.totalBytes);
      }
    });
    await task;
    return ref.getDownloadURL();
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty) {
      Get.snackbar('error'.tr, 'announce_title_required'.tr);
      return;
    }
    setState(() => _sending = true);
    try {
      final imageUrl = await _uploadImage();
      await NotificationService.sendAnnouncement(
        title: _title.text,
        body: _body.text,
        imageUrl: imageUrl,
        expiresAt: _expiryDays == 0
            ? null
            : DateTime.now().add(Duration(days: _expiryDays)),
      );
      _title.clear();
      _body.clear();
      setState(() {
        _imageBytes = null;
        _imageName = '';
      });
      Get.snackbar('success'.tr, 'announce_sent'.tr);
    } catch (error) {
      Get.snackbar('error'.tr, '$error');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _progress = null;
        });
      }
    }
  }

  Widget _section(String title, IconData icon, Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E9F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: _brand, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _composer() {
    return _section(
      'announce_compose'.tr,
      Icons.edit_note_rounded,
      Column(
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
          if (_imageBytes == null)
            OutlinedButton.icon(
              onPressed: _sending ? null : _pickImage,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text('announce_add_image'.tr),
            )
          else
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _imageBytes!,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      color: Colors.white,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _sending
                          ? null
                          : () => setState(() => _imageBytes = null),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _expiryDays,
            decoration: InputDecoration(
              labelText: 'announce_expiry'.tr,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(value: 0, child: Text('announce_never'.tr)),
              const DropdownMenuItem(value: 1, child: Text('1 day')),
              const DropdownMenuItem(value: 7, child: Text('7 days')),
              const DropdownMenuItem(value: 30, child: Text('30 days')),
            ],
            onChanged: (v) => setState(() => _expiryDays = v ?? 0),
          ),
          if (_progress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _brand,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded),
            label: Text('announce_send'.tr),
          ),
        ],
      ),
    );
  }

  Widget _preview() {
    final title = _title.text.trim();
    final body = _body.text.trim();
    return _section(
      'announce_preview'.tr,
      Icons.visibility_outlined,
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F6FB),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: _brand.withValues(alpha: 0.12),
              child: const Icon(Icons.campaign_rounded, color: _brand),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isEmpty ? 'announce_title'.tr : title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: title.isEmpty ? Colors.grey : null,
                    ),
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(body),
                  ],
                  if (_imageBytes != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(
                        _imageBytes!,
                        height: 120,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyCard(AppNotification n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E9F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (n.imageUrl != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      n.imageUrl!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      n.createdAt == null
                          ? ''
                          : DateFormat(
                              'd MMM yyyy, HH:mm',
                            ).format(n.createdAt!),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'delete'.tr,
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  final ok = await Get.defaultDialog<bool>(
                    title: 'delete'.tr,
                    middleText: n.title,
                    textConfirm: 'delete'.tr,
                    textCancel: 'cancel'.tr,
                    onConfirm: () => Get.back(result: true),
                    onCancel: () {},
                  );
                  if (ok == true) {
                    await NotificationService.deleteAnnouncement(n.id);
                  }
                },
              ),
            ],
          ),
          if (n.body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              n.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade800),
            ),
          ],
          const SizedBox(height: 10),
          FutureBuilder<List<int>>(
            future: Future.wait([
              NotificationService.announcementReadCount(n.id),
              _audience,
            ]),
            builder: (context, snap) {
              final reads = snap.data?[0];
              final total = snap.data?[1] ?? 0;
              final pct = (reads != null && total > 0)
                  ? (reads / total).clamp(0.0, 1.0)
                  : 0.0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _chip(
                        Icons.mark_email_read_outlined,
                        '${'announce_opened'.tr}: ${reads ?? '…'}',
                        const Color(0xFF16A34A),
                      ),
                      _chip(
                        Icons.phone_android_rounded,
                        '${'announce_push_sent'.tr}: ${n.sentCount ?? '—'}',
                        const Color(0xFF1565C0),
                      ),
                      if ((n.failureCount ?? 0) > 0)
                        _chip(
                          Icons.error_outline_rounded,
                          '${'announce_push_failed'.tr}: ${n.failureCount}',
                          const Color(0xFFDC2626),
                        ),
                    ],
                  ),
                  if (total > 0) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 6,
                        backgroundColor: const Color(0xFFE5E9F2),
                        color: const Color(0xFF16A34A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(pct * 100).round()}% · ${reads ?? 0}/$total ${'announce_users'.tr}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _historySection() {
    return StreamBuilder<List<AppNotification>>(
      stream: _history,
      builder: (context, snap) {
        final items = snap.data ?? const <AppNotification>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'announce_history'.tr,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text('notif_empty'.tr)),
              )
            else
              for (final n in items) _historyCard(n),
          ],
        );
      },
    );
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
              _composer(),
              const SizedBox(height: 12),
              _preview(),
              const SizedBox(height: 20),
              _historySection(),
            ],
          ),
        ),
      ),
    );
  }
}
