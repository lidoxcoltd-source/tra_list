import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tra_list/jobs/models/debt.dart';

class PublicDebtProofPage extends StatelessWidget {
  const PublicDebtProofPage({
    super.key,
    required this.businessId,
    required this.debtId,
  });

  final String businessId;
  final String debtId;

  Future<Map<String, dynamic>?> _loadDebt() async {
    if (businessId.isEmpty || debtId.isEmpty) return null;
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(businessId)
        .collection('publicDebtProofs')
        .doc(debtId)
        .get();
    if (!snapshot.exists) return null;
    return snapshot.data();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF1F6F8),
    body: SafeArea(
      child: FutureBuilder<Map<String, dynamic>?>(
        future: _loadDebt(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _PublicDebtMessage(
              icon: Icons.link_off_rounded,
              title: 'Uthibitisho haupatikani',
              message:
                  'Imeshindikana kufungua taarifa. Hakikisha kiungo ni sahihi au wasiliana na biashara iliyotoa uthibitisho.',
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF087E8B)),
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return const _PublicDebtMessage(
              icon: Icons.receipt_long_outlined,
              title: 'Deni halijapatikana',
              message:
                  'Namba hii ya uthibitisho haipo au rekodi imeondolewa.',
            );
          }

          final debtorName = data['debtorName']?.toString() ?? '';
          final shopNickname = data['shopNickname']?.toString() ?? '';
          final principal = (data['principal'] as num?)?.toDouble() ?? 0;
          final amountPaid = (data['amountPaid'] as num?)?.toDouble() ?? 0;
          final balance = (principal - amountPaid).clamp(0, double.infinity);
          final paid = balance <= 0;
          final rawDueDate = data['dueDate'];
          final dueDate = rawDueDate is Timestamp
              ? rawDueDate.toDate()
              : rawDueDate is DateTime
              ? rawDueDate
              : null;
          final daysLeft = dueDate == null
              ? null
              : DateTime(
                      dueDate.year,
                      dueDate.month,
                      dueDate.day,
                    )
                    .difference(DateTime.now().dateOnly)
                    .inDays;
          final direction = data['direction']?.toString();
          final money = NumberFormat('#,##0.00');
          final date = DateFormat('dd MMM yyyy');

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 20),
                  const Icon(
                    Icons.verified_user_rounded,
                    color: Color(0xFF087E8B),
                    size: 42,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'UTHIBITISHO WA DENI',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF173B45),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    shopNickname,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF60777D)),
                  ),
                  const SizedBox(height: 22),
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: const BorderSide(color: Color(0xFFDDE9EC)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: paid
                                  ? const Color(0xFFE8F7EF)
                                  : const Color(0xFFFFF6E8),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  paid
                                      ? Icons.check_circle_rounded
                                      : Icons.hourglass_bottom_rounded,
                                  color: paid
                                      ? const Color(0xFF17824B)
                                      : const Color(0xFFBC7915),
                                  size: 42,
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  paid ? 'LIMELIPWA' : 'HALIJALIPWA KIKAMILIFU',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: paid
                                        ? const Color(0xFF176A40)
                                        : const Color(0xFF8D5A0B),
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: .4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          _ProofRow(label: 'Jina', value: debtorName),
                          _ProofRow(
                            label: 'Aina ya deni',
                            value: direction == DebtDirection.customerOwesShop.name
                                ? 'Mteja anadaiwa na biashara'
                                : 'Biashara inadaiwa',
                          ),
                          _ProofRow(
                            label: 'Kiasi cha awali',
                            value: 'TZS ${money.format(principal)}',
                          ),
                          _ProofRow(
                            label: 'Kilicholipwa',
                            value: 'TZS ${money.format(amountPaid)}',
                          ),
                          _ProofRow(
                            label: 'Salio',
                            value: 'TZS ${money.format(balance)}',
                            emphasize: true,
                          ),
                          _ProofRow(
                            label: 'Tarehe ya mwisho',
                            value: dueDate == null
                                ? 'Haijawekwa'
                                : date.format(dueDate),
                          ),
                          if (!paid && daysLeft != null)
                            _ProofRow(
                              label: daysLeft < 0 ? 'Muda uliopita' : 'Siku zilizobaki',
                              value: daysLeft < 0
                                  ? '${daysLeft.abs()} siku'
                                  : '$daysLeft siku',
                              emphasize: true,
                            ),
                          _ProofRow(
                            label: 'Namba ya kumbukumbu',
                            value: debtId,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Taarifa hii ni uthibitisho wa hali ya deni kwenye mfumo wakati ukurasa huu umefunguliwa.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF75888D),
                              fontSize: 12,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Mjasi POS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF829398),
                      fontSize: 12,
                      letterSpacing: .6,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _ProofRow extends StatelessWidget {
  const _ProofRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF687D82), fontSize: 13),
          ),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: const Color(0xFF183941),
              fontSize: 13,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

class _PublicDebtMessage extends StatelessWidget {
  const _PublicDebtMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF087E8B), size: 46),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF173B45),
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF647A80), height: 1.5),
            ),
          ],
        ),
      ),
    ),
  );
}

extension on DateTime {
  DateTime get dateOnly => DateTime(year, month, day);
}
