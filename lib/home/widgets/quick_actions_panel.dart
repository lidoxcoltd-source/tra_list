import 'package:flutter/material.dart';

typedef QuickActionData = ({String label, IconData icon, VoidCallback onTap});

class QuickActionsPanel extends StatelessWidget {
  const QuickActionsPanel({
    super.key,
    required this.actions,
    required this.onSelected,
    required this.onClose,
    this.desktop = false,
    this.title,
    this.headerIcon = Icons.bolt_rounded,
  });

  final List<QuickActionData> actions;
  final ValueChanged<QuickActionData> onSelected;
  final VoidCallback onClose;
  final bool desktop;
  final String? title;
  final IconData headerIcon;

  @override
  Widget build(BuildContext context) {
    const iconColors = [
      Color(0xFF168A62),
      Color(0xFFE06B35),
      Color(0xFF3269D3),
      Color(0xFF8051C7),
      Color(0xFF168A9B),
      Color(0xFFC04468),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, Color(0xFFF5F8FF)],
              ),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xFFE5EBF5)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x26071932),
                  blurRadius: 36,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE5EBF5)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF2FF),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          headerIcon,
                          color: const Color(0xFF0D6FEB),
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title ?? 'Actions',
                          style: const TextStyle(
                            color: Color(0xFF172942),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: onClose,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFF788AA0),
                          size: 18,
                        ),
                        splashRadius: 18,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    itemCount: actions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final action = actions[index];
                      return TweenAnimationBuilder<double>(
                        duration: Duration(milliseconds: 140 + index * 35),
                        curve: Curves.easeOutCubic,
                        tween: Tween<double>(begin: 0, end: 1),
                        builder: (context, value, child) => Transform.translate(
                          offset: Offset(0, 12 * (1 - value)),
                          child: Opacity(
                            opacity: value.clamp(0.0, 1.0),
                            child: child,
                          ),
                        ),
                        child: QuickActionTile(
                          action: action,
                          color: iconColors[index % iconColors.length],
                          onTap: () => onSelected(action),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!desktop)
          CustomPaint(
            size: const Size(42, 22),
            painter: QuickActionsTailPainter(),
          ),
      ],
    );
  }
}

class QuickActionTile extends StatelessWidget {
  const QuickActionTile({
    super.key,
    required this.action,
    required this.color,
    required this.onTap,
  });

  final QuickActionData action;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFBFE),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0xFFE6ECF5)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(action.icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  action.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF172942),
                    fontSize: 12,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Color(0xFF9AA7B9),
                size: 13,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QuickActionsTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Color(0xFFF5F8FF)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
