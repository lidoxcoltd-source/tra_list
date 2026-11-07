import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/business_intelligence/chat_period.dart';

void main() {
  final now = DateTime(2026, 11, 7, 12);

  test('full dates select the exact day', () {
    for (final question in [
      'biashara tarehe 2024-02-02 iliendaje?',
      'biashara 02/02/2024 iliendaje?',
      'biashara 2 februari 2024 iliendaje?',
    ]) {
      final result = resolveChatPeriod(question, now);
      expect(result.kind, ChatPeriodKind.resolved);
      expect(result.period!.start, DateTime(2024, 2, 2));
      expect(result.period!.end, DateTime(2024, 2, 3));
    }
  });

  test('incomplete and invalid dates require selection', () {
    expect(resolveChatPeriod('biashara tarhe 2 ilienda je', now).kind,
        ChatPeriodKind.needsSelection);
    expect(resolveChatPeriod('tarehe 31/02/2024', now).kind,
        ChatPeriodKind.needsSelection);
    expect(resolveChatPeriod('mauzo wiki iliyopita', now).kind,
        ChatPeriodKind.needsSelection);
  });

  test('follow-ups retain period and comparisons are not silently aggregated', () {
    expect(resolveChatPeriod('Je, matumizi?', now).kind, ChatPeriodKind.none);
    expect(resolveChatPeriod('Linganisha mwezi huu na uliopita', now).kind,
        ChatPeriodKind.comparison);
    final yesterday = resolveChatPeriod('jana', now);
    expect(yesterday.period!.start, DateTime(2026, 11, 6));
    expect(yesterday.period!.end, DateTime(2026, 11, 7));
  });
}
