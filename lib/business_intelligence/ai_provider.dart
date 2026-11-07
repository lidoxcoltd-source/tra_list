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
  });
}
