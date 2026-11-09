import 'package:flutter/material.dart';
import 'package:tra_list/home/models/home_models.dart';
import 'package:tra_list/theme/app_theme.dart';

enum _StaffSort { sales, count, name }

class HomeStaffSummary extends StatefulWidget {
  const HomeStaffSummary({
    super.key,
    required this.staffStats,
    required this.onViewHistory,
    required this.formatAmount,
  });

  final List<StaffStat> staffStats;
  final ValueChanged<StaffStat> onViewHistory;
  final String Function(double) formatAmount;

  @override
  State<HomeStaffSummary> createState() => _HomeStaffSummaryState();
}

class _HomeStaffSummaryState extends State<HomeStaffSummary> {
  _StaffSort _sort = _StaffSort.sales;

  @override
  Widget build(BuildContext context) {
    final staff = [...widget.staffStats]
      ..sort((a, b) {
        switch (_sort) {
          case _StaffSort.sales:
            return b.sales.compareTo(a.sales);
          case _StaffSort.count:
            return b.saleCount.compareTo(a.saleCount);
          case _StaffSort.name:
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        }
      });
    return Material(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(MjasiRadius.sm),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(MjasiSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.point_of_sale_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text(
                    'Mauzo ya wafanyakazi',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<_StaffSort>(
                    value: _sort,
                    dropdownColor: const Color(0xFF17304F),
                    icon: const Icon(
                      Icons.sort_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    items: const [
                      DropdownMenuItem(
                        value: _StaffSort.sales,
                        child: Text('Mauzo mengi'),
                      ),
                      DropdownMenuItem(
                        value: _StaffSort.count,
                        child: Text('Idadi ya risiti'),
                      ),
                      DropdownMenuItem(
                        value: _StaffSort.name,
                        child: Text('Jina'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _sort = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            _header(),
            Divider(height: 12, color: Colors.white.withValues(alpha: .18)),
            if (staff.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Hakuna mauzo katika kipindi hiki.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              )
            else
              for (final member in staff.take(8)) _row(member),
          ],
        ),
      ),
    );
  }

  Widget _header() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(flex: 4, child: Text('Mfanyakazi', style: _headerStyle)),
        Expanded(
          flex: 3,
          child: Text(
            'Jumla ya mauzo',
            textAlign: TextAlign.right,
            style: _headerStyle,
          ),
        ),
        SizedBox(
          width: 42,
          child: Text('Vitu', textAlign: TextAlign.right, style: _headerStyle),
        ),
        SizedBox(width: 23),
      ],
    ),
  );

  Widget _row(StaffStat staff) => InkWell(
    onTap: staff.uid.isEmpty ? null : () => widget.onViewHistory(staff),
    borderRadius: BorderRadius.circular(9),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: Colors.white24,
                  foregroundImage: staff.photoUrl.isEmpty
                      ? null
                      : NetworkImage(staff.photoUrl),
                  onForegroundImageError: staff.photoUrl.isEmpty
                      ? null
                      : (_, _) {},
                  child: staff.photoUrl.isEmpty
                      ? Text(
                          _initials(staff.name),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        staff.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${staff.saleCount} risiti',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              widget.formatAmount(staff.sales),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF34D399),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(
            width: 42,
            child: Text(
              staff.unitsSold.toStringAsFixed(
                staff.unitsSold == staff.unitsSold.roundToDouble() ? 0 : 1,
              ),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Icon(
            Icons.chevron_right_rounded,
            color: Colors.white70,
            size: 18,
          ),
        ],
      ),
    ),
  );
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  return parts
      .take(2)
      .map((part) => String.fromCharCode(part.runes.first).toUpperCase())
      .join();
}

const _headerStyle = TextStyle(
  color: Colors.white70,
  fontSize: 10,
  fontWeight: FontWeight.w700,
);
