import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tra_list/invoice/app_translations.dart';
import 'package:tra_list/payment/card_payment_flow.dart';
import 'package:tra_list/payment/card_payment_service.dart';
import 'package:tra_list/subscription_page.dart';

void main() {
  Future<void> openDialog(
    WidgetTester tester,
    Future<void> Function() submit,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => SubscriptionPaymentDialog(onSubmit: submit),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets('subscription shows loading then confirmed success', (
    tester,
  ) async {
    final payment = Completer<void>();
    var submissions = 0;
    await openDialog(tester, () {
      submissions++;
      return payment.future;
    });
    expect(
      find.byKey(const ValueKey('subscription_payment_loading')),
      findsOneWidget,
    );
    expect(find.text('Usajili unaendelea...'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(SubscriptionPaymentDialog), findsOneWidget);
    expect(submissions, 1);
    payment.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      find.byKey(const ValueKey('subscription_payment_success')),
      findsOneWidget,
    );
    expect(find.text('Usajili umeanza!'), findsOneWidget);
    await tester.tap(find.text('Funga'));
    await tester.pumpAndSettle();
    expect(find.byType(SubscriptionPaymentDialog), findsNothing);
  });

  testWidgets('subscription failure hides server error details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final payment = Completer<void>();
    await openDialog(tester, () => payment.future);
    payment.completeError(StateError('private server error'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      find.byKey(const ValueKey('subscription_payment_failure')),
      findsOneWidget,
    );
    expect(find.text('Usajili haujathibitishwa'), findsOneWidget);
    expect(find.textContaining('private server error'), findsNothing);
    expect(find.textContaining('Hakiki hali ya malipo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card payment starts with loading and hides server errors', (
    tester,
  ) async {
    final payment = Completer<CardPaymentSession>();
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => CardPaymentFlow.start(
                context,
                businessId: 'business',
                amount: 100,
                buyerName: 'Name',
                buyerEmail: 'test@example.com',
                buyerPhone: '0712345678',
                createSession: () => payment.future,
              ),
              child: const Text('Pay'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pay'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Usajili unaendelea...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Usajili unaendelea...'), findsOneWidget);
    payment.completeError(CardPaymentException('private server error'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Usajili haujathibitishwa'), findsOneWidget);
    expect(find.textContaining('private server error'), findsNothing);
    expect(find.textContaining('Hakiki hali ya malipo'), findsOneWidget);
  });
}
