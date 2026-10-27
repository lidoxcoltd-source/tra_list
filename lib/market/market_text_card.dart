import 'package:flutter/material.dart';

const marketTextGradients = <List<Color>>[
  [Color(0xFF1D4ED8), Color(0xFF0EA5E9)],
  [Color(0xFF7C3AED), Color(0xFFEC4899)],
  [Color(0xFF047857), Color(0xFF34D399)],
  [Color(0xFFB45309), Color(0xFFF59E0B)],
  [Color(0xFF0F172A), Color(0xFF334155)],
  [Color(0xFFBE123C), Color(0xFFFB7185)],
  [Color(0xFF0F766E), Color(0xFF2DD4BF)],
  [Color(0xFF4338CA), Color(0xFF8B5CF6)],
  [Color(0xFF111111), Color(0xFF111111)],
  [Color(0xFFFFF7E0), Color(0xFFFFE3A3)],
];

const marketTextFontLabels = <String>[
  'text_font_bold',
  'text_font_serif',
  'text_font_mono',
  'text_font_italic',
  'text_font_light',
];

TextStyle marketTextStyle(int font, double size, Color color) {
  final base = TextStyle(color: color, fontSize: size, height: 1.3);
  return switch (font) {
    1 => base.copyWith(
      fontFamily: 'serif',
      fontFamilyFallback: const ['Georgia', 'Times New Roman'],
      fontWeight: FontWeight.w700,
    ),
    2 => base.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Courier New', 'Courier'],
      fontWeight: FontWeight.w600,
    ),
    3 => base.copyWith(
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w600,
    ),
    4 => base.copyWith(fontWeight: FontWeight.w300, letterSpacing: 1),
    _ => base.copyWith(fontWeight: FontWeight.w800),
  };
}

/// Background for posts that contain only words. [bg] < 0 picks one from
/// [seed] so older posts keep a stable colour.
class MarketTextCard extends StatelessWidget {
  const MarketTextCard({
    super.key,
    required this.text,
    required this.seed,
    this.bg = -1,
    this.font = 0,
    this.fontSize = 22,
    this.maxLines = 10,
  });

  final String text;
  final String seed;
  final int bg;
  final int font;
  final double fontSize;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final index = bg >= 0
        ? bg % marketTextGradients.length
        : seed.hashCode.abs() % (marketTextGradients.length - 2);
    final colors = marketTextGradients[index];
    final light = colors.first.computeLuminance() > .6;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: marketTextStyle(
              font,
              fontSize,
              light ? const Color(0xFF1F2937) : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
