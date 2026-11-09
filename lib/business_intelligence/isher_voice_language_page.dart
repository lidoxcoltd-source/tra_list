import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class IsherVoiceLanguagePage extends StatefulWidget {
  const IsherVoiceLanguagePage({
    super.key,
    this.call,
    this.pickFile,
    this.saveSample,
  });

  final Future<Map<String, dynamic>> Function(
    String name,
    Map<String, dynamic> data,
  )?
  call;
  final Future<PlatformFile?> Function()? pickFile;
  final Future<String?> Function(Uint8List bytes)? saveSample;

  @override
  State<IsherVoiceLanguagePage> createState() => _IsherVoiceLanguagePageState();
}

class _IsherVoiceLanguagePageState extends State<IsherVoiceLanguagePage> {
  final _name = TextEditingController();
  final _test = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _csv;
  String? _fileName;
  String? _activeId;
  List<Map<String, dynamic>> _preview = [];
  List<Map<String, dynamic>> _versions = [];
  bool _hasMore = false;
  bool _loaded = false;

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final customCall = widget.call;
    if (customCall != null) return customCall(name, data);
    final result = await FirebaseFunctions.instance
        .httpsCallable(name)
        .call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _test.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await _call('listIsherVoiceExamples', {});
      if (!mounted) return;
      setState(() {
        _activeId = data['activeId'] as String?;
        _versions = (data['versions'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _hasMore = data['hasMore'] == true;
        _loaded = true;
      });
    } catch (error, stack) {
      debugPrint('Voice language versions load failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        setState(() {
          _loaded = false;
          _versions = [];
          _activeId = null;
          _error = 'isher_language_load_error'.tr;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    setState(() => _busy = true);
    try {
      final customPicker = widget.pickFile;
      final PlatformFile? file;
      if (customPicker != null) {
        file = await customPicker();
      } else {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['csv'],
          withData: true,
        );
        file = picked?.files.single;
      }
      if (file == null || !mounted) return;
      if (file.size > 16384 || file.bytes == null) {
        _notice('isher_language_file_error'.tr);
        return;
      }
      final fileName = file.name;
      final csv = utf8.decode(file.bytes!, allowMalformed: false);
      setState(() {
        _busy = true;
        _csv = null;
        _fileName = null;
        _preview = [];
      });
      final data = await _call('previewIsherVoiceExamples', {'csv': csv});
      if (!mounted) return;
      setState(() {
        _csv = csv;
        _fileName = fileName;
        _name.text = fileName.replaceFirst(
          RegExp(r'\.csv$', caseSensitive: false),
          '',
        );
        _preview = (data['examples'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      });
    } on FirebaseFunctionsException catch (error, stack) {
      debugPrint('Voice language preview failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        _notice(
          '${'isher_language_invalid'.tr}: ${error.message ?? error.code}',
        );
      }
    } on FormatException catch (error, stack) {
      debugPrint('Invalid voice language file: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) _notice('isher_language_file_error'.tr);
    } catch (error, stack) {
      debugPrint('Voice language file selection failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) _notice('isher_language_file_error'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadSample() async {
    setState(() => _busy = true);
    try {
      final data = await rootBundle.load('assets/isher_voice_sample.csv');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final customSave = widget.saveSample;
      final path = customSave != null
          ? await customSave(bytes)
          : await FilePicker.platform.saveFile(
              dialogTitle: 'isher_language_download'.tr,
              fileName: 'isher_voice_sample.csv',
              type: FileType.custom,
              allowedExtensions: const ['csv'],
              bytes: bytes,
            );
      if (!mounted) return;
      if (kIsWeb && customSave == null) {
        _notice('isher_language_download_started'.tr);
      } else if (path != null) {
        _notice('isher_language_download_saved'.tr);
      }
    } catch (error, stack) {
      debugPrint('Voice language sample download failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) _notice('isher_language_download_error'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final csv = _csv;
    final name = _name.text.trim();
    if (csv == null || name.isEmpty || name.length > 80) {
      _notice('isher_language_name_error'.tr);
      return;
    }
    setState(() => _busy = true);
    try {
      await _call('saveIsherVoiceExamples', {'csv': csv, 'name': name});
      if (!mounted) return;
      setState(() {
        _csv = null;
        _fileName = null;
        _preview = [];
        _name.clear();
      });
      _notice('isher_language_saved'.tr);
      await _load();
    } catch (error, stack) {
      debugPrint('Voice language save failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) _notice('isher_language_save_error'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _activate(String? id, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('isher_language_activate'.tr),
        content: Text('isher_language_confirm'.trParams({'name': label})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('isher_language_activate'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _call('activateIsherVoiceExamples', {'versionId': id});
      if (!mounted) return;
      _notice('isher_language_activated'.tr);
      await _load();
    } catch (error, stack) {
      debugPrint('Voice language activation failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) _notice('isher_language_save_error'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notice(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  void _showVersion(Map<String, dynamic> version) {
    final examples = (version['examples'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(version['name'] as String),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(child: _examples(examples)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('close'.tr),
          ),
        ],
      ),
    );
  }

  Widget _examples(List<Map<String, dynamic>> examples) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final example in examples)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text('${example['number']} → ${example['spoken']}'),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final query = _test.text.trim();
    final matching = _preview.where((item) => item['number'] == query).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text('isher_language_title'.tr),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            Text(_error!),
            TextButton(
              onPressed: _busy ? null : _load,
              child: Text('refresh'.tr),
            ),
          ],
          Text('isher_language_intro'.tr),
          const SizedBox(height: 12),
          Text('isher_language_sample_instructions'.tr),
          OutlinedButton.icon(
            onPressed: _busy ? null : _downloadSample,
            icon: const Icon(Icons.download),
            label: Text('isher_language_download'.tr),
          ),
          const SizedBox(height: 12),
          SelectableText(
            'number,spoken\n30000,shilingi elfu thelathini\n12.5%,asilimia kumi na mbili nukta tano',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.upload_file),
            label: Text('isher_language_pick'.tr),
          ),
          if (_fileName != null) ...[
            Text(_fileName!),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              maxLength: 80,
              decoration: InputDecoration(labelText: 'isher_language_name'.tr),
            ),
            Text('isher_language_review'.tr),
            _examples(_preview),
            TextField(
              controller: _test,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: 'isher_language_test'.tr),
            ),
            if (query.isNotEmpty)
              Text(
                matching.isEmpty
                    ? 'isher_language_no_match'.tr
                    : '${matching.first['spoken']}',
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text('isher_language_save'.tr),
            ),
          ],
          const Divider(height: 40),
          Text(
            'isher_language_versions'.tr,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text('isher_language_voice_test'.tr),
          if (_loaded)
            ListTile(
              title: Text('isher_language_default'.tr),
              subtitle: _activeId == null
                  ? Text('isher_language_active'.tr)
                  : null,
              trailing: _activeId == null
                  ? null
                  : TextButton(
                      onPressed: _busy
                          ? null
                          : () => _activate(null, 'isher_language_default'.tr),
                      child: Text('isher_language_activate'.tr),
                    ),
            ),
          for (final version in _versions)
            ListTile(
              title: Text(version['name'] as String),
              subtitle: Text(
                [
                  if (version['id'] == _activeId) 'isher_language_active'.tr,
                  if (version['createdAt'] is num)
                    DateFormat.yMMMd().add_Hm().format(
                      DateTime.fromMillisecondsSinceEpoch(
                        (version['createdAt'] as num).toInt(),
                      ),
                    ),
                ].join(' · '),
              ),
              onTap: () => _showVersion(version),
              trailing: version['id'] == _activeId
                  ? null
                  : TextButton(
                      onPressed: _busy
                          ? null
                          : () => _activate(
                              version['id'] as String,
                              version['name'] as String,
                            ),
                      child: Text('isher_language_activate'.tr),
                    ),
            ),
          if (_hasMore) Text('isher_language_limited'.tr),
        ],
      ),
    );
  }
}
