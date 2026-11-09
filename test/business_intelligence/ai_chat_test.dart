import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/ai_assistant_page.dart';
import 'package:tra_list/business_intelligence/ai_chat.dart';
import 'package:tra_list/business_intelligence/ai_document_draft.dart';
import 'package:tra_list/business_intelligence/ai_history.dart';
import 'package:tra_list/business_intelligence/ai_provider.dart';
import 'package:tra_list/business_intelligence/business_context.dart';
import 'package:tra_list/business_intelligence/ai_transaction_suggestions.dart';
import 'package:tra_list/business_intelligence/ai_invoice_guide.dart';
import 'package:tra_list/business_intelligence/voice_transaction_draft.dart';
import 'package:tra_list/invoice/app_translations.dart';
import 'package:tra_list/invoice/InvoicePage.dart';
import 'package:tra_list/AddReceiptPage.dart';
import 'package:tra_list/services/business_access_service.dart';

class FakeProvider implements AIProvider {
  int sends = 0;
  Completer<void>? pendingPreparation;
  Completer<String>? pendingAnswer;
  String? language;
  String? messageId;
  String? sentToken;
  List<Map<String, String>> messages = [];

  @override
  Future<AiSnapshot> prepare(BusinessContext context) async {
    if (pendingPreparation != null) await pendingPreparation!.future;
    return const AiSnapshot({'businessName': 'Duka', 'income': 100}, 'token');
  }

  @override
  Future<String> respond({
    required BusinessContext context,
    required AiSnapshot snapshot,
    required List<Map<String, String>> messages,
    required String language,
    String? messageId,
  }) async {
    sends++;
    this.language = language;
    this.messageId = messageId;
    sentToken = snapshot.token;
    this.messages = messages;
    return pendingAnswer == null
        ? 'Jibu la biashara'
        : await pendingAnswer!.future;
  }
}

class FakeReviewProvider extends FakeProvider
    implements AiDocumentReviewProvider {
  @override
  Future<AiDocumentReview?> prepareDocumentReview({
    required BusinessContext context,
    required AiSnapshot snapshot,
    required String question,
  }) async => const AiDocumentReview({
    'invoices': [
      {'number': 'INV-1', 'clientName': 'Mteja'},
    ],
  }, 'reviewed-token');
}

class FakeHistory implements AiHistoryRepository, AiHistoryEditing {
  final messages = <AiChatMessage>[];
  Completer<AiHistoryPage>? pendingLoad;
  bool failAnswer = false;
  bool failQuestion = false;
  @override
  Future<AiHistoryPage> load(String businessId, {String? before}) async {
    if (pendingLoad != null) return pendingLoad!.future;
    return AiHistoryPage(List.of(messages), false);
  }

  @override
  Future<void> save(String businessId, AiChatMessage message) async {
    if (failAnswer && message.role == 'assistant') throw StateError('offline');
    if (failQuestion && message.role == 'user') throw StateError('offline');
    messages.add(message);
  }

  @override
  Future<void> edit(String businessId, String messageId, String content) async {
    final index = messages.indexWhere((message) => message.id == messageId);
    final original = messages[index];
    messages[index] = AiChatMessage(
      id: original.id,
      role: original.role,
      content: content,
      createdAt: original.createdAt,
    );
  }

  @override
  Future<void> delete(String businessId, String messageId) async {
    messages.removeWhere((message) => message.id == messageId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    TestFirebaseCoreHostApi.setUp(MockFirebaseApp());
    await Firebase.initializeApp();
  });

  testWidgets('voice transaction only fills chat and does not record', (
    tester,
  ) async {
    BusinessAccessService.businessUid.value = 'business';
    BusinessAccessService.isReady.value = true;
    BusinessAccessService.isActive.value = true;
    BusinessAccessService.isOwner.value = true;
    addTearDown(() {
      BusinessAccessService.businessUid.value = '';
      BusinessAccessService.isReady.value = false;
      BusinessAccessService.isActive.value = false;
      BusinessAccessService.isOwner.value = false;
    });
    final key = GlobalKey<BusinessAiChatState>();
    final history = FakeHistory();
    final provider = FakeProvider();
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
            key: key,
            businessContext: business,
            isCurrent: () => true,
            provider: provider,
            historyRepository: history,
          ),
        ),
      ),
    );
    await tester.pump();
    await key.currentState!.stageVoiceTransaction(
      const VoiceTransactionDraft(
        type: 'expense',
        amount: 10000,
        category: 'Kodi',
        description: 'Kodi ya duka',
      ),
    );
    await tester.pump();
    expect(
      find.text(
        'record expense 10000; category: Kodi; description: Kodi ya duka',
      ),
      findsOneWidget,
    );
    expect(provider.sends, 0);
    expect(history.messages, isEmpty);
  });

  testWidgets('voice draft requires review and cancellation does not save', (
    tester,
  ) async {
    BusinessAccessService.businessUid.value = 'business';
    BusinessAccessService.isReady.value = true;
    BusinessAccessService.isActive.value = true;
    BusinessAccessService.isOwner.value = true;
    addTearDown(() {
      BusinessAccessService.businessUid.value = '';
      BusinessAccessService.isReady.value = false;
      BusinessAccessService.isActive.value = false;
      BusinessAccessService.isOwner.value = false;
    });
    final key = GlobalKey<BusinessAiChatState>();
    final history = FakeHistory();
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
            key: key,
            businessContext: business,
            isCurrent: () => true,
            provider: FakeProvider(),
            historyRepository: history,
          ),
        ),
      ),
    );
    await tester.pump();
    final pending = key.currentState!.openVoiceDraft(
      const AiDocumentDraft(
        kind: AiDocumentKind.invoice,
        customer: 'Mteja',
        description: 'Bidhaa',
        quantity: 2,
        unitPrice: 5000,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kagua nyaraka mpya'), findsOneWidget);
    await tester.tap(find.text('cancel'.tr));
    await tester.pumpAndSettle();
    await pending;
    expect(history.messages, isEmpty);
    expect(find.byType(InvoicePage), findsNothing);
  });

  test('resource limit messages distinguish quota, rate and report limits', () {
    expect(
      aiResourceLimitMessageKey('package-quota-exhausted'),
      'isher_package_exhausted_notice',
    );
    expect(
      aiResourceLimitMessageKey('quota-exhausted'),
      'bi_chat_quota_exhausted',
    );
    expect(aiResourceLimitMessageKey('rate-limited'), 'bi_chat_rate_limited');
    expect(
      aiResourceLimitMessageKey(
        'Report preparation limit reached. Try again later.',
      ),
      'bi_chat_preparation_limited',
    );
    expect(
      aiResourceLimitMessageKey(
        'Too many records to prepare a complete report. Select a shorter period.',
      ),
      'bi_chat_report_too_large',
    );
    expect(aiResourceLimitMessageKey(null), 'bi_chat_limit_error');
  });

  testWidgets('bare invoice request guides locally and saves reviewed draft', (
    tester,
  ) async {
    BusinessAccessService.businessUid.value = 'business';
    BusinessAccessService.isReady.value = true;
    BusinessAccessService.isActive.value = true;
    BusinessAccessService.isOwner.value = true;
    addTearDown(() {
      BusinessAccessService.businessUid.value = '';
      BusinessAccessService.isReady.value = false;
      BusinessAccessService.isActive.value = false;
      BusinessAccessService.isOwner.value = false;
    });
    final provider = FakeProvider();
    final history = FakeHistory();
    var attempts = 0;
    var factories = 0;
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
            isCurrent: () => true,
            provider: provider,
            historyRepository: history,
            invoiceSaveFactory: () {
              factories++;
              return (draft) async {
                expect(draft.customer, 'Asha');
                expect(draft.invoiceItems.single.description, 'Mchele');
                if (++attempts == 1) throw StateError('offline');
                return 'saved-invoice';
              };
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    history.failQuestion = true;
    await tester.enterText(find.byType(TextField), 'nitengenezee invoice');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(find.byType(AiInvoiceGuide), findsNothing);
    expect(history.messages, isEmpty);
    history.failQuestion = false;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(find.byType(AiInvoiceGuide), findsOneWidget);
    final input = find.descendant(
      of: find.byType(AiInvoiceGuide),
      matching: find.byType(TextField),
    );
    Future<void> answer(String value) async {
      await tester.enterText(input, value);
      await tester.ensureVisible(find.text('Endelea'));
      await tester.tap(find.text('Endelea'));
      await tester.pump();
    }

    await answer('Asha');
    for (var i = 0; i < 4; i++) {
      await tester.ensureVisible(find.text('Ruka'));
      await tester.tap(find.text('Ruka'));
      await tester.pump();
    }
    await answer('Mchele');
    await answer('2');
    await answer('5000');
    await tester.ensureVisible(find.text('Hakuna nyingine'));
    await tester.tap(find.text('Hakuna nyingine'));
    await tester.pump();
    await tester.ensureVisible(find.text('Ruka'));
    await tester.tap(find.text('Ruka'));
    await tester.pump();
    await tester.ensureVisible(find.text('Hifadhi invoice'));
    await tester.tap(find.text('Hifadhi invoice'));
    await tester.pumpAndSettle();
    expect(find.byType(AiInvoiceGuide), findsOneWidget);
    expect(find.textContaining('Uhifadhi haujathibitishwa'), findsWidgets);
    history.failAnswer = true;
    await tester.ensureVisible(find.text('Hifadhi invoice'));
    await tester.tap(find.text('Hifadhi invoice'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Invoice imehifadhiwa.'), findsOneWidget);
    expect(find.text('Fungua PDF'), findsOneWidget);
    expect(find.text('Hifadhi PDF kwenye kifaa'), findsOneWidget);
    expect(attempts, 2);
    expect(factories, 1);
    expect(provider.sends, 0);
    expect(history.messages.length, 1);
    expect(find.text('Jaribu kuhifadhi jibu tena'), findsOneWidget);
    history.failAnswer = false;
    await tester.tap(find.text('Jaribu kuhifadhi jibu tena'));
    await tester.pumpAndSettle();
    expect(history.messages.length, 2);
    expect(
      decodeDocumentHistoryEvent(history.messages.last)!.invoiceId,
      'saved-invoice',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: Scaffold(
          body: BusinessAiChat(
            businessContext: business,
            isCurrent: () => true,
            provider: provider,
            historyRepository: history,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('nitengenezee invoice'), findsOneWidget);
    expect(find.textContaining('Invoice imehifadhiwa.'), findsOneWidget);
    expect(find.text('Fungua PDF'), findsOneWidget);
    expect(find.text('Hifadhi PDF kwenye kifaa'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Habari za biashara');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(provider.messages.length, 1);
    expect(provider.messages.single['content'], 'Habari za biashara');
  });

  testWidgets('invoice request opens the existing form after review', (
    tester,
  ) async {
    BusinessAccessService.businessUid.value = 'business';
    BusinessAccessService.isReady.value = true;
    BusinessAccessService.isActive.value = true;
    BusinessAccessService.isOwner.value = true;
    addTearDown(() {
      BusinessAccessService.businessUid.value = '';
      BusinessAccessService.isReady.value = false;
      BusinessAccessService.isActive.value = false;
      BusinessAccessService.isOwner.value = false;
    });
    final provider = FakeProvider();
    final history = FakeHistory();
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
            isCurrent: () => true,
            provider: provider,
            historyRepository: history,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'nitengenezee Invoice; mteja: Asha',
    );
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(find.text('Kagua nyaraka mpya'), findsOneWidget);
    expect(provider.sends, 0);
    expect(history.messages, isEmpty);
    await tester.tap(find.text('Fungua fomu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(InvoicePage), findsOneWidget);
    expect(provider.sends, 0);
    expect(
      decodeDocumentHistoryEvent(history.messages.first)!.text,
      'nitengenezee Invoice; mteja: Asha',
    );
    expect(
      decodeDocumentHistoryEvent(history.messages.last)!.text,
      contains('Uhifadhi haujathibitishwa'),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    }
    Navigator.of(tester.element(find.byType(InvoicePage))).pop();
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'sawa tengeneza receipt ya 30,000',
    );
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(find.text('Kagua nyaraka mpya'), findsOneWidget);
    await tester.tap(find.text('Fungua fomu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AddReceiptPage), findsOneWidget);
    expect(find.textContaining('Kiasi ulichotaja: TZS 30,000'), findsOneWidget);
    expect(provider.sends, 0);
    expect(history.messages.length, 4);
    Navigator.of(tester.element(find.byType(AddReceiptPage))).pop();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('pending transaction category selection sends existing follow-up', (
    tester,
  ) async {
    BusinessAccessService.businessUid.value = 'business';
    BusinessAccessService.isReady.value = true;
    BusinessAccessService.isActive.value = true;
    BusinessAccessService.isOwner.value = true;
    addTearDown(() {
      BusinessAccessService.businessUid.value = '';
      BusinessAccessService.isReady.value = false;
      BusinessAccessService.isActive.value = false;
      BusinessAccessService.isOwner.value = false;
    });
    final provider = FakeProvider();
    final history = FakeHistory()
      ..messages.addAll([
        AiChatMessage(
          id: 'question',
          role: 'user',
          content: 'rekodi matumizi 30000',
          createdAt: DateTime(2024),
        ),
        AiChatMessage(
          id: 'followup',
          role: 'assistant',
          content:
              'Tafadhali tuma kundi na maelezo kwa muundo: kundi: Kodi; maelezo: Kodi ya duka. Tumia kundi lililopo; tarehe itakuwa leo.',
          createdAt: DateTime(2024),
        ),
      ]);
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
    String? requestedType;
    var current = true;
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: Scaffold(
          body: BusinessAiChat(
            businessContext: business,
            isCurrent: () => current,
            provider: provider,
            historyRepository: history,
            transactionCategoryLoader: (type) async {
              requestedType = type;
              return ['Kodi'];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requestedType, 'expense');
    expect(find.byType(AiTransactionSuggestions), findsOneWidget);
    await tester.ensureVisible(find.text('Chagua kundi lililopo'));
    await tester.tap(find.text('Chagua kundi lililopo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kodi'));
    await tester.pumpAndSettle();
    final description = find.descendant(
      of: find.byType(AiTransactionSuggestions),
      matching: find.byType(TextField),
    );
    await tester.enterText(description, 'Kodi ya duka');
    await tester.ensureVisible(find.text('Rekodi muamala'));
    current = false;
    await tester.tap(find.text('Rekodi muamala'));
    await tester.pump();
    expect(provider.sends, 0);
    current = true;
    await tester.tap(find.text('Rekodi muamala'));
    await tester.pumpAndSettle();
    expect(provider.sends, 1);
    expect(
      provider.messages.last['content'],
      'kundi: Kodi; maelezo: Kodi ya duka',
    );
    expect(
      provider.messages[provider.messages.length - 3]['content'],
      'rekodi matumizi 30000',
    );
    expect(find.byType(AiTransactionSuggestions), findsNothing);
  });

  testWidgets('document details require review before sending', (tester) async {
    final provider = FakeReviewProvider();
    final history = FakeHistory();
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
            isCurrent: () => true,
            provider: provider,
            historyRepository: history,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'historia ya wateja');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Kagua taarifa za nyaraka'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('INV-1'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
    expect(provider.sends, 0);
    expect(history.messages, isEmpty);
    await tester.tap(find.text('cancel'.tr));
    await tester.pumpAndSettle();
    expect(provider.sends, 0);
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Tuma taarifa zilizokaguliwa'));
    await tester.pumpAndSettle();
    expect(provider.sends, 1);
    expect(provider.sentToken, 'reviewed-token');
  });

  testWidgets(
    'cached chat appears while history refreshes and is cleared on access denial',
    (tester) async {
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
      final cache = AiHistoryCache()
        ..store(business, [
          AiChatMessage(
            id: 'old',
            role: 'assistant',
            content: 'Ujumbe wa awali',
            createdAt: DateTime(2024),
          ),
        ], false);
      final history = FakeHistory()..pendingLoad = Completer<AiHistoryPage>();
      await tester.pumpWidget(
        GetMaterialApp(
          translations: AppTranslations(),
          locale: const Locale('sw', 'TZ'),
          home: Scaffold(
            body: BusinessAiChat(
              businessContext: business,
              isCurrent: () => true,
              provider: FakeProvider(),
              historyRepository: history,
              historyCache: cache,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Ujumbe wa awali'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
      history.pendingLoad!.completeError(
        FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'Access denied',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ujumbe wa awali'), findsNothing);
      expect(cache.read(business), isNull);
    },
  );

  testWidgets('thinking indicator follows the actual response request', (
    tester,
  ) async {
    final provider = FakeProvider()..pendingAnswer = Completer<String>();
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
            isCurrent: () => true,
            provider: provider,
            historyRepository: FakeHistory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Chambua mauzo');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(provider.sends, 1);
    expect(provider.messageId, isNotNull);
    expect(find.text('Tuma kwa OpenAI'), findsNothing);
    expect(find.text('Isher anaandaa jibu...'), findsOneWidget);
    provider.pendingAnswer!.complete('Jibu la biashara');
    await tester.pumpAndSettle();
    expect(find.text('Isher anaandaa jibu...'), findsNothing);
    expect(find.text('Jibu la biashara'), findsOneWidget);
  });

  testWidgets('assistant can open directly on the voice tab', (tester) async {
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
          initialTab: AiAssistantTab.voice,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Mazungumzo ya sauti yanapatikana kwenye Android pekee kwa sasa.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

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
    await tester.tap(find.byTooltip('Simu'));
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
    await tester.tap(find.byTooltip('Ongeza emoji'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('😊'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Draft😊',
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Swahili chat sends directly and retains follow-ups', (
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
    await tester.pumpAndSettle();
    expect(provider.sends, 1);
    expect(find.text('Kagua taarifa zitakazotumwa kwa OpenAI'), findsNothing);
    expect(provider.language, 'sw');
    expect(find.text('Jibu la biashara'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Je, matumizi?');
    await tester.tap(find.byIcon(Icons.send));
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

    provider.pendingPreparation = Completer<void>();
    await tester.enterText(find.byType(TextField), 'Swali jingine');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    current.value = false;
    provider.pendingPreparation!.complete();
    await tester.pump();
    expect(provider.sends, 3);
  });

  testWidgets(
    'edits a message without resending and deletes after confirmation',
    (tester) async {
      final provider = FakeProvider();
      final original = newAiChatMessage('user', 'Chambua mauzo');
      final document = newAiChatMessage(
        'user',
        encodeDocumentHistoryEvent('tengeneza invoice'),
      );
      final history = FakeHistory()
        ..messages.addAll([
          original,
          newAiChatMessage('assistant', 'Jibu la awali'),
          document,
        ]);
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
              isCurrent: () => true,
              provider: provider,
              historyRepository: history,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final editButtons = find.byTooltip('Hariri ujumbe');
      expect(editButtons, findsOneWidget);
      await tester.tap(editButtons.first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Chambua matumizi',
      );
      await tester.tap(find.text('Hifadhi mabadiliko'));
      await tester.pumpAndSettle();
      expect(provider.sends, 0);
      expect(history.messages.first.id, original.id);
      expect(history.messages.first.content, 'Chambua matumizi');
      await tester.tap(find.byTooltip('Futa ujumbe').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Futa ujumbe').last);
      await tester.pumpAndSettle();
      expect(
        history.messages.any((message) => message.id == original.id),
        isFalse,
      );
    },
  );

  testWidgets('swiping right replies with the selected message', (
    tester,
  ) async {
    final provider = FakeProvider();
    final original = newAiChatMessage('assistant', 'Mauzo ni 100');
    final history = FakeHistory()..messages.add(original);
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
            isCurrent: () => true,
            provider: provider,
            historyRepository: history,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.fling(
      find.byKey(ValueKey('ai_message_${original.id}')),
      const Offset(250, 0),
      600,
    );
    await tester.pumpAndSettle();
    expect(find.text('Jibu: Mauzo ni 100'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Eleza zaidi');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(provider.messages.last['content'], contains('Mauzo ni 100'));
    expect(provider.messages.last['content'], contains('Eleza zaidi'));
    expect(history.messages[1].content, provider.messages.last['content']);
  });
}
