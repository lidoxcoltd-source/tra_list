import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/invoice/language_switcher.dart';
import 'package:tra_list/routes.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  static const _navy = Color(0xFF071B35);
  static const _blue = Color(0xFF0866E8);
  static const _cyan = Color(0xFF32B9E8);

  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    _logoScale = Tween<double>(begin: 0.82, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.34, curve: Curves.easeOutCubic),
      ),
    );
    _logoFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.28, curve: Curves.easeOut),
    );
    _textFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 0.52, curve: Curves.easeOut),
    );
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.2, 0.52, curve: Curves.easeOutCubic),
          ),
        );
    _controller.forward();
    _continueToApp();
  }

  Future<void> _continueToApp() async {
    await Future<void>.delayed(const Duration(milliseconds: 3200));
    if (!mounted) return;
    final signedIn = FirebaseAuth.instance.currentUser != null;
    Get.offAllNamed(signedIn ? AppRoutes.home : AppRoutes.login);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _greeting {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName?.trim() ?? '';
    if (user == null) return 'splash_welcome'.tr;
    final firstName = name.isEmpty ? '' : name.split(' ').first;
    return firstName.isEmpty
        ? 'splash_welcome_back'.tr
        : 'splash_welcome_back_name'.trParams({'name': firstName});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_navy, Color(0xFF0A2A51), Color(0xFF071B35)],
                stops: [0, .55, 1],
              ),
            ),
          ),
          Positioned(
            top: -130,
            right: -100,
            child: _glow(size: 320, color: _blue),
          ),
          Positioned(
            bottom: -160,
            left: -110,
            child: _glow(size: 360, color: _cyan),
          ),
          Positioned(
            right: -90,
            bottom: 45,
            child: Transform.rotate(
              angle: -.42,
              child: Container(
                width: 420,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .025),
                  borderRadius: BorderRadius.circular(60),
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Positioned(
                    top: 8,
                    right: 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .12),
                        ),
                      ),
                      child: const LanguageSwitcher(color: Colors.white),
                    ),
                  ),
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 64, 24, 92),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight > 156
                              ? constraints.maxHeight - 156
                              : 0,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FadeTransition(
                              opacity: _logoFade,
                              child: ScaleTransition(
                                scale: _logoScale,
                                child: Container(
                                  width: 116,
                                  height: 116,
                                  padding: const EdgeInsets.all(19),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: .75,
                                      ),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _blue.withValues(alpha: .24),
                                        blurRadius: 38,
                                        spreadRadius: 2,
                                        offset: const Offset(0, 14),
                                      ),
                                    ],
                                  ),
                                  child: Image.asset(
                                    'assets/mjas.png',
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) => const Icon(
                                      Icons.storefront_rounded,
                                      size: 58,
                                      color: _navy,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            FadeTransition(
                              opacity: _textFade,
                              child: SlideTransition(
                                position: _textSlide,
                                child: Column(
                                  children: [
                                    const Text(
                                      'MJASI POS',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 2.2,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      width: 42,
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: _cyan,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    Text(
                                      _greeting,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 25,
                                        height: 1.2,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -.3,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 340,
                                      ),
                                      child: Text(
                                        'splash_tagline'.tr,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: .72,
                                          ),
                                          fontSize: 14,
                                          height: 1.55,
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
                  ),
                  Positioned(
                    left: 32,
                    right: 32,
                    bottom: 20,
                    child: FadeTransition(
                      opacity: _textFade,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AnimatedBuilder(
                              animation: _controller,
                              builder: (context, _) => LinearProgressIndicator(
                                value: _controller.value,
                                minHeight: 3,
                                backgroundColor: Colors.white.withValues(
                                  alpha: .14,
                                ),
                                valueColor: const AlwaysStoppedAnimation(_cyan),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'splash_loading'.tr,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .58),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              letterSpacing: .3,
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

  Widget _glow({required double size, required Color color}) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [color.withValues(alpha: .2), color.withValues(alpha: 0)],
      ),
    ),
  );
}
