import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'download_center_service.dart';
import 'super_admin_subscription_service.dart';

const _navy = Color(0xFF0B1F3A);
const _navyDeep = Color(0xFF071426);
const _surface = Color(0xFF132840);
const _teal = Color(0xFF0E5962);
const _mint = Color(0xFF29D3C2);
const _violet = Color(0xFF8B5CF6);
const _muted = Color(0xFFB8C7D9);

bool _sw = false;

const _swahili = <String, String>{
  'Could not open the link. Please try again.':
      'Imeshindwa kufungua kiungo. Tafadhali jaribu tena.',
  'Could not load the page.': 'Imeshindwa kupakia ukurasa.',
  'Try again': 'Jaribu tena',
  'Features': 'Vipengele',
  'Pricing': 'Bei',
  'Screenshots': 'Picha',
  'Downloads': 'Pakua',
  'Open app': 'Fungua app',
  'SMART TOOLS FOR YOUR BUSINESS': 'ZANA SMART ZA BIASHARA YAKO',
  'DOWNLOAD MJASI POS': 'PAKUA MJASI POS',
  'Explore features': 'Angalia vipengele',
  'Professional documents': 'Nyaraka za kitaalamu',
  'Cloud sync': 'Data mtandaoni',
  'Multi-platform': 'Majukwaa mengi',
  'Invoices & proformas': 'Ankara na proforma',
  'Create professional invoices and proforma invoices in seconds.':
      'Tengeneza ankara na proforma za kitaalamu kwa sekunde.',
  'Quotations': 'Nukuu za bei',
  'Prepare clear quotations and convert accepted quotes into invoices.':
      'Andaa nukuu za bei zilizo wazi na zibadilishe kuwa ankara zikikubaliwa.',
  'Verified receipts': 'Risiti zilizothibitishwa',
  'Give customers receipts with QR codes for online verification.':
      'Wape wateja risiti zenye QR code za kuthibitisha mtandaoni.',
  'Document designs': 'Muundo wa nyaraka',
  'Choose from 11 designs, your brand colours, logo and business details.':
      'Chagua kati ya miundo 11, rangi za chapa yako, nembo na taarifa za biashara.',
  'Custom terms': 'Masharti yako',
  'Save multiple terms and conditions and use the right version.':
      'Hifadhi masharti na vigezo mbalimbali na utumie toleo sahihi.',
  'Easy sharing': 'Kushiriki kwa urahisi',
  'Share documents as PDFs or images via WhatsApp, email or print.':
      'Shiriki nyaraka kama PDF au picha kupitia WhatsApp, barua pepe au chapisha.',
  'Job tracking': 'Ufuatiliaji wa kazi',
  'Monitor work from the start to completion and archive finished jobs.':
      'Fuatilia kazi tangu mwanzo hadi mwisho na uhifadhi kazi zilizokamilika.',
  'Business reports': 'Ripoti za biashara',
  'Review sales, categories and client credit in one place.':
      'Angalia mauzo, kategoria na madeni ya wateja mahali pamoja.',
  'Staff & permissions': 'Wafanyakazi na ruhusa',
  'Invite staff and manage access according to their roles.':
      'Alika wafanyakazi na udhibiti ufikiaji kulingana na majukumu yao.',
  'English & Kiswahili': 'Kiingereza na Kiswahili',
  'Use the language that works best for your business.':
      'Tumia lugha inayofaa zaidi biashara yako.',
  'Cloud synchronisation': 'Usawazishaji mtandaoni',
  'Access your business information across supported devices.':
      'Fikia taarifa za biashara yako kwenye vifaa vinavyotumika.',
  'Multiple platforms': 'Majukwaa mbalimbali',
  'Use Android, Windows, iOS and the web with the same account.':
      'Tumia Android, Windows, iOS na wavuti kwa akaunti moja.',
  'Everything in one place': 'Kila kitu mahali pamoja',
  'The essential tools to create documents, manage jobs and organise your business.':
      'Zana muhimu za kutengeneza nyaraka, kusimamia kazi na kupanga biashara yako.',
  'Invoices': 'Ankara',
  'Business dashboard': 'Dashibodi ya biashara',
  'Designed for everyday work': 'Imeundwa kwa kazi za kila siku',
  'A clean interface to help you focus on your business.':
      'Muonekano safi unaokusaidia kuangazia biashara yako.',
  'Choose your platform': 'Chagua jukwaa lako',
  'Download the app or open MJASI POS on the web.':
      'Pakua app au fungua MJASI POS kwenye wavuti.',
  'Set up your business': 'Weka taarifa za biashara',
  'Add your business details, logo and preferred document design.':
      'Ongeza taarifa za biashara, nembo na muundo wa nyaraka unaopenda.',
  'Create and share': 'Tengeneza na shiriki',
  'Prepare a document and send it directly to your customer.':
      'Andaa nyaraka kisha mtumie mteja wako moja kwa moja.',
  'Get started in three steps': 'Anza kwa hatua tatu',
  'Simple setup. Practical tools. A more organised business.':
      'Usanidi rahisi. Zana za vitendo. Biashara iliyopangwa zaidi.',
  'Get MJASI POS': 'Pata MJASI POS',
  'Choose the platform that fits your workflow.':
      'Chagua jukwaa linalofaa kazi zako.',
  'Get it on Google Play': 'Pakua kupitia Google Play',
  'Download on the App Store': 'Pakua kupitia App Store',
  'Direct APK download': 'Pakua APK moja kwa moja',
  'Desktop app for Windows': 'App ya kompyuta ya Windows',
  'Open in your browser': 'Fungua kwenye kivinjari',
  'Coming soon': 'Inakuja hivi karibuni',
  'Simple pricing': 'Bei rahisi',
  'One plan with everything included. No hidden fees.':
      'Mpango mmoja wenye kila kitu. Hakuna gharama zilizofichwa.',
  'per year': 'kwa mwaka',
  'per month': 'kwa mwezi',
  'Unlimited invoices, quotations & receipts':
      'Ankara, nukuu na risiti bila kikomo',
  'Staff accounts with permissions': 'Akaunti za wafanyakazi zenye ruhusa',
  'Income, expense & debt tracking':
      'Ufuatiliaji wa mapato, matumizi na madeni',
  'Cloud sync across all your devices':
      'Data inasawazishwa kwenye vifaa vyako vyote',
  '11 professional document designs': 'Miundo 11 ya kitaalamu ya nyaraka',
  'Get started': 'Anza sasa',
  'Privacy policy': 'Sera ya faragha',
  'Delete account': 'Futa akaunti',
};

String _t(String en) => _sw ? (_swahili[en] ?? en) : en;

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage>
    with TickerProviderStateMixin {
  late final AnimationController _background = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  final _featuresKey = GlobalKey();
  final _screensKey = GlobalKey();
  final _downloadKey = GlobalKey();
  final _pricingKey = GlobalKey();

  DownloadCenter? _center;
  SubscriptionPlanSettings? _plan;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _sw = _initialSwahili();
    _load();
    DownloadCenterService.trackVisit();
  }

  /// Saved choice wins; otherwise Swahili for Tanzania/Swahili browsers.
  bool _initialSwahili() {
    try {
      final saved = GetStorage().read<String>('downloads_lang');
      if (saved != null) return saved == 'sw';
    } catch (_) {}
    return WidgetsBinding.instance.platformDispatcher.locales.any(
      (l) => l.languageCode == 'sw' || l.countryCode == 'TZ',
    );
  }

  void _setLanguage(bool swahili) {
    setState(() => _sw = swahili);
    try {
      GetStorage().write('downloads_lang', swahili ? 'sw' : 'en');
    } catch (_) {}
  }

  @override
  void dispose() {
    _background.dispose();
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() => _failed = false);
    }

    try {
      final center = await DownloadCenterService.load();
      if (!mounted) return;

      setState(() => _center = center);
      _entrance.forward(from: 0);
      _loadPlan();
    } catch (error, stackTrace) {
      debugPrint('Download center error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _loadPlan() async {
    try {
      final plan = await SuperAdminSubscriptionService.loadPlanSettings();
      if (mounted) setState(() => _plan = plan);
    } catch (error) {
      debugPrint('Pricing unavailable: $error');
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);

    if (uri == null ||
        !uri.hasScheme ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('Could not open the link. Please try again.')),
        ),
      );
    }
  }

  void _download(DownloadItemDef def, DownloadCenter center) {
    final item = center.item(def.key);
    if (def.key == 'web' || item.isAvailable) {
      DownloadCenterService.trackDownload(def.key);
    }

    if (def.key == 'web') {
      final uri = Uri.tryParse(item.url);
      final usable =
          item.isAvailable &&
          uri != null &&
          uri.hasScheme &&
          !uri.path.contains('downloads');

      _open(usable ? item.url : '${Uri.base.origin}/');
      return;
    }

    if (item.isAvailable) {
      _open(item.url);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _sw
              ? '${def.title} haipatikani bado. Tafadhali rudi baadaye.'
              : '${def.title} is not available yet. Please check back soon.',
        ),
      ),
    );
  }

  void _scrollTo(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;

    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeInOutCubic,
      alignment: 0.08,
    );
  }

  Animation<double> _stagger(double start, double end) {
    return CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  Widget _reveal(double start, double end, Widget child) {
    final animation = _stagger(start, end);

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.07),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navyDeep,
      body: Stack(
        children: [
          Positioned.fill(child: _animatedBackground()),
          Positioned.fill(
            child: _center == null ? _loadingView() : _page(_center!),
          ),
        ],
      ),
    );
  }

  Widget _loadingView() {
    return Center(
      child: _failed
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, color: _muted, size: 48),
                const SizedBox(height: 16),
                Text(
                  _t('Could not load the page.'),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 18),
                FilledButton(onPressed: _load, child: Text(_t('Try again'))),
              ],
            )
          : const CircularProgressIndicator(color: _mint),
    );
  }

  Widget _animatedBackground() {
    return AnimatedBuilder(
      animation: _background,
      builder: (context, _) {
        final t = _background.value * 2 * math.pi;

        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_navyDeep, _navy, Color(0xFF102B3D)],
            ),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                top: -150 + math.sin(t) * 24,
                right: -110,
                child: _glow(400, _mint.withValues(alpha: 0.12)),
              ),
              Positioned(
                bottom: -200,
                left: -100 + math.cos(t) * 25,
                child: _glow(460, _violet.withValues(alpha: 0.09)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _glow(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, Colors.transparent]),
      ),
    );
  }

  Widget _page(DownloadCenter center) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wide = width >= 900;
        final padding = width >= 1200
            ? 64.0
            : width >= 700
            ? 36.0
            : 20.0;

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              children: [
                _section(padding, _navBar(wide)),
                _section(padding, _hero(center, wide), top: wide ? 40 : 24),
                _section(
                  padding,
                  KeyedSubtree(
                    key: _downloadKey,
                    child: _downloads(center, width),
                  ),
                  top: 36,
                ),
                _section(
                  padding,
                  KeyedSubtree(key: _pricingKey, child: _pricing(wide)),
                  top: 100,
                ),
                _section(
                  padding,
                  KeyedSubtree(key: _featuresKey, child: _features(width)),
                  top: 100,
                ),
                _section(
                  padding,
                  KeyedSubtree(key: _screensKey, child: _screens(width)),
                  top: 100,
                ),
                _section(padding, _steps(wide), top: 100),
                const SizedBox(height: 100),
                _footer(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _section(double padding, Widget child, {double top = 0}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, top, padding, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: child,
        ),
      ),
    );
  }

  Widget _navBar(bool wide) {
    Widget link(String label, GlobalKey key) {
      return TextButton(
        onPressed: () => _scrollTo(key),
        style: TextButton.styleFrom(
          foregroundColor: _muted,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(_t(label)),
      );
    }

    Widget langToggle() {
      Widget chip(String text, bool selected, VoidCallback onTap) {
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? _mint : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              text,
              style: TextStyle(
                color: selected ? _navyDeep : _muted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        );
      }

      return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            chip('EN', !_sw, () => _setLanguage(false)),
            chip('SW', _sw, () => _setLanguage(true)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Image.asset(
              'assets/mjas.png',
              width: 42,
              height: 42,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MJASI POS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'BUSINESS MANAGEMENT',
                style: TextStyle(
                  color: _muted,
                  fontSize: 9,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (wide) ...[
            link('Features', _featuresKey),
            link('Pricing', _pricingKey),
            link('Screenshots', _screensKey),
            link('Downloads', _downloadKey),
            const SizedBox(width: 16),
          ],
          langToggle(),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: () => Get.toNamed('/login'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 18 : 12,
                vertical: 15,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(_t('Open app')),
          ),
        ],
      ),
    );
  }

  Widget _hero(DownloadCenter center, bool wide) {
    final alignment = wide
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center;
    final textAlignment = wide ? TextAlign.left : TextAlign.center;

    final text = Column(
      crossAxisAlignment: alignment,
      children: [
        _reveal(
          0,
          0.35,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: _mint.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: _mint.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome, color: _mint, size: 15),
                const SizedBox(width: 8),
                Text(
                  _t('SMART TOOLS FOR YOUR BUSINESS'),
                  style: const TextStyle(
                    color: _mint,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 26),
        _reveal(
          0.08,
          0.48,
          Text(
            center.title,
            textAlign: textAlignment,
            style: TextStyle(
              color: Colors.white,
              fontSize: wide ? 58 : 38,
              height: 1.08,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.7,
            ),
          ),
        ),
        const SizedBox(height: 20),
        _reveal(
          0.16,
          0.56,
          Text(
            center.subtitle,
            textAlign: textAlignment,
            style: const TextStyle(color: _muted, fontSize: 16, height: 1.8),
          ),
        ),
        const SizedBox(height: 30),
        _reveal(
          0.24,
          0.65,
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: wide ? WrapAlignment.start : WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () => _scrollTo(_downloadKey),
                icon: const Icon(Icons.download_rounded, size: 20),
                label: Text(
                  _t('DOWNLOAD MJASI POS'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _mint,
                  foregroundColor: _navyDeep,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 23,
                    vertical: 19,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _scrollTo(_screensKey),
                icon: const Icon(Icons.visibility_outlined, size: 19),
                label: Text(_t('Explore features')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 19,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        _reveal(
          0.3,
          0.75,
          Wrap(
            spacing: 18,
            runSpacing: 10,
            alignment: wide ? WrapAlignment.start : WrapAlignment.center,
            children: [
              _trustLabel(
                Icons.receipt_long_rounded,
                _t('Professional documents'),
              ),
              _trustLabel(Icons.cloud_done_rounded, _t('Cloud sync')),
              _trustLabel(Icons.devices_rounded, _t('Multi-platform')),
            ],
          ),
        ),
      ],
    );

    final preview = _reveal(
      0.16,
      0.88,
      AnimatedBuilder(
        animation: _background,
        builder: (context, _) {
          final bob = math.sin(_background.value * 2 * math.pi) * 5;

          return SizedBox(
            height: wide ? 500 : 440,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Transform.translate(
                  offset: Offset(-65, 15 + bob),
                  child: Transform.rotate(
                    angle: -0.09,
                    child: _PhoneFrame(
                      width: wide ? 178 : 160,
                      child: const _ReceiptScreen(),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(65, 15 - bob),
                  child: Transform.rotate(
                    angle: 0.09,
                    child: _PhoneFrame(
                      width: wide ? 178 : 160,
                      child: const _DashboardScreen(),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(0, -10),
                  child: _PhoneFrame(
                    width: wide ? 198 : 180,
                    child: const _InvoiceScreen(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (!wide) {
      return Column(children: [text, const SizedBox(height: 34), preview]);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 11, child: text),
        const SizedBox(width: 24),
        Expanded(flex: 10, child: preview),
      ],
    );
  }

  Widget _trustLabel(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _mint, size: 16),
        const SizedBox(width: 7),
        Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
      ],
    );
  }

  Widget _heading(String title, String subtitle) {
    return Column(
      children: [
        Text(
          _t(title),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            height: 1.2,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Text(
            _t(subtitle),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 15, height: 1.8),
          ),
        ),
        const SizedBox(height: 36),
      ],
    );
  }

  Widget _features(double width) {
    const items = [
      (
        Icons.receipt_long_rounded,
        'Invoices & proformas',
        'Create professional invoices and proforma invoices in seconds.',
      ),
      (
        Icons.request_quote_rounded,
        'Quotations',
        'Prepare clear quotations and convert accepted quotes into invoices.',
      ),
      (
        Icons.qr_code_2_rounded,
        'Verified receipts',
        'Give customers receipts with QR codes for online verification.',
      ),
      (
        Icons.palette_outlined,
        'Document designs',
        'Choose from 11 designs, your brand colours, logo and business details.',
      ),
      (
        Icons.edit_note_rounded,
        'Custom terms',
        'Save multiple terms and conditions and use the right version.',
      ),
      (
        Icons.ios_share_rounded,
        'Easy sharing',
        'Share documents as PDFs or images via WhatsApp, email or print.',
      ),
      (
        Icons.work_history_outlined,
        'Job tracking',
        'Monitor work from the start to completion and archive finished jobs.',
      ),
      (
        Icons.insights_rounded,
        'Business reports',
        'Review sales, categories and client credit in one place.',
      ),
      (
        Icons.groups_rounded,
        'Staff & permissions',
        'Invite staff and manage access according to their roles.',
      ),
      (
        Icons.translate_rounded,
        'English & Kiswahili',
        'Use the language that works best for your business.',
      ),
      (
        Icons.cloud_done_outlined,
        'Cloud synchronisation',
        'Access your business information across supported devices.',
      ),
      (
        Icons.devices_rounded,
        'Multiple platforms',
        'Use Android, Windows, iOS and the web with the same account.',
      ),
    ];

    final columns = width >= 1000
        ? 4
        : width >= 640
        ? 2
        : 1;
    const gap = 16.0;

    return Column(
      children: [
        _heading(
          'Everything in one place',
          'The essential tools to create documents, manage jobs and organise your business.',
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final item in items)
                  SizedBox(
                    width: itemWidth,
                    child: _GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: _mint.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Icon(item.$1, color: _mint, size: 23),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              _t(item.$2),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              _t(item.$3),
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 13,
                                height: 1.7,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _screens(double width) {
    const screens = [
      ('Invoices', _InvoiceScreen()),
      ('Verified receipts', _ReceiptScreen()),
      ('Business dashboard', _DashboardScreen()),
    ];

    return Column(
      children: [
        _heading(
          'Designed for everyday work',
          'A clean interface to help you focus on your business.',
        ),
        Wrap(
          spacing: 30,
          runSpacing: 30,
          alignment: WrapAlignment.center,
          children: [
            for (final screen in screens)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PhoneFrame(width: width < 480 ? 215 : 235, child: screen.$2),
                  const SizedBox(height: 16),
                  Text(
                    _t(screen.$1),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _steps(bool wide) {
    const steps = [
      (
        '01',
        Icons.download_rounded,
        'Choose your platform',
        'Download the app or open MJASI POS on the web.',
      ),
      (
        '02',
        Icons.tune_rounded,
        'Set up your business',
        'Add your business details, logo and preferred document design.',
      ),
      (
        '03',
        Icons.send_rounded,
        'Create and share',
        'Prepare a document and send it directly to your customer.',
      ),
    ];

    return Column(
      children: [
        _heading(
          'Get started in three steps',
          'Simple setup. Practical tools. A more organised business.',
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 760 ? 3 : 1;

            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final step in steps)
                  SizedBox(
                    width: columns == 3
                        ? (constraints.maxWidth - 32) / 3
                        : constraints.maxWidth,
                    child: _GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(23),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: _mint.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(step.$2, color: _mint),
                                ),
                                const Spacer(),
                                Text(
                                  step.$1,
                                  style: const TextStyle(
                                    color: Colors.white24,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),
                            Text(
                              _t(step.$3),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              _t(step.$4),
                              style: const TextStyle(
                                color: _muted,
                                height: 1.7,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _downloads(DownloadCenter center, double width) {
    const brand = {
      'playstore': Color(0xFF01875F),
      'appstore': Color(0xFF111827),
      'apk': Color(0xFF218C54),
      'windows': Color(0xFF0078D4),
      'web': Color(0xFF5B3FD0),
    };

    final columns = width >= 1000
        ? 3
        : width >= 640
        ? 2
        : 1;
    const gap = 16.0;

    return Column(
      children: [
        _heading(
          'Get MJASI POS',
          'Choose the platform that fits your workflow.',
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final def in downloadItemDefs)
                  SizedBox(
                    width: itemWidth,
                    child: _DownloadButton(
                      def: def,
                      item: center.item(def.key),
                      color: brand[def.key] ?? _violet,
                      onTap: () => _download(def, center),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _pricing(bool wide) {
    final plan = _plan;
    if (plan == null) return const SizedBox.shrink();

    final price = NumberFormat.decimalPattern('en_US').format(plan.amount);
    final days = plan.durationDays;
    final period = days == 365
        ? _t('per year')
        : days == 30
        ? _t('per month')
        : days % 365 == 0
        ? (_sw ? 'kwa miaka ${days ~/ 365}' : 'per ${days ~/ 365} years')
        : days % 30 == 0
        ? (_sw ? 'kwa miezi ${days ~/ 30}' : 'per ${days ~/ 30} months')
        : (_sw ? 'kwa siku $days' : 'per $days days');
    const perks = [
      'Unlimited invoices, quotations & receipts',
      'Staff accounts with permissions',
      'Income, expense & debt tracking',
      'Cloud sync across all your devices',
      '11 professional document designs',
    ];

    return Column(
      children: [
        _heading(
          'Simple pricing',
          'One plan with everything included. No hidden fees.',
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(wide ? 36 : 26),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _mint.withValues(alpha: 0.45)),
              boxShadow: [
                BoxShadow(
                  color: _mint.withValues(alpha: 0.12),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text(
                  'MJASI POS PRO',
                  style: TextStyle(
                    color: _mint,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 18),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      const Text(
                        'Tsh ',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        price,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: wide ? 76 : 60,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  period,
                  style: const TextStyle(color: _muted, fontSize: 16),
                ),
                const SizedBox(height: 24),
                Divider(color: Colors.white.withValues(alpha: 0.1)),
                const SizedBox(height: 14),
                for (final perk in perks)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: _mint,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _t(perk),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _scrollTo(_downloadKey),
                    icon: const Icon(Icons.download_rounded),
                    label: Text(
                      _t('Get started'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _mint,
                      foregroundColor: _navyDeep,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _footer() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 100),
      decoration: BoxDecoration(
        color: _navyDeep.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 24,
              runSpacing: 16,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MJASI POS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                      ),
                    ),
                    SizedBox(height: 7),
                    Text(
                      '© ${'2026'} MJASI POS · Lidox',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    TextButton(
                      onPressed: () => _open('${Uri.base.origin}/privacy.html'),
                      style: TextButton.styleFrom(foregroundColor: _muted),
                      child: Text(_t('Privacy policy')),
                    ),
                    TextButton(
                      onPressed: () =>
                          _open('${Uri.base.origin}/delete-account.html'),
                      style: TextButton.styleFrom(foregroundColor: _muted),
                      child: Text(_t('Delete account')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _DownloadButton extends StatefulWidget {
  const _DownloadButton({
    required this.def,
    required this.item,
    required this.color,
    required this.onTap,
  });

  final DownloadItemDef def;
  final DownloadItem item;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<_DownloadButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final available = widget.item.isAvailable || widget.def.key == 'web';

    final label = !available
        ? _t('Coming soon')
        : widget.item.version.isEmpty
        ? _t(widget.def.subtitle)
        : '${_t(widget.def.subtitle)} · v${widget.item.version}';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        transform: Matrix4.translationValues(
          0,
          available && _hover ? -3 : 0,
          0,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF132840),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: available && _hover
                ? widget.color.withValues(alpha: 0.8)
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(21),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: available
                          ? widget.color.withValues(alpha: 0.17)
                          : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      widget.def.icon,
                      color: available ? widget.color : _muted,
                      size: 27,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.def.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          label,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    available
                        ? Icons.arrow_forward_rounded
                        : Icons.schedule_rounded,
                    color: available ? _mint : _muted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: width * 2,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: const Color(0xFF080D16),
        borderRadius: BorderRadius.circular(31),
        border: Border.all(color: Colors.white24, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 28,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: Container(
          color: const Color(0xFFF5F7FA),
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(width: 220, height: 440, child: child),
          ),
        ),
      ),
    );
  }
}

Widget _appBar(String title) {
  return Container(
    width: double.infinity,
    height: 70,
    padding: const EdgeInsets.fromLTRB(15, 24, 15, 0),
    color: _teal,
    alignment: Alignment.centerLeft,
    child: Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        decoration: TextDecoration.none,
      ),
    ),
  );
}

Widget _line(double width, {Color? color, double height = 8}) {
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color ?? Colors.black12,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}

class _InvoiceScreen extends StatelessWidget {
  const _InvoiceScreen();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _appBar('Create invoice'),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      'assets/mjas.png',
                      width: 34,
                      height: 34,
                    ),
                  ),
                  _line(60, color: _teal, height: 11),
                ],
              ),
              const SizedBox(height: 16),
              _line(110),
              const SizedBox(height: 7),
              _line(80),
              const SizedBox(height: 16),
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [_line(85), _line(43)],
                  ),
                ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _line(55, height: 10),
                  _line(72, color: _violet, height: 12),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                height: 35,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _teal,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Text(
                  'Share invoice',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReceiptScreen extends StatelessWidget {
  const _ReceiptScreen();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _appBar('Payment receipt'),
        Padding(
          padding: const EdgeInsets.all(15),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 8),
              ],
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.verified_rounded,
                  color: Color(0xFF16A34A),
                  size: 36,
                ),
                const SizedBox(height: 10),
                _line(95, height: 10),
                const SizedBox(height: 15),
                for (var i = 0; i < 4; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [_line(70), _line(38)],
                    ),
                  ),
                const Divider(),
                const Icon(Icons.qr_code_2_rounded, size: 110, color: _navy),
                const SizedBox(height: 8),
                _line(100),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DashboardScreen extends StatelessWidget {
  const _DashboardScreen();

  @override
  Widget build(BuildContext context) {
    Widget stat(Color color, IconData icon) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 9),
              _line(40, color: color.withValues(alpha: 0.5), height: 9),
            ],
          ),
        ),
      );
    }

    const bars = [0.4, 0.7, 0.5, 0.9, 0.6, 0.8];

    return Column(
      children: [
        _appBar('Dashboard'),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                children: [
                  stat(_teal, Icons.receipt_long_rounded),
                  stat(_violet, Icons.request_quote_rounded),
                ],
              ),
              Row(
                children: [
                  stat(const Color(0xFFF59E0B), Icons.work_rounded),
                  stat(const Color(0xFF16A34A), Icons.payments_rounded),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                height: 130,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final bar in bars)
                      Container(
                        width: 18,
                        height: 100 * bar,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          gradient: const LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [_teal, _mint],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
