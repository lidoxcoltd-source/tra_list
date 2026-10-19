import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import 'download_center_service.dart';

const _navy = Color(0xFF0B1F3A);
const _teal = Color(0xFF0E5962);
const _violet = Color(0xFF5B3FD0);
const _mint = Color(0xFF29D3C2);

/// Public landing page (no sign-in) where visitors learn about and download
/// MJASI POS.
class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage>
    with TickerProviderStateMixin {
  late final AnimationController _background = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  )..repeat();
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  final _featuresKey = GlobalKey();
  final _screensKey = GlobalKey();
  final _downloadKey = GlobalKey();
  DownloadCenter? _center;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _background.dispose();
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final center = await DownloadCenterService.load();
      if (!mounted) return;
      setState(() => _center = center);
      _entrance.forward(from: 0);
    } catch (error, stackTrace) {
      debugPrint('Could not load download center: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open the link.')));
    }
  }

  void _download(DownloadItemDef def, DownloadCenter center) {
    final item = center.item(def.key);
    if (def.key == 'web') {
      // The web app lives at the site root, never on this landing page.
      final uri = Uri.tryParse(item.url);
      final usable =
          item.isAvailable && uri != null && !uri.path.contains('downloads');
      _open(usable ? item.url : '${Uri.base.origin}/');
    } else if (item.isAvailable) {
      _open(item.url);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${def.title} is not available yet. Please check back soon.',
          ),
        ),
      );
    }
  }

  void _scrollTo(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOutCubic,
    );
  }

  Animation<double> _stagger(double start, double end) => CurvedAnimation(
    parent: _entrance,
    curve: Interval(start, math.min(end, 1.0), curve: Curves.easeOutCubic),
  );

  Widget _reveal(double start, double end, Widget child) {
    final animation = _stagger(start, end);
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(child: _animatedBackground()),
            Positioned.fill(
              child: _center == null
                  ? Center(
                      child: _failed
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Could not load the page.',
                                  style: TextStyle(color: Colors.white),
                                ),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: _load,
                                  child: const Text('Try again'),
                                ),
                              ],
                            )
                          : const CircularProgressIndicator(
                              color: Colors.white,
                            ),
                    )
                  : _page(_center!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _animatedBackground() {
    return AnimatedBuilder(
      animation: _background,
      builder: (context, _) {
        final t = _background.value * 2 * math.pi;
        final size = MediaQuery.sizeOf(context);
        const colors = [
          Color(0xFF29D3C2),
          Color(0xFF8B5CF6),
          Color(0xFF38BDF8),
          Color(0xFFF472B6),
          Color(0xFF34D399),
          Color(0xFFFBBF24),
        ];
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(math.cos(t), math.sin(t)),
              end: Alignment(-math.cos(t), -math.sin(t)),
              colors: const [_navy, _teal, _violet, _navy],
            ),
          ),
          child: Stack(
            children: [
              for (var i = 0; i < 6; i++)
                Positioned(
                  left:
                      (math.sin(t + i * 1.3) + 1) /
                      2 *
                      math.max(0, size.width - 120 - i * 28),
                  top:
                      (math.cos(t * (i.isEven ? 1 : -1) + i) + 1) /
                      2 *
                      math.max(0, size.height - 120 - i * 28),
                  child: Container(
                    width: 120.0 + i * 28,
                    height: 120.0 + i * 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          colors[i].withValues(alpha: 0.3),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _page(DownloadCenter center) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final wide = w >= 900;
        final pad = w >= 1200 ? 64.0 : (wide ? 40.0 : 20.0);
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              children: [
                _section(pad, _navBar(wide)),
                _section(pad, _hero(center, wide), top: wide ? 40 : 16),
                _section(
                  pad,
                  KeyedSubtree(key: _featuresKey, child: _features(w)),
                  top: 72,
                ),
                _section(
                  pad,
                  KeyedSubtree(key: _screensKey, child: _screens(w)),
                  top: 72,
                ),
                _section(pad, _steps(wide), top: 72),
                _section(
                  pad,
                  KeyedSubtree(key: _downloadKey, child: _downloads(center, w)),
                  top: 72,
                ),
                _footer(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _section(double pad, Widget child, {double top = 0}) => Padding(
    padding: EdgeInsets.fromLTRB(pad, top, pad, 0),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: child,
      ),
    ),
  );

  Widget _navBar(bool wide) {
    Widget link(String label, GlobalKey key) => TextButton(
      onPressed: () => _scrollTo(key),
      child: Text(label, style: const TextStyle(color: Colors.white)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset('assets/mjas.png', width: 38, height: 38),
          ),
          const SizedBox(width: 10),
          const Text(
            'MJASI POS',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          if (wide) ...[
            link('Features', _featuresKey),
            link('Screens', _screensKey),
            link('Download', _downloadKey),
            const SizedBox(width: 8),
          ],
          OutlinedButton(
            onPressed: () => Get.toNamed('/login'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
            ),
            child: const Text('Open app'),
          ),
        ],
      ),
    );
  }

  Widget _hero(DownloadCenter center, bool wide) {
    final align = wide ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final textAlign = wide ? TextAlign.start : TextAlign.center;
    final text = Column(
      crossAxisAlignment: align,
      children: [
        _reveal(
          0,
          0.4,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white24),
            ),
            child: const Text(
              'Invoices · Quotations · Receipts · Jobs',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _reveal(
          0.1,
          0.5,
          Text(
            center.title,
            textAlign: textAlign,
            style: TextStyle(
              color: Colors.white,
              fontSize: wide ? 56 : 38,
              fontWeight: FontWeight.w800,
              height: 1.08,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _reveal(
          0.2,
          0.6,
          Text(
            center.subtitle,
            textAlign: textAlign,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: wide ? 18 : 16,
              height: 1.55,
            ),
          ),
        ),
        const SizedBox(height: 28),
        _reveal(
          0.3,
          0.7,
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: wide ? WrapAlignment.start : WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () => _scrollTo(_downloadKey),
                style: FilledButton.styleFrom(
                  backgroundColor: _mint,
                  foregroundColor: _navy,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 18,
                  ),
                ),
                icon: const Icon(Icons.download_rounded),
                label: const Text(
                  'Download now',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _scrollTo(_screensKey),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 18,
                  ),
                ),
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: const Text('See screens'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _reveal(
          0.4,
          0.8,
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: wide ? WrapAlignment.start : WrapAlignment.center,
            children: [
              for (final d in downloadItemDefs)
                ActionChip(
                  onPressed: () => _download(d, center),
                  backgroundColor: Colors.white.withValues(alpha: 0.16),
                  side: const BorderSide(color: Colors.white30),
                  avatar: Icon(d.icon, color: Colors.white, size: 20),
                  label: Text(
                    d.title,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    final phones = _reveal(
      0.2,
      0.9,
      AnimatedBuilder(
        animation: _background,
        builder: (context, _) {
          final bob = math.sin(_background.value * 2 * math.pi * 3) * 8;
          return SizedBox(
            height: 460,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Transform.translate(
                  offset: Offset(-95, 30 - bob),
                  child: Transform.rotate(
                    angle: -0.1,
                    child: const _PhoneFrame(
                      width: 190,
                      child: _ReceiptScreen(),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(95, 30 + bob),
                  child: Transform.rotate(
                    angle: 0.1,
                    child: const _PhoneFrame(
                      width: 190,
                      child: _DashboardScreen(),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(0, -bob),
                  child: const _PhoneFrame(width: 210, child: _InvoiceScreen()),
                ),
              ],
            ),
          );
        },
      ),
    );

    return wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 5, child: text),
              const SizedBox(width: 32),
              Expanded(flex: 5, child: phones),
            ],
          )
        : Column(children: [text, const SizedBox(height: 40), phones]);
  }

  Widget _heading(String title, String subtitle) => Column(
    children: [
      Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 32,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        subtitle,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.8),
          fontSize: 16,
        ),
      ),
      const SizedBox(height: 32),
    ],
  );

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
        'Send clear quotations and turn them into invoices when accepted.',
      ),
      (
        Icons.qr_code_2_rounded,
        'Receipts with QR',
        'Every receipt carries a QR code so customers can verify it online.',
      ),
      (
        Icons.palette_rounded,
        '11 document designs',
        'Pick a layout and your brand colour. Add your logo and details.',
      ),
      (
        Icons.edit_note_rounded,
        'Editable terms',
        'Save several versions of terms and conditions and choose which to use.',
      ),
      (
        Icons.ios_share_rounded,
        'Share anywhere',
        'Share as PDF or image over WhatsApp, email or print.',
      ),
      (
        Icons.work_history_rounded,
        'Jobs tracking',
        'Track jobs from start to completion and archive finished work.',
      ),
      (
        Icons.insights_rounded,
        'Reports & analytics',
        'See sales, categories and client credit at a glance.',
      ),
      (
        Icons.groups_rounded,
        'Staff & roles',
        'Invite staff and control exactly what each person can access.',
      ),
      (
        Icons.translate_rounded,
        'English & Kiswahili',
        'Use the app in the language your team is comfortable with.',
      ),
      (
        Icons.cloud_done_rounded,
        'Cloud sync',
        'Your data is safe in the cloud and available on every device.',
      ),
      (
        Icons.devices_rounded,
        'Every platform',
        'Android, Windows, iOS and web — same account everywhere.',
      ),
    ];
    final columns = width >= 1000 ? 4 : (width >= 640 ? 2 : 1);
    const gap = 16.0;
    return Column(
      children: [
        _heading(
          'Everything your business needs',
          'One app to quote, invoice, get paid and stay organised.',
        ),
        LayoutBuilder(
          builder: (context, c) {
            final itemWidth = (c.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final item in items)
                  SizedBox(
                    width: itemWidth,
                    child: _GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: const LinearGradient(
                                  colors: [_mint, Color(0xFF8B5CF6)],
                                ),
                              ),
                              child: Icon(item.$1, color: Colors.white),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              item.$2,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.$3,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                height: 1.45,
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
      ('Create invoices', _InvoiceScreen()),
      ('Verified receipts', _ReceiptScreen()),
      ('Business dashboard', _DashboardScreen()),
    ];
    return Column(
      children: [
        _heading(
          'See it in action',
          'A clean, fast interface on every screen.',
        ),
        Wrap(
          spacing: 28,
          runSpacing: 28,
          alignment: WrapAlignment.center,
          children: [
            for (final s in screens)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PhoneFrame(width: width < 480 ? 230 : 250, child: s.$2),
                  const SizedBox(height: 12),
                  Text(
                    s.$1,
                    style: const TextStyle(
                      color: Colors.white,
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
      ('1', 'Download', 'Install on your phone, computer or open the web app.'),
      ('2', 'Set up', 'Add your business name, logo and preferred design.'),
      ('3', 'Create & share', 'Make a document and send it to your customer.'),
    ];
    final cards = [
      for (final s in steps)
        _GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: _mint,
                  child: Text(
                    s.$1,
                    style: const TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.$2,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.$3,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
    return Column(
      children: [
        _heading('Start in 3 steps', 'No complicated setup.'),
        wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 16),
                    Expanded(child: cards[i]),
                  ],
                ],
              )
            : Column(
                children: [
                  for (final c in cards)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: c,
                    ),
                ],
              ),
      ],
    );
  }

  Widget _downloads(DownloadCenter center, double width) {
    const brand = {
      'playstore': Color(0xFF01875F),
      'appstore': Color(0xFF111111),
      'apk': Color(0xFF1E8E4E),
      'windows': Color(0xFF0078D4),
      'web': _violet,
    };
    final columns = width >= 1000 ? 3 : (width >= 640 ? 2 : 1);
    const gap = 16.0;
    return Column(
      children: [
        _heading(
          'Download MJASI POS',
          'Choose your platform. Your account works on all of them.',
        ),
        LayoutBuilder(
          builder: (context, c) {
            final itemWidth = (c.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              alignment: WrapAlignment.center,
              children: [
                for (final d in downloadItemDefs)
                  SizedBox(
                    width: itemWidth,
                    child: _DownloadButton(
                      def: d,
                      item: center.item(d.key),
                      color: brand[d.key] ?? _violet,
                      onTap: () => _download(d, center),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _footer() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 72, 20, 32),
    child: Column(
      children: [
        Divider(color: Colors.white.withValues(alpha: 0.2)),
        const SizedBox(height: 16),
        Text(
          '© ${DateTime.now().year} MJASI POS · Lidox',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          children: [
            TextButton(
              onPressed: () => _open('${Uri.base.origin}/privacy.html'),
              child: const Text(
                'Privacy',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            TextButton(
              onPressed: () => _open('${Uri.base.origin}/delete-account.html'),
              child: const Text(
                'Delete account',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
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
    const fg = Colors.white;
    final label = available
        ? (widget.item.version.isEmpty
              ? widget.def.subtitle
              : '${widget.def.subtitle} · v${widget.item.version}')
        : 'Coming soon';
    return MouseRegion(
      cursor: available ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: available && _hover ? 1.04 : 1,
        duration: const Duration(milliseconds: 180),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: available
                  ? [widget.color, Color.lerp(widget.color, _navy, 0.35)!]
                  : [const Color(0xFF3B4A63), const Color(0xFF2A3650)],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: available && _hover ? 0.45 : 0.25,
                ),
                blurRadius: available && _hover ? 22 : 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                child: Row(
                  children: [
                    Icon(widget.def.icon, color: fg, size: 38),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.def.title,
                            style: TextStyle(
                              color: fg,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            label,
                            style: TextStyle(
                              color: fg.withValues(alpha: 0.85),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      available
                          ? Icons.download_rounded
                          : Icons.hourglass_top_rounded,
                      color: fg,
                    ),
                  ],
                ),
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
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          color: const Color(0xFFF5F7F8),
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(width: 220, height: 440, child: child),
          ),
        ),
      ),
    );
  }
}

Widget _appBar(String title) => Container(
  width: double.infinity,
  height: 70,
  padding: const EdgeInsets.fromLTRB(14, 24, 14, 0),
  color: _teal,
  alignment: Alignment.centerLeft,
  child: Text(
    title,
    style: const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w700,
      fontSize: 15,
      decoration: TextDecoration.none,
    ),
  ),
);

Widget _line(double w, {Color? color, double h = 8}) => Container(
  width: w,
  height: h,
  decoration: BoxDecoration(
    color: color ?? Colors.black12,
    borderRadius: BorderRadius.circular(4),
  ),
);

class _InvoiceScreen extends StatelessWidget {
  const _InvoiceScreen();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _appBar('Invoice'),
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
                  _line(60, color: _teal, h: 12),
                ],
              ),
              const SizedBox(height: 14),
              _line(110),
              const SizedBox(height: 6),
              _line(80),
              const SizedBox(height: 16),
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [_line(90), _line(40)],
                  ),
                ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _line(50, h: 10),
                  _line(70, color: _violet, h: 12),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _teal,
                  borderRadius: BorderRadius.circular(10),
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
        _appBar('Receipt'),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
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
                const SizedBox(height: 8),
                _line(90, h: 10),
                const SizedBox(height: 14),
                for (var i = 0; i < 4; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [_line(70), _line(36)],
                    ),
                  ),
                const Divider(),
                const Icon(Icons.qr_code_2_rounded, size: 110, color: _navy),
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
    Widget stat(Color c, IconData i) => Expanded(
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(i, color: c, size: 20),
            const SizedBox(height: 8),
            _line(40, color: c.withValues(alpha: 0.5), h: 10),
          ],
        ),
      ),
    );
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
                    for (final b in bars)
                      Container(
                        width: 18,
                        height: 100 * b,
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
