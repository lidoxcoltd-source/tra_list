import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'admin_analytics_service.dart';

class AdminAnalyticsPage extends StatefulWidget {
  const AdminAnalyticsPage({super.key});

  @override
  State<AdminAnalyticsPage> createState() => _AdminAnalyticsPageState();
}

class _AdminAnalyticsPageState extends State<AdminAnalyticsPage> {
  static const _brand = Color(0xFF0E5962);
  static const _navy = Color(0xFF102A43);
  static const _ink = Color(0xFF172B4D);
  static const _muted = Color(0xFF718096);
  static const _canvas = Color(0xFFF4F7FB);
  static const _line = Color(0xFFE7EDF4);
  static const _green = Color(0xFF159A72);
  static const _purple = Color(0xFF6750D8);
  static const _blue = Color(0xFF2787D8);
  static const _amber = Color(0xFFE99A24);
  static const _red = Color(0xFFD94B54);

  final NumberFormat _money = NumberFormat('#,##0');
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
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

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

  String _tzs(double value) => 'TZS ${_money.format(value.round())}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleSpacing: 20,
        title: const Row(
          children: [
            _BrandMark(),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Analytics',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'SUPER ADMIN OVERVIEW',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.25,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Tooltip(
              message: 'Refresh analytics',
              child: Material(
                color: _canvas,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _loading ? null : _load,
                  child: Padding(
                    padding: const EdgeInsets.all(11),
                    child: _loading
                        ? const SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _brand,
                            ),
                          )
                        : const Icon(
                            Icons.refresh_rounded,
                            color: _navy,
                            size: 21,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading && _data == null
          ? const _LoadingView()
          : _error != null && _data == null
          ? _ErrorView(message: _error!, onRetry: _load)
          : _data == null
          ? _ErrorView(
              message: 'No analytics data is available.',
              onRetry: _load,
            )
          : _buildDashboard(_data!),
    );
  }

  Widget _buildDashboard(AdminAnalytics analytics) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final horizontalPadding = width >= 1100
            ? 30.0
            : width >= 700
            ? 24.0
            : 16.0;
        final contentWidth = (width - horizontalPadding * 2)
            .clamp(0.0, 1240.0)
            .toDouble();
        final columns = contentWidth >= 1050
            ? 4
            : contentWidth >= 620
            ? 2
            : 1;
        const gap = 14.0;
        final statWidth = (contentWidth - gap * (columns - 1)) / columns;
        final panelColumns = contentWidth >= 850 ? 2 : 1;
        final panelWidth =
            (contentWidth - gap * (panelColumns - 1)) / panelColumns;
        final months = analytics.months();

        Widget statGrid(List<Widget> children) {
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: children
                .map((child) => SizedBox(width: statWidth, child: child))
                .toList(),
          );
        }

        Widget panelGrid(List<Widget> children) {
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: children
                .map((child) => SizedBox(width: panelWidth, child: child))
                .toList(),
          );
        }

        return RefreshIndicator(
          color: _brand,
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              24,
              horizontalPadding,
              32,
            ),
            child: Center(
              child: SizedBox(
                width: 1240,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWelcomeHeader(analytics),
                    const SizedBox(height: 28),

                    _sectionHeading(
                      'Revenue overview',
                      'A snapshot of your subscription income',
                      Icons.account_balance_wallet_outlined,
                    ),
                    const SizedBox(height: 14),
                    statGrid([
                      _StatCard(
                        label: 'Estimated total income',
                        value: _tzs(analytics.totalRevenue),
                        hint: 'Based on subscribers’ latest plan prices',
                        icon: Icons.account_balance_wallet_rounded,
                        color: _brand,
                        featured: true,
                      ),
                      _StatCard(
                        label: 'Monthly recurring revenue',
                        value: _tzs(analytics.monthlyRecurring),
                        hint: 'Estimated monthly revenue',
                        icon: Icons.autorenew_rounded,
                        color: _purple,
                      ),
                      _StatCard(
                        label: 'Yearly run-rate',
                        value: _tzs(analytics.annualRecurring),
                        hint: 'Projected recurring revenue',
                        icon: Icons.trending_up_rounded,
                        color: _green,
                      ),
                      _StatCard(
                        label: 'Renewals at risk',
                        value: _tzs(analytics.renewalsAtRisk),
                        hint: 'Renewals due in 30 days',
                        icon: Icons.event_repeat_rounded,
                        color: _amber,
                      ),
                    ]),
                    const SizedBox(height: 28),

                    _sectionHeading(
                      'App usage',
                      'Understand how people use your app',
                      Icons.query_stats_rounded,
                    ),
                    const SizedBox(height: 14),
                    statGrid([
                      _StatCard(
                        label: 'Online now',
                        value: '${_usage?.onlineNow ?? 0}',
                        hint: 'Active in the last 5 minutes',
                        icon: Icons.circle_rounded,
                        color: _green,
                        iconSize: 15,
                      ),
                      _StatCard(
                        label: 'Active today',
                        value: '${_usage?.today ?? 0}',
                        hint: 'Last 24 hours',
                        icon: Icons.today_rounded,
                        color: _brand,
                      ),
                      _StatCard(
                        label: 'Active this week',
                        value: '${_usage?.week ?? 0}',
                        hint: 'Last 7 days',
                        icon: Icons.date_range_rounded,
                        color: _purple,
                      ),
                      _StatCard(
                        label: 'Active this month',
                        value: '${_usage?.month ?? 0}',
                        hint: 'Last 30 days',
                        icon: Icons.calendar_month_rounded,
                        color: _blue,
                      ),
                      _StatCard(
                        label: 'People who used it',
                        value: '${_usage?.everUsed ?? 0}',
                        hint: '${_usage?.newThisWeek ?? 0} new this week',
                        icon: Icons.people_alt_rounded,
                        color: _brand,
                      ),
                      _StatCard(
                        label: 'Total app opens',
                        value: '${_usage?.totalOpens ?? 0}',
                        hint: 'Recorded app launches',
                        icon: Icons.touch_app_rounded,
                        color: _amber,
                      ),
                    ]),
                    const SizedBox(height: 14),
                    panelGrid([
                      _panel(
                        title: 'Active users by platform',
                        subtitle: 'Last 30 days',
                        icon: Icons.devices_rounded,
                        child: _counts(_usage?.byPlatform ?? const {}),
                      ),
                      _panel(
                        title: 'Installed app versions',
                        subtitle: 'Version distribution',
                        icon: Icons.phone_android_rounded,
                        child: _counts(_usage?.byVersion ?? const {}),
                      ),
                    ]),
                    if (_usage == null)
                      const _InfoBanner(
                        icon: Icons.info_outline_rounded,
                        color: _amber,
                        message:
                            'Usage data could not be loaded. Check your Firestore rules and activity-tracking setup.',
                      )
                    else
                      const _InfoBanner(
                        icon: Icons.lightbulb_outline_rounded,
                        color: _blue,
                        message:
                            'Activity data is available for app versions that include activity tracking. Users on older builds may appear after updating.',
                      ),
                    const SizedBox(height: 28),

                    _sectionHeading(
                      'Business accounts',
                      'Subscription health and account status',
                      Icons.business_center_outlined,
                    ),
                    const SizedBox(height: 14),
                    statGrid([
                      _StatCard(
                        label: 'Total businesses',
                        value: '${analytics.total}',
                        hint: '${analytics.newThisMonth} new this month',
                        icon: Icons.groups_rounded,
                        color: _brand,
                      ),
                      _StatCard(
                        label: 'Active subscribers',
                        value: '${analytics.active}',
                        hint: 'Currently active',
                        icon: Icons.verified_rounded,
                        color: _green,
                      ),
                      _StatCard(
                        label: 'On free trial',
                        value: '${analytics.trials}',
                        hint: 'Trial accounts',
                        icon: Icons.hourglass_top_rounded,
                        color: _blue,
                      ),
                      _StatCard(
                        label: 'Expiring soon',
                        value: '${analytics.expiringSoon}',
                        hint: 'Within 30 days',
                        icon: Icons.schedule_rounded,
                        color: _amber,
                      ),
                      _StatCard(
                        label: 'Expired',
                        value: '${analytics.expired}',
                        hint: 'Subscription expired',
                        icon: Icons.event_busy_rounded,
                        color: _red,
                      ),
                      _StatCard(
                        label: 'Never subscribed',
                        value: '${analytics.neverPaid}',
                        hint: 'No paid subscription recorded',
                        icon: Icons.person_outline_rounded,
                        color: const Color(0xFF718096),
                      ),
                      _StatCard(
                        label: 'Disabled accounts',
                        value: '${analytics.disabled}',
                        hint: 'Currently disabled',
                        icon: Icons.block_rounded,
                        color: _red,
                      ),
                      _StatCard(
                        label: 'Conversion rate',
                        value:
                            '${(analytics.conversionRate * 100).toStringAsFixed(1)}%',
                        hint:
                            'Average ${_tzs(analytics.averageRevenuePerSubscriber)} per subscriber',
                        icon: Icons.swap_vert_rounded,
                        color: _purple,
                      ),
                    ]),
                    const SizedBox(height: 28),

                    _sectionHeading(
                      'Growth & performance',
                      'Track trends over the last six months',
                      Icons.insights_rounded,
                    ),
                    const SizedBox(height: 14),
                    panelGrid([
                      _panel(
                        title: 'Income by month',
                        subtitle: 'Estimated revenue · TZS',
                        icon: Icons.payments_outlined,
                        child: _bars(
                          months,
                          (m) => m.revenue,
                          _green,
                          (v) => _compactMoney(v),
                        ),
                      ),
                      _panel(
                        title: 'New sign-ups',
                        subtitle: 'New business accounts',
                        icon: Icons.person_add_alt_rounded,
                        child: _bars(
                          months,
                          (m) => m.signups.toDouble(),
                          _brand,
                          (v) => v.round().toString(),
                        ),
                      ),
                      _panel(
                        title: 'New subscriptions',
                        subtitle: 'Subscription growth',
                        icon: Icons.card_membership_rounded,
                        child: _bars(
                          months,
                          (m) => m.subscriptions.toDouble(),
                          _purple,
                          (v) => v.round().toString(),
                        ),
                      ),
                      _panel(
                        title: 'User breakdown',
                        subtitle: 'Accounts by subscription status',
                        icon: Icons.donut_large_rounded,
                        child: _breakdown(analytics),
                      ),
                    ]),
                    const SizedBox(height: 28),

                    _sectionHeading(
                      'Account activity',
                      'Recently created accounts and upcoming expiries',
                      Icons.history_rounded,
                    ),
                    const SizedBox(height: 14),
                    panelGrid([
                      _panel(
                        title: 'Recent sign-ups',
                        subtitle: 'Latest business profiles',
                        icon: Icons.person_add_alt_1_rounded,
                        child: _list(
                          analytics.recentSignups,
                          (r) => r.createdAt == null
                              ? 'Date unavailable'
                              : 'Joined ${DateFormat.yMMMd().format(r.createdAt!)}',
                          emptyMessage: 'No recent sign-ups to show.',
                        ),
                      ),
                      _panel(
                        title: 'Next expiries',
                        subtitle: 'Subscriptions to follow up',
                        icon: Icons.event_available_rounded,
                        child: _list(
                          analytics.nextExpiries,
                          (r) => r.expiry == null
                              ? 'Expiry date unavailable'
                              : 'Expires ${DateFormat.yMMMd().format(r.expiry!)}',
                          emptyMessage: 'No upcoming expiries to show.',
                        ),
                      ),
                    ]),
                    const SizedBox(height: 20),
                    const _InfoBanner(
                      icon: Icons.info_outline_rounded,
                      color: _muted,
                      message:
                          'Income is estimated from each subscriber’s latest plan price because payments are not stored as a ledger. Sign-up dates come from the business profile.',
                    ),
                    if (_loading) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(
                        minHeight: 2,
                        color: _brand,
                        backgroundColor: _line,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'ADMIN ANALYTICS  •  ${DateFormat.yMMMd().format(DateTime.now())}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWelcomeHeader(AdminAnalytics analytics) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_navy, _brand],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _brand.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -32,
            child: Icon(
              Icons.query_stats_rounded,
              size: 150,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      color: Color(0xFF9AF0D1),
                      size: 15,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'LIVE BUSINESS OVERVIEW',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Your business at a glance',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Monitor revenue, app activity and subscription growth in one place.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _heroMetric(
                    Icons.business_rounded,
                    '${analytics.total}',
                    'Businesses',
                  ),
                  _heroMetric(
                    Icons.verified_rounded,
                    '${analytics.active}',
                    'Active subscribers',
                  ),
                  _heroMetric(
                    Icons.people_alt_rounded,
                    '${_usage?.today ?? 0}',
                    'Active today',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroMetric(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF9AF0D1)),
          const SizedBox(width: 9),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionHeading(String title, String subtitle, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _brand.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _brand, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _panel({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.025),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _brand.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _brand, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _counts(Map<String, int> counts) {
    if (counts.isEmpty) {
      return const _EmptyState(
        icon: Icons.bar_chart_rounded,
        message: 'No data available yet.',
      );
    }

    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);

    return Column(
      children: [
        for (var i = 0; i < entries.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == entries.length - 1 ? 0 : 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entries[i].key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${entries[i].value}',
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      total == 0
                          ? '0%'
                          : '${(entries[i].value * 100 / total).round()}%',
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : entries[i].value / total,
                    minHeight: 7,
                    color: i == 0 ? _brand : _blue.withValues(alpha: 0.75),
                    backgroundColor: _canvas,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _bars(
    List<MonthBucket> months,
    double Function(MonthBucket) value,
    Color color,
    String Function(double) format,
  ) {
    final maximum = months.map(value).fold<double>(0, (a, b) => a > b ? a : b);

    if (months.isEmpty) {
      return const SizedBox(
        height: 160,
        child: _EmptyState(
          icon: Icons.insert_chart_outlined_rounded,
          message: 'No monthly data available.',
        ),
      );
    }

    return SizedBox(
      height: 178,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final month in months)
            Expanded(
              child: Tooltip(
                message:
                    '${DateFormat.yMMM().format(month.month)}: ${format(value(month))}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: 27,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            value(month) == 0 ? '—' : format(value(month)),
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 450),
                            curve: Curves.easeOutCubic,
                            width: 22,
                            height: maximum == 0
                                ? 5
                                : 8 + 105 * (value(month) / maximum),
                            decoration: BoxDecoration(
                              color: color.withValues(
                                alpha: value(month) == 0 ? 0.25 : 1,
                              ),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(7),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        DateFormat.MMM().format(month.month),
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _compactMoney(double value) {
    if (value.abs() >= 1000000000) {
      return ' ${(value / 1000000000).toStringAsFixed(1)}B';
    }
    if (value.abs() >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value.abs() >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}K';
    }
    return value.round().toString();
  }

  Widget _breakdown(AdminAnalytics analytics) {
    final rows = [
      ('Active', analytics.active, _green),
      ('Trial', analytics.trials, _blue),
      ('Expired', analytics.expired, _red),
      ('Never subscribed', analytics.neverPaid, _muted),
    ];
    final total = analytics.total;

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == rows.length - 1 ? 0 : 17),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: rows[i].$3,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rows[i].$1,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${rows[i].$2}',
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 40,
                      child: Text(
                        total == 0
                            ? '0%'
                            : '${(rows[i].$2 * 100 / total).round()}%',
                        textAlign: TextAlign.end,
                        style: const TextStyle(color: _muted, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : rows[i].$2 / total,
                    minHeight: 7,
                    color: rows[i].$3,
                    backgroundColor: rows[i].$3.withValues(alpha: 0.10),
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
    String Function(BusinessRecord) subtitle, {
    required String emptyMessage,
  }) {
    if (items.isEmpty) {
      return _EmptyState(icon: Icons.inbox_outlined, message: emptyMessage);
    }

    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Container(
            margin: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: i.isEven ? _canvas.withValues(alpha: 0.75) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _line.withValues(alpha: 0.75)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _brand.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Center(
                    child: Text(
                      items[i].label.trim().isEmpty
                          ? '?'
                          : items[i].label.characters.first.toUpperCase(),
                      style: const TextStyle(
                        color: _brand,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        items[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle(items[i]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Color(0xFFADB9C7),
                  size: 13,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 39,
      height: 39,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            _AdminAnalyticsPageState._brand,
            _AdminAnalyticsPageState._navy,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.insights_rounded, color: Colors.white, size: 22),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.color,
    this.featured = false,
    this.iconSize = 20,
  });

  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final Color color;
  final bool featured;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    const ink = _AdminAnalyticsPageState._ink;
    const muted = _AdminAnalyticsPageState._muted;
    const line = _AdminAnalyticsPageState._line;

    return Container(
      constraints: const BoxConstraints(minHeight: 156),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: featured ? color.withValues(alpha: 0.28) : line,
          width: featured ? 1.3 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF102A43).withValues(alpha: 0.025),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 11,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: iconSize),
              ),
            ],
          ),
          const SizedBox(height: 17),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: ink,
                fontSize: 23,
                letterSpacing: -0.7,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: muted, fontSize: 10, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: _AdminAnalyticsPageState._muted,
                fontSize: 11,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFFADB9C7), size: 31),
            const SizedBox(height: 9),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _AdminAnalyticsPageState._muted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 42,
            height: 42,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: _AdminAnalyticsPageState._brand,
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Loading your analytics...',
            style: TextStyle(
              color: _AdminAnalyticsPageState._muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _AdminAnalyticsPageState._line),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _AdminAnalyticsPageState._red.withValues(
                      alpha: 0.09,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.cloud_off_rounded,
                    color: _AdminAnalyticsPageState._red,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Unable to load analytics',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _AdminAnalyticsPageState._ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _AdminAnalyticsPageState._muted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try again'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _AdminAnalyticsPageState._brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
