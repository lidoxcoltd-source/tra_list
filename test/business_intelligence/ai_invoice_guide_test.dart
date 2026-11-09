import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/ai_document_draft.dart';
import 'package:tra_list/business_intelligence/ai_invoice_guide.dart';
import 'package:tra_list/invoice/app_translations.dart';
import 'package:tra_list/stock/stock_models.dart';

void main() {
  testWidgets('guide can be cancelled without creating a draft', (
    tester,
  ) async {
    var cancelled = false;
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: Scaffold(
          body: AiInvoiceGuide(
            enabled: true,
            onCancel: () => cancelled = true,
            onComplete: (_) => fail('A cancelled draft must not be completed'),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Asha');
    await tester.tap(find.text('cancel'.tr));
    expect(cancelled, isTrue);
  });

  testWidgets(
    'guide validates entries and builds invoice with multiple items',
    (tester) async {
      AiDocumentDraft? draft;
      await tester.pumpWidget(
        GetMaterialApp(
          translations: AppTranslations(),
          locale: const Locale('sw', 'TZ'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AiInvoiceGuide(
                enabled: true,
                onCancel: () {},
                onComplete: (value) => draft = value,
              ),
            ),
          ),
        ),
      );
      Future<void> answer(String value) async {
        await tester.enterText(find.byType(TextField), value);
        await tester.tap(find.text('Endelea'));
        await tester.pump();
      }

      await answer('Asha');
      await answer('Ofisi');
      await answer('INV-123');
      await answer('31/02/2026');
      expect(find.textContaining('Weka tarehe sahihi'), findsOneWidget);
      await answer('08/11/2026');
      await answer('20/11/2026');
      await answer('Mchele');
      await answer('0');
      expect(find.textContaining('Weka namba sahihi'), findsOneWidget);
      await answer('2');
      await answer('5,000');
      await tester.tap(find.text('Ongeza bidhaa'));
      await tester.pump();
      await answer('Mafuta');
      await answer('3');
      await answer('1000');
      await tester.tap(find.text('Hakuna nyingine'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Lipa baada ya kupokea');
      await tester.tap(find.text('Kagua invoice'));
      await tester.pump();
      expect(find.text('Muhtasari wa invoice'), findsOneWidget);
      expect(find.textContaining('Jumla: TZS 13,000'), findsOneWidget);
      await tester.ensureVisible(find.text('Hifadhi invoice'));
      await tester.tap(find.text('Hifadhi invoice'));
      expect(draft!.customer, 'Asha');
      expect(draft!.invoiceName, 'Ofisi');
      expect(draft!.invoiceNumber, 'INV-123');
      expect(draft!.issueDate, DateTime(2026, 11, 8));
      expect(draft!.dueDate, DateTime(2026, 11, 20));
      expect(draft!.invoiceItems.map((e) => e.description), [
        'Mchele',
        'Mafuta',
      ]);
      expect(draft!.invoiceItems.first.unitPrice, 5000);
      expect(draft!.terms, 'Lipa baada ya kupokea');
    },
  );

  testWidgets(
    'stock selection and manual items are reviewed before typed save',
    (tester) async {
      AiDocumentDraft? saved;
      await tester.pumpWidget(
        GetMaterialApp(
          translations: AppTranslations(),
          locale: const Locale('sw', 'TZ'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AiInvoiceGuide(
                enabled: true,
                onCancel: () {},
                onComplete: (draft) => saved = draft,
                pickStock: () async =>
                    Product(id: 'rice-id', name: 'Mchele', sku: 'R'),
              ),
            ),
          ),
        ),
      );
      Future<void> answer(String value) async {
        await tester.enterText(find.byType(TextField), value);
        await tester.ensureVisible(find.text('Endelea'));
        await tester.tap(find.text('Endelea'));
        await tester.pump();
      }

      await answer('Asha');
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Ruka'));
        await tester.pump();
      }
      await tester.tap(find.text('Chagua bidhaa kutoka stock'));
      await tester.pump();
      await tester.tap(find.text('Endelea'));
      await tester.pump();
      await answer('2');
      await answer('5000');
      await tester.tap(find.text('Ongeza bidhaa'));
      await tester.pump();
      await answer('Usafiri');
      await answer('0.01');
      await answer('0.01');
      await tester.tap(find.text('Hakuna nyingine'));
      await tester.pump();
      await tester.tap(find.text('Ruka'));
      await tester.pump();
      expect(saved, isNull);
      expect(find.textContaining('Mchele (stock)'), findsOneWidget);
      expect(find.textContaining('Usafiri (bila stock)'), findsOneWidget);
      expect(find.textContaining('10,000.0001'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'hifadhi');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(saved!.invoiceItems.first.productId, 'rice-id');
      expect(saved!.invoiceItems.last.productId, isNull);
      expect(saved!.issueDate, isNotNull);
      expect(saved!.dueDate, isNotNull);
    },
  );
}
