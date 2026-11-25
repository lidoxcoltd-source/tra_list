import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/isher_avatar.dart';

const _background = Color(0xFF0C1110);
const _panel = Color(0xFF17201E);
const _lime = Color(0xFFD8F36A);
const _coral = Color(0xFFFF956B);
const _text = Color(0xFFF3F5EE);
const _muted = Color(0xFFA8B3AA);
final _fallbackLaunch = DateTime.utc(2026, 12, 12, 12);

class AiEarlyAccessPage extends StatefulWidget {
  const AiEarlyAccessPage({super.key});

  @override
  State<AiEarlyAccessPage> createState() => _AiEarlyAccessPageState();
}

class _AiEarlyAccessPageState extends State<AiEarlyAccessPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _website = TextEditingController();
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 36),
  )..repeat();
  Timer? _countdownTimer;
  DateTime _launchAt = _fallbackLaunch;
  Duration _remaining = Duration.zero;
  bool _consent = false;
  bool _submitting = false;
  bool _registered = false;
  bool _swahili = false;

  bool get _sw => _swahili;

  @override
  void initState() {
    super.initState();
    final locale = Get.locale?.languageCode;
    _swahili =
        locale == 'sw' ||
        (locale == null &&
            WidgetsBinding.instance.platformDispatcher.locales.any(
              (item) => item.languageCode == 'sw' || item.countryCode == 'TZ',
            ));
    _refreshCountdown();
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshCountdown(),
    );
    _loadLaunchDate();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _ambient.dispose();
    _email.dispose();
    _phone.dispose();
    _website.dispose();
    super.dispose();
  }

  Future<void> _loadLaunchDate() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('ai_early_access')
          .get();
      final value = snapshot.data()?['launchAt'];
      if (value is Timestamp && mounted) {
        setState(() => _launchAt = value.toDate());
        _refreshCountdown();
      }
    } catch (error) {
      debugPrint(
        'Early access launch schedule unavailable: ${error.runtimeType}',
      );
    }
  }

  void _refreshCountdown() {
    if (!mounted) return;
    final next = _launchAt.difference(DateTime.now());
    final remaining = next.isNegative ? Duration.zero : next;
    if (remaining.inSeconds != _remaining.inSeconds) {
      setState(() => _remaining = remaining);
    }
  }

  String _copy(String english, String swahili) => _sw ? swahili : english;

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return _copy('Enter a valid email address.', 'Weka email sahihi.');
    }
    return null;
  }

  String? _validatePhone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length < 9 || digits.length > 15) {
      return _copy('Enter a valid phone number.', 'Weka namba sahihi ya simu.');
    }
    return null;
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (!_consent) {
      _showMessage(
        _copy(
          'Please agree to beta updates first.',
          'Tafadhali kubali kupokea taarifa za beta kwanza.',
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('registerAiEarlyAccess')
          .call({
            'email': _email.text.trim(),
            'phone': _phone.text.trim(),
            'consent': _consent,
            'website': _website.text.trim(),
          });
      if (!mounted) return;
      setState(() => _registered = true);
    } catch (error, stackTrace) {
      debugPrint('Early access registration failed: ${error.runtimeType}');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        _showMessage(
          _copy(
            'We could not save your request. Please try again.',
            'Ombi halikuhifadhiwa. Tafadhali jaribu tena.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ambient,
              builder: (context, _) =>
                  CustomPaint(painter: _EarlyAccessGridPainter(_ambient.value)),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final compact = constraints.maxWidth < 430;
                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: constraints.maxWidth >= 1200
                        ? 64
                        : constraints.maxWidth >= 700
                        ? 36
                        : 20,
                    vertical: 18,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _topBar(compact: compact),
                          SizedBox(height: wide ? 76 : 44),
                          if (wide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(flex: 11, child: _intro()),
                                const SizedBox(width: 56),
                                Expanded(flex: 9, child: _registrationCard()),
                              ],
                            )
                          else ...[
                            _intro(),
                            const SizedBox(height: 34),
                            _registrationCard(),
                          ],
                          const SizedBox(height: 40),
                          Center(child: _downloadsButton()),
                          const SizedBox(height: 26),
                          Center(
                            child: Text(
                              _copy(
                                'A small first wave. Built around real businesses.',
                                'Kundi dogo la kwanza. Tutaijenga kwa mahitaji halisi ya biashara.',
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
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
  }

  Widget _topBar({required bool compact}) => Row(
    children: [
      const _BrandMark(),
      const SizedBox(width: 12),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MJASI LAB',
            style: TextStyle(
              color: _text,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 2),
            const Text(
              'EARLY ACCESS',
              style: TextStyle(
                color: _muted,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
      const Spacer(),
      TextButton.icon(
        onPressed: () => setState(() => _swahili = !_swahili),
        icon: compact ? null : const Icon(Icons.language_rounded, size: 17),
        label: Text(_sw ? 'SW' : 'EN'),
        style: TextButton.styleFrom(
          foregroundColor: _muted,
          minimumSize: Size.zero,
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 12),
        ),
      ),
      const SizedBox(width: 4),
      OutlinedButton.icon(
        onPressed: () => Get.toNamed('/downloads'),
        icon: Icon(
          compact ? Icons.arrow_back_rounded : Icons.apps_rounded,
          size: 16,
        ),
        label: compact
            ? const SizedBox.shrink()
            : Text(_copy('Downloads', 'Pakua app')),
        style: OutlinedButton.styleFrom(
          foregroundColor: _text,
          minimumSize: compact ? const Size(38, 38) : null,
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    ],
  );

  Widget _intro() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _eyebrow(),
      const SizedBox(height: 25),
      Text(
        _copy(
          'Be the first to test\nNzuri.',
          'Kuwa wa kwanza\nkumjaribu Nzuri.',
        ),
        style: TextStyle(
          color: _text,
          fontFamily: 'Hypermarket',
          fontSize: MediaQuery.sizeOf(context).width >= 900 ? 68 : 46,
          height: 1.04,
        ),
      ),
      const SizedBox(height: 20),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Text(
          _copy(
            'Meet a smarter way to understand your business. Join the first group testing Isher AI and help shape what comes next.',
            'Kutana na njia mpya ya kuelewa biashara yako. Jiunge na kundi la kwanza kumjaribu Isher AI na tusaidie kuboresha kinachofuata.',
          ),
          style: const TextStyle(color: _muted, fontSize: 16, height: 1.65),
        ),
      ),
      const SizedBox(height: 30),
      Text(
        _copy('BETA OPENS IN', 'BETA INAANZA BAADA YA'),
        style: const TextStyle(
          color: _muted,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 10),
      _countdown(),
    ],
  );

  Widget _eyebrow() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: _lime.withValues(alpha: 0.08),
      border: Border.all(color: _lime.withValues(alpha: 0.35)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(color: _lime, shape: BoxShape.circle),
        ),
        const SizedBox(width: 9),
        Text(
          _copy('PRIVATE BETA', 'BETA YA MWALIKO'),
          style: const TextStyle(
            color: _lime,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );

  Widget _countdown() {
    final days = _remaining.inDays;
    final hours = _remaining.inHours.remainder(24);
    final minutes = _remaining.inMinutes.remainder(60);
    final seconds = _remaining.inSeconds.remainder(60);
    final values = [
      (days, _copy('DAYS', 'SIKU')),
      (hours, _copy('HRS', 'SAA')),
      (minutes, _copy('MIN', 'DK')),
      (seconds, _copy('SEC', 'SEK')),
    ];
    final unitWidth = MediaQuery.sizeOf(context).width < 430 ? 58.0 : 82.0;
    return Wrap(
      spacing: 7,
      runSpacing: 9,
      children: [
        for (final (value, label) in values)
          _CountdownUnit(value: value, label: label, width: unitWidth),
      ],
    );
  }

  Widget _registrationCard() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: _panel.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      boxShadow: [
        BoxShadow(
          color: _lime.withValues(alpha: 0.055),
          blurRadius: 42,
          spreadRadius: 1,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 34,
          offset: const Offset(0, 20),
        ),
      ],
    ),
    child: _registered ? _successState() : _form(),
  );

  Widget _form() => Form(
    key: _formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const IsherAvatar(size: 50),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _copy('TEST WITH ISHER', 'JARIBU NA ISHER'),
                    style: const TextStyle(
                      color: _lime,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _copy('Get on the first list', 'Jiunge na kundi la kwanza'),
                    style: const TextStyle(
                      color: _text,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _inputLabel(_copy('EMAIL ADDRESS', 'BARUA PEPE')),
        const SizedBox(height: 8),
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          validator: _validateEmail,
          style: const TextStyle(color: _text),
          decoration: _inputDecoration(
            _copy('you@business.com', 'wewe@biashara.com'),
            Icons.alternate_email_rounded,
          ),
        ),
        const SizedBox(height: 17),
        _inputLabel(_copy('PHONE NUMBER', 'NAMBA YA SIMU')),
        const SizedBox(height: 8),
        TextFormField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          validator: _validatePhone,
          style: const TextStyle(color: _text),
          decoration: _inputDecoration('+255 7XX XXX XXX', Icons.phone_rounded),
        ),
        Offstage(
          child: SizedBox(
            width: 1,
            height: 1,
            child: TextField(controller: _website),
          ),
        ),
        const SizedBox(height: 10),
        Theme(
          data: Theme.of(context).copyWith(unselectedWidgetColor: _muted),
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _consent,
            activeColor: _lime,
            checkColor: _background,
            onChanged: _submitting
                ? null
                : (value) => setState(() => _consent = value == true),
            title: Text(
              _copy(
                'Email and text me about the Nzuri beta. See Privacy Policy.',
                'Nitumie email na SMS kuhusu beta ya Nzuri. Soma Sera ya Faragha.',
              ),
              style: const TextStyle(color: _muted, fontSize: 11, height: 1.4),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => Get.toNamed('/privacy'),
            style: TextButton.styleFrom(
              foregroundColor: _lime,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(_copy('Read Privacy Policy', 'Soma Sera ya Faragha')),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _submitting ? null : _register,
            style: FilledButton.styleFrom(
              backgroundColor: _lime,
              foregroundColor: _background,
              disabledBackgroundColor: _lime.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _background,
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _copy('RESERVE MY SPOT', 'WEKA NAFASI YANGU'),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 11),
        Text(
          _copy(
            'No spam. Only beta access and product updates.',
            'Hakuna spam. Taarifa za beta na bidhaa tu.',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontSize: 10),
        ),
      ],
    ),
  );

  Widget _inputLabel(String value) => Text(
    value,
    style: const TextStyle(
      color: _muted,
      fontSize: 9,
      fontWeight: FontWeight.w800,
    ),
  );

  InputDecoration _inputDecoration(
    String hint,
    IconData icon,
  ) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: _muted.withValues(alpha: 0.55), fontSize: 13),
    prefixIcon: Icon(icon, color: _muted, size: 18),
    filled: true,
    fillColor: _background,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(6)),
      borderSide: BorderSide(color: _lime),
    ),
    errorBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(6)),
      borderSide: BorderSide(color: _coral),
    ),
    focusedErrorBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(6)),
      borderSide: BorderSide(color: _coral),
    ),
  );

  Widget _successState() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 23),
    child: Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 520),
          curve: Curves.elasticOut,
          builder: (context, value, child) =>
              Transform.scale(scale: value, child: child),
          child: const Icon(Icons.check_circle_rounded, color: _lime, size: 62),
        ),
        const SizedBox(height: 17),
        Text(
          _copy('You are on the list.', 'Umejiunga na kundi la kwanza.'),
          style: const TextStyle(
            color: _text,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _copy(
            'We will reach out when your beta invite is ready.',
            'Tutakutumia mwaliko wa beta utakapokuwa tayari.',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, height: 1.5),
        ),
      ],
    ),
  );

  Widget _downloadsButton() => OutlinedButton.icon(
    onPressed: () => Get.toNamed('/downloads'),
    icon: const Icon(Icons.apps_rounded, size: 18),
    label: Text(_copy('Explore MJASI downloads', 'Angalia downloads za MJASI')),
    style: OutlinedButton.styleFrom(
      foregroundColor: _text,
      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    ),
  );
}

class _CountdownUnit extends StatelessWidget {
  const _CountdownUnit({
    required this.value,
    required this.label,
    required this.width,
  });

  final int value;
  final String label;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    padding: EdgeInsets.fromLTRB(
      width < 70 ? 7 : 11,
      12,
      width < 70 ? 7 : 11,
      10,
    ),
    decoration: BoxDecoration(
      color: _panel,
      border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.25),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Text(
            '$value'.padLeft(2, '0'),
            key: ValueKey(value),
            style: const TextStyle(
              color: _text,
              fontSize: 25,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: _muted,
            fontSize: 8,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Image.asset(
      'assets/mjas.png',
      width: 40,
      height: 40,
      fit: BoxFit.cover,
    ),
  );
}

class _EarlyAccessGridPainter extends CustomPainter {
  const _EarlyAccessGridPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _lime.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += 42) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += 42) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    final scanTop = progress * (size.height + 80) - 80;
    final scanPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          _lime.withValues(alpha: 0.075),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, scanTop, size.width, 80));
    canvas.drawRect(Rect.fromLTWH(0, scanTop, size.width, 80), scanPaint);
    final rail = Paint()
      ..color = _coral.withValues(alpha: 0.45)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(size.width * 0.72, 0),
      Offset(size.width * 0.72, 72),
      rail,
    );
    canvas.drawCircle(
      Offset(size.width * 0.72, 76),
      3,
      Paint()..color = _coral,
    );
  }

  @override
  bool shouldRepaint(covariant _EarlyAccessGridPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
