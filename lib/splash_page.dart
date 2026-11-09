import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/isher_brand_mark.dart';
import 'package:tra_list/invoice/language_switcher.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/services/account_mode_service.dart';
import 'package:tra_list/services/business_access_service.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 5000);
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
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
    await Future<void>.delayed(_duration);
    if (!mounted) return;
    final signedIn = FirebaseAuth.instance.currentUser != null;
    final route = !signedIn
        ? AppRoutes.login
        : AccountModeService.current == AccountMode.business &&
              !BusinessAccessService.hasBusinessAccess
        ? AppRoutes.businessSetup
        : AppRoutes.home;
    Get.offAllNamed(route);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFF101A54),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF082D72),
                  Color(0xFF193580),
                  Color(0xFF4A257E),
                  Color(0xFF201342),
                ],
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
                        color: Colors.white.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .18),
                        ),
                      ),
                      child: const LanguageSwitcher(color: Colors.white),
                    ),
                  ),
                  Center(
                    child: FadeTransition(
                      opacity: reduceMotion
                          ? const AlwaysStoppedAnimation(1.0)
                          : _logoFade,
                      child: ScaleTransition(
                        scale: reduceMotion
                            ? const AlwaysStoppedAnimation(1.0)
                            : _logoScale,
                        child: Container(
                          width: 148,
                          height: 148,
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(42),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .24),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF8A71FF)
                                    .withValues(alpha: .35),
                                blurRadius: 52,
                                spreadRadius: 4,
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: .22),
                                blurRadius: 30,
                                offset: const Offset(0, 16),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(37),
                            child: Image.asset(
                              'assets/mjas.png',
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.storefront_rounded,
                                size: 64,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: constraints.maxHeight < 300 ? 8 : 56,
                    child: FadeTransition(
                      opacity: reduceMotion
                          ? const AlwaysStoppedAnimation(1.0)
                          : _textFade,
                      child: SlideTransition(
                        position: reduceMotion
                            ? const AlwaysStoppedAnimation(Offset.zero)
                            : _textSlide,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const IsherBrandMark(size: 32),
                            const SizedBox(height: 8),
                            Text(
                              'Isher AI',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .9),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'isher_welcome_subtitle'.tr,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .65),
                                fontSize: 10,
                                letterSpacing: .2,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: 92,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: AnimatedBuilder(
                                  animation: _controller,
                                  builder: (context, _) =>
                                      LinearProgressIndicator(
                                        value: _controller.value,
                                        minHeight: 2,
                                        backgroundColor: Colors.white
                                            .withValues(alpha: .18),
                                        valueColor:
                                            const AlwaysStoppedAnimation(
                                              Color(0xFF8ADFFF),
                                            ),
                                      ),
                                ),
                              ),
                            ),
                          ],
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
    );
  }
}
