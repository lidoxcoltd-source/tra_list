import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import 'package:tra_list/business_intelligence/business_context.dart';

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

class AiHistoryPage {
  const AiHistoryPage(this.messages, this.hasMore);
  final List<AiChatMessage> messages;
  final bool hasMore;
}

class CloudAiHistoryRepository implements AiHistoryRepository {
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
        period: message['periodStartMillis'] is num && message['periodEndMillis'] is num
            ? ReportingPeriod(
                DateTime.fromMillisecondsSinceEpoch((message['periodStartMillis'] as num).toInt()),
                DateTime.fromMillisecondsSinceEpoch((message['periodEndMillis'] as num).toInt()),
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
}

AiChatMessage newAiChatMessage(String role, String content, {ReportingPeriod? period}) => AiChatMessage(
  id: const Uuid().v4(),
  role: role,
  content: content,
  createdAt: DateTime.now(),
  period: period,
);
