import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/services/thousands_separator_formatter.dart';

TextEditingValue _type(String text) =>
    const ThousandsSeparatorFormatter().formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );

void main() {
  test('adds separators while typing', () {
    expect(_type('1234567').text, '1,234,567');
    expect(_type('1,2345').text, '12,345');
    expect(_type('1234.50').text, '1,234.50');
    expect(_type('12a3').text, '123');
    expect(_type('').text, '');
  });

  test('keeps the cursor at the end after typing', () {
    expect(_type('1234').selection.baseOffset, 5);
  });

  test('formats and parses values', () {
    expect(ThousandsSeparatorFormatter.format(2500000), '2,500,000');
    expect(ThousandsSeparatorFormatter.format(0), '0');
    expect(ThousandsSeparatorFormatter.parse('2,500,000.5'), 2500000.5);
  });
}
