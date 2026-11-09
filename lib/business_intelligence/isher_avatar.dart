import 'package:flutter/material.dart';

class IsherAvatar extends StatelessWidget {
  const IsherAvatar({super.key, this.size = 38});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0xFF8F74DE)),
    ),
    child: ClipOval(
      child: Image.asset(
        'assets/isher.png',
        fit: BoxFit.cover,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
      ),
    ),
  );
}
