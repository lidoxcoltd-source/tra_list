import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'admin_analytics_service.dart';

/// Super Admin dashboard: subscribers, revenue and growth.
class AdminAnalyticsPage extends StatefulWidget {
  const AdminAnalyticsPage({super.key});

  @override
  State<AdminAnalyticsPage> createState() => _AdminAnalyticsPageState();
}

class _AdminAnalyticsPageState extends State<AdminAnalyticsPage> {
  static const _brand = Color(0xFF0E5962);
  static const _ink = Color(0xFF19313A);

  final _money = NumberFormat('#,##0');
  AdminAnalytics? _data;
  UsageStats? _usage;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AdminAnalyticsService.load();
      UsageStats? usage;
      try {
        usage = await AdminAnalyticsService.loadUsage();
      } catch (error) {
        debugPrint('Usage stats unavailable: $error');
      }
      if (!mounted) return;
      setState(() {
        _data = data;
        _usage = usage;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load analytics: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  String _tzs(double v) => 'TZS ${_money.format(v.round())}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F8),
      appBar: AppBar(
        title: const Text('App analytics'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          : _body(_data!),
    );
  }

  Widget _body(AdminAnalytics a) {
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        final pad = width >= 900 ? 28.0 : 16.0;
        final cols = width >= 1100 ? 4 : (width >= 700 ? 2 : 2);
        const gap = 12.0;
        final inner = (width - pad * 2).clamp(0, 1200).toDouble();
        final cardWidth = (inner - gap * (cols - 1)) / cols;
        final twoPanels = inner >= 800;
        final panelWidth = twoPanels ? (inner - gap) / 2 : inner;

        Widget stat(
          String label,
          String value,
          IconData icon,
          Color color, {
          String? hint,
        }) {
          return SizedBox(
            width: cardWidth,
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    const SizedBox(height: 12),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                    ),
                    Text(label, style: const TextStyle(color: Colors.black54)),
                    if (hint != null)
                      Text(
                        hint,
                        style: const TextStyle(
                          color: Colors.black38,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        final months = a.months();
        return SingleChildScrollView(
          padding: EdgeInsets.all(pad),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _title('App usage (people using the app)'),
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      stat(
                        'Online now',
                        '${_usage?.onlineNow ?? 0}',
                        Icons.circle,
                        const Color(0xFF16A34A),
                        hint: 'Active in the last 5 minutes',
                      ),
                      stat(
                        'Active today',
                        '${_usage?.today ?? 0}',
                        Icons.today_rounded,
                        _brand,
                        hint: 'Last 24 hours',
                      ),
                      stat(
                        'Active this week',
                        '${_usage?.week ?? 0}',
                        Icons.date_range_rounded,
                        const Color(0xFF5B3FD0),
                        hint: 'Last 7 days',
                      ),
                      stat(
                        'Active this month',
                        '${_usage?.month ?? 0}',
                        Icons.calendar_month_rounded,
                        const Color(0xFF0EA5E9),
                        hint: 'Last 30 days',
                      ),
                      stat(
                        'People who used it',
                        '${_usage?.everUsed ?? 0}',
                        Icons.people_alt_rounded,
                        _brand,
                        hint: '${_usage?.newThisWeek ?? 0} new this week',
                      ),
                      stat(
                        'Total app opens',
                        '${_usage?.totalOpens ?? 0}',
                        Icons.touch_app_rounded,
                        const Color(0xFFF59E0B),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      _panel(
                        panelWidth,
                        'Active users by platform (30 days)',
                        _counts(_usage?.byPlatform ?? const {}),
                      ),
                      _panel(
                        panelWidth,
                        'Installed app versions',
                        _counts(_usage?.byVersion ?? const {}),
                      ),
                    ],
                  ),
                  if (_usage == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Usage data could not be loaded. Deploy the latest Firestore rules.',
                        style: TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Usage is counted from versions that include activity tracking, '
                        'so people on older builds appear once they update.',
                        style: TextStyle(color: Colors.black45, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 24),
                  _title('Revenue'),
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      stat(
                        'Estimated total income',
                        _tzs(a.totalRevenue),
                        Icons.account_balance_wallet_rounded,
                        _brand,
                        hint: 'Latest plan price of every subscriber',
                      ),
                      stat(
                        'Monthly recurring (MRR)',
                        _tzs(a.monthlyRecurring),
                        Icons.autorenew_rounded,
                        const Color(0xFF5B3FD0),
                      ),
                      stat(
                        'Yearly run-rate',
                        _tzs(a.annualRecurring),
                        Icons.trending_up_rounded,
                        const Color(0xFF16A34A),
                      ),
                      stat(
                        'Renewals due in 30 days',
                        _tzs(a.renewalsAtRisk),
                        Icons.event_repeat_rounded,
                        const Color(0xFFF59E0B),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _title('Users'),
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      stat(
                        'Total businesses',
                        '${a.total}',
                        Icons.groups_rounded,
                        _brand,
                        hint: '${a.newThisMonth} new this month',
                      ),
                      stat(
                        'Active subscribers',
                        '${a.active}',
                        Icons.verified_rounded,
                        const Color(0xFF16A34A),
                      ),
                      stat(
                        'On free trial',
                        '${a.trials}',
                        Icons.hourglass_top_rounded,
                        const Color(0xFF0EA5E9),
                      ),
                      stat(
                        'Expiring in 30 days',
                        '${a.expiringSoon}',
                        Icons.schedule_rounded,
                        const Color(0xFFF59E0B),
                      ),
                      stat(
                        'Expired',
                        '${a.expired}',
                        Icons.event_busy_rounded,
                        const Color(0xFFDC2626),
                      ),
                      stat(
                        'Never subscribed',
                        '${a.neverPaid}',
                        Icons.person_outline_rounded,
                        Colors.blueGrey,
                      ),
                      stat(
                        'Disabled accounts',
                        '${a.disabled}',
                        Icons.block_rounded,
                        Colors.black54,
                      ),
                      stat(
                        'Conversion rate',
                        '${(a.conversionRate * 100).toStringAsFixed(1)}%',
                        Icons.swap_vert_rounded,
                        const Color(0xFF5B3FD0),
                        hint: 'Avg ${_tzs(a.averageRevenuePerSubscriber)} each',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _title('Last 6 months'),
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      _panel(
                        panelWidth,
                        'Income by month',
                        _bars(
                          months,
                          (m) => m.revenue,
                          const Color(0xFF16A34A),
                          (v) => _tzs(v),
                        ),
                      ),
                      _panel(
                        panelWidth,
                        'New sign-ups',
                        _bars(
                          months,
                          (m) => m.signups.toDouble(),
                          _brand,
                          (v) => v.round().toString(),
                        ),
                      ),
                      _panel(
                        panelWidth,
                        'New subscriptions',
                        _bars(
                          months,
                          (m) => m.subscriptions.toDouble(),
                          const Color(0xFF5B3FD0),
                          (v) => v.round().toString(),
                        ),
                      ),
                      _panel(panelWidth, 'User breakdown', _breakdown(a)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      _panel(
                        panelWidth,
                        'Recent sign-ups',
                        _list(
                          a.recentSignups,
                          (r) => DateFormat.yMMMd().format(r.createdAt!),
                        ),
                      ),
                      _panel(
                        panelWidth,
                        'Next expiries',
                        _list(
                          a.nextExpiries,
                          (r) =>
                              'Expires ${DateFormat.yMMMd().format(r.expiry!)}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Income is estimated from each subscriber\'s latest plan '
                    'price because payments are not stored as a ledger. '
                    'Sign-up dates come from the business profile.',
                    style: TextStyle(color: Colors.black45, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _counts(Map<String, int> counts) {
    if (counts.isEmpty) {
      return const Text(
        'No data yet.',
        style: TextStyle(color: Colors.black45),
      );
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold(0, (a, e) => a + e.value);
    return Column(
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: Text(e.key)),
                    Text('${e.value}'),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: e.value / total,
                    minHeight: 8,
                    color: _brand,
                    backgroundColor: _brand.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _title(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: _ink,
      ),
    ),
  );

  Widget _panel(double width, String title, Widget child) => SizedBox(
    width: width,
    child: Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    ),
  );

  Widget _bars(
    List<MonthBucket> months,
    double Function(MonthBucket) value,
    Color color,
    String Function(double) format,
  ) {
    final max = months.map(value).fold(0.0, (a, b) => a > b ? a : b);
    return SizedBox(
      height: 170,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final m in months)
            Expanded(
              child: Tooltip(
                message:
                    '${DateFormat.yMMM().format(m.month)}: ${format(value(m))}',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      value(m) == 0 ? '' : format(value(m)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      height: max == 0 ? 4 : 4 + 110 * (value(m) / max),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      DateFormat.MMM().format(m.month),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _breakdown(AdminAnalytics a) {
    final rows = [
      ('Active', a.active, const Color(0xFF16A34A)),
      ('Trial', a.trials, const Color(0xFF0EA5E9)),
      ('Expired', a.expired, const Color(0xFFDC2626)),
      ('Never subscribed', a.neverPaid, Colors.blueGrey),
    ];
    final total = a.total == 0 ? 1 : a.total;
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: Text(r.$1)),
                    Text(
                      '${r.$2}  ·  ${(r.$2 * 100 / total).toStringAsFixed(0)}%',
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: r.$2 / total,
                    minHeight: 8,
                    color: r.$3,
                    backgroundColor: r.$3.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _list(
    List<BusinessRecord> items,
    String Function(BusinessRecord) sub,
  ) {
    if (items.isEmpty) {
      return const Text(
        'Nothing yet.',
        style: TextStyle(color: Colors.black45),
      );
    }
    return Column(
      children: [
        for (final r in items)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: _brand.withValues(alpha: 0.12),
              child: Text(
                r.label.characters.first.toUpperCase(),
                style: const TextStyle(color: _brand),
              ),
            ),
            title: Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(sub(r)),
          ),
      ],
    );
  }
}
