import 'package:flutter/material.dart';

class ScanFrame extends StatefulWidget {
  const ScanFrame({super.key, this.width = 280, this.height = 220});

  final double width;
  final double height;

  @override
  State<ScanFrame> createState() => _ScanFrameState();
}

class _ScanFrameState extends State<ScanFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) =>
            CustomPaint(painter: _ScanFramePainter(_controller.value)),
      ),
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  const _ScanFramePainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Offset.zero & size;
    final radius = Radius.circular(20);
    final corner = Paint()
      ..color = const Color(0xFFFFC629)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const arm = 27.0;
    final path = Path()
      ..moveTo(arm, 2)
      ..lineTo(20, 2)
      ..quadraticBezierTo(2, 2, 2, 20)
      ..lineTo(2, arm)
      ..moveTo(size.width - arm, 2)
      ..lineTo(size.width - 20, 2)
      ..quadraticBezierTo(size.width - 2, 2, size.width - 2, 20)
      ..lineTo(size.width - 2, arm)
      ..moveTo(2, size.height - arm)
      ..lineTo(2, size.height - 20)
      ..quadraticBezierTo(2, size.height - 2, 20, size.height - 2)
      ..lineTo(arm, size.height - 2)
      ..moveTo(size.width - arm, size.height - 2)
      ..lineTo(size.width - 20, size.height - 2)
      ..quadraticBezierTo(
        size.width - 2,
        size.height - 2,
        size.width - 2,
        size.height - 20,
      )
      ..lineTo(size.width - 2, size.height - arm);
    canvas.drawPath(path, corner);

    final beamY = 18 + progress * (size.height - 36);
    final beamRect = Rect.fromLTWH(4, beamY, size.width - 8, 2);
    final beam = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0x00FFC629),
          const Color(0xFFFFC629).withValues(alpha: 0.95),
          const Color(0x00FFC629),
        ],
      ).createShader(beamRect);
    canvas.drawRect(beamRect, beam);
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, radius),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanFramePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
