import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:tra_list/business_intelligence/ai_transaction_suggestions.dart';
import 'package:tra_list/invoice/app_translations.dart';
import 'package:tra_list/theme/app_theme.dart';

const followup =
    'Tafadhali tuma kundi na maelezo kwa muundo: kundi: Kodi; maelezo: Kodi ya duka. Tumia kundi lililopo; tarehe itakuwa leo.';

void main() {
  testWidgets('compact card keeps input readable with the app theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        theme: MjasiTheme.light,
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: Scaffold(
          body: AiTransactionSuggestions(
            request: const AiTransactionRequest('expense', 20),
            loadCategories: (_) async => ['Kodi'],
            onSubmit: (_) {},
            enabled: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Card)).width, lessThanOrEqualTo(420));
    final description = tester.widget<TextField>(find.byType(TextField));
    expect(description.style?.color, Colors.white);
    expect(description.decoration?.filled, isTrue);
    expect(description.decoration?.fillColor, const Color(0xFF19162C));
    expect(
      description.style!.color!.computeLuminance() -
          description.decoration!.fillColor!.computeLuminance(),
      greaterThan(0.8),
    );
    await tester.tap(find.text('Chagua kundi lililopo'));
    await tester.pumpAndSettle();
    final search = tester.widget<TextField>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
    );
    expect(search.style?.color, MjasiTheme.light.colorScheme.onSurface);
    expect(search.decoration?.fillColor, MjasiTheme.light.colorScheme.surface);
    expect(
      tester.getSize(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
      ).width,
      lessThanOrEqualTo(320),
    );
  });

  testWidgets('category picker fits a small screen with keyboard open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      GetMaterialApp(
        theme: MjasiTheme.light,
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiTransactionSuggestions(
              request: const AiTransactionRequest('expense', 20),
              loadCategories: (_) async => ['Kodi', 'Umeme'],
              onSubmit: (_) {},
              enabled: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chagua kundi lililopo'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final search = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(search, 'umeme');
    await tester.pump();
    expect(find.text('Umeme'), findsOneWidget);
    await tester.tap(find.text('Umeme'));
    await tester.pumpAndSettle();
    expect(find.text('Umeme'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('only an immediately pending supported transaction is offered', () {
    final messages = [
      {'role': 'user', 'content': 'rekodi matumizi 30,000'},
      {'role': 'assistant', 'content': followup},
    ];
    expect(pendingAiTransaction(messages)?.type, 'expense');
    expect(pendingAiTransaction(messages)?.amount, 30000);
    expect(
      pendingAiTransaction([
        ...messages,
        {'role': 'user', 'content': 'sawa'},
      ]),
      isNull,
    );
    expect(
      pendingAiTransaction([
        {'role': 'user', 'content': 'rekodi mapato 0'},
        messages.last,
      ]),
      isNull,
    );
    expect(
      pendingAiTransaction([
        {'role': 'user', 'content': 'record income 2,500'},
        messages.last,
      ])?.type,
      'income',
    );
  });

  testWidgets('loads matching categories and submits validated details', (
    tester,
  ) async {
    final loading = Completer<List<String>>();
    String? requestedType;
    String? command;
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiTransactionSuggestions(
              request: const AiTransactionRequest('expense', 30000),
              loadCategories: (type) {
                requestedType = type;
                return loading.future;
              },
              onSubmit: (value) => command = value,
              enabled: true,
            ),
          ),
        ),
      ),
    );
    expect(requestedType, 'expense');
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      find.textContaining(DateFormat.yMMMd().format(DateTime.now())),
      findsOneWidget,
    );
    loading.complete(['Kodi', 'Umeme']);
    await tester.pumpAndSettle();
    expect(find.text('Kodi'), findsNothing);
    await tester.tap(find.text('Chagua kundi lililopo'));
    await tester.pumpAndSettle();
    expect(find.text('Kodi'), findsOneWidget);
    await tester.tap(find.text('Kodi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tumia jina la kundi kama maelezo'));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Kodi',
    );
    await tester.enterText(find.byType(TextField), 'Kodi; nyingine');
    await tester.tap(find.text('Rekodi muamala'));
    await tester.pump();
    expect(command, isNull);
    expect(find.textContaining('semikolon'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Kodi ya duka');
    await tester.tap(find.text('Rekodi muamala'));
    expect(command, 'kundi: Kodi; maelezo: Kodi ya duka');
  });

  testWidgets(
    'category search stays compact and supports cancel and no match',
    (tester) async {
      final categories = List.generate(40, (index) => 'Kundi $index')
        ..add('Umeme');
      await tester.pumpWidget(
        GetMaterialApp(
          translations: AppTranslations(),
          locale: const Locale('sw', 'TZ'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AiTransactionSuggestions(
                request: const AiTransactionRequest('expense', 20),
                loadCategories: (_) async => categories,
                onSubmit: (_) => fail('No transaction should be submitted'),
                enabled: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('Kundi 0'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Maelezo yaliyopo');
      await tester.tap(find.text('Chagua kundi lililopo'));
      await tester.pumpAndSettle();
      final search = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, 'haipo');
      await tester.pump();
      expect(find.text('Hakuna kundi linalolingana'), findsOneWidget);
      await tester.enterText(search, 'UMEME');
      await tester.pump();
      expect(find.text('Umeme'), findsOneWidget);
      await tester.tap(find.text('cancel'.tr));
      await tester.pumpAndSettle();
      expect(find.text('Chagua kundi lililopo'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Maelezo yaliyopo',
      );
      await tester.tap(find.text('Chagua kundi lililopo'));
      await tester.pumpAndSettle();
      await tester.enterText(search, 'umeme');
      await tester.pump();
      await tester.tap(find.text('Umeme'));
      await tester.pumpAndSettle();
      expect(find.text('Umeme'), findsOneWidget);
    },
  );

  testWidgets('loading failure can be retried and empty results are explicit', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: Scaffold(
          body: AiTransactionSuggestions(
            request: const AiTransactionRequest('income', 5),
            loadCategories: (type) async {
              attempts++;
              if (attempts == 1) throw StateError('offline');
              return [];
            },
            onSubmit: (_) => fail('Cannot save without a category'),
            enabled: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Imeshindikana kupata makundi'), findsOneWidget);
    await tester.tap(find.text('Burudisha'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.textContaining('Hakuna kundi la aina hii'), findsOneWidget);
  });
}
