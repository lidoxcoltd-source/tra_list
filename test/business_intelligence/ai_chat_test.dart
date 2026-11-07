import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/ai_assistant_page.dart';
import 'package:tra_list/business_intelligence/ai_chat.dart';
import 'package:tra_list/business_intelligence/ai_history.dart';
import 'package:tra_list/business_intelligence/ai_provider.dart';
import 'package:tra_list/business_intelligence/business_context.dart';
import 'package:tra_list/invoice/app_translations.dart';

class FakeProvider implements AIProvider {
  int sends = 0;
  String? language;
  List<Map<String, String>> messages = [];

  @override
  Future<AiSnapshot> prepare(BusinessContext context) async =>
      const AiSnapshot({'businessName': 'Duka', 'income': 100}, 'token');

  @override
  Future<String> respond({
    required BusinessContext context,
    required AiSnapshot snapshot,
    required List<Map<String, String>> messages,
    required String language,
  }) async {
    sends++;
    this.language = language;
    this.messages = messages;
    return 'Jibu la biashara';
  }
}

class FakeHistory implements AiHistoryRepository {
  final messages = <AiChatMessage>[];
  bool failAnswer = false;
  @override
  Future<AiHistoryPage> load(String businessId, {String? before}) async =>
      AiHistoryPage(List.of(messages), false);

  @override
  Future<void> save(String businessId, AiChatMessage message) async {
    if (failAnswer && message.role == 'assistant') throw StateError('offline');
    messages.add(message);
  }
}

void main() {
  testWidgets('chat and call are separate tabs and preserve the draft', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
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
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: AiAssistantPage(
          business: Rxn<BusinessContext>(business),
          loading: false.obs,
          error: ''.obs,
          provider: FakeProvider(),
          historyRepository: FakeHistory(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Draft');
    await tester.tap(find.text('Simu'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Mazungumzo ya sauti yanapatikana kwenye Android pekee kwa sasa.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Draft',
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Swahili chat sends only after review and retains follow-ups', (
    tester,
  ) async {
    final provider = FakeProvider();
    final history = FakeHistory();
    final current = true.obs;
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
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: Scaffold(
          body: BusinessAiChat(
            businessContext: business,
            isCurrent: () => current.value,
            provider: provider,
            historyRepository: history,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Chambua mauzo');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(provider.sends, 0);
    expect(find.text('Kagua taarifa zitakazotumwa kwa OpenAI'), findsOneWidget);
    expect(find.textContaining('Jina la biashara'), findsOneWidget);
    await tester.tap(find.text('Tuma kwa OpenAI'));
    await tester.pumpAndSettle();
    expect(provider.sends, 1);
    expect(provider.language, 'sw');
    expect(find.text('Jibu la biashara'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Je, matumizi?');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(provider.sends, 1);
    await tester.tap(find.text('Tuma kwa OpenAI'));
    await tester.pumpAndSettle();
    expect(provider.sends, 2);
    expect(provider.messages.map((e) => e['content']), [
      'Chambua mauzo',
      'Jibu la biashara',
      'Je, matumizi?',
    ]);
    expect(history.messages.map((e) => e.content), [
      'Chambua mauzo',
      'Jibu la biashara',
      'Je, matumizi?',
      'Jibu la biashara',
    ]);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: Scaffold(
          body: BusinessAiChat(
            businessContext: business,
            isCurrent: () => current.value,
            provider: provider,
            historyRepository: history,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chambua mauzo'), findsOneWidget);
    expect(find.text('Je, matumizi?'), findsOneWidget);

    history.failAnswer = true;
    await tester.enterText(find.byType(TextField), 'Swali la tatu');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Tuma kwa OpenAI'));
    await tester.pumpAndSettle();
    expect(find.text('Jaribu kuhifadhi jibu tena'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
    history.failAnswer = false;
    await tester.tap(find.text('Jaribu kuhifadhi jibu tena'));
    await tester.pumpAndSettle();
    expect(find.text('Jaribu kuhifadhi jibu tena'), findsNothing);
    expect(history.messages.last.content, 'Jibu la biashara');
    ScaffoldMessenger.of(
      tester.element(find.byType(TextField)),
    ).clearSnackBars();
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Swali jingine');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    current.value = false;
    await tester.pump();
    expect(find.text('Tuma kwa OpenAI'), findsNothing);
    expect(provider.sends, 3);
  });
}
