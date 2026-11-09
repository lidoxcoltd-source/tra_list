import 'package:flutter/material.dart';

class IsherBrandMark extends StatelessWidget {
  const IsherBrandMark({super.key, this.size = 38});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF171D55), Color(0xFF4A1683), Color(0xFF15112E)],
        ),
        border: Border.all(color: const Color(0xFF8F8BFF), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7162FF).withValues(alpha: 0.28),
            blurRadius: size * 0.25,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.hub_outlined,
            size: size * 0.62,
            color: const Color(0xFF92ECFF),
          ),
          Positioned(
            right: size * 0.13,
            top: size * 0.12,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: size * 0.24,
              color: const Color(0xFFF0D6FF),
            ),
          ),
        ],
      ),
    ),
  );
}
