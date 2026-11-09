import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/isher_avatar.dart';

class IsherThinkingIndicator extends StatefulWidget {
  const IsherThinkingIndicator({super.key});

  @override
  State<IsherThinkingIndicator> createState() => _IsherThinkingIndicatorState();
}

class _IsherThinkingIndicatorState extends State<IsherThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IsherAvatar(size: 32),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF25213D),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF51446F)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'bi_chat_thinking'.tr,
                  style: const TextStyle(
                    color: Color(0xFFD8CCFF),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                ExcludeSemantics(
                  child: AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var index = 0; index < 3; index++)
                          Transform.translate(
                            offset: Offset(
                              0,
                              MediaQuery.disableAnimationsOf(context)
                                  ? 0
                                  : -3 *
                                        (0.5 +
                                            0.5 *
                                                math.sin(
                                                  (_animation.value *
                                                          2 *
                                                          math.pi) -
                                                      index * math.pi / 2,
                                                )),
                            ),
                            child: Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(right: 5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFB9A4FF).withValues(
                                  alpha: MediaQuery.disableAnimationsOf(context)
                                      ? 0.75
                                      : 0.5 +
                                            0.5 *
                                                (0.5 +
                                                    0.5 *
                                                        math.sin(
                                                          (_animation.value *
                                                                  2 *
                                                                  math.pi) -
                                                              index *
                                                                  math.pi /
                                                                  2,
                                                        )),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
