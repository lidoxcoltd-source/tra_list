import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'download_center_service.dart';

/// Super Admin editor for the public downloads page.
class DownloadCenterManagementPage extends StatefulWidget {
  const DownloadCenterManagementPage({super.key});

  @override
  State<DownloadCenterManagementPage> createState() =>
      _DownloadCenterManagementPageState();
}

class _DownloadCenterManagementPageState
    extends State<DownloadCenterManagementPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _subtitle = TextEditingController();
  final _urls = {
    for (final d in downloadItemDefs) d.key: TextEditingController(),
  };
  final _versions = {
    for (final d in downloadItemDefs) d.key: TextEditingController(),
  };
  final _enabled = {for (final d in downloadItemDefs) d.key: false};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  static const publicUrl = 'https://mjasipos.web.app/downloads';
  final Future<Map<String, int>> _statsFuture =
      DownloadCenterService.loadStats();

  final Map<String, double?> _uploadProgress = {};
  final Map<String, String> _uploadedLinks = {};

  Future<void> _uploadFile(String key) async {
    StreamSubscription<TaskSnapshot>? progressSubscription;
    try {
      final extensions = key == 'apk' ? ['apk'] : ['zip', 'exe', 'msix', 'msi'];
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
        withData: true,
      );
      final file = picked?.files.single;
      if (file == null) return;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('The selected file could not be read.');
      }

      final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final ref = FirebaseStorage.instance.ref('downloads/${key}_$safeName');
      if (!mounted) return;
      setState(() {
        _uploadProgress[key] = 0;
        _error = null;
        _uploadedLinks.remove(key);
      });
      final task = ref.putData(
        bytes,
        SettableMetadata(contentType: 'application/octet-stream'),
      );
      progressSubscription = task.snapshotEvents.listen(
        (snapshot) {
          if (!mounted || snapshot.totalBytes == 0) return;
          setState(
            () => _uploadProgress[key] =
                snapshot.bytesTransferred / snapshot.totalBytes,
          );
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Download file upload progress failed: $error');
          debugPrintStack(stackTrace: stackTrace);
        },
      );
      await task;
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() {
        _urls[key]!.text = url;
        _enabled[key] = true;
        _uploadedLinks[key] = url;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${file.name} uploaded. Copy the link below, then save to publish it.',
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Could not upload download file: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _error = 'Upload failed: $error');
    } finally {
      await progressSubscription?.cancel();
      if (mounted) setState(() => _uploadProgress.remove(key));
    }
  }

  Future<void> _copyUploadedLink(String key) async {
    final link = _uploadedLinks[key];
    if (link == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: link));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Download link copied.')));
    } catch (error, stackTrace) {
      debugPrint('Could not copy uploaded download link: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _error = 'Could not copy the download link: $error');
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    for (final c in [..._urls.values, ..._versions.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final center = await DownloadCenterService.load();
      _title.text = center.title;
      _subtitle.text = center.subtitle;
      for (final d in downloadItemDefs) {
        final item = center.item(d.key);
        _urls[d.key]!.text = item.url;
        _versions[d.key]!.text = item.version;
        _enabled[d.key] = item.enabled;
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await DownloadCenterService.save(
        DownloadCenter(
          title: _title.text.trim(),
          subtitle: _subtitle.text.trim(),
          items: {
            for (final d in downloadItemDefs)
              d.key: DownloadItem(
                enabled: _enabled[d.key]!,
                url: _urls[d.key]!.text.trim(),
                version: _versions[d.key]!.text.trim(),
              ),
          },
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Downloads page saved.')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sharePublicPage() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          title: 'MJASI POS downloads',
          text: 'Download MJASI POS: $publicUrl',
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Could not share downloads page: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share the link.')),
      );
    }
  }

  Future<void> _copyPublicPage() async {
    try {
      await Clipboard.setData(const ClipboardData(text: publicUrl));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Link copied.')));
    } catch (error, stackTrace) {
      debugPrint('Could not copy downloads page link: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not copy the link.')));
    }
  }

  String? _httpsValidator(String key, String? value) {
    final text = value?.trim() ?? '';
    if (!_enabled[key]!) return null;
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return 'Enter a valid https:// link';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F8),
      appBar: AppBar(title: const Text('Downloads page')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.public_rounded),
                      title: const Text('Public page'),
                      subtitle: SelectableText(publicUrl),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'Share download page',
                            icon: const Icon(Icons.share_rounded),
                            onPressed: _sharePublicPage,
                          ),
                          IconButton(
                            tooltip: 'Copy link',
                            icon: const Icon(Icons.copy_rounded),
                            onPressed: _copyPublicPage,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _StatsCard(future: _statsFuture),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _title,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _subtitle,
                    maxLength: 300,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  for (final d in downloadItemDefs)
                    Card(
                      margin: const EdgeInsets.only(top: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              secondary: Icon(d.icon),
                              title: Text(d.title),
                              subtitle: const Text('Show on public page'),
                              value: _enabled[d.key]!,
                              onChanged: (v) =>
                                  setState(() => _enabled[d.key] = v),
                            ),
                            TextFormField(
                              controller: _urls[d.key],
                              keyboardType: TextInputType.url,
                              decoration: const InputDecoration(
                                labelText: 'Download link (https)',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) => _httpsValidator(d.key, v),
                            ),
                            if (d.key == 'apk' || d.key == 'windows') ...[
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  onPressed: _uploadProgress.containsKey(d.key)
                                      ? null
                                      : () => _uploadFile(d.key),
                                  icon: const Icon(Icons.upload_file_rounded),
                                  label: Text(
                                    d.key == 'apk'
                                        ? 'Upload APK file'
                                        : 'Upload Windows file (.zip, .exe, .msix)',
                                  ),
                                ),
                              ),
                              if (_uploadProgress.containsKey(d.key))
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: LinearProgressIndicator(
                                    value: _uploadProgress[d.key],
                                  ),
                                ),
                              if (_uploadedLinks[d.key] case final link?)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: SelectableText(
                                          link,
                                          maxLines: 2,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Copy download link',
                                        onPressed: () =>
                                            _copyUploadedLink(d.key),
                                        icon: const Icon(Icons.copy_rounded),
                                      ),
                                    ],
                                  ),
                                ),
                              if (_uploadedLinks.containsKey(d.key))
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Save downloads page to publish this link.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ),
                            ],
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _versions[d.key],
                              maxLength: 30,
                              decoration: const InputDecoration(
                                labelText: 'Version label (optional)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: const Text('Save downloads page'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.future});

  final Future<Map<String, int>> future;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<Map<String, int>>(
          future: future,
          builder: (context, snap) {
            final stats = snap.data ?? const <String, int>{};
            final visits = stats['visits'] ?? 0;
            final clicks = {
              for (final d in downloadItemDefs)
                d.key: stats['click_${d.key}'] ?? 0,
            };
            final totalClicks = clicks.values.fold<int>(0, (a, b) => a + b);
            final rate = visits > 0
                ? '${(totalClicks / visits * 100).toStringAsFixed(1)}%'
                : '—';
            Widget metric(IconData icon, String label, String value) {
              return Expanded(
                child: Column(
                  children: [
                    Icon(icon, color: const Color(0xFF0E5962)),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      label,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Page statistics',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 12),
                if (snap.connectionState == ConnectionState.waiting)
                  const LinearProgressIndicator()
                else ...[
                  Row(
                    children: [
                      metric(Icons.visibility_outlined, 'Visitors', '$visits'),
                      metric(
                        Icons.download_rounded,
                        'Download clicks',
                        '$totalClicks',
                      ),
                      metric(Icons.percent_rounded, 'Click rate', rate),
                    ],
                  ),
                  const Divider(height: 24),
                  for (final d in downloadItemDefs)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(d.icon, size: 18, color: Colors.grey.shade700),
                          const SizedBox(width: 8),
                          Expanded(child: Text(d.title)),
                          Text(
                            '${clicks[d.key]}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  if (snap.hasError)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Could not load statistics.',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
