import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  static String get publicUrl => '${Uri.base.origin}/downloads';

  final Map<String, double?> _uploadProgress = {};

  Future<void> _uploadFile(String key) async {
    final extensions = key == 'apk' ? ['apk'] : ['zip', 'exe', 'msix', 'msi'];
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: true,
    );
    final file = picked?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;

    final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final ref = FirebaseStorage.instance.ref('downloads/${key}_$safeName');
    setState(() {
      _uploadProgress[key] = 0;
      _error = null;
    });
    try {
      final task = ref.putData(
        bytes,
        SettableMetadata(contentType: 'application/octet-stream'),
      );
      task.snapshotEvents.listen((s) {
        if (!mounted || s.totalBytes == 0) return;
        setState(
          () => _uploadProgress[key] = s.bytesTransferred / s.totalBytes,
        );
      });
      await task;
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() {
        _urls[key]!.text = url;
        _enabled[key] = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${file.name} uploaded. Press Save to publish it.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Upload failed: $error');
    } finally {
      if (mounted) setState(() => _uploadProgress.remove(key));
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
                      trailing: IconButton(
                        tooltip: 'Copy link',
                        icon: const Icon(Icons.copy_rounded),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: publicUrl));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link copied.')),
                          );
                        },
                      ),
                    ),
                  ),
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
