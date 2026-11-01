import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'legal_service.dart';

const _brand = Color(0xFF0E5962);
const _ink = Color(0xFF19313A);
const _muted = Color(0xFF6B7C85);
const _bg = Color(0xFFF3F6F7);

/// Renders the lightweight format admins edit:
/// `# Section`, `## Sub-section`, `- bullet`, `---` divider, `**bold**`.
class LegalBody extends StatelessWidget {
  const LegalBody(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var number = 0;
    for (final raw in text.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 6));
      } else if (line.startsWith('## ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              line.substring(3),
              style: const TextStyle(
                color: _ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      } else if (line.startsWith('# ')) {
        number++;
        children.add(_sectionTitle(number, line.substring(2)));
      } else if (line.trim() == '---') {
        children.add(
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
        );
      } else if (line.startsWith('- ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 8, right: 10),
                  child: CircleAvatar(radius: 2.5, backgroundColor: _brand),
                ),
                Expanded(child: _rich(line.substring(2))),
              ],
            ),
          ),
        );
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _rich(line),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _sectionTitle(int number, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                color: _brand,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _ink,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rich(String value) {
    final parts = value.split('**');
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < parts.length; i++)
            TextSpan(
              text: parts[i],
              style: i.isOdd
                  ? const TextStyle(fontWeight: FontWeight.w700, color: _ink)
                  : null,
            ),
        ],
      ),
      style: const TextStyle(
        color: Color(0xFF3B515B),
        fontSize: 15,
        height: 1.65,
      ),
    );
  }
}

class LegalPage extends StatefulWidget {
  const LegalPage({super.key, required this.kind});

  final LegalKind kind;

  @override
  State<LegalPage> createState() => _LegalPageState();
}

class _LegalPageState extends State<LegalPage> {
  late Future<LegalContent> _future;
  late Future<LegalContact> _contactFuture;
  late bool _sw;

  @override
  void initState() {
    super.initState();
    _sw = Get.locale?.languageCode == 'sw';
    _future = LegalService.load(widget.kind);
    _contactFuture = LegalService.loadContact();
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Widget _contactCard() {
    return FutureBuilder<LegalContact>(
      future: _contactFuture,
      builder: (context, snapshot) {
        final c = snapshot.data;
        if (c == null || c.isEmpty) return const SizedBox.shrink();
        Widget row(IconData icon, String text, [String? url]) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: InkWell(
            onTap: url == null ? null : () => _open(url),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: _brand),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: url == null ? _ink : _brand,
                      fontWeight: url == null
                          ? FontWeight.w500
                          : FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E9EA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _sw ? 'Wasiliana nasi' : 'Contact us',
                style: const TextStyle(
                  color: _ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (c.companyName.isNotEmpty)
                row(Icons.business_rounded, c.companyName),
              if (c.email.isNotEmpty)
                row(Icons.email_outlined, c.email, 'mailto:${c.email}'),
              if (c.phone.isNotEmpty)
                row(
                  Icons.phone_outlined,
                  c.phone,
                  'tel:${c.phone.replaceAll(RegExp(r'[^0-9+]'), '')}',
                ),
              if (c.address.isNotEmpty)
                row(Icons.location_on_outlined, c.address),
            ],
          ),
        );
      },
    );
  }

  void _go(LegalKind kind) {
    if (kind == widget.kind) return;
    Get.offNamed(kind.path);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: FutureBuilder<LegalContent>(
          future: _future,
          builder: (context, snapshot) {
            final content = snapshot.data;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _hero(content, wide)),
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          wide ? 0 : 16,
                          0,
                          wide ? 0 : 16,
                          40,
                        ),
                        child: _card(content, snapshot.connectionState, wide),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _hero(LegalContent? content, bool wide) {
    final isPrivacy = widget.kind == LegalKind.privacy;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0A333D), _brand],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, wide ? 56 : 44),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (Navigator.of(context).canPop())
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  const Text(
                    'MJASI POS',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  _langToggle(),
                ],
              ),
              SizedBox(height: wide ? 36 : 26),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isPrivacy ? Icons.privacy_tip_outlined : Icons.gavel_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                content?.title(_sw) ?? LegalDefaults.of(widget.kind).title(_sw),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: wide ? 34 : 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              if (content?.updatedAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  '${_sw ? 'Imesasishwa' : 'Last updated'}: '
                  '${DateFormat('d MMM yyyy').format(content!.updatedAt!)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _langToggle() {
    Widget item(String label, bool active, bool sw) => GestureDetector(
      onTap: () => setState(() => _sw = sw),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: active ? _brand : Colors.white70,
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [item('SW', _sw, true), item('EN', !_sw, false)]),
    );
  }

  Widget _card(LegalContent? content, ConnectionState state, bool wide) {
    return Transform.translate(
      offset: const Offset(0, -28),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(wide ? 36 : 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: content == null
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : LegalBody(content.body(_sw)),
          ),
          _contactCard(),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _footerLink(
                LegalKind.privacy,
                _sw ? 'Sera ya Faragha' : 'Privacy Policy',
              ),
              _footerLink(
                LegalKind.terms,
                _sw ? 'Masharti na Vigezo' : 'Terms & Conditions',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '© ${DateTime.now().year} MJASI POS',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _footerLink(LegalKind kind, String label) {
    final active = kind == widget.kind;
    return ActionChip(
      onPressed: () => _go(kind),
      label: Text(label),
      backgroundColor: active ? _brand : Colors.white,
      side: BorderSide(color: active ? _brand : const Color(0xFFD9E3E6)),
      labelStyle: TextStyle(
        color: active ? Colors.white : _brand,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
    );
  }
}
