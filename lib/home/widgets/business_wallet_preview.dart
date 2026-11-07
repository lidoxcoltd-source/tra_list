import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:tra_list/theme/app_theme.dart';

class BusinessWalletPreview extends StatelessWidget {
  const BusinessWalletPreview({super.key, this.onBack});

  final VoidCallback? onBack;

  static const _background = MjasiColors.background;
  static const _darkBlue = Color(0xFF123B72);
  static const _surface = Color(0xFF163B68);
  static const _muted = Color(0xFF9BA9BE);

  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Coming soon'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final fullName = user?.displayName?.trim();
    final greeting = fullName == null || fullName.isEmpty
        ? 'Biashara yako'
        : fullName.split(RegExp(r'\s+')).first;
    final photoUrl = user?.photoURL;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 620),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      decoration: const BoxDecoration(color: _background),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _darkBlue,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                if (onBack != null)
                  _iconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Rudi',
                    onPressed: onBack!,
                  ),
                CircleAvatar(
                  radius: 20,
                  backgroundColor: MjasiColors.primaryBlue,
                  foregroundImage: photoUrl == null
                      ? null
                      : NetworkImage(photoUrl),
                  child: photoUrl == null
                      ? Text(
                          _initials(greeting),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : null,
                ),
                const Spacer(),
                _iconButton(
                  icon: Icons.dark_mode_outlined,
                  tooltip: 'Coming soon',
                  onPressed: () => _comingSoon(context),
                ),
                const SizedBox(width: 5),
                _iconButton(
                  icon: Icons.notifications_none_rounded,
                  tooltip: 'Coming soon',
                  onPressed: () => _comingSoon(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_darkBlue, MjasiColors.primaryBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x332457D6),
                  blurRadius: 22,
                  offset: Offset(0, 9),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -45,
                  top: -55,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .10),
                        width: 22,
                      ),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => _comingSoon(context),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$greeting Account',
                              style: const TextStyle(
                                color: Color(0xFFD7E6FF),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFFD7E6FF),
                              size: 19,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 17),
                    Row(
                      children: [
                        const Text(
                          'Jumla ya salio',
                          style: TextStyle(
                            color: Color(0xFFC7D8F1),
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        _iconButton(
                          icon: Icons.visibility_outlined,
                          tooltip: 'Coming soon',
                          onPressed: () => _comingSoon(context),
                          compact: true,
                          iconColor: Colors.white,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '3,567,000 TZS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    OutlinedButton(
                      onPressed: () => _comingSoon(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: .25),
                        ),
                        backgroundColor: Colors.white.withValues(alpha: .10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                        textStyle: const TextStyle(fontSize: 11),
                      ),
                      child: const Text('Angalia akaunti zote'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),
          Row(
            children: [
              _action(context, Icons.add_card_rounded, 'Weka pesa'),
              _action(context, Icons.receipt_long_outlined, 'Lipa bili'),
              _action(context, Icons.arrow_upward_rounded, 'Tuma pesa'),
              _action(context, Icons.south_west_rounded, 'Toa pesa'),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_darkBlue, MjasiColors.primaryBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF303D54)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x332457D6),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: InkWell(
              onTap: () => _comingSoon(context),
              borderRadius: BorderRadius.circular(17),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFF263958),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Color(0xFF8DBBFF),
                      size: 27,
                    ),
                  ),
                  const SizedBox(width: 13),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'COMING SOON',
                          style: TextStyle(
                            color: Color(0xFF69D8B1),
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .9,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'TUMA NA POKEA PESA',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .2,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Kutoka biashara nyingine kwa makato ya TZS 200 tu.',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Color(0xFF83B5FF),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 23),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _tab(context, 'WALLET', active: true),
              _tab(context, 'MIAMALA'),
              _tab(context, 'AKIBA'),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF26344B)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.storefront_rounded,
                  color: Color(0xFF83B5FF),
                  size: 22,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nunua kutoka biashara nyingine',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Nunua bidhaa ndani ya mtandao wa MJASI.',
                        style: TextStyle(color: _muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: _muted),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(BuildContext context, IconData icon, String label) => Expanded(
    child: InkWell(
      onTap: () => _comingSoon(context),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: MjasiColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: MjasiColors.border),
              ),
              child: Icon(icon, color: MjasiColors.primaryBlue, size: 21),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                color: MjasiColors.textPrimary,
                fontSize: 10,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _tab(BuildContext context, String label, {bool active = false}) =>
      InkWell(
        onTap: () => _comingSoon(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: active
                      ? MjasiColors.primaryBlue
                      : MjasiColors.textSecondary,
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: .5,
                ),
              ),
              const SizedBox(height: 7),
              Container(
                width: active ? 34 : 12,
                height: 2,
                decoration: BoxDecoration(
                  color: active
                      ? MjasiColors.secondaryBlue
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _iconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool compact = false,
    Color iconColor = const Color(0xFFDCE7F7),
  }) => IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: BoxConstraints.tightFor(
      width: compact ? 28 : 36,
      height: compact ? 28 : 36,
    ),
    color: iconColor,
    icon: Icon(icon, size: compact ? 17 : 20),
  );

  String _initials(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part.characters.first.toUpperCase())
      .join();
}
