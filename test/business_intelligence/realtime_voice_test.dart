import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/ai_provider.dart';
import 'package:tra_list/business_intelligence/business_context.dart';
import 'package:tra_list/business_intelligence/realtime_voice.dart';
import 'package:tra_list/invoice/app_translations.dart';

class _Provider implements AIProvider {
  int preparations = 0;

  @override
  Future<AiSnapshot> prepare(BusinessContext context) async {
    preparations++;
    return const AiSnapshot({'businessName': 'Duka'}, 'snapshot');
  }

  @override
  Future<String> respond({
    required BusinessContext context,
    required AiSnapshot snapshot,
    required List<Map<String, String>> messages,
    required String language,
  }) => throw UnimplementedError();
}

void main() {
  testWidgets('voice requires review and cancellation does not start session', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final provider = _Provider();
    final business = BusinessContext(
      businessId: 'business',
      businessName: 'Duka',
      period: ReportingPeriod(DateTime(2024), DateTime(2024, 2)),
      updatedAt: DateTime(2024),
      income: 100,
      expenses: 10,
      transactionCount: 1,
      expenseCategories: const {},
      lowStock: null,
      receivable: null,
      payable: null,
      limitations: const [],
    );
    final current = true.obs;
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: Scaffold(
          body: BusinessRealtimeVoice(
            businessContext: business,
            isCurrent: () => current.value,
            provider: provider,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Anza sauti'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(provider.preparations, 1);
    expect(find.text('Kagua na uanze mazungumzo ya sauti'), findsOneWidget);
    expect(find.textContaining('Jina la biashara'), findsOneWidget);
    expect(find.text('Kubali na uanze'), findsOneWidget);
    current.value = false;
    await tester.pump();
    expect(find.text('Kubali na uanze'), findsNothing);
    await tester.tap(find.text('cancel'.tr));
    await tester.pumpAndSettle();
    expect(
      find.text('Kipaza sauti kiko wazi. Sauti yako inatumwa OpenAI.'),
      findsNothing,
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
