import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tra_list/AddReceiptPage.dart';
import 'package:tra_list/business_intelligence/ai_document_draft.dart';
import 'package:tra_list/invoice/InvoicePage.dart';
import 'package:tra_list/invoice/advance_invoice_page.dart';
import 'package:tra_list/invoice/quotation_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    TestFirebaseCoreHostApi.setUp(MockFirebaseApp());
    await Firebase.initializeApp();
  });

  testWidgets('draft data enters the existing document forms', (tester) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Finder fieldWith(String value) => find.byWidgetPredicate(
      (widget) => widget is EditableText && widget.controller.text == value,
    );
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      GetMaterialApp(navigatorKey: navigator, home: const SizedBox()),
    );
    Future<void> open(Widget page) async {
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => page),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    const item = AiDocumentDraft(
      kind: AiDocumentKind.invoice,
      customer: 'Sample customer',
      description: 'Sample product',
      quantity: 2,
      unitPrice: 5000,
    );
    for (final page in [
      const InvoicePage(aiDraft: item),
      const QuotationPage(aiDraft: item),
      const AddReceiptPage(aiDraft: item),
    ]) {
      await open(page);
      expect(fieldWith('Sample customer'), findsWidgets);
      expect(fieldWith('Sample product'), findsWidgets);
      navigator.currentState!.pop();
      await tester.pump(const Duration(milliseconds: 300));
    }

    final guided = AiDocumentDraft(
      kind: AiDocumentKind.invoice,
      customer: 'Guided customer',
      invoiceName: 'Office supplies',
      invoiceNumber: 'INV-TEST',
      issueDate: DateTime(2026, 11, 8),
      dueDate: DateTime(2026, 11, 20),
      terms: 'Pay on delivery',
      invoiceItems: const [
        AiInvoiceItem(description: 'Paper', quantity: 2, unitPrice: 5000),
        AiInvoiceItem(description: 'Pens', quantity: 3, unitPrice: 1000),
      ],
    );
    await open(InvoicePage(aiDraft: guided));
    for (final value in [
      'Guided customer',
      'Office supplies',
      'INV-TEST',
      '8/11/2026',
      '20/11/2026',
      'Pay on delivery',
      'Paper',
      'Pens',
      '5,000',
      '1,000',
    ]) {
      expect(fieldWith(value), findsWidgets, reason: value);
    }
    navigator.currentState!.pop();
    await tester.pump(const Duration(milliseconds: 300));

    await open(QuotationPage(aiDraft: guided));
    for (final value in ['Guided customer', 'Paper', 'Pens']) {
      expect(fieldWith(value), findsWidgets, reason: value);
    }
    navigator.currentState!.pop();
    await tester.pump(const Duration(milliseconds: 300));

    const advance = AiDocumentDraft(
      kind: AiDocumentKind.advance,
      customer: 'Advance customer',
      subtotal: 10000,
      tax: 500,
      advancePaid: 2000,
    );
    await open(const AdvanceInvoicePage(aiDraft: advance));
    expect(fieldWith('Advance customer'), findsOneWidget);
    expect(fieldWith('10000.0'), findsOneWidget);
    expect(fieldWith('500.0'), findsOneWidget);
    expect(fieldWith('2000.0'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    }
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
