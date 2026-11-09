import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
    this.onAiChat,
    this.onAiVoice,
  });

  final List<QuickActionData> actions;
  final ValueChanged<QuickActionData> onSelected;
  final VoidCallback onClose;
  final bool desktop;
  final String? title;
  final IconData headerIcon;
  final VoidCallback? onAiChat;
  final VoidCallback? onAiVoice;

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
                            inherit: false,
                            decoration: TextDecoration.none,
                            color: Color(0xFF172942),
                            fontSize: 16,
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
                  child: LayoutBuilder(
                    builder: (context, constraints) => GridView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(10),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: constraints.maxWidth < 230 ? 1 : 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        mainAxisExtent: 82 +
                            (MediaQuery.textScalerOf(context).scale(14) - 14)
                                .clamp(0.0, 28.0) *
                                2,
                      ),
                      itemCount: actions.length,
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
                ),
                if (onAiChat != null || onAiVoice != null)
                  AiShortcutsBar(
                    onAiChat: onAiChat,
                    onAiVoice: onAiVoice,
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

class AiShortcutsBar extends StatelessWidget {
  const AiShortcutsBar({super.key, this.onAiChat, this.onAiVoice});

  final VoidCallback? onAiChat;
  final VoidCallback? onAiVoice;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF161A50), Color(0xFF38236F), Color(0xFF24205B)],
      ),
      border: Border(top: BorderSide(color: Color(0xFF8271D1))),
    ),
    child: Wrap(
      alignment: WrapAlignment.center,
      spacing: 36,
      runSpacing: 12,
      children: [
        if (onAiChat != null)
          _AiShortcut(
            label: 'bi_tab_chat'.tr,
            icon: Icons.chat_bubble_outline_rounded,
            onTap: onAiChat!,
          ),
        if (onAiVoice != null)
          _AiShortcut(
            label: 'bi_tab_call'.tr,
            icon: Icons.graphic_eq_rounded,
            onTap: onAiVoice!,
          ),
      ],
    ),
  );
}

class _AiShortcut extends StatelessWidget {
  const _AiShortcut({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Tooltip(
        message: label,
        child: Container(
          width: 58,
          height: 58,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF80E4FF), Color(0xFF7464FF)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6186FF).withValues(alpha: .42),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF188FFF), Color(0xFF4142C9)],
              ),
            ),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Icon(icon, color: Colors.white, size: 25),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: const TextStyle(
          inherit: false,
          decoration: TextDecoration.none,
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: .4,
        ),
      ),
    ],
  );
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
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFBFE),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0xFFE6ECF5)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
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
              const SizedBox(height: 4),
              Flexible(
                child: Text(
                  action.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    inherit: false,
                    decoration: TextDecoration.none,
                    color: Color(0xFF172942),
                    fontSize: 14,
                    height: 1.05,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
