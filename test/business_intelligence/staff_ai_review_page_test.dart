import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/staff_ai_review_page.dart';

class FakeReviewClient implements StaffAiReviewClient {
  int sends = 0;
  Object? failure;
  Map<String, dynamic> prepared = {
    'token': 'review-token',
    'item': {'kind': 'text', 'text': 'Selected staff message'},
  };

  @override
  Future<Map<String, dynamic>> prepare(
    String businessId,
    Map<String, Object> selection,
  ) async => prepared;

  @override
  Future<String> analyze(
    String businessId,
    Map<String, Object> selection,
    String token,
    String question,
    String language,
  ) async {
    sends++;
    expect(businessId, 'business');
    expect(selection['messageId'], 'message');
    expect(token, 'review-token');
    expect(question, 'Summarize');
    if (failure != null) throw failure!;
    return 'Reviewed answer';
  }
}

void main() {
  const selection = <String, Object>{
    'conversationId': 'chat',
    'messageId': 'message',
    'kind': 'text',
  };

  Future<void> render(
    WidgetTester tester,
    FakeReviewClient client,
    RxBool access,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      GetMaterialApp(
        home: StaffAiReviewItemPage(
          businessId: 'business',
          isCurrent: () => access.value,
          selection: selection,
          client: client,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('requires review and explicit confirmation before sending', (
    tester,
  ) async {
    final client = FakeReviewClient();
    final access = true.obs;
    await render(tester, client, access);
    expect(find.text('Selected staff message'), findsOneWidget);
    expect(find.text('bi_staff_review_warning'), findsOneWidget);
    final button = find.ancestor(
      of: find.text('bi_staff_review_send'),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'Summarize');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(client.sends, 1);
    expect(find.text('Reviewed answer'), findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
  });

  testWidgets('expired review requires another preview', (tester) async {
    final client = FakeReviewClient()
      ..failure = FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Expired',
      );
    await render(tester, client, true.obs);
    await tester.enterText(find.byType(TextField), 'Summarize');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    final button = find.ancestor(
      of: find.text('bi_staff_review_send'),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('bi_staff_review_expired'), findsOneWidget);
    await tester.ensureVisible(find.text('bi_staff_review_retry'));
    await tester.tap(find.text('bi_staff_review_retry'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      false,
    );
  });

  testWidgets('access change hides content and prevents sending', (
    tester,
  ) async {
    final client = FakeReviewClient();
    final access = true.obs;
    await render(tester, client, access);
    access.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Selected staff message'), findsNothing);
    expect(find.text('bi_access_error'), findsOneWidget);
    expect(client.sends, 0);
  });

  testWidgets('an unreadable image cannot be approved or sent', (tester) async {
    final client = FakeReviewClient()
      ..prepared = {
        'token': 'review-token',
        'item': {
          'kind': 'attachment',
          'contentType': 'image/png',
          'data': 'bm90IGFuIGltYWdl',
        },
      };
    await render(tester, client, true.obs);
    expect(find.text('bi_staff_review_load_error'), findsOneWidget);
    final checkbox = tester.widget<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(checkbox.onChanged, isNull);
    expect(client.sends, 0);
  });
}
