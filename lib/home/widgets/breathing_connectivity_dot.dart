import 'package:flutter/material.dart';

class BreathingConnectivityDot extends StatefulWidget {
  const BreathingConnectivityDot({
    super.key,
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  State<BreathingConnectivityDot> createState() =>
      _BreathingConnectivityDotState();
}

class _BreathingConnectivityDotState extends State<BreathingConnectivityDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  late final Animation<double> _breath = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.label,
      child: Semantics(
        label: widget.label,
        child: SizedBox(
          width: 20,
          height: 20,
          child: AnimatedBuilder(
            animation: _breath,
            builder: (context, child) {
              final progress = _breath.value;
              final haloSize = 10 + progress * 8;
              return Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: haloSize,
                      height: haloSize,
                      decoration: BoxDecoration(
                        color: widget.color.withValues(
                          alpha: .28 * (1 - progress),
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                    child!,
                  ],
                ),
              );
            },
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: .45),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
