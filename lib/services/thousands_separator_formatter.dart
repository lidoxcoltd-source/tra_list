import 'package:flutter/services.dart';

/// Formats digits with thousand separators while typing (1234567.5 -> 1,234,567.5).
class ThousandsSeparatorFormatter extends TextInputFormatter {
  const ThousandsSeparatorFormatter({this.allowDecimal = true});

  final bool allowDecimal;

  static String format(num value) {
    final text = value == value.truncateToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
    return _group(text);
  }

  /// Parses a formatted string such as "1,234.5" back to a number.
  static double? parse(String text) =>
      double.tryParse(text.replaceAll(',', '').trim());

  static String _group(String raw) {
    final parts = raw.split('.');
    final whole = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return parts.length > 1 ? '$whole.${parts[1]}' : whole;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var clean = newValue.text.replaceAll(',', '');
    clean = clean.replaceAll(
      allowDecimal ? RegExp(r'[^0-9.]') : RegExp(r'\D'),
      '',
    );
    final dot = clean.indexOf('.');
    if (dot != -1) {
      clean =
          '${clean.substring(0, dot + 1)}${clean.substring(dot + 1).replaceAll('.', '')}';
    }
    if (clean.isEmpty) return const TextEditingValue();

    final formatted = _group(clean);
    final digitsBeforeCursor = newValue.text
        .substring(0, newValue.selection.end.clamp(0, newValue.text.length))
        .replaceAll(RegExp(r'[^0-9.]'), '')
        .length;

    var offset = 0;
    var seen = 0;
    while (offset < formatted.length && seen < digitsBeforeCursor) {
      if (formatted[offset] != ',') seen++;
      offset++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
