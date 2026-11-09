import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import 'package:tra_list/business_intelligence/business_context.dart';

const _documentEventPrefix = 'MJASI_DOCUMENT_EVENT_V1:';

class AiDocumentHistoryEvent {
  const AiDocumentHistoryEvent(this.text, {this.invoiceId});
  final String text;
  final String? invoiceId;
}

String encodeDocumentHistoryEvent(String text, {String? invoiceId}) =>
    '$_documentEventPrefix${jsonEncode({'text': text, if (invoiceId != null) 'invoiceId': invoiceId})}';

String encodeBoundedDocumentHistoryEvent(
  String text, {
  required String truncatedNotice,
  String? invoiceId,
}) {
  final encoded = encodeDocumentHistoryEvent(text, invoiceId: invoiceId);
  if (encoded.length <= 12000) return encoded;
  final runes = text.runes.toList();
  var low = 0;
  var high = runes.length;
  while (low < high) {
    final middle = (low + high + 1) ~/ 2;
    final candidate = encodeDocumentHistoryEvent(
      '${String.fromCharCodes(runes.take(middle))}\n$truncatedNotice',
      invoiceId: invoiceId,
    );
    if (candidate.length <= 12000) {
      low = middle;
    } else {
      high = middle - 1;
    }
  }
  return encodeDocumentHistoryEvent(
    '${String.fromCharCodes(runes.take(low))}\n$truncatedNotice',
    invoiceId: invoiceId,
  );
}

AiDocumentHistoryEvent? decodeDocumentHistoryEvent(AiChatMessage message) {
  if (!message.content.startsWith(_documentEventPrefix)) return null;
  try {
    final value = jsonDecode(
      message.content.substring(_documentEventPrefix.length),
    );
    if (value is! Map ||
        value['text'] is! String ||
        (value['text'] as String).isEmpty) {
      return null;
    }
    final id = value['invoiceId'];
    if (id != null &&
        (message.role != 'assistant' ||
            id is! String ||
            !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id))) {
      return null;
    }
    return AiDocumentHistoryEvent(
      value['text'] as String,
      invoiceId: id as String?,
    );
  } on FormatException {
    return null;
  }
}

class AiChatMessage {
  const AiChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.period,
  });

  final String id;
  final String role;
  final String content;
  final DateTime createdAt;
  final ReportingPeriod? period;
}

abstract class AiHistoryRepository {
  Future<AiHistoryPage> load(String businessId, {String? before});
  Future<void> save(String businessId, AiChatMessage message);
}

abstract class AiHistoryEditing {
  Future<void> edit(String businessId, String messageId, String content);
  Future<void> delete(String businessId, String messageId);
}

class AiHistoryPage {
  const AiHistoryPage(this.messages, this.hasMore);
  final List<AiChatMessage> messages;
  final bool hasMore;
}

class AiHistoryCache {
  BusinessContext? _context;
  AiHistoryPage? _page;

  AiHistoryPage? read(BusinessContext context) =>
      identical(_context, context) ? _page : null;

  void store(
    BusinessContext context,
    List<AiChatMessage> messages,
    bool hasMore,
  ) {
    _context = context;
    _page = AiHistoryPage(List.unmodifiable(messages), hasMore);
  }

  void clear() {
    _context = null;
    _page = null;
  }
}

class CloudAiHistoryRepository implements AiHistoryRepository, AiHistoryEditing {
  CloudAiHistoryRepository({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;
  final FirebaseFunctions _functions;

  @override
  Future<AiHistoryPage> load(String businessId, {String? before}) async {
    final result = await _functions.httpsCallable('loadBusinessAiHistory').call(
      {'businessUid': businessId, if (before != null) 'before': before},
    );
    final data = Map<String, dynamic>.from(result.data as Map);
    final messages = (data['messages'] as List).map((value) {
      final message = Map<String, dynamic>.from(value as Map);
      return AiChatMessage(
        id: message['id'] as String,
        role: message['role'] as String,
        content: message['content'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (message['createdAt'] as num).toInt(),
        ),
        period:
            message['periodStartMillis'] is num &&
                message['periodEndMillis'] is num
            ? ReportingPeriod(
                DateTime.fromMillisecondsSinceEpoch(
                  (message['periodStartMillis'] as num).toInt(),
                ),
                DateTime.fromMillisecondsSinceEpoch(
                  (message['periodEndMillis'] as num).toInt(),
                ),
              )
            : null,
      );
    }).toList();
    return AiHistoryPage(messages, data['hasMore'] as bool);
  }

  @override
  Future<void> save(String businessId, AiChatMessage message) async {
    await _functions.httpsCallable('saveBusinessAiMessage').call({
      'businessUid': businessId,
      'messageId': message.id,
      'message': {
        'role': message.role,
        'content': message.content,
        if (message.period != null) ...{
          'periodStartMillis': message.period!.start.millisecondsSinceEpoch,
          'periodEndMillis': message.period!.end.millisecondsSinceEpoch,
        },
      },
    });
  }

  @override
  Future<void> edit(String businessId, String messageId, String content) async {
    await _functions.httpsCallable('changeBusinessAiMessage').call({
      'businessUid': businessId,
      'messageId': messageId,
      'action': 'edit',
      'content': content,
    });
  }

  @override
  Future<void> delete(String businessId, String messageId) async {
    await _functions.httpsCallable('changeBusinessAiMessage').call({
      'businessUid': businessId,
      'messageId': messageId,
      'action': 'delete',
    });
  }
}

AiChatMessage newAiChatMessage(
  String role,
  String content, {
  ReportingPeriod? period,
}) => AiChatMessage(
  id: const Uuid().v4(),
  role: role,
  content: content,
  createdAt: DateTime.now(),
  period: period,
);
