import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:printing/printing.dart';
import 'package:tra_list/services/business_access_service.dart';

class StaffAiReviewPage extends StatefulWidget {
  const StaffAiReviewPage({
    super.key,
    required this.businessId,
    required this.isCurrent,
  });

  final String businessId;
  final bool Function() isCurrent;

  @override
  State<StaffAiReviewPage> createState() => _StaffAiReviewPageState();
}

class _StaffAiReviewPageState extends State<StaffAiReviewPage> {
  int _chatLimit = 50;

  bool get _hasAccess =>
      widget.isCurrent() &&
      BusinessAccessService.hasBusinessAccess &&
      BusinessAccessService.isOwner.value &&
      BusinessAccessService.businessId == widget.businessId;

  @override
  Widget build(BuildContext context) => Obx(() {
    if (!_hasAccess) {
      return Scaffold(
        appBar: AppBar(title: Text('bi_staff_review_title'.tr)),
        body: Center(child: Text('bi_access_error'.tr)),
      );
    }
    final chats = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.businessId)
        .collection('chats')
        .orderBy('updatedAt', descending: true)
        .limit(_chatLimit + 1);
    return Scaffold(
      appBar: AppBar(title: Text('bi_staff_review_title'.tr)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('bi_staff_review_choose'.tr),
          ),
          Expanded(
            child: StreamBuilder(
              stream: chats.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('bi_staff_review_load_error'.tr));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs.take(_chatLimit).toList();
                final hasMore = snapshot.data!.docs.length > _chatLimit;
                if (docs.isEmpty) {
                  return Center(child: Text('bi_staff_review_no_chats'.tr));
                }
                return ListView.builder(
                  itemCount: docs.length + (hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == docs.length) {
                      return TextButton(
                        onPressed: () => setState(() => _chatLimit += 50),
                        child: Text('bi_staff_review_more'.tr),
                      );
                    }
                    final chat = docs[index];
                    final data = chat.data();
                    final names = data['participantNames'];
                    final groupTitle = data['title'];
                    final title =
                        groupTitle is String && groupTitle.trim().isNotEmpty
                        ? groupTitle.trim()
                        : names is Map
                        ? names.values
                              .map((value) => value.toString())
                              .join(', ')
                        : '';
                    return ExpansionTile(
                      leading: const Icon(Icons.forum_outlined),
                      title: Text(
                        title.isEmpty ? 'bi_staff_review_chat'.tr : title,
                      ),
                      children: [
                        _Messages(
                          businessId: widget.businessId,
                          conversationId: chat.id,
                          isCurrent: () => _hasAccess,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  });
}

class _Messages extends StatefulWidget {
  const _Messages({
    required this.businessId,
    required this.conversationId,
    required this.isCurrent,
  });

  final String businessId;
  final String conversationId;
  final bool Function() isCurrent;

  @override
  State<_Messages> createState() => _MessagesState();
}

class _MessagesState extends State<_Messages> {
  int _messageLimit = 100;

  void _open(
    BuildContext context,
    String messageId,
    String kind, [
    int? index,
  ]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StaffAiReviewItemPage(
          businessId: widget.businessId,
          isCurrent: widget.isCurrent,
          selection: {
            'conversationId': widget.conversationId,
            'messageId': messageId,
            'kind': kind,
            if (index != null) 'attachmentIndex': index,
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.businessId)
        .collection('chats')
        .doc(widget.conversationId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(_messageLimit + 1);
    return StreamBuilder(
      stream: messages.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ListTile(title: Text('bi_staff_review_load_error'.tr));
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          );
        }
        if (snapshot.data!.docs.isEmpty) {
          return ListTile(title: Text('bi_staff_review_no_messages'.tr));
        }
        return Column(
          children: [
            for (final doc in snapshot.data!.docs.take(_messageLimit))
              Builder(
                builder: (context) {
                  final data = doc.data();
                  final text = data['text'] is String
                      ? data['text'] as String
                      : '';
                  final attachments = data['attachments'] is List
                      ? data['attachments'] as List
                      : const [];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (text.trim().isNotEmpty)
                        ListTile(
                          leading: const Icon(Icons.text_snippet_outlined),
                          title: Text(data['senderName']?.toString() ?? ''),
                          subtitle: Text(
                            text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _open(context, doc.id, 'text'),
                        ),
                      for (var i = 0; i < attachments.length && i < 5; i++)
                        Builder(
                          builder: (context) {
                            final value = attachments[i];
                            final attachment = value is Map ? value : const {};
                            final type = attachment['contentType'];
                            final size = attachment['size'];
                            final supported =
                                const {
                                  'image/jpeg',
                                  'image/png',
                                  'image/webp',
                                  'application/pdf',
                                }.contains(type) &&
                                size is int &&
                                size > 0 &&
                                size <= 5 * 1024 * 1024;
                            return ListTile(
                              leading: Icon(
                                type == 'application/pdf'
                                    ? Icons.picture_as_pdf_outlined
                                    : Icons.image_outlined,
                              ),
                              title: Text(
                                attachment['name']?.toString() ??
                                    'bi_staff_review_file'.tr,
                              ),
                              subtitle: Text(
                                supported
                                    ? 'bi_staff_review_preview'.tr
                                    : 'bi_staff_review_unsupported'.tr,
                              ),
                              enabled: supported,
                              onTap: supported
                                  ? () =>
                                        _open(context, doc.id, 'attachment', i)
                                  : null,
                            );
                          },
                        ),
                      if (snapshot.data!.docs.length > _messageLimit)
                        TextButton(
                          onPressed: () => setState(() => _messageLimit += 100),
                          child: Text('bi_staff_review_more'.tr),
                        ),
                    ],
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

abstract class StaffAiReviewClient {
  Future<Map<String, dynamic>> prepare(
    String businessId,
    Map<String, Object> selection,
  );
  Future<String> analyze(
    String businessId,
    Map<String, Object> selection,
    String token,
    String question,
    String language,
  );
}

class CloudStaffAiReviewClient implements StaffAiReviewClient {
  @override
  Future<Map<String, dynamic>> prepare(
    String businessId,
    Map<String, Object> selection,
  ) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('prepareStaffAiReview')
        .call<Map<String, dynamic>>({
          'businessUid': businessId,
          'selection': [selection],
        });
    return result.data;
  }

  @override
  Future<String> analyze(
    String businessId,
    Map<String, Object> selection,
    String token,
    String question,
    String language,
  ) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable(
          'analyzeStaffAiReview',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 100)),
        )
        .call<Map<String, dynamic>>({
          'businessUid': businessId,
          'selection': [selection],
          'token': token,
          'question': question,
          'language': language,
        });
    return result.data['answer'] as String;
  }
}

class StaffAiReviewItemPage extends StatefulWidget {
  const StaffAiReviewItemPage({
    required this.businessId,
    required this.isCurrent,
    required this.selection,
    this.client,
    super.key,
  });
  final String businessId;
  final bool Function() isCurrent;
  final Map<String, Object> selection;
  final StaffAiReviewClient? client;

  @override
  State<StaffAiReviewItemPage> createState() => _ReviewItemState();
}

class _ReviewItemState extends State<StaffAiReviewItemPage> {
  final _question = TextEditingController();
  late final StaffAiReviewClient _client;
  bool _loading = true;
  bool _sending = false;
  bool _confirmed = false;
  bool _previewReady = false;
  String? _error;
  String? _answer;
  String? _token;
  String? _text;
  String? _contentType;
  Uint8List? _bytes;
  List<Uint8List>? _pdfPages;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? CloudStaffAiReviewClient();
    _prepare();
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    setState(() {
      _loading = true;
      _error = null;
      _confirmed = false;
      _previewReady = false;
      _token = null;
      _bytes = null;
      _pdfPages = null;
      _text = null;
    });
    try {
      final result = await _client.prepare(widget.businessId, widget.selection);
      final item = Map<String, dynamic>.from(result['item'] as Map);
      final token = result['token'] as String;
      final type = item['contentType'] as String?;
      final text = item['text'] as String?;
      final bytes = item['data'] is String
          ? base64Decode(item['data'] as String)
          : null;
      List<Uint8List>? pages;
      if (type == 'application/pdf' && bytes != null) {
        pages = [];
        var totalBytes = 0;
        await for (final page in Printing.raster(bytes, dpi: 72)) {
          if (pages.length >= 20) {
            throw StateError('PDF preview exceeds 20 pages.');
          }
          final image = await page.toPng();
          totalBytes += image.length;
          if (totalBytes > 32 * 1024 * 1024) {
            throw StateError('PDF preview exceeds memory limit.');
          }
          pages.add(image);
        }
        if (pages.isEmpty) throw StateError('PDF preview is empty.');
      }
      if (!mounted || !widget.isCurrent()) return;
      setState(() {
        _token = token;
        _contentType = type;
        _text = text;
        _bytes = bytes;
        _pdfPages = pages;
        _previewReady = text != null || pages != null;
      });
    } catch (error, stack) {
      debugPrint('Staff review preparation failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) setState(() => _error = 'bi_staff_review_prepare_error'.tr);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    if (_sending ||
        !_confirmed ||
        !_previewReady ||
        _token == null ||
        !widget.isCurrent()) {
      return;
    }
    final question = _question.text.trim();
    if (question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('bi_staff_review_question_required'.tr)),
      );
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _answer = null;
    });
    try {
      final answer = await _client.analyze(
        widget.businessId,
        widget.selection,
        _token!,
        question,
        Get.locale?.languageCode ?? 'en',
      );
      if (!mounted || !widget.isCurrent()) return;
      setState(() {
        _answer = answer;
        _confirmed = false;
      });
    } on FirebaseFunctionsException catch (error, stack) {
      debugPrint('Staff review analysis failed: ${error.code}');
      debugPrintStack(stackTrace: stack);
      if (mounted && widget.isCurrent()) {
        setState(() {
          _error = error.code == 'failed-precondition'
              ? 'bi_staff_review_expired'.tr
              : error.code == 'resource-exhausted'
              ? 'bi_chat_limit_error'.tr
              : error.code == 'permission-denied' ||
                    error.code == 'unauthenticated'
              ? 'bi_access_error'.tr
              : 'bi_staff_review_send_error'.tr;
        });
      }
    } catch (error, stack) {
      debugPrint('Staff review analysis failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted && widget.isCurrent()) {
        setState(() => _error = 'bi_staff_review_send_error'.tr);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _setPreviewReady(bool ready) {
    if (_previewReady == ready) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _previewReady != ready) {
        setState(() {
          _previewReady = ready;
          if (!ready) _confirmed = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    if (!widget.isCurrent()) {
      return Scaffold(
        appBar: AppBar(title: Text('bi_staff_review_preview'.tr)),
        body: Center(child: Text('bi_access_error'.tr)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text('bi_staff_review_preview'.tr)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('bi_staff_review_warning'.tr),
                const SizedBox(height: 12),
                if (_text != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(_text!),
                    ),
                  ),
                if (_pdfPages != null)
                  SizedBox(
                    height: 480,
                    child: ListView.builder(
                      itemCount: _pdfPages!.length,
                      itemBuilder: (_, index) => InteractiveViewer(
                        child: Image.memory(_pdfPages![index]),
                      ),
                    ),
                  ),
                if (_bytes != null && _contentType != 'application/pdf')
                  SizedBox(
                    height: 360,
                    child: InteractiveViewer(
                      child: Image.memory(
                        _bytes!,
                        frameBuilder: (context, child, frame, synchronous) {
                          if (frame != null || synchronous) {
                            _setPreviewReady(true);
                          }
                          return child;
                        },
                        errorBuilder: (_, _, _) {
                          _setPreviewReady(false);
                          return Center(
                            child: Text('bi_staff_review_load_error'.tr),
                          );
                        },
                      ),
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: _sending ? null : _prepare,
                    child: Text('bi_staff_review_retry'.tr),
                  ),
                ],
                if (_token != null) ...[
                  CheckboxListTile(
                    value: _confirmed,
                    onChanged: _sending || !_previewReady
                        ? null
                        : (value) => setState(() => _confirmed = value == true),
                    title: Text('bi_staff_review_confirm'.tr),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  TextField(
                    controller: _question,
                    maxLength: 2000,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'bi_staff_review_question'.tr,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: !_confirmed || !_previewReady || _sending
                        ? null
                        : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text('bi_staff_review_send'.tr),
                  ),
                ],
                if (_answer != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Isher AI',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(_answer!),
                  const SizedBox(height: 12),
                  Text('bi_staff_review_not_saved'.tr),
                ],
              ],
            ),
    );
  });
}
