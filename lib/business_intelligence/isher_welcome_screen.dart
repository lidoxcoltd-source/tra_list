import 'dart:async';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tra_list/business_intelligence/ai_models.dart';
import 'package:tra_list/business_intelligence/business_context.dart';
import 'package:tra_list/business_intelligence/isher_avatar.dart';
import 'package:tra_list/business_intelligence/isher_brand_mark.dart';
import 'package:tra_list/business_intelligence/isher_greeting_voice.dart';
import 'package:tra_list/stock/daily_brief_weather_service.dart';

@visibleForTesting
bool shouldIntroduceIsher(DateTime? lastGreeting, DateTime now) =>
    lastGreeting == null ||
    !lastGreeting.isAfter(now) &&
        now.difference(lastGreeting) >= const Duration(days: 7);

const _swahiliSmallNumbers = [
  'sifuri',
  'moja',
  'mbili',
  'tatu',
  'nne',
  'tano',
  'sita',
  'saba',
  'nane',
  'tisa',
  'kumi',
  'kumi na moja',
  'kumi na mbili',
  'kumi na tatu',
  'kumi na nne',
  'kumi na tano',
  'kumi na sita',
  'kumi na saba',
  'kumi na nane',
  'kumi na tisa',
];

const _swahiliTens = {
  20: 'ishirini',
  30: 'thelathini',
  40: 'arobaini',
  50: 'hamsini',
  60: 'sitini',
  70: 'sabini',
  80: 'themanini',
  90: 'tisini',
};

String _swahiliBelowHundred(int value) {
  if (value < 20) return _swahiliSmallNumbers[value];
  final tens = value ~/ 10 * 10;
  final remainder = value % 10;
  final tensWord = _swahiliTens[tens]!;
  return remainder == 0
      ? tensWord
      : '$tensWord na ${_swahiliSmallNumbers[remainder]}';
}

String _swahiliBelowThousand(int value) {
  if (value < 100) return _swahiliBelowHundred(value);
  final hundreds = value ~/ 100;
  final remainder = value % 100;
  final hundredsWord = 'mia ${_swahiliSmallNumbers[hundreds]}';
  return remainder == 0
      ? hundredsWord
      : '$hundredsWord na ${_swahiliBelowHundred(remainder)}';
}

String _swahiliIntegerWords(int value) {
  if (value == 0) return _swahiliSmallNumbers.first;
  var remaining = value;
  final parts = <String>[];
  const scales = [
    1000000000000,
    1000000000,
    1000000,
    100000,
    1000,
  ];
  const scaleNames = ['trilioni', 'bilioni', 'milioni', 'laki', 'elfu'];
  for (var index = 0; index < scales.length; index++) {
    final group = remaining ~/ scales[index];
    if (group == 0) continue;
    parts.add('${scaleNames[index]} ${_swahiliIntegerWords(group)}');
    remaining %= scales[index];
  }
  if (remaining > 0) parts.add(_swahiliBelowThousand(remaining));
  return parts.join(' na ');
}

String _swahiliTanzaniaShillings(num amount) {
  if (!amount.isFinite) throw ArgumentError.value(amount, 'amount');
  final totalCents = (amount.abs() * 100).round();
  final shillings = totalCents ~/ 100;
  final cents = totalCents % 100;
  final amountWords = _swahiliIntegerWords(shillings);
  final centsWords = cents == 0
      ? ''
      : ' na senti ${_swahiliIntegerWords(cents)}';
  return '${amount < 0 ? 'hasi ' : ''}shilingi $amountWords$centsWords';
}

@visibleForTesting
String isherWelcomeGreeting({
  required String language,
  required String name,
  required DateTime now,
  required bool introduce,
  required BusinessContext? business,
  DailyBriefWeather? weather,
  bool weatherUnavailable = false,
}) {
  final sw = language == 'sw';
  final tanzaniaTime = now.toUtc().add(const Duration(hours: 3));
  final hour = tanzaniaTime.hour;
  final String timeOfDay;
  if (sw) {
    timeOfDay = hour < 12
        ? 'asubuhi'
        : hour < 17
        ? 'mchana'
        : hour < 19
        ? 'jioni'
        : 'usiku';
  } else {
    timeOfDay = hour < 12
        ? 'morning'
        : hour < 17
        ? 'afternoon'
        : 'evening';
  }
  final safeName = name.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
  final greeting = sw
      ? safeName.isEmpty
            ? 'Habari za $timeOfDay.'
            : 'Habari $safeName, za $timeOfDay.'
      : 'Good $timeOfDay${safeName.isEmpty ? '' : ', $safeName'}.';
  final lines = <String>[
    greeting,
    if (introduce)
      sw
          ? 'Naitwa Isher AI, msaidizi wako wa biashara.'
          : 'My name is Isher AI, your business assistant.',
  ];
  if (business != null) {
    final money = NumberFormat('#,##0.##', 'en_US');
    final period = DateFormat('yyyy-MM').format(business.period.start);
    lines.add(
      sw
          ? 'Muhtasari wa biashara yako kwa kipindi cha $period.'
          : 'Here is your business summary for $period.',
    );
    if (business.income != null) {
      lines.add(
        sw
            ? 'Mapato yaliyorekodiwa ni ${_swahiliTanzaniaShillings(business.income!)}.'
            : 'Recorded income is ${money.format(business.income)} Tanzanian shillings.',
      );
    }
    if (business.expenses != null) {
      lines.add(
        sw
            ? 'Matumizi yaliyorekodiwa ni ${_swahiliTanzaniaShillings(business.expenses!)}.'
            : 'Recorded expenses are ${money.format(business.expenses)} Tanzanian shillings.',
      );
    }
    if (business.income != null && business.expenses != null) {
      final cashFlow = business.income! - business.expenses!;
      final swahiliCashFlow = cashFlow < 0
          ? 'upungufu wa ${_swahiliTanzaniaShillings(-cashFlow)}'
          : _swahiliTanzaniaShillings(cashFlow);
      lines.add(
        sw
            ? 'Salio la fedha, si faida ni $swahiliCashFlow.'
            : 'Cash flow, not profit, is ${money.format(cashFlow)} Tanzanian shillings.',
      );
    }
    if (business.lowStock != null && business.lowStock!.isNotEmpty) {
      final products = business.lowStock!.take(3).join(', ');
      lines.add(
        sw
            ? 'Bidhaa zenye akiba ndogo: $products.'
            : 'Low-stock products: $products.',
      );
    }
    if (business.receivable != null && business.receivable! > 0) {
      lines.add(
        sw
            ? 'Madeni ya wateja ni ${_swahiliTanzaniaShillings(business.receivable!)}.'
            : 'Customer debts are ${money.format(business.receivable)} Tanzanian shillings.',
      );
    }
    if (business.payable != null && business.payable! > 0) {
      lines.add(
        sw
            ? 'Madeni ya biashara ni ${_swahiliTanzaniaShillings(business.payable!)}.'
            : 'Business debts are ${money.format(business.payable)} Tanzanian shillings.',
      );
    }
  }
  if (weather != null) {
    lines.add(weather.explanation(language));
    final tips = weather.practicalTips(language);
    if (tips.isNotEmpty) {
      lines.add(
        sw
            ? 'Hatua za kuchukua: ${tips.join(' ')}'
            : 'Actions to consider: ${tips.join(' ')}',
      );
    }
  } else if (weatherUnavailable) {
    lines.add(
      sw
          ? 'Sikuweza kupata taarifa za hali ya hewa ya eneo lako kwa sasa.'
          : "I couldn't get your local weather right now.",
    );
  }
  return lines.join(' ');
}

class IsherWelcomeScreen extends StatefulWidget {
  const IsherWelcomeScreen({
    super.key,
    required this.loading,
    required this.error,
    required this.ready,
    required this.businessName,
    required this.businessId,
    this.businessContext,
    this.greetingName = '',
    this.greetingUserId,
    required this.greetingReady,
    this.voiceProvidersLoader,
    this.weatherLoader,
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
  final BusinessContext? businessContext;
  final String greetingName;
  final String? greetingUserId;
  final bool greetingReady;
  final Future<List<String>> Function()? voiceProvidersLoader;
  final Future<DailyBriefWeather> Function()? weatherLoader;
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
  static final _random = Random();
  static final Map<String, int> _lastGreetingVariants = {};
  static const _greetingVariantCount = 3;

  late final AnimationController _ambient;
  late final IsherGreetingVoice _voice;
  late final DailyBriefWeatherService _weatherService;
  int _voiceGeneration = 0;
  int _providerGeneration = 0;
  bool? _shouldIntroduce;
  bool _voiceError = false;
  bool _voiceBusy = false;
  Object? _voiceFailure;
  bool _leaving = false;
  bool _foreground = true;
  List<String> _greetingProviders = const [];
  String _greetingProvider = 'gemini';
  bool _greetingProvidersLoading = false;
  bool _greetingProvidersReady = false;
  bool _greetingProviderLoadError = false;
  bool _greetingProviderPreferenceError = false;
  DailyBriefWeather? _greetingWeather;
  bool _greetingWeatherLoaded = false;
  bool _greetingWeatherUnavailable = false;

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
        );
    _weatherService = DailyBriefWeatherService();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    if (widget.greetingReady) unawaited(_loadGreetingProviders());
  }

  @override
  void didUpdateWidget(covariant IsherWelcomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final identityChanged =
        oldWidget.businessId != widget.businessId ||
        oldWidget.businessName != widget.businessName ||
        oldWidget.greetingUserId != widget.greetingUserId;
    if (identityChanged ||
        (oldWidget.greetingReady && !widget.greetingReady)) {
      _stopGreeting();
      _shouldIntroduce = null;
    }
    if (!widget.greetingReady) {
      _providerGeneration++;
      _greetingProvidersLoading = false;
      _greetingProvidersReady = false;
    } else if (identityChanged ||
        (!oldWidget.greetingReady && widget.greetingReady)) {
      unawaited(_loadGreetingProviders());
    }
  }

  String _greetingProviderPreferenceKey() =>
      'isher_greeting_provider_${widget.greetingUserId ?? ''}_${widget.businessId ?? ''}';

  Future<void> _loadGreetingProviders() async {
    final generation = ++_providerGeneration;
    setState(() {
      _greetingProvidersLoading = true;
      _greetingProvidersReady = false;
      _greetingProviderLoadError = false;
      _greetingProviderPreferenceError = false;
    });
    try {
      final loader = widget.voiceProvidersLoader;
      final configured = loader == null
          ? await AiModelRepository().voiceProviders()
          : await loader();
      final providers = configured
          .where((provider) => provider == 'gemini' || provider == 'openai')
          .toSet()
          .toList();
      if (providers.isEmpty) throw StateError('No voice providers available');

      SharedPreferences? preferences;
      String? savedProvider;
      var preferenceError = false;
      try {
        preferences = await SharedPreferences.getInstance();
        savedProvider = preferences.getString(
          _greetingProviderPreferenceKey(),
        );
      } catch (error, stackTrace) {
        debugPrint('Greeting model preference load failed: $error');
        debugPrintStack(stackTrace: stackTrace);
        preferenceError = true;
      }
      final selected = providers.contains(savedProvider)
          ? savedProvider!
          : defaultVoiceEngine(providers);
      if (!mounted || generation != _providerGeneration) return;
      setState(() {
        _greetingProviders = providers;
        _greetingProvider = selected;
        _greetingProvidersLoading = false;
        _greetingProvidersReady = true;
        _greetingProviderPreferenceError = preferenceError;
      });
      if (preferences != null && savedProvider != selected) {
        try {
          await preferences.setString(
            _greetingProviderPreferenceKey(),
            selected,
          );
        } catch (error, stackTrace) {
          debugPrint('Greeting model preference save failed: $error');
          debugPrintStack(stackTrace: stackTrace);
          if (mounted && generation == _providerGeneration) {
            setState(() => _greetingProviderPreferenceError = true);
          }
        }
      }
    } catch (error, stackTrace) {
      debugPrint('Greeting voice providers failed to load: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted || generation != _providerGeneration) return;
      setState(() {
        _greetingProvidersLoading = false;
        _greetingProvidersReady = false;
        _greetingProviderLoadError = true;
      });
    }
  }

  Future<void> _selectGreetingProvider(String provider) async {
    if (_voiceBusy || !_greetingProviders.contains(provider)) return;
    setState(() {
      _greetingProvider = provider;
      _greetingProviderPreferenceError = false;
    });
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_greetingProviderPreferenceKey(), provider);
    } catch (error, stackTrace) {
      debugPrint('Greeting model preference save failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _greetingProviderPreferenceError = true);
    }
  }

  Widget _greetingModelSelector() {
    final providerLabel = _greetingProvider == 'gemini' ? 'Gemini' : 'OpenAI';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'isher_greeting_model'.tr,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        if (_greetingProvidersLoading)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (_greetingProviderLoadError)
          TextButton.icon(
            onPressed: () => unawaited(_loadGreetingProviders()),
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: Text('isher_greeting_model_retry'.tr),
          )
        else if (_greetingProviders.length > 1)
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final provider in _greetingProviders)
                ButtonSegment(
                  value: provider,
                  label: Text(provider == 'gemini' ? 'Gemini' : 'OpenAI'),
                ),
            ],
            selected: {_greetingProvider},
            onSelectionChanged: _voiceBusy
                ? null
                : (selection) =>
                      unawaited(_selectGreetingProvider(selection.first)),
          )
        else
          Text(
            providerLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (_greetingProviderPreferenceError) ...[
          const SizedBox(height: 4),
          Text(
            'isher_greeting_model_preference_error'.tr,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ],
    );
  }

  int _nextGreetingVariant(String language) {
    final previous = _lastGreetingVariants[language];
    final choices = List<int>.generate(
      _greetingVariantCount,
      (index) => index,
    ).where((index) => index != previous).toList();
    final selected = choices[_random.nextInt(choices.length)];
    _lastGreetingVariants[language] = selected;
    return selected;
  }

  String _greetingPreferenceKey() =>
      'isher_last_greeting_${widget.greetingUserId ?? ''}_${widget.businessId ?? ''}';

  Future<void> _loadGreetingWeather() async {
    if (_greetingWeatherLoaded) return;
    try {
      final loader = widget.weatherLoader;
      _greetingWeather = loader == null
          ? await _weatherService.fetch()
          : await loader();
    } catch (error, stackTrace) {
      debugPrint('Isher greeting weather unavailable: $error');
      debugPrintStack(stackTrace: stackTrace);
      _greetingWeatherUnavailable = true;
    } finally {
      _greetingWeatherLoaded = true;
    }
  }

  Future<bool> _introductionDue(DateTime now) async {
    final cached = _shouldIntroduce;
    if (cached != null) return cached;
    try {
      final preferences = await SharedPreferences.getInstance();
      final milliseconds = preferences.getInt(_greetingPreferenceKey());
      final lastGreeting = milliseconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
      final due = shouldIntroduceIsher(lastGreeting, now);
      _shouldIntroduce = due;
      return due;
    } catch (error, stack) {
      debugPrint('Isher greeting history load failed: $error');
      debugPrintStack(stackTrace: stack);
      return true;
    }
  }

  Future<void> _playGreeting() async {
    if (!_greetingProvidersReady) return;
    final generation = ++_voiceGeneration;
    if (mounted) {
      setState(() {
        _voiceError = false;
        _voiceBusy = true;
        _voiceFailure = null;
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
      final greetingVariant = _nextGreetingVariant(language);
      final now = DateTime.now().toUtc();
      final introduce = await _introductionDue(now);
      if (!mounted ||
          generation != _voiceGeneration ||
          !widget.ready ||
          widget.loading ||
          !_foreground ||
          _leaving) {
        return;
      }
      await _loadGreetingWeather();
      if (!mounted ||
          generation != _voiceGeneration ||
          !widget.ready ||
          widget.loading ||
          !_foreground ||
          _leaving) {
        return;
      }
      final greetingText = isherWelcomeGreeting(
        language: language,
        name: widget.greetingName,
        now: now,
        introduce: introduce,
        business: widget.businessContext,
        weather: _greetingWeather,
        weatherUnavailable: _greetingWeatherUnavailable,
      );
      await _voice.speak(
        greetingText,
        language,
        () =>
            mounted &&
            widget.greetingReady &&
            _foreground &&
            !_leaving &&
            generation == _voiceGeneration,
        greetingVariant: greetingVariant,
        provider: _greetingProvider,
      );
      if (mounted &&
          generation == _voiceGeneration &&
          _foreground &&
          !_leaving) {
        try {
          final preferences = await SharedPreferences.getInstance();
          await preferences.setInt(
            _greetingPreferenceKey(),
            now.millisecondsSinceEpoch,
          );
        } catch (error, stack) {
          debugPrint('Isher greeting history save failed: $error');
          debugPrintStack(stackTrace: stack);
        }
      }
    } catch (error, stack) {
      debugPrint('Isher greeting voice failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted && generation == _voiceGeneration) {
        setState(() {
          _voiceError = true;
          _voiceFailure = error;
        });
      }
    } finally {
      if (mounted && generation == _voiceGeneration) {
        setState(() => _voiceBusy = false);
      }
    }
  }

  String _voiceErrorMessage() {
    final failure = _voiceFailure;
    if (failure is FirebaseFunctionsException &&
        failure.code == 'resource-exhausted') {
      return 'isher_greeting_limit'.tr;
    }
    return 'isher_greeting_voice_unavailable'.tr;
  }

  Future<void> _toggleGreetingPlayback() async {
    if (_voiceBusy) {
      await _stopGreeting();
      return;
    }
    if (!_greetingProvidersReady) return;
    await _playGreeting();
  }

  Future<void> _stopGreeting({bool updateState = true}) {
    _voiceGeneration++;
    if (_voiceBusy) {
      if (mounted && updateState) {
        setState(() => _voiceBusy = false);
      } else {
        _voiceBusy = false;
      }
    }
    return _voice.stop().catchError((Object error, StackTrace stack) {
      debugPrint('Isher greeting stop failed: $error');
      debugPrintStack(stackTrace: stack);
    });
  }

  void _navigate(VoidCallback action) {
    _leaving = true;
    _stopGreeting();
    action();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _stopGreeting();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final stopped = _stopGreeting(updateState: false);
    final voice = _voice;
    if (voice is CloudIsherGreetingVoice) {
      unawaited(stopped.then((_) => voice.dispose()));
    }
    _weatherService.dispose();
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
                                    if (_voiceError)
                                      Text(
                                        _voiceErrorMessage(),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                        ),
                                      ),
                                    const SizedBox(height: 12),
                                    _greetingModelSelector(),
                                    const SizedBox(height: 10),
                                    _GreetingListenButton(
                                      animation: reduceMotion
                                          ? const AlwaysStoppedAnimation<double>(
                                              0.5,
                                            )
                                          : _ambient,
                                      busy: _voiceBusy,
                                      enabled:
                                          _greetingProvidersReady ||
                                          _voiceBusy,
                                      onPressed: () =>
                                          unawaited(_toggleGreetingPlayback()),
                                    ),
                                  ],
                                  const SizedBox(height: 20),
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _Capability(
                                        label: 'isher_capability_insights'.tr,
                                      ),
                                      _Capability(
                                        label: 'isher_capability_documents'.tr,
                                      ),
                                      _Capability(
                                        label:
                                            'isher_capability_transactions'.tr,
                                      ),
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

class _GreetingListenButton extends StatelessWidget {
  const _GreetingListenButton({
    required this.animation,
    required this.busy,
    required this.enabled,
    required this.onPressed,
  });

  final Animation<double> animation;
  final bool busy;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, _) => Transform.scale(
      scale: busy ? 1 : 0.97 + animation.value * 0.05,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [Color(0xFF9C43F4), Color(0xFF176CFF)],
          ),
          border: Border.all(color: const Color(0xFFCFB4FF), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8A28F5).withValues(
                alpha: 0.24 + animation.value * 0.18,
              ),
              blurRadius: 16 + animation.value * 8,
              spreadRadius: animation.value * 1.5,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          child: Opacity(
            opacity: enabled ? 1 : 0.58,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              borderRadius: BorderRadius.circular(28),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 9,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                      ),
                      child: Center(
                        child: busy
                            ? const Icon(
                                Icons.stop_rounded,
                                color: Colors.white,
                                size: 25,
                              )
                            : const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 27,
                              ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          busy
                              ? 'isher_greeting_stop'.tr
                              : 'isher_greeting_replay'.tr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (busy)
                          Text(
                            'isher_greeting_listening'.tr,
                            style: const TextStyle(
                              color: Color(0xFFE9DFFF),
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
