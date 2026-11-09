import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/isher_avatar.dart';
import 'package:tra_list/business_intelligence/isher_brand_mark.dart';
import 'package:tra_list/business_intelligence/isher_greeting_voice.dart';

class IsherWelcomeScreen extends StatefulWidget {
  const IsherWelcomeScreen({
    super.key,
    required this.loading,
    required this.error,
    required this.ready,
    required this.businessName,
    required this.businessId,
    required this.greetingReady,
    required this.onRetry,
    required this.onChat,
    required this.onVoice,
    required this.onUsage,
    required this.onReport,
    this.greetingVoice,
  });

  final bool loading;
  final String error;
  final bool ready;
  final String businessName;
  final String? businessId;
  final bool greetingReady;
  final IsherGreetingVoice? greetingVoice;
  final VoidCallback onRetry;
  final VoidCallback onChat;
  final VoidCallback onVoice;
  final VoidCallback onUsage;
  final VoidCallback onReport;

  @override
  State<IsherWelcomeScreen> createState() => _IsherWelcomeScreenState();
}

class _IsherWelcomeScreenState extends State<IsherWelcomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _ambient;
  late final IsherGreetingVoice _voice;
  int _voiceGeneration = 0;
  bool _scheduled = false;
  bool _attempted = false;
  bool _voiceError = false;
  bool _cloudFallback = false;
  bool _leaving = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _voice =
        widget.greetingVoice ??
        CloudIsherGreetingVoice(
          businessId: () => widget.businessId,
          onFallback: () {
            if (mounted) setState(() => _cloudFallback = true);
          },
        );
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleGreeting();
  }

  @override
  void didUpdateWidget(covariant IsherWelcomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.businessName != widget.businessName) {
      _stopGreeting();
      _attempted = false;
    } else if (oldWidget.greetingReady && !widget.greetingReady) {
      _stopGreeting();
      _attempted = false;
    }
    _scheduleGreeting();
  }

  void _scheduleGreeting() {
    if (!widget.greetingReady ||
        !_foreground ||
        _leaving ||
        _attempted ||
        _scheduled) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted ||
          !widget.greetingReady ||
          !_foreground ||
          _leaving ||
          _attempted) {
        return;
      }
      _attempted = true;
      _playGreeting();
    });
  }

  String get _greeting {
    final name = widget.businessName.trim();
    return name.isEmpty
        ? 'isher_personal_greeting_no_name'.tr
        : 'isher_personal_greeting'.trParams({'name': name});
  }

  Future<void> _playGreeting() async {
    final generation = ++_voiceGeneration;
    if (mounted) {
      setState(() {
        _voiceError = false;
        _cloudFallback = false;
      });
    }
    try {
      await _voice.stop();
      if (!mounted ||
          generation != _voiceGeneration ||
          !widget.greetingReady ||
          !_foreground ||
          _leaving) {
        return;
      }
      final language = Get.locale?.languageCode == 'sw' ? 'sw' : 'en';
      await _voice.speak(
        _greeting,
        language,
        () =>
            mounted &&
            widget.greetingReady &&
            _foreground &&
            !_leaving &&
            generation == _voiceGeneration,
      );
    } catch (error, stack) {
      debugPrint('Isher greeting voice failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted && generation == _voiceGeneration) {
        setState(() => _voiceError = true);
      }
    }
  }

  Future<void> _stopGreeting() {
    _voiceGeneration++;
    return _voice.stop().catchError((Object error, StackTrace stack) {
      debugPrint('Isher greeting stop failed: $error');
      debugPrintStack(stackTrace: stack);
    });
  }

  void _navigate(VoidCallback action) {
    _leaving = true;
    _attempted = true;
    _stopGreeting();
    action();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _stopGreeting();
    } else {
      _scheduleGreeting();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final stopped = _stopGreeting();
    final voice = _voice;
    if (voice is CloudIsherGreetingVoice) {
      unawaited(stopped.then((_) => voice.dispose()));
    }
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFF080817),
      body: AnimatedBuilder(
        animation: _ambient,
        builder: (context, child) {
          final glow = reduceMotion ? 0.5 : _ambient.value;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.5),
                radius: 1.25,
                colors: [
                  Color.lerp(
                    const Color(0xFF111134),
                    const Color(0xFF1C1037),
                    glow,
                  )!,
                  const Color(0xFF080817),
                ],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  bottom: -120,
                  left: -100,
                  child: _AmbientGlow(
                    color: const Color(0xFF176CFF),
                    opacity: 0.13 + glow * 0.05,
                  ),
                ),
                Positioned(
                  bottom: -140,
                  right: -100,
                  child: _AmbientGlow(
                    color: const Color(0xFF8A28F5),
                    opacity: 0.17 + glow * 0.05,
                  ),
                ),
                SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxHeight < 700;
                      final avatarSize = (constraints.maxWidth * 0.48)
                          .clamp(140.0, compact ? 175.0 : 210.0)
                          .toDouble();
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight > 24
                                ? constraints.maxHeight - 24
                                : 0,
                          ),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 480),
                              child: Column(
                                children: [
                                  _header(context),
                                  SizedBox(height: compact ? 18 : 28),
                                  Transform.translate(
                                    offset: Offset(0, (glow - 0.5) * 8),
                                    child: _avatar(avatarSize, glow),
                                  ),
                                  SizedBox(height: compact ? 20 : 26),
                                  Text(
                                    'Isher AI',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 27,
                                      fontWeight: FontWeight.w800,
                                      height: 1.15,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    'isher_welcome_subtitle'.tr,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFFC7A9FF),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (widget.greetingReady) ...[
                                    const SizedBox(height: 8),
                                    if (_cloudFallback && !_voiceError)
                                      Text(
                                        'isher_greeting_cloud_fallback'.tr,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10,
                                        ),
                                      ),
                                    if (_voiceError)
                                      Text(
                                        (!kIsWeb &&
                                                    defaultTargetPlatform ==
                                                        TargetPlatform.android
                                                ? 'isher_greeting_voice_error'
                                                : 'isher_greeting_voice_unavailable')
                                            .tr,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10,
                                        ),
                                      ),
                                  ],
                                  const SizedBox(height: 20),
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _Capability(label: 'isher_capability_insights'.tr),
                                      _Capability(label: 'isher_capability_documents'.tr),
                                      _Capability(label: 'isher_capability_transactions'.tr),
                                    ],
                                  ),
                                  SizedBox(height: compact ? 24 : 34),
                                  if (widget.loading)
                                    _WelcomeLoading(glow: glow)
                                  else if (!widget.ready)
                                    Column(
                                      children: [
                                        Text(
                                          widget.error.isEmpty
                                              ? 'bi_access_error'.tr
                                              : widget.error,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: widget.onRetry,
                                          child: Text('refresh'.tr),
                                        ),
                                      ],
                                    )
                                  else ...[
                                    LayoutBuilder(
                                      builder: (context, actionConstraints) {
                                        final chat = _WelcomeButton(
                                          label: 'bi_tab_chat'.tr,
                                          icon: Icons.chat_bubble_rounded,
                                          primary: true,
                                          onPressed: () =>
                                              _navigate(widget.onChat),
                                        );
                                        final voice = _WelcomeButton(
                                          label: 'bi_tab_call'.tr,
                                          icon: Icons.call_rounded,
                                          primary: false,
                                          onPressed: () =>
                                              _navigate(widget.onVoice),
                                        );
                                        if (actionConstraints.maxWidth < 260 ||
                                            MediaQuery.textScalerOf(
                                                  context,
                                                ).scale(1) >
                                                1.6) {
                                          return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              chat,
                                              const SizedBox(height: 12),
                                              voice,
                                            ],
                                          );
                                        }
                                        return Row(
                                          children: [
                                            Expanded(child: chat),
                                            const SizedBox(width: 12),
                                            Expanded(child: voice),
                                          ],
                                        );
                                      },
                                    ),
                                    TextButton.icon(
                                      onPressed: () =>
                                          _navigate(widget.onReport),
                                      icon: const Icon(
                                        Icons.bar_chart_rounded,
                                        size: 18,
                                      ),
                                      label: Text('bi_view_report'.tr),
                                      style: TextButton.styleFrom(
                                        foregroundColor: const Color(
                                          0xFFBEBBD0,
                                        ),
                                      ),
                                    ),
                                  ],
                                  SizedBox(height: compact ? 10 : 24),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Color(0xFF6FE3A4),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Color(0xAA6FE3A4),
                                              blurRadius: 8,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'isher_powered'.tr,
                                        style: const TextStyle(
                                          color: Color(0xFF8E8AA3),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context) => Row(
    children: [
      Expanded(
        child: Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => _navigate(() => Navigator.of(context).pop()),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF26233D),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
          ),
        ),
      ),
      const IsherBrandMark(size: 26),
      const SizedBox(width: 8),
      const Text(
        'ISHER AI',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
      Expanded(
        child: Align(
          alignment: Alignment.centerRight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: OutlinedButton.icon(
              onPressed: () => _navigate(widget.onUsage),
              icon: const Icon(Icons.bolt_rounded, size: 18),
              label: Text('isher_usage'.tr),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE5D8FF),
                side: const BorderSide(color: Color(0xFF8656C6)),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _avatar(double size, double glow) => Stack(
    clipBehavior: Clip.none,
    alignment: Alignment.center,
    children: [
      Container(
        width: size + 12,
        height: size + 12,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const SweepGradient(
            colors: [
              Color(0xFF00D9FF),
              Color(0xFF176CFF),
              Color(0xFF8A28F5),
              Color(0xFFC7A9FF),
              Color(0xFF00D9FF),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(
                0xFF176CFF,
              ).withValues(alpha: 0.2 + glow * 0.1),
              blurRadius: 24,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: const Color(
                0xFF8A28F5,
              ).withValues(alpha: 0.15 + glow * 0.1),
              blurRadius: 32,
              spreadRadius: 2,
            ),
          ],
        ),
        child: IsherAvatar(size: size),
      ),
      Positioned(
        right: 0,
        top: size * 0.13,
        child: const Icon(
          Icons.auto_awesome_rounded,
          color: Color(0xFFE9D9FF),
          size: 25,
        ),
      ),
    ],
  );
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({required this.color, required this.opacity});

  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: 300,
      height: 300,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    ),
  );
}

class _Capability extends StatelessWidget {
  const _Capability({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFF201A3D),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFF554479)),
    ),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Color(0xFFE5D9FF),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _WelcomeLoading extends StatelessWidget {
  const _WelcomeLoading({required this.glow});

  final double glow;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: 'isher_loading'.tr,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1730),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF40365E)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF342551),
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFF8A28F5,
                  ).withValues(alpha: 0.12 + glow * 0.12),
                  blurRadius: 16,
                ),
              ],
            ),
            child: const Padding(
              padding: EdgeInsets.all(11),
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFFC7A9FF),
                backgroundColor: Color(0xFF57446F),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'isher_loading'.tr,
              style: const TextStyle(
                color: Color(0xFFE7DFFF),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _WelcomeButton extends StatefulWidget {
  const _WelcomeButton({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onPressed;

  @override
  State<_WelcomeButton> createState() => _WelcomeButtonState();
}

class _WelcomeButtonState extends State<_WelcomeButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: _pressed ? 0.98 : 1,
    duration: const Duration(milliseconds: 120),
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: widget.primary
            ? const LinearGradient(
                colors: [Color(0xFF9C43F4), Color(0xFF6334C4)],
              )
            : null,
        color: widget.primary ? null : const Color(0xCC10142B),
        border: Border.all(
          color: widget.primary
              ? const Color(0xFFB783FF)
              : const Color(0xFF00BCE8),
        ),
        boxShadow: [
          BoxShadow(
            color:
                (widget.primary
                        ? const Color(0xFF8A28F5)
                        : const Color(0xFF176CFF))
                    .withValues(alpha: 0.25),
            blurRadius: 18,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onHighlightChanged: (value) => setState(() => _pressed = value),
          onTap: widget.onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, color: Colors.white, size: 26),
                const SizedBox(height: 8),
                Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
