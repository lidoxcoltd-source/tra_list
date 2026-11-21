import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class HomePromoCard {
  const HomePromoCard({
    required this.brand,
    required this.headline,
    required this.body,
  });

  final String brand;
  final String headline;
  final String body;
}

class HomePromoService {
  HomePromoService._();

  static final _sessionRequests = <String, Future<List<HomePromoCard>>>{};

  static Future<List<HomePromoCard>> forSession({required String language}) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Future.error(StateError('Sign in to load Home promotions.'));
    }
    final normalizedLanguage = language == 'sw' ? 'sw' : 'en';
    final key = '$uid:$normalizedLanguage';
    return _sessionRequests.putIfAbsent(
      key,
      () => _generate(normalizedLanguage),
    );
  }

  static Future<List<HomePromoCard>> _generate(String language) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('generateHomePromo')
        .call({'language': language});
    final data = Map<String, dynamic>.from(result.data as Map);
    final rawCards = data['cards'];
    if (rawCards is! List || rawCards.length != 3) {
      throw const FormatException('Invalid Home promotions response.');
    }
    return rawCards
        .map((rawCard) {
          final card = Map<String, dynamic>.from(rawCard as Map);
          return HomePromoCard(
            brand: card['brand'] as String,
            headline: card['headline'] as String,
            body: card['body'] as String,
          );
        })
        .toList(growable: false);
  }

  static List<HomePromoCard> fallbackCards(String language) {
    if (language == 'sw') {
      return const [
        HomePromoCard(
          brand: 'MJASI',
          headline: 'Simamia biashara yako',
          body: 'Rekodi mauzo, fuatilia stoo na unda ankara kwa urahisi.',
        ),
        HomePromoCard(
          brand: 'ISHER AI',
          headline: 'Uliza Isher AI',
          body: 'Pata muhtasari wa mauzo na matumizi kwa mazungumzo.',
        ),
        HomePromoCard(
          brand: 'MJASI',
          headline: 'Taarifa muhimu, pamoja',
          body: 'Angalia ripoti za biashara yako kwa urahisi.',
        ),
      ];
    }
    return const [
      HomePromoCard(
        brand: 'MJASI',
        headline: 'Run your business simply',
        body: 'Record sales, track stock, and create invoices in one place.',
      ),
      HomePromoCard(
        brand: 'ISHER AI',
        headline: 'Ask Isher AI',
        body: 'Get helpful summaries of your sales and expenses.',
      ),
      HomePromoCard(
        brand: 'MJASI',
        headline: 'See the bigger picture',
        body: 'Review clear reports about your business.',
      ),
    ];
  }
}

class HomePromoCarousel extends StatefulWidget {
  const HomePromoCarousel({
    super.key,
    required this.language,
    this.compact = false,
  });

  final String language;
  final bool compact;

  @override
  State<HomePromoCarousel> createState() => _HomePromoCarouselState();
}

class _HomePromoCarouselState extends State<HomePromoCarousel> {
  static const _firstPage = 30000;

  late final PageController _pageController;
  late List<HomePromoCard> _cards;
  int _currentIndex = 0;
  Timer? _rotationTimer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _firstPage);
    _cards = HomePromoService.fallbackCards(widget.language);
    unawaited(_loadPromotions());
    _scheduleNextPage();
  }

  @override
  void didUpdateWidget(covariant HomePromoCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language) {
      _cards = HomePromoService.fallbackCards(widget.language);
      _currentIndex =
          (_pageController.page?.round() ?? _firstPage) % _cards.length;
      unawaited(_loadPromotions());
    }
  }

  void _scheduleNextPage() {
    _rotationTimer?.cancel();
    _rotationTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      if (!_pageController.hasClients) {
        _scheduleNextPage();
        return;
      }
      final page = _pageController.page?.round() ?? _firstPage;
      _pageController.animateToPage(
        page + 1,
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _onPageChanged(int page) {
    if (mounted) {
      setState(() => _currentIndex = page % _cards.length);
      _scheduleNextPage();
    }
  }

  Future<void> _loadPromotions() async {
    try {
      final cards = await HomePromoService.forSession(
        language: widget.language,
      );
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _currentIndex =
            (_pageController.page?.round() ?? _firstPage) % _cards.length;
      });
    } catch (error, stackTrace) {
      debugPrint('Home promotion generation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildPromoCard(HomePromoCard card, int page) {
    final isIsher = card.brand == 'ISHER AI';
    final compact = widget.compact;
    final colors = isIsher
        ? const [Color(0xFF32105D), Color(0xFF9A2BB1)]
        : const [Color(0xFF082B55), Color(0xFF008A91)];
    final brandIcon = isIsher
        ? Icons.psychology_alt_rounded
        : Icons.point_of_sale_rounded;
    final iconSize = compact ? 42.0 : 54.0;

    return Container(
      key: ValueKey(page),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 16,
        vertical: compact ? 8 : 13,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(compact ? 19 : 22),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: .24),
            blurRadius: compact ? 8 : 16,
            offset: Offset(0, compact ? 3 : 7),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            right: compact ? -18 : -24,
            top: compact ? -44 : -55,
            child: Container(
              width: compact ? 94 : 132,
              height: compact ? 94 : 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: isIsher ? .1 : .08),
              ),
            ),
          ),
          Positioned(
            right: compact ? 40 : 58,
            bottom: compact ? -56 : -72,
            child: Container(
              width: compact ? 88 : 112,
              height: compact ? 88 : 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: .1),
                  width: compact ? 9 : 12,
                ),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(compact ? 14 : 18),
                  border: Border.all(color: Colors.white.withValues(alpha: .2)),
                ),
                child: Icon(
                  brandIcon,
                  color: Colors.white,
                  size: compact ? 23 : 29,
                ),
              ),
              SizedBox(width: compact ? 10 : 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          card.brand,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .82),
                            fontSize: compact ? 9 : 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                        const Spacer(),
                        ...List.generate(
                          _cards.length,
                          (index) => AnimatedContainer(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                            width: index == _currentIndex ? 14 : 5,
                            height: 5,
                            margin: const EdgeInsets.only(left: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(
                                alpha: index == _currentIndex ? .95 : .45,
                              ),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 2 : 4),
                    Text(
                      card.headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 16 : 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.35,
                        height: 1.05,
                      ),
                    ),
                    SizedBox(height: compact ? 2 : 4),
                    Text(
                      card.body,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .88),
                        fontSize: compact ? 10 : 12,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    return SizedBox(
      height: compact ? 80 : 110,
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) =>
            _buildPromoCard(_cards[index % _cards.length], index),
        itemCount: null,
        padEnds: false,
        pageSnapping: true,
        physics: const PageScrollPhysics(),
      ),
    );
  }
}
