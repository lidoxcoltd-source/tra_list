import 'package:tra_list/business_intelligence/business_context.dart';

class AiSnapshot {
  const AiSnapshot(this.context, this.token);
  final Map<String, dynamic> context;
  final String token;
}

abstract class AIProvider {
  Future<AiSnapshot> prepare(BusinessContext context);
  Future<String> respond({
    required BusinessContext context,
    required AiSnapshot snapshot,
    required List<Map<String, String>> messages,
    required String language,
    String? messageId,
  });
}

class AiDocumentReview {
  const AiDocumentReview(this.details, this.token);
  final Map<String, dynamic> details;
  final String token;
}

abstract class AiDocumentReviewProvider {
  Future<AiDocumentReview?> prepareDocumentReview({
    required BusinessContext context,
    required AiSnapshot snapshot,
    required String question,
  });
}
