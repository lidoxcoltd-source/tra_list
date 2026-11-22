import 'package:cloud_functions/cloud_functions.dart';
import 'package:tra_list/business_intelligence/ai_models.dart';
import 'package:tra_list/services/business_access_service.dart';

class DailyBusinessBrief {
  const DailyBusinessBrief({
    required this.answer,
    required this.facts,
    required this.model,
  });

  final String answer;
  final Map<String, dynamic> facts;
  final String model;
}

class DailyBusinessBriefService {
  DailyBusinessBriefService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<DailyBusinessBrief> generate({
    required DateTime now,
    required String language,
  }) async {
    await AiModelSelection.load();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final timeOfDay = switch (now.hour) {
      >= 5 && < 12 => 'morning',
      >= 12 && < 17 => 'afternoon',
      _ => 'evening',
    };
    final model = AiModelSelection.selectedId.value;
    final response = await _functions
        .httpsCallable('generateDailyBusinessBrief')
        .call({
          'businessUid': BusinessAccessService.businessId,
          'startMillis': start.millisecondsSinceEpoch,
          'endMillis': end.millisecondsSinceEpoch,
          'timezoneOffsetMinutes': now.timeZoneOffset.inMinutes,
          'language': language,
          'timeOfDay': timeOfDay,
          if (model != null) 'model': model,
        });
    final data = Map<String, dynamic>.from(response.data as Map);
    return DailyBusinessBrief(
      answer: data['answer']?.toString() ?? '',
      facts: Map<String, dynamic>.from(data['facts'] as Map),
      model: data['model']?.toString() ?? '',
    );
  }
}
