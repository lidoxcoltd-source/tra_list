import 'package:flutter/material.dart';

/// Gradient background shared by the login and registration pages.
class AuthBackdrop extends StatelessWidget {
  const AuthBackdrop({super.key, required this.isBusiness});

  final bool isBusiness;

  static const personalAccent = Color(0xFF36D6B0);
  static const businessAccent = Color(0xFF37CFFF);

  @override
  Widget build(BuildContext context) {
    final accent = isBusiness ? businessAccent : personalAccent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isBusiness
              ? const [Color(0xFF06152E), Color(0xFF0B3B78), Color(0xFF087CA7)]
              : const [Color(0xFF071B2A), Color(0xFF0A4A5B), Color(0xFF087C78)],
        ),
      ),
      child: CustomPaint(
        painter: _TexturePainter(accent),
        size: Size.infinite,
      ),
    );
  }
}

class _TexturePainter extends CustomPainter {
  const _TexturePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color.withValues(alpha: .07)
      ..strokeWidth = 1;
    const gap = 28.0;
    for (double x = -size.height; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), line);
    }
    final dot = Paint()..color = color.withValues(alpha: .1);
    for (double y = gap / 2; y < size.height; y += gap * 2) {
      for (double x = gap / 2; x < size.width; x += gap * 2) {
        canvas.drawCircle(Offset(x, y), 1.6, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_TexturePainter old) => old.color != color;
}

class _WavePainter extends CustomPainter {
  const _WavePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final soft = Paint()..color = color.withValues(alpha: .1);
    canvas.drawCircle(Offset(size.width * .9, size.height * .08), 120, soft);
    canvas.drawCircle(Offset(size.width * .05, size.height * .95), 150, soft);
    final wave = Path()
      ..moveTo(0, size.height * .8)
      ..quadraticBezierTo(
        size.width * .3,
        size.height * .7,
        size.width * .6,
        size.height * .82,
      )
      ..quadraticBezierTo(
        size.width * .85,
        size.height * .92,
        size.width,
        size.height * .84,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(wave, Paint()..color = color.withValues(alpha: .08));
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.color != color;
}
