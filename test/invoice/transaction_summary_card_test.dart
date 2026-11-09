import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/invoice/transactions_page.dart';

void main() {
  testWidgets('summary cards select filters without AI shortcuts', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: List.generate(
              3,
              (index) => Expanded(
                child: TransactionSummaryCard(
                  title: 'Card $index',
                  value: 'TSH 100',
                  accent: Colors.blue,
                  isSelected: false,
                  onTap: () => selected++,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsNothing);
    await tester.tap(find.text('Card 0'));
    expect(selected, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shortcuts are hidden without callbacks on a narrow screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(280, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: List.generate(
              3,
              (index) => const Expanded(
                child: TransactionSummaryCard(
                  title: 'Income',
                  value: 'TSH 123456789',
                  accent: Colors.green,
                  isSelected: false,
                  onTap: _noop,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cards fit at narrow widths with enlarged text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(280, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Scaffold(
            body: Row(
              children: List.generate(
                3,
                (index) => const Expanded(
                  child: TransactionSummaryCard(
                    title: 'Income',
                    value: 'TSH 123456789',
                    accent: Colors.green,
                    isSelected: false,
                    onTap: _noop,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
