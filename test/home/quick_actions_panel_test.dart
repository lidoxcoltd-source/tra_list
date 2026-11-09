import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tra_list/home/widgets/quick_actions_panel.dart';
import 'package:tra_list/invoice/app_translations.dart';

void main() {
  testWidgets('AI shortcuts invoke the selected action', (tester) async {
    var chats = 0;
    var voices = 0;
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('en', 'US'),
        home: Scaffold(
          body: QuickActionsPanel(
            actions: [
              (label: 'Action', icon: Icons.add, onTap: () {}),
            ],
            onSelected: (_) {},
            onClose: () {},
            onAiChat: () => chats++,
            onAiVoice: () => voices++,
          ),
        ),
      ),
    );
    expect(
      tester.getCenter(find.byTooltip('Chat')).dy,
      greaterThan(tester.getCenter(find.text('Action')).dy),
    );
    await tester.tap(find.byTooltip('Chat'));
    await tester.tap(find.byTooltip('Call'));
    expect(chats, 1);
    expect(voices, 1);
  });

  testWidgets('AI shortcuts are hidden without callbacks', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickActionsPanel(
            actions: const [],
            onSelected: (_) {},
            onClose: () {},
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsNothing);
  });

  testWidgets('actions use a grid and dialog labels have no underline', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('en', 'US'),
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340, maxHeight: 500),
              child: QuickActionsPanel(
                title: 'Actions',
                actions: [
                  (label: 'Income', icon: Icons.add, onTap: () {}),
                  (label: 'Expense', icon: Icons.remove, onTap: () {}),
                ],
                onSelected: (action) => selected = action.label,
                onClose: () {},
                onAiChat: () {},
                onAiVoice: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('Income')).dy,
        tester.getCenter(find.text('Expense')).dy);
    expect(tester.getCenter(find.text('Income')).dx,
        lessThan(tester.getCenter(find.text('Expense')).dx));
    for (final label in ['Actions', 'Income', 'Expense', 'Chat', 'Call']) {
      expect(tester.widget<Text>(find.text(label)).style!.decoration,
          TextDecoration.none);
    }
    await tester.tap(find.text('Expense'));
    expect(selected, 'Expense');
  });
}
