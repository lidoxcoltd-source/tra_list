import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'add_transaction_page.dart';
import 'transaction_model.dart';
import 'transaction_service.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'analytics_page.dart';
import 'transactions_controller.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/theme/app_theme.dart';

typedef _Tile = (IconData, Color, String);

class _InsightReport {
  final double income;
  final double expense;
  final bool hasAnyData;
  final List<(String, List<_Tile>)> sections;
  final String scope;
  final String? focusTitle;
  final String? focusSubtitle;
  const _InsightReport({
    required this.income,
    required this.expense,
    required this.hasAnyData,
    required this.sections,
    this.scope = '',
    this.focusTitle,
    this.focusSubtitle,
  });
}

class _FocusData {
  final List<TransactionModel> list;
  final double? totalIncome;
  final double? totalExpense;
  const _FocusData(this.list, {this.totalIncome, this.totalExpense});
}

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  final TransactionsController controller = Get.put(TransactionsController());

  @override
  void initState() {
    super.initState();
    final arguments = Get.arguments;
    final type = arguments is Map
        ? arguments['type']?.toString()
        : arguments?.toString();
    final periodName = arguments is Map
        ? arguments['period']?.toString()
        : null;
    switch (type) {
      case 'income':
        controller.selectSummaryFilter(SummaryFilter.income);
        break;
      case 'expense':
        controller.selectSummaryFilter(SummaryFilter.expense);
        break;
    }
    if (type == 'income' || type == 'expense') {
      final period = switch (periodName) {
        'yesterday' => FilterPeriod.yesterday,
        'thisWeek' => FilterPeriod.week,
        'thisMonth' => FilterPeriod.month,
        _ => FilterPeriod.today,
      };
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        while (mounted && controller.isFetching.value) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        if (mounted) controller.setFilter(period);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Initialize controller
    // Initialize date formatting for the current locale.
    initializeDateFormatting(Get.locale?.toString());
    return _buildMobileLayout(context);
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      backgroundColor: MjasiColors.background,
      body: RefreshIndicator(
        onRefresh: controller.fetchFirstPage,
        child: CustomScrollView(
          controller: controller.scrollController,
          slivers: [
            _buildSliverAppBar(context),
            _buildFilterChipsSliver(),
            _buildTransactionListSliver(),
          ],
        ),
      ),
      floatingActionButton: _buildFabs(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget? _buildFabs() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (BusinessAccessService.hasBusinessAccess)
          FloatingActionButton.small(
            heroTag: 'tx_chat_fab',
            tooltip: 'chat_title'.tr,
            backgroundColor: const Color(0xFF1565C0),
            foregroundColor: Colors.white,
            onPressed: () => Get.toNamed(AppRoutes.chat),
            child: const Icon(Icons.forum_outlined),
          ),
        if (BusinessAccessService.hasBusinessAccess) const SizedBox(height: 12),
        FloatingActionButton.small(
          heroTag: 'tx_insight_fab',
          tooltip: _sw ? 'Ushauri wa leo' : "Today's insights",
          backgroundColor: MjasiColors.primaryNavy,
          foregroundColor: Colors.white,
          onPressed: _openInsights,
          child: const Icon(Icons.auto_awesome),
        ),
        if (BusinessAccessService.can('transactions', 'create')) ...[
          const SizedBox(height: 12),
          _buildSpeedDialFab(),
        ],
      ],
    );
  }

  bool get _sw => Get.locale?.languageCode == 'sw';

  void _openCategorySearch() {
    final search = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MjasiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final q = search.text.trim().toLowerCase();
            final all = controller.availableCategories.toList();
            final list = q.isEmpty
                ? all
                : all.where((c) => c.toLowerCase().contains(q)).toList();
            void pick(String value) {
              Navigator.of(ctx).pop();
              controller.setCategoryFilter(value);
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.7,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: MjasiColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: TextField(
                        controller: search,
                        autofocus: true,
                        onChanged: (_) => setSheet(() {}),
                        decoration: InputDecoration(
                          hintText: _sw
                              ? 'Tafuta kategoria...'
                              : 'Search category...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: q.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    search.clear();
                                    setSheet(() {});
                                  },
                                ),
                          filled: true,
                          fillColor: MjasiColors.background,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.apps_rounded),
                      title: Text('transactions_all_categories'.tr),
                      trailing: controller.selectedCategory.value.isEmpty
                          ? const Icon(
                              Icons.check_circle,
                              color: MjasiColors.primaryBlue,
                            )
                          : null,
                      onTap: () => pick(''),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: list.isEmpty
                          ? Center(
                              child: Text(
                                _sw
                                    ? 'Hakuna kategoria iliyopatikana'
                                    : 'No category found',
                                style: const TextStyle(
                                  color: MjasiColors.textSecondary,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: list.length,
                              itemBuilder: (_, i) {
                                final c = list[i];
                                final selected =
                                    controller.selectedCategory.value == c;
                                return ListTile(
                                  leading: const Icon(Icons.sell_outlined),
                                  title: Text(c),
                                  trailing: selected
                                      ? const Icon(
                                          Icons.check_circle,
                                          color: MjasiColors.primaryBlue,
                                        )
                                      : null,
                                  onTap: () => pick(c),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(search.dispose);
  }

  Future<List<TransactionModel>> _loadInsightData() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 1, 1);
    final end = DateTime(now.year, now.month, now.day + 1);
    final snap = await TransactionService.getTransactions(
      limit: 3000,
      startDate: start,
      endDate: end,
    );
    final list = snap.docs.map((d) => d.data()).toList();
    final ids = list.map((t) => t.id).whereType<String>().toSet();
    for (final t in controller.allFetchedTransactions) {
      if (controller.isPending(t) &&
          !t.date.isBefore(start) &&
          (t.id == null || ids.add(t.id!))) {
        list.add(t);
      }
    }
    return list;
  }

  _InsightReport _buildInsightReport(List<TransactionModel> all) {
    final now = DateTime.now();
    DateTime day(int back) => DateTime(now.year, now.month, now.day - back);
    final today0 = day(0);
    final tomorrow = day(-1);
    final monthStart = DateTime(now.year, now.month, 1);
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);

    List<TransactionModel> within(DateTime s, DateTime e) =>
        all.where((t) => !t.date.isBefore(s) && t.date.isBefore(e)).toList();
    double sum(Iterable<TransactionModel> l, TransactionType type) =>
        l.where((t) => t.type == type).fold(0.0, (a, t) => a + t.amount);
    double inc(Iterable<TransactionModel> l) => sum(l, TransactionType.income);
    double exp(Iterable<TransactionModel> l) => sum(l, TransactionType.expense);
    String m(double v) => 'TSH ${TransactionsController.money(v)}';
    String t(String en, String sw) => _sw ? sw : en;
    List<MapEntry<String, double>> byCat(
      Iterable<TransactionModel> l,
      TransactionType type,
    ) {
      final map = <String, double>{};
      for (final x in l.where((x) => x.type == type)) {
        final key = x.category.trim().isEmpty ? '-' : x.category.trim();
        map[key] = (map[key] ?? 0) + x.amount;
      }
      return map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    }

    int change(double now, double before) =>
        ((now - before) / before * 100).round();

    final today = within(today0, tomorrow);
    final yest = within(day(1), today0);
    final week = within(day(6), tomorrow);
    final prevWeek = within(day(13), day(6));
    final month = within(monthStart, tomorrow);
    final lastMonth = within(lastMonthStart, monthStart);

    final tInc = inc(today), tExp = exp(today);
    final wInc = inc(week), wExp = exp(week);
    final mInc = inc(month), mExp = exp(month);
    final sections = <(String, List<_Tile>)>[];

    // Today
    final todayTiles = <_Tile>[];
    if (today.isEmpty) {
      todayTiles.add((
        Icons.edit_note,
        MjasiColors.warning,
        t(
          'No transactions recorded today yet. Log your sales and expenses so your reports stay accurate.',
          'Bado hakuna muamala ulioandikwa leo. Rekodi mauzo na matumizi yako ili ripoti ziwe sahihi.',
        ),
      ));
      if (yest.isNotEmpty) {
        todayTiles.add((
          Icons.history,
          MjasiColors.primaryBlue,
          t(
            'Yesterday you had income ${m(inc(yest))} and expenses ${m(exp(yest))}.',
            'Jana ulikuwa na mapato ${m(inc(yest))} na matumizi ${m(exp(yest))}.',
          ),
        ));
      }
    } else {
      final net = tInc - tExp;
      todayTiles.add((
        net >= 0 ? Icons.trending_up : Icons.trending_down,
        net >= 0 ? MjasiColors.success : MjasiColors.error,
        t(
          '${today.length} transactions today: income ${m(tInc)}, expenses ${m(tExp)}. ${net >= 0 ? 'Profit' : 'Loss'} ${m(net.abs())}.',
          'Miamala ${today.length} leo: mapato ${m(tInc)}, matumizi ${m(tExp)}. ${net >= 0 ? 'Faida' : 'Hasara'} ${m(net.abs())}.',
        ),
      ));
      final incomes = today.where((x) => x.type == TransactionType.income);
      if (incomes.isNotEmpty) {
        final biggest = incomes.reduce((a, b) => a.amount >= b.amount ? a : b);
        todayTiles.add((
          Icons.payments_outlined,
          MjasiColors.success,
          t(
            'Average sale ${m(tInc / incomes.length)} across ${incomes.length} income entries. Largest: ${m(biggest.amount)} (${biggest.description}).',
            'Wastani wa mauzo ${m(tInc / incomes.length)} kwa mapato ${incomes.length}. Kubwa zaidi: ${m(biggest.amount)} (${biggest.description}).',
          ),
        ));
      } else {
        todayTiles.add((
          Icons.info_outline,
          MjasiColors.warning,
          t(
            'Only expenses were recorded today. If you made sales, remember to add the income.',
            'Matumizi pekee ndiyo yameandikwa leo. Kama ulifanya mauzo, kumbuka kuongeza mapato.',
          ),
        ));
      }
      final expCats = byCat(today, TransactionType.expense);
      if (expCats.isNotEmpty && tExp > 0) {
        final top = expCats.first;
        todayTiles.add((
          Icons.pie_chart_outline,
          MjasiColors.warning,
          t(
            'Biggest expense today: "${top.key}" ${m(top.value)} (${(top.value / tExp * 100).round()}% of spending).',
            'Matumizi makubwa leo: "${top.key}" ${m(top.value)} (${(top.value / tExp * 100).round()}% ya matumizi).',
          ),
        ));
      }
      final incCats = byCat(today, TransactionType.income);
      if (incCats.isNotEmpty) {
        todayTiles.add((
          Icons.emoji_events_outlined,
          MjasiColors.success,
          t(
            'Top income source today: "${incCats.first.key}" ${m(incCats.first.value)}.',
            'Chanzo bora cha mapato leo: "${incCats.first.key}" ${m(incCats.first.value)}.',
          ),
        ));
      }
      final yInc = inc(yest);
      if (yInc > 0) {
        final diff = change(tInc, yInc);
        todayTiles.add((
          diff >= 0 ? Icons.north_east : Icons.south_east,
          diff >= 0 ? MjasiColors.success : MjasiColors.error,
          t(
            "Today's income is ${diff.abs()}% ${diff >= 0 ? 'higher' : 'lower'} than yesterday (${m(yInc)}).",
            'Mapato ya leo yako ${diff.abs()}% ${diff >= 0 ? 'juu' : 'chini'} kuliko jana (${m(yInc)}).',
          ),
        ));
      }
    }
    sections.add((t('Today', 'Leo'), todayTiles));

    // Last 7 days
    if (week.isNotEmpty) {
      final tiles = <_Tile>[];
      final activeDays = week
          .map((x) => DateTime(x.date.year, x.date.month, x.date.day))
          .toSet();
      tiles.add((
        Icons.date_range_outlined,
        MjasiColors.primaryBlue,
        t(
          'Last 7 days: income ${m(wInc)}, expenses ${m(wExp)}, net ${m(wInc - wExp)}. Records on ${activeDays.length} of 7 days.',
          'Siku 7 zilizopita: mapato ${m(wInc)}, matumizi ${m(wExp)}, jumla ${m(wInc - wExp)}. Umerekodi siku ${activeDays.length} kati ya 7.',
        ),
      ));
      final pwInc = inc(prevWeek);
      if (pwInc > 0) {
        final diff = change(wInc, pwInc);
        tiles.add((
          diff >= 0 ? Icons.north_east : Icons.south_east,
          diff >= 0 ? MjasiColors.success : MjasiColors.error,
          t(
            'Income is ${diff.abs()}% ${diff >= 0 ? 'up' : 'down'} compared with the previous 7 days (${m(pwInc)}).',
            'Mapato yako ${diff.abs()}% ${diff >= 0 ? 'juu' : 'chini'} ukilinganisha na siku 7 zilizotangulia (${m(pwInc)}).',
          ),
        ));
      }
      final perDay = <DateTime, double>{};
      for (final x in week.where((x) => x.type == TransactionType.income)) {
        final k = DateTime(x.date.year, x.date.month, x.date.day);
        perDay[k] = (perDay[k] ?? 0) + x.amount;
      }
      if (perDay.isNotEmpty) {
        final best = perDay.entries.reduce(
          (a, b) => a.value >= b.value ? a : b,
        );
        final name = DateFormat.EEEE(Get.locale?.toString()).format(best.key);
        tiles.add((
          Icons.star_outline,
          MjasiColors.success,
          t(
            'Best day: $name with ${m(best.value)}. Daily average income ${m(wInc / 7)}.',
            'Siku bora: $name kwa ${m(best.value)}. Wastani wa mapato kwa siku ${m(wInc / 7)}.',
          ),
        ));
      }
      sections.add((t('Last 7 days', 'Siku 7 zilizopita'), tiles));
    }

    // This month
    if (month.isNotEmpty) {
      final tiles = <_Tile>[];
      final net = mInc - mExp;
      tiles.add((
        net >= 0 ? Icons.account_balance_wallet_outlined : Icons.warning_amber,
        net >= 0 ? MjasiColors.success : MjasiColors.error,
        t(
          'This month: income ${m(mInc)}, expenses ${m(mExp)}, ${net >= 0 ? 'profit' : 'loss'} ${m(net.abs())}${mInc > 0 ? ' (margin ${(net / mInc * 100).round()}%)' : ''}.',
          'Mwezi huu: mapato ${m(mInc)}, matumizi ${m(mExp)}, ${net >= 0 ? 'faida' : 'hasara'} ${m(net.abs())}${mInc > 0 ? ' (asilimia ${(net / mInc * 100).round()}%)' : ''}.',
        ),
      ));
      final lmInc = inc(lastMonth), lmExp = exp(lastMonth);
      if (lmInc > 0) {
        final diff = change(mInc, lmInc);
        tiles.add((
          Icons.compare_arrows,
          diff >= 0 ? MjasiColors.success : MjasiColors.warning,
          t(
            'Income so far is ${diff.abs()}% ${diff >= 0 ? 'above' : 'below'} the whole of last month (${m(lmInc)}).',
            'Mapato hadi sasa ni ${diff.abs()}% ${diff >= 0 ? 'juu ya' : 'chini ya'} mwezi mzima uliopita (${m(lmInc)}).',
          ),
        ));
      }
      if (lmExp > 0 && mExp > lmExp * 1.2) {
        tiles.add((
          Icons.warning_amber,
          MjasiColors.error,
          t(
            'Expenses already exceed last month by ${change(mExp, lmExp)}%. Check where the costs are growing.',
            'Matumizi tayari yamezidi mwezi uliopita kwa ${change(mExp, lmExp)}%. Angalia gharama zinapokua.',
          ),
        ));
      }
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      if (now.day >= 5 && mInc > 0 && now.day < daysInMonth) {
        tiles.add((
          Icons.timeline,
          MjasiColors.primaryBlue,
          t(
            'At this pace, income could reach about ${m(mInc / now.day * daysInMonth)} by month end.',
            'Kwa kasi hii, mapato yanaweza kufika takriban ${m(mInc / now.day * daysInMonth)} mwisho wa mwezi.',
          ),
        ));
      }
      final cats = byCat(month, TransactionType.expense);
      if (cats.isNotEmpty && mExp > 0) {
        final top = cats
            .take(3)
            .map((e) => '${e.key} ${(e.value / mExp * 100).round()}%')
            .join(', ');
        tiles.add((
          Icons.pie_chart_outline,
          MjasiColors.warning,
          t(
            'Top expense categories: $top.',
            'Kategoria kuu za matumizi: $top.',
          ),
        ));
      }
      final incCats = byCat(month, TransactionType.income);
      if (incCats.isNotEmpty && mInc > 0) {
        final top = incCats
            .take(3)
            .map((e) => '${e.key} ${(e.value / mInc * 100).round()}%')
            .join(', ');
        tiles.add((
          Icons.emoji_events_outlined,
          MjasiColors.success,
          t('Top income sources: $top.', 'Vyanzo vikuu vya mapato: $top.'),
        ));
      }
      final shops = <String, double>{};
      for (final x in month.where((x) => x.type == TransactionType.income)) {
        final s = x.shopNickname.trim();
        if (s.isNotEmpty) shops[s] = (shops[s] ?? 0) + x.amount;
      }
      if (shops.length > 1) {
        final best = shops.entries.reduce((a, b) => a.value >= b.value ? a : b);
        tiles.add((
          Icons.storefront_outlined,
          MjasiColors.primaryBlue,
          t(
            'Best performing shop this month: ${best.key} with ${m(best.value)}.',
            'Duka linaloongoza mwezi huu: ${best.key} kwa ${m(best.value)}.',
          ),
        ));
      }
      sections.add((t('This month', 'Mwezi huu'), tiles));
    }

    // Advice
    final advice = <_Tile>[];
    if (mInc > 0 && mExp > mInc) {
      advice.add((
        Icons.report_problem_outlined,
        MjasiColors.error,
        t(
          'Expenses are higher than income this month. Cut non-essential costs and review pricing.',
          'Matumizi ni makubwa kuliko mapato mwezi huu. Punguza gharama zisizo za lazima na pitia bei zako.',
        ),
      ));
    } else if (mInc > 0 && mExp / mInc > 0.7) {
      advice.add((
        Icons.lightbulb_outline,
        MjasiColors.warning,
        t(
          'Expenses take ${(mExp / mInc * 100).round()}% of income. Aim to keep them below 70%.',
          'Matumizi yanachukua ${(mExp / mInc * 100).round()}% ya mapato. Lenga kuyaweka chini ya 70%.',
        ),
      ));
    } else if (mInc > mExp && mInc > 0) {
      advice.add((
        Icons.savings_outlined,
        MjasiColors.success,
        t(
          'Healthy margin. Set aside 10–20% of profit as savings or reinvest in stock.',
          'Faida nzuri. Weka 10–20% ya faida kama akiba au nunua bidhaa zaidi.',
        ),
      ));
    }
    final topMonthExp = byCat(month, TransactionType.expense);
    if (topMonthExp.isNotEmpty &&
        mExp > 0 &&
        topMonthExp.first.value / mExp > 0.4) {
      advice.add((
        Icons.content_cut,
        MjasiColors.warning,
        t(
          '"${topMonthExp.first.key}" is over 40% of your spending. Negotiate prices or look for cheaper options.',
          '"${topMonthExp.first.key}" inachukua zaidi ya 40% ya matumizi. Jadili bei au tafuta mbadala nafuu.',
        ),
      ));
    }
    final pwInc = inc(prevWeek);
    if (pwInc > 0 && wInc < pwInc * 0.85) {
      advice.add((
        Icons.campaign_outlined,
        MjasiColors.primaryBlue,
        t(
          'Sales dropped this week. Follow up with regular customers or run a small promotion.',
          'Mauzo yameshuka wiki hii. Wasiliana na wateja wa kawaida au fanya punguzo dogo.',
        ),
      ));
    }
    final recordedDays = week
        .map((x) => DateTime(x.date.year, x.date.month, x.date.day))
        .toSet()
        .length;
    if (recordedDays < 5) {
      advice.add((
        Icons.edit_calendar_outlined,
        MjasiColors.primaryBlue,
        t(
          'You recorded on only $recordedDays of the last 7 days. Daily records make these insights more accurate.',
          'Umerekodi siku $recordedDays tu kati ya 7. Rekodi za kila siku zinafanya ushauri huu kuwa sahihi zaidi.',
        ),
      ));
    }
    if (advice.isNotEmpty) {
      sections.add((t('Advice', 'Ushauri'), advice));
    }

    return _InsightReport(
      income: tInc,
      expense: tExp,
      hasAnyData: all.isNotEmpty,
      sections: sections,
      scope: _sw ? 'leo' : 'today',
    );
  }

  Future<_FocusData> _loadFocusData(
    String cat,
    DateTime? start,
    DateTime? end,
    bool dayMode,
  ) async {
    DateTime? from;
    if (start != null && end != null) {
      final len = end.difference(start);
      from = start.subtract(len);
      if (dayMode) {
        final week = start.subtract(const Duration(days: 7));
        if (week.isBefore(from)) from = week;
      }
    }
    final snap = await TransactionService.getTransactions(
      limit: 3000,
      startDate: from,
      endDate: end,
      category: cat,
    );
    final list = snap.docs.map((d) => d.data()).toList();
    final ids = list.map((t) => t.id).whereType<String>().toSet();
    for (final t in controller.allFetchedTransactions) {
      if (!controller.isPending(t)) continue;
      if (cat.isNotEmpty && t.category != cat) continue;
      if (from != null && t.date.isBefore(from)) continue;
      if (end != null && !t.date.isBefore(end)) continue;
      if (t.id == null || ids.add(t.id!)) list.add(t);
    }
    double? ti;
    double? te;
    if (cat.isNotEmpty) {
      try {
        final totals = await TransactionService.getTotals(
          startDate: start,
          endDate: end,
        );
        ti = totals['income'];
        te = totals['expense'];
      } catch (_) {}
    }
    return _FocusData(list, totalIncome: ti, totalExpense: te);
  }

  _InsightReport _buildFocusReport(
    _FocusData d,
    String cat,
    DateTime? start,
    DateTime? end,
    bool dayMode,
  ) {
    String t(String en, String sw) => _sw ? sw : en;
    String m(double v) => 'TSH ${TransactionsController.money(v)}';
    bool within(DateTime x, DateTime s, DateTime e) =>
        !x.isBefore(s) && x.isBefore(e);
    double sum(Iterable<TransactionModel> l, TransactionType type) =>
        l.where((x) => x.type == type).fold(0.0, (a, x) => a + x.amount);
    double inc(Iterable<TransactionModel> l) => sum(l, TransactionType.income);
    double exp(Iterable<TransactionModel> l) => sum(l, TransactionType.expense);
    int change(double now, double before) =>
        ((now - before) / before * 100).round();

    final hasRange = start != null && end != null;
    final len = hasRange ? end.difference(start) : Duration.zero;
    final cur = hasRange
        ? d.list.where((x) => within(x.date, start, end)).toList()
        : d.list;
    final prev = hasRange
        ? d.list
              .where((x) => within(x.date, start.subtract(len), start))
              .toList()
        : <TransactionModel>[];
    final last7 = dayMode && hasRange
        ? d.list
              .where(
                (x) => within(
                  x.date,
                  start.subtract(const Duration(days: 7)),
                  start,
                ),
              )
              .toList()
        : <TransactionModel>[];

    final locale = Get.locale?.toString();
    final scopeText = dayMode && hasRange
        ? DateFormat.yMMMMEEEEd(locale).format(start)
        : hasRange
        ? controller.filterTitle.value
        : t('All time', 'Muda wote');
    final title = cat.isNotEmpty
        ? '${t('Category', 'Kategoria')}: $cat'
        : t('Day analysis', 'Uchambuzi wa siku');

    final cInc = inc(cur), cExp = exp(cur);
    final sections = <(String, List<_Tile>)>[];

    if (cur.isEmpty) {
      sections.add((
        t('Summary', 'Muhtasari'),
        [
          (
            Icons.search_off,
            MjasiColors.warning,
            t(
              'No transactions found for this selection.',
              'Hakuna miamala iliyopatikana kwa uchaguzi huu.',
            ),
          ),
        ],
      ));
      return _InsightReport(
        income: 0,
        expense: 0,
        hasAnyData: true,
        sections: sections,
        focusTitle: title,
        focusSubtitle: scopeText,
      );
    }

    // Summary
    final summary = <_Tile>[];
    final net = cInc - cExp;
    final incCount = cur.where((x) => x.type == TransactionType.income).length;
    final expCount = cur.length - incCount;
    summary.add((
      net >= 0 ? Icons.trending_up : Icons.trending_down,
      net >= 0 ? MjasiColors.success : MjasiColors.error,
      t(
        '${cur.length} transactions: income ${m(cInc)} ($incCount), expenses ${m(cExp)} ($expCount). ${net >= 0 ? 'Net profit' : 'Net loss'} ${m(net.abs())}.',
        'Miamala ${cur.length}: mapato ${m(cInc)} ($incCount), matumizi ${m(cExp)} ($expCount). ${net >= 0 ? 'Faida' : 'Hasara'} ${m(net.abs())}.',
      ),
    ));
    summary.add((
      Icons.calculate_outlined,
      MjasiColors.primaryBlue,
      t(
        'Average entry ${m((cInc + cExp) / cur.length)}.',
        'Wastani wa muamala mmoja ${m((cInc + cExp) / cur.length)}.',
      ),
    ));
    final largest = cur.reduce((a, b) => a.amount >= b.amount ? a : b);
    final smallest = cur.reduce((a, b) => a.amount <= b.amount ? a : b);
    summary.add((
      Icons.swap_vert,
      MjasiColors.primaryBlue,
      t(
        'Largest: ${m(largest.amount)} (${largest.description}, ${DateFormat.MMMd(locale).format(largest.date)}). Smallest: ${m(smallest.amount)} (${smallest.description}).',
        'Kubwa zaidi: ${m(largest.amount)} (${largest.description}, ${DateFormat.MMMd(locale).format(largest.date)}). Ndogo zaidi: ${m(smallest.amount)} (${smallest.description}).',
      ),
    ));
    sections.add((t('Summary', 'Muhtasari'), summary));

    // Comparison
    final compare = <_Tile>[];
    final prevLabel = dayMode
        ? t('the previous day', 'siku iliyotangulia')
        : t('the previous period', 'kipindi kilichotangulia');
    final pInc = inc(prev), pExp = exp(prev);
    if (pInc > 0) {
      final diff = change(cInc, pInc);
      compare.add((
        diff >= 0 ? Icons.north_east : Icons.south_east,
        diff >= 0 ? MjasiColors.success : MjasiColors.error,
        t(
          'Income is ${diff.abs()}% ${diff >= 0 ? 'higher' : 'lower'} than $prevLabel (${m(pInc)}).',
          'Mapato yako ${diff.abs()}% ${diff >= 0 ? 'juu' : 'chini'} kuliko $prevLabel (${m(pInc)}).',
        ),
      ));
    }
    if (pExp > 0) {
      final diff = change(cExp, pExp);
      compare.add((
        diff <= 0 ? Icons.south_east : Icons.north_east,
        diff <= 0 ? MjasiColors.success : MjasiColors.warning,
        t(
          'Expenses are ${diff.abs()}% ${diff >= 0 ? 'higher' : 'lower'} than $prevLabel (${m(pExp)}).',
          'Matumizi yako ${diff.abs()}% ${diff >= 0 ? 'juu' : 'chini'} kuliko $prevLabel (${m(pExp)}).',
        ),
      ));
    }
    final avg7 = inc(last7) / 7;
    if (dayMode && avg7 > 0) {
      final diff = change(cInc, avg7);
      compare.add((
        Icons.stacked_line_chart,
        diff >= 0 ? MjasiColors.success : MjasiColors.warning,
        t(
          'Compared with the daily average of the previous 7 days (${m(avg7)}), this day is ${diff.abs()}% ${diff >= 0 ? 'above' : 'below'}.',
          'Ukilinganisha na wastani wa kila siku wa siku 7 zilizotangulia (${m(avg7)}), siku hii iko ${diff.abs()}% ${diff >= 0 ? 'juu' : 'chini'}.',
        ),
      ));
    }
    if (!hasRange) {
      final now = DateTime.now();
      final ms = DateTime(now.year, now.month, 1);
      final lms = DateTime(now.year, now.month - 1, 1);
      final thisM = d.list.where(
        (x) => within(x.date, ms, DateTime(now.year, now.month + 1, 1)),
      );
      final lastM = d.list.where((x) => within(x.date, lms, ms));
      final a = cat.isNotEmpty && exp(d.list) > inc(d.list)
          ? exp(thisM)
          : inc(thisM);
      final b = cat.isNotEmpty && exp(d.list) > inc(d.list)
          ? exp(lastM)
          : inc(lastM);
      if (b > 0) {
        final diff = change(a, b);
        compare.add((
          Icons.compare_arrows,
          MjasiColors.primaryBlue,
          t(
            'This month so far ${m(a)} vs last month ${m(b)} (${diff >= 0 ? '+' : ''}$diff%).',
            'Mwezi huu hadi sasa ${m(a)} dhidi ya mwezi uliopita ${m(b)} (${diff >= 0 ? '+' : ''}$diff%).',
          ),
        ));
      }
    }
    if (compare.isNotEmpty) {
      sections.add((t('Comparison', 'Ulinganisho'), compare));
    }

    // Share of total
    final share = <_Tile>[];
    if (cat.isNotEmpty) {
      final tE = d.totalExpense ?? 0, tI = d.totalIncome ?? 0;
      if (cExp > 0 && tE > 0) {
        share.add((
          Icons.donut_large,
          MjasiColors.warning,
          t(
            '"$cat" is ${(cExp / tE * 100).round()}% of all expenses in this period.',
            '"$cat" ni ${(cExp / tE * 100).round()}% ya matumizi yote ya kipindi hiki.',
          ),
        ));
      }
      if (cInc > 0 && tI > 0) {
        share.add((
          Icons.donut_large,
          MjasiColors.success,
          t(
            '"$cat" brings ${(cInc / tI * 100).round()}% of all income in this period.',
            '"$cat" inaleta ${(cInc / tI * 100).round()}% ya mapato yote ya kipindi hiki.',
          ),
        ));
      }
    }
    if (share.isNotEmpty) {
      sections.add((t('Share of total', 'Sehemu ya jumla'), share));
    }

    // Patterns
    final patterns = <_Tile>[];
    if (cur.length >= 3) {
      final hours = <int, int>{};
      for (final x in cur) {
        hours[x.date.hour] = (hours[x.date.hour] ?? 0) + 1;
      }
      final h = hours.entries.reduce((a, b) => a.value >= b.value ? a : b);
      final hh = h.key.toString().padLeft(2, '0');
      final hn = ((h.key + 1) % 24).toString().padLeft(2, '0');
      patterns.add((
        Icons.schedule,
        MjasiColors.primaryBlue,
        t(
          'Busiest time: $hh:00–$hn:00 (${h.value} entries).',
          'Muda wenye shughuli nyingi: $hh:00–$hn:00 (miamala ${h.value}).',
        ),
      ));
    }
    final spansDays = !dayMode && (!hasRange || len.inHours > 36);
    if (spansDays) {
      final perDayInc = <DateTime, double>{};
      final perDayExp = <DateTime, double>{};
      final active = <DateTime>{};
      for (final x in cur) {
        final k = DateTime(x.date.year, x.date.month, x.date.day);
        active.add(k);
        if (x.type == TransactionType.income) {
          perDayInc[k] = (perDayInc[k] ?? 0) + x.amount;
        } else {
          perDayExp[k] = (perDayExp[k] ?? 0) + x.amount;
        }
      }
      patterns.add((
        Icons.event_available_outlined,
        MjasiColors.primaryBlue,
        t(
          'Activity on ${active.length} different days.',
          'Shughuli zimetokea siku ${active.length} tofauti.',
        ),
      ));
      if (perDayInc.isNotEmpty) {
        final b = perDayInc.entries.reduce(
          (a, c) => a.value >= c.value ? a : c,
        );
        patterns.add((
          Icons.star_outline,
          MjasiColors.success,
          t(
            'Best income day: ${DateFormat.yMMMEd(locale).format(b.key)} with ${m(b.value)}.',
            'Siku bora ya mapato: ${DateFormat.yMMMEd(locale).format(b.key)} kwa ${m(b.value)}.',
          ),
        ));
      }
      if (perDayExp.isNotEmpty) {
        final b = perDayExp.entries.reduce(
          (a, c) => a.value >= c.value ? a : c,
        );
        patterns.add((
          Icons.local_fire_department_outlined,
          MjasiColors.warning,
          t(
            'Highest spending day: ${DateFormat.yMMMEd(locale).format(b.key)} with ${m(b.value)}.',
            'Siku ya matumizi makubwa: ${DateFormat.yMMMEd(locale).format(b.key)} kwa ${m(b.value)}.',
          ),
        ));
      }
    }
    final items = <String, (int, double)>{};
    for (final x in cur) {
      final key = x.description.trim().toLowerCase();
      if (key.isEmpty) continue;
      final p = items[key] ?? (0, 0.0);
      items[key] = (p.$1 + 1, p.$2 + x.amount);
    }
    if (items.length >= 2) {
      final top = items.entries.toList()
        ..sort((a, b) => b.value.$2.compareTo(a.value.$2));
      patterns.add((
        Icons.list_alt,
        MjasiColors.primaryBlue,
        t(
          'Top items: ${top.take(3).map((e) => '${e.key} (${e.value.$1}×, ${m(e.value.$2)})').join('; ')}.',
          'Vitu vikuu: ${top.take(3).map((e) => '${e.key} (${e.value.$1}×, ${m(e.value.$2)})').join('; ')}.',
        ),
      ));
    }
    if (cat.isEmpty) {
      for (final type in TransactionType.values) {
        final total = type == TransactionType.income ? cInc : cExp;
        if (total <= 0) continue;
        final map = <String, double>{};
        for (final x in cur.where((x) => x.type == type)) {
          final k = x.category.trim().isEmpty ? '-' : x.category.trim();
          map[k] = (map[k] ?? 0) + x.amount;
        }
        final top = map.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final text = top
            .take(3)
            .map((e) => '${e.key} ${(e.value / total * 100).round()}%')
            .join(', ');
        final isInc = type == TransactionType.income;
        patterns.add((
          isInc ? Icons.emoji_events_outlined : Icons.pie_chart_outline,
          isInc ? MjasiColors.success : MjasiColors.warning,
          isInc
              ? t('Income by category: $text.', 'Mapato kwa kategoria: $text.')
              : t(
                  'Spending by category: $text.',
                  'Matumizi kwa kategoria: $text.',
                ),
        ));
      }
    }
    final shops = <String, double>{};
    for (final x in cur) {
      final s = x.shopNickname.trim();
      if (s.isNotEmpty) shops[s] = (shops[s] ?? 0) + x.amount;
    }
    if (shops.length > 1) {
      final top = shops.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      patterns.add((
        Icons.storefront_outlined,
        MjasiColors.primaryBlue,
        t(
          'By shop: ${top.take(3).map((e) => '${e.key} ${m(e.value)}').join(', ')}.',
          'Kwa duka: ${top.take(3).map((e) => '${e.key} ${m(e.value)}').join(', ')}.',
        ),
      ));
    }
    if (patterns.isNotEmpty) {
      sections.add((t('Patterns', 'Mwenendo'), patterns));
    }

    // Advice
    final advice = <_Tile>[];
    if (cat.isNotEmpty && cExp > 0 && cInc == 0) {
      advice.add((
        Icons.content_cut,
        MjasiColors.warning,
        t(
          '"$cat" is a pure cost here. Compare supplier prices and check whether every spend is necessary.',
          '"$cat" ni gharama tupu hapa. Linganisha bei za wauzaji na hakikisha kila matumizi ni ya lazima.',
        ),
      ));
    }
    if (cat.isNotEmpty && cInc > 0 && cExp == 0) {
      advice.add((
        Icons.rocket_launch_outlined,
        MjasiColors.success,
        t(
          '"$cat" is generating income with no recorded cost. Make sure its costs are recorded so profit is accurate.',
          '"$cat" inaleta mapato bila gharama iliyorekodiwa. Hakikisha gharama zake zinarekodiwa ili faida iwe sahihi.',
        ),
      ));
    }
    if (pExp > 0 && cExp > pExp * 1.2) {
      advice.add((
        Icons.warning_amber,
        MjasiColors.error,
        t(
          'Spending rose by ${change(cExp, pExp)}%. Find out what drove the increase.',
          'Matumizi yameongezeka kwa ${change(cExp, pExp)}%. Chunguza nini kimesababisha ongezeko.',
        ),
      ));
    }
    if (cat.isNotEmpty &&
        (d.totalExpense ?? 0) > 0 &&
        cExp / d.totalExpense! > 0.4) {
      advice.add((
        Icons.balance,
        MjasiColors.warning,
        t(
          'This category takes over 40% of spending. Set a monthly limit for it.',
          'Kategoria hii inachukua zaidi ya 40% ya matumizi. Weka kikomo cha kila mwezi.',
        ),
      ));
    }
    if (dayMode && avg7 > 0 && cInc < avg7 * 0.7) {
      advice.add((
        Icons.campaign_outlined,
        MjasiColors.primaryBlue,
        t(
          'A slower day than usual. Check stock availability, opening hours or run a small promotion.',
          'Siku yenye mauzo madogo kuliko kawaida. Angalia upatikanaji wa bidhaa, saa za kufungua au fanya punguzo dogo.',
        ),
      ));
    }
    if (dayMode && avg7 > 0 && cInc > avg7 * 1.3) {
      advice.add((
        Icons.thumb_up_alt_outlined,
        MjasiColors.success,
        t(
          'A strong day. Note what worked (products, offers, timing) and repeat it.',
          'Siku nzuri. Andika kilichofanya kazi (bidhaa, ofa, muda) na kirudie.',
        ),
      ));
    }
    if (dayMode && net < 0) {
      advice.add((
        Icons.report_problem_outlined,
        MjasiColors.error,
        t(
          'This day closed with a loss. Review the biggest expenses and whether sales were fully recorded.',
          'Siku hii imeisha kwa hasara. Pitia matumizi makubwa na hakikisha mauzo yote yamerekodiwa.',
        ),
      ));
    }
    if (advice.isEmpty) {
      advice.add((
        Icons.check_circle_outline,
        MjasiColors.success,
        t(
          'No warning signs for this selection. Keep recording regularly.',
          'Hakuna dalili za tatizo kwa uchaguzi huu. Endelea kurekodi mara kwa mara.',
        ),
      ));
    }
    sections.add((t('Advice', 'Ushauri'), advice));

    return _InsightReport(
      income: cInc,
      expense: cExp,
      hasAnyData: true,
      sections: sections,
      focusTitle: title,
      focusSubtitle: scopeText,
    );
  }

  void _openInsights() {
    final cat = controller.selectedCategory.value;
    final dayMode = controller.filter.value == FilterPeriod.singleDay;
    final dateFilterActive = controller.filter.value != FilterPeriod.all;
    final focus = cat.isNotEmpty || dateFilterActive;
    final start = controller.startDate.value;
    final end = controller.endDate.value;
    final Future<_FocusData> future = focus
        ? _loadFocusData(cat, start, end, dayMode)
        : _loadInsightData().then(_FocusData.new);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(
            color: MjasiColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: FutureBuilder<_FocusData>(
            future: future,
            builder: (ctx, snap) {
              final Widget body;
              if (snap.connectionState != ConnectionState.done) {
                body = const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                );
              } else if (snap.hasError) {
                body = Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _sw
                        ? 'Imeshindwa kupakia data: ${snap.error}'
                        : 'Could not load data: ${snap.error}',
                    style: const TextStyle(color: MjasiColors.error),
                  ),
                );
              } else {
                final data = snap.data!;
                body = _insightBody(
                  focus
                      ? _buildFocusReport(data, cat, start, end, dayMode)
                      : _buildInsightReport(data.list),
                );
              }
              return ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: MjasiColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: MjasiColors.primaryNavy,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.auto_awesome,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _sw ? 'Uchambuzi na Ushauri' : 'Insights & Advice',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: MjasiColors.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.bar_chart_rounded),
                        tooltip: 'Analytics'.tr,
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          Get.to(() => const AnalyticsPage());
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  body,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _insightBody(_InsightReport r) {
    if (!r.hasAnyData) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _sw
              ? 'Bado hakuna miamala ya kutosha kuchambua. Anza kurekodi mapato na matumizi.'
              : 'Not enough transactions to analyse yet. Start recording income and expenses.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: MjasiColors.textSecondary),
        ),
      );
    }
    final net = r.income - r.expense;
    Widget kpi(String label, double v, Color c) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: MjasiColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MjasiColors.border),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: MjasiColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                TransactionsController.money(v),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: c,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (r.focusTitle != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [MjasiColors.primaryNavy, MjasiColors.primaryBlue],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.focusTitle!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (r.focusSubtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    r.focusSubtitle!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        Row(
          children: [
            kpi(
              '${_sw ? 'Mapato' : 'Income'} ${r.scope}'.trim(),
              r.income,
              MjasiColors.success,
            ),
            const SizedBox(width: 8),
            kpi(
              '${_sw ? 'Matumizi' : 'Expenses'} ${r.scope}'.trim(),
              r.expense,
              MjasiColors.error,
            ),
            const SizedBox(width: 8),
            kpi(
              _sw ? 'Jumla' : 'Net',
              net,
              net >= 0 ? MjasiColors.success : MjasiColors.error,
            ),
          ],
        ),
        for (final section in r.sections) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
            child: Text(
              section.$1.toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: MjasiColors.textSecondary,
              ),
            ),
          ),
          for (final it in section.$2)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MjasiColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MjasiColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: it.$2.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(it.$1, color: it.$2, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      it.$3,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: MjasiColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildSpeedDialFab() {
    return SpeedDial(
      icon: Icons.add,
      activeIcon: Icons.close,
      backgroundColor: MjasiColors.primaryBlue,
      foregroundColor: Colors.white,
      overlayColor: Colors.black,
      overlayOpacity: 0.4,
      spacing: 12,
      children: _getSpeedDialChildren(),
    );
  }

  List<SpeedDialChild> _getSpeedDialChildren() {
    return [
      SpeedDialChild(
        child: const Icon(Icons.arrow_downward, color: Colors.white),
        backgroundColor: MjasiColors.error,
        label: 'expense'.tr,
        onTap: () async {
          final result = await Get.to(
            () =>
                const AddTransactionPage(initialType: TransactionType.expense),
          );
          if (result == true) controller.fetchFirstPage();
        },
      ),
      SpeedDialChild(
        child: const Icon(Icons.arrow_upward, color: Colors.white),
        backgroundColor: MjasiColors.success,
        label: 'income'.tr,
        onTap: () async {
          final result = await Get.to(
            () => const AddTransactionPage(initialType: TransactionType.income),
          );
          if (result == true) controller.fetchFirstPage();
        },
      ),
    ];
  }

  Widget _buildSummaryRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use a Column layout on narrow screens
        final incomeCard = Obx(
          () => _SummaryCard(
            title: 'income'.tr,
            value:
                'TSH ${TransactionsController.money(controller.currentIncome.value)}',
            accent: MjasiColors.success,
            isSelected: controller.summaryFilter.value == SummaryFilter.income,
            onTap: () => controller.setSummaryFilter(SummaryFilter.income),
          ),
        );

        final expenseCard = Obx(
          () => _SummaryCard(
            title: 'expenses'.tr,
            value:
                'TSH ${TransactionsController.money(controller.currentExpense.value)}',
            accent: MjasiColors.error,
            isSelected: controller.summaryFilter.value == SummaryFilter.expense,
            onTap: () => controller.setSummaryFilter(SummaryFilter.expense),
          ),
        );

        final netCard = Obx(() {
          final netValue = controller.currentNet.value;
          final netString =
              'TSH ${TransactionsController.money(netValue.abs())}';
          return _SummaryCard(
            title: 'net'.tr,
            value: (netValue >= 0 ? '' : '-') + netString,
            accent: netValue >= 0 ? MjasiColors.success : MjasiColors.warning,
            currentNet: netValue,
            isSelected: controller.summaryFilter.value == SummaryFilter.all,
            onTap: () => controller.setSummaryFilter(SummaryFilter.all),
          );
        });

        // Always one compact row of three cards.
        return Row(
          children: [
            Expanded(child: incomeCard),
            const SizedBox(width: 6),
            Expanded(child: expenseCard),
            const SizedBox(width: 6),
            Expanded(child: netCard),
          ],
        );
      },
    );
  }

  Widget _buildTransactionCard(TransactionModel t, int index) {
    final isExpense = t.type == TransactionType.expense;
    final accent = isExpense ? MjasiColors.error : MjasiColors.success;

    // Dismissible for swipe-to-delete with undo
    return Dismissible(
      // Keep Dismissible for swipe actions
      key: ValueKey(t.id ?? index),
      direction: DismissDirection.horizontal,
      background: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
        ), // No tr needed for widgets
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: MjasiColors.primaryBlue,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.edit, color: Colors.white),
      ),
      secondaryBackground: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
        ), // No tr needed for widgets
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: MjasiColors.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Edit action
          final result = await Get.to(() => AddTransactionPage(transaction: t));
          // Only refresh if the transaction was actually saved.
          if (result == true) controller.fetchFirstPage();
          return false; // Do not dismiss the item
        } else {
          // Delete action
          return await controller.confirmDelete(t);
        }
      },
      child: Card(
        // REDESIGN: Cleaner card with no border
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: MjasiColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => controller.showActions(t),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                // REDESIGN: Avatar with icon
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isExpense ? Icons.trending_down : Icons.trending_up,
                    color: accent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.description,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => controller.setCategoryFilter(
                            controller.selectedCategory.value == t.category
                                ? ''
                                : t.category,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: MjasiColors.primaryBlue.withValues(
                                alpha: 0.08,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.sell_outlined,
                                  size: 12,
                                  color: MjasiColors.primaryBlue,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    t.category,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: MjasiColors.primaryBlue,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${'transactions_shop'.tr}: ${t.shopNickname.isEmpty ? 'transactions_shop_not_recorded'.tr : t.shopNickname}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      if (controller.isPending(t)) ...[
                        const SizedBox(height: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'transaction_sync_pending'.tr,
                            style: TextStyle(
                              color: Colors.orange.shade800,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isExpense ? '-' : '+'}TSH ${TransactionsController.money(t.amount)}',
                      style: TextStyle(
                        // Bolder amount
                        color: accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      DateFormat.jm().format(t.date), // e.g., "5:08 PM"
                      style: const TextStyle(
                        color: MjasiColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
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
  }

  Widget _buildSliverAppBar(BuildContext context) {
    // Make the expanded height adaptive to the screen size.
    // Calculate height based on content.
    // Card height is roughly 100px (16*2 padding + content).
    // Title + padding + summary row(s).
    // One compact row of cards (~64px) plus title and spacing.
    const summaryHeight = 68.0;
    final topContentHeight =
        14.0 + 12.0 + summaryHeight; // Title + spacing + summary
    final totalPadding =
        MediaQuery.of(context).padding.top +
        kToolbarHeight +
        8.0; // Top and bottom padding
    final adaptiveHeight = totalPadding + topContentHeight;

    return Obx(
      () => SliverAppBar(
        pinned: true,
        floating: true,
        snap: true,
        expandedHeight: adaptiveHeight,
        elevation: 1,
        backgroundColor: MjasiColors.primaryBlue,
        foregroundColor: Colors.white,
        title: controller.isSearching.value
            // NEW: Animated search bar transition
            ? Hero(
                tag: 'search_field',
                child: TextField(
                  controller: controller.searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: '${'search'.tr}...',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                    border: InputBorder.none,
                  ),
                ),
              )
            : Text('transactions_title'.tr), // No tr needed for variables
        actions: _buildAppBarActions(),
        flexibleSpace: FlexibleSpaceBar(
          background: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [MjasiColors.primaryNavy, MjasiColors.primaryBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    // Use MediaQuery to get status bar height + toolbar height for accurate top padding
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + kToolbarHeight,
                      left: 16,
                      right: 16,
                      bottom: 8, // Add some bottom padding
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            controller.filterTitle.value,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildSummaryRow(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // NEW: Show a "Clear Filter" button when a single day is selected.
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildAppBarActions() {
    return [
      // Show a compact clear action in the toolbar when single-day filter is active
      if (controller.filter.value == FilterPeriod.singleDay &&
          !controller.isSearching.value)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: TextButton.icon(
            onPressed: controller.clearSingleDayFilter,
            icon: const Icon(Icons.close, color: Colors.white, size: 18),
            label: Text(
              'clear'.tr,
              style: const TextStyle(color: Colors.white),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      IconButton(
        tooltip: 'search'.tr,
        onPressed: controller.toggleSearch,
        icon: Hero(
          tag: 'search_icon',
          child: Icon(
            controller.isSearching.value ? Icons.close : Icons.search,
          ),
        ),
      ),
      if (!controller.isSearching.value)
        PopupMenuButton<SortOption>(
          tooltip: 'Sort by'.tr,
          icon: const Icon(Icons.sort),
          onSelected: controller.setSortOption,
          itemBuilder: (context) => [
            PopupMenuItem(
              enabled: false,
              child: Text(
                'Sort by'.tr,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            CheckedPopupMenuItem(
              value: SortOption.dateDesc,
              checked: controller.sortOption.value == SortOption.dateDesc,
              child: Text('Date (Newest First)'.tr),
            ),
            CheckedPopupMenuItem(
              value: SortOption.dateAsc,
              checked: controller.sortOption.value == SortOption.dateAsc,
              child: Text('Date (Oldest First)'.tr),
            ),
            CheckedPopupMenuItem(
              value: SortOption.amountDesc,
              checked: controller.sortOption.value == SortOption.amountDesc,
              child: Text('Amount (Highest First)'.tr),
            ),
            CheckedPopupMenuItem(
              value: SortOption.amountAsc,
              checked: controller.sortOption.value == SortOption.amountAsc,
              child: Text('Amount (Lowest First)'.tr),
            ),
          ],
        ),
      if (!controller.isSearching.value)
        IconButton(
          tooltip: 'transactions_export_pdf'.tr,
          onPressed:
              controller.transactions.isEmpty || controller.isPdfBusy.value
              ? null
              : controller.exportPdf,
          icon: controller.isPdfBusy.value
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ), // No tr needed for widgets
                )
              : const Icon(Icons.picture_as_pdf_outlined),
        ),
      if (!controller.isSearching.value)
        IconButton(
          tooltip: 'Export as Excel'.tr,
          onPressed:
              controller.transactions.isEmpty || controller.isExcelBusy.value
              ? null
              : controller.exportExcel,
          icon: controller.isExcelBusy.value
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ) // No tr needed for widgets
              : const Icon(Icons.table_chart_outlined),
        ),
      if (!controller.isSearching.value)
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'refresh') controller.fetchFirstPage();
            if (v == 'clear_filters') controller.setFilter(FilterPeriod.all);
            if (v == 'export_excel') controller.exportExcel();
            if (v == 'export_pdf') controller.exportPdf();
            if (v == 'analytics') {
              Get.to(() => const AnalyticsPage());
            }
          }, // No tr needed for logic
          itemBuilder: (context) => [
            PopupMenuItem(value: 'refresh', child: Text('refresh'.tr)),
            PopupMenuItem(
              value: 'clear_filters',
              child: Text('transactions_clear_filters'.tr),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'export_pdf',
              child: Row(
                children: [
                  const Icon(
                    Icons.picture_as_pdf_outlined,
                    size: 20,
                  ), // No tr needed for widgets
                  const SizedBox(width: 8), // No tr needed for widgets
                  Text('Export PDF'.tr),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'export_excel',
              child: Row(
                children: [
                  const Icon(Icons.table_chart_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text('Export Excel'.tr),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'analytics',
              child: Row(
                children: [
                  const Icon(Icons.analytics_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text('Analytics'.tr),
                ],
              ),
            ),
          ],
        ),
    ];
  }

  Widget _buildFilterChipsSliver() {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _SliverFilterChipsDelegate(
        minHeight: 112,
        maxHeight: 112,
        child: Obx(
          () => Container(
            color: MjasiColors.primaryBlue, // Match app bar color
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            alignment: Alignment.centerLeft,
            child: _buildFilterChipsPanel(),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChipsPanel() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            if (BusinessAccessService.isOwner.value) ...[
              Expanded(
                child: _buildSelectionFilter(
                  title: 'transactions_filter_shop'.tr,
                  value: controller.selectedShopNickname.value.isEmpty
                      ? 'transactions_all_shops'.tr
                      : controller.selectedShopNickname.value,
                  icon: Icons.storefront_outlined,
                  items: [
                    ('', 'transactions_all_shops'.tr),
                    for (final shop in controller.availableShopNames)
                      (shop, shop),
                  ],
                  onSelected: controller.setShopFilter,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: _buildSelectionFilter(
                title: 'transactions_filter_category'.tr,
                value: controller.selectedCategory.value.isEmpty
                    ? 'transactions_all_categories'.tr
                    : controller.selectedCategory.value,
                icon: Icons.category_outlined,
                items: [
                  ('', 'transactions_all_categories'.tr),
                  for (final category in controller.availableCategories)
                    (category, category),
                ],
                onSelected: controller.setCategoryFilter,
                onTap: _openCategorySearch,
                onClear: controller.selectedCategory.value.isEmpty
                    ? null
                    : () => controller.setCategoryFilter(''),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip(FilterPeriod.all, 'transactions_all_time'.tr),
              const SizedBox(width: 8),
              _buildFilterChip(FilterPeriod.today, 'transactions_today'.tr),
              const SizedBox(width: 8),
              _buildFilterChip(FilterPeriod.yesterday, 'yesterday'.tr),
              const SizedBox(width: 8),
              _buildFilterChip(FilterPeriod.week, 'transactions_this_week'.tr),
              const SizedBox(width: 8),
              _buildFilterChip(
                FilterPeriod.month,
                'transactions_this_month'.tr,
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                FilterPeriod.custom,
                'transactions_custom_range'.tr,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionFilter({
    required String title,
    required String value,
    required IconData icon,
    required List<(String, String)> items,
    required ValueChanged<String> onSelected,
    VoidCallback? onTap,
    VoidCallback? onClear,
  }) {
    if (onTap != null) {
      return Tooltip(
        message: title,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: _selectionFilterBox(icon, value, onClear: onClear),
        ),
      );
    }
    return PopupMenuButton<String>(
      tooltip: title,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final item in items)
          PopupMenuItem(value: item.$1, child: Text(item.$2)),
      ],
      child: _selectionFilterBox(icon, value),
    );
  }

  Widget _selectionFilterBox(
    IconData icon,
    String value, {
    VoidCallback? onClear,
  }) {
    return Builder(
      builder: (context) => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (onClear != null)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, color: Colors.white, size: 18),
                ),
              )
            else
              const Icon(Icons.arrow_drop_down, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionListSliver() {
    return Obx(
      () => SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          120,
        ), // More bottom padding for FAB
        sliver: controller.isFetching.value && controller.transactions.isEmpty
            ? const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            : controller.transactions.isEmpty
            ? SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 60,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        controller.searchController.text.isNotEmpty
                            ? '${'transactions_no_transactions'.tr} for "${controller.searchController.text}"'
                            : 'transactions_no_transactions'.tr,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : SliverMainAxisGroup(
                slivers: controller.groupedTransactions.entries.map((entry) {
                  final date = entry.key;
                  final transactionsInGroup = entry.value;
                  return _TransactionGroup(
                    onHeaderTap: () => controller.filterBySingleDay(date),
                    header: TransactionsController.formatDateHeader(date),
                    children: transactionsInGroup
                        .map(
                          (t) => _buildTransactionCard(
                            t,
                            controller.allFetchedTransactions.indexOf(t),
                          ),
                        )
                        .toList(),
                  );
                }).toList(),
              ),
      ),
    );
  }

  Widget _buildFilterChip(FilterPeriod p, String label) {
    final selected = controller.filter.value == p;
    return ChoiceChip(
      avatar: selected
          ? const Icon(
              Icons.check_rounded,
              size: 15,
              color: MjasiColors.primaryNavy,
            )
          : null,
      label: Text(label, maxLines: 1, softWrap: false),
      labelStyle: TextStyle(
        color: selected ? MjasiColors.primaryNavy : Colors.white,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        fontSize: 12.5,
      ),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => controller.setFilter(p),
      selectedColor: Colors.white,
      backgroundColor: MjasiColors.primaryNavy,
      side: BorderSide(
        color: selected ? MjasiColors.success : MjasiColors.primaryNavy,
        width: selected ? 1.5 : 1,
      ),
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}

// NEW: A custom Sliver widget to group a header and a list of children.
class _TransactionGroup extends StatelessWidget {
  // Can be used for both sliver and non-sliver lists
  final String header;
  final List<Widget> children;
  final VoidCallback onHeaderTap;

  const _TransactionGroup({
    required this.header,
    required this.children,
    required this.onHeaderTap,
  });

  @override
  Widget build(BuildContext context) {
    // If the parent is a regular ListView, use a Column.
    // If it's a CustomScrollView, use SliverMainAxisGroup.
    final isSliver =
        context.findAncestorWidgetOfExactType<CustomScrollView>() != null;

    final headerWidget = InkWell(
      onTap: onHeaderTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(
          header,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.grey.shade700,
          ),
        ),
      ),
    );

    if (!isSliver) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [headerWidget, ...children],
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverPersistentHeader(
          pinned: false, // Keep headers from sticking
          delegate: _SliverHeaderDelegate(
            child: InkWell(
              onTap: onHeaderTap,
              child: Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 8),
                child: Text(
                  header,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => children[index],
            childCount: children.length,
          ),
        ),
      ],
    );
  }
}

/// A delegate for creating a persistent header for the filter chips.
class _SliverFilterChipsDelegate extends SliverPersistentHeaderDelegate {
  _SliverFilterChipsDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });

  final double minHeight;
  final double maxHeight;
  final Widget child;

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => (minHeight > maxHeight) ? minHeight : maxHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(_SliverFilterChipsDelegate oldDelegate) {
    return maxHeight != oldDelegate.maxHeight ||
        minHeight != oldDelegate.minHeight ||
        child != oldDelegate.child;
  }
}

// NEW: A simple delegate for the date group headers.
class _SliverHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _SliverHeaderDelegate({required this.child});

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  double get maxExtent => 50;

  @override
  double get minExtent => 50;

  @override
  bool shouldRebuild(covariant _SliverHeaderDelegate oldDelegate) {
    return child != oldDelegate.child;
  }
}

/// Compact solid-colour summary card. Selection is shown with a deeper fill.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.accent,
    required this.isSelected,
    required this.onTap,
    this.currentNet = 0,
  });

  final String title;
  final String value;
  final Color accent;
  final bool isSelected;
  final VoidCallback onTap;
  final double currentNet;

  @override
  Widget build(BuildContext context) {
    final isNetCard = title == 'net'.tr;
    final isIncome = title == 'income'.tr;

    final List<Color> fill = isNetCard
        ? (currentNet >= 0
              ? isSelected
                    ? const [Color(0xFF0D2A4A), Color(0xFF124F9C)]
                    : const [MjasiColors.primaryBlue, MjasiColors.secondaryBlue]
              : isSelected
              ? const [Color(0xFF8A3D08), Color(0xFFC66A12)]
              : const [Color(0xFFCB7A22), Color(0xFFE59A45)])
        : isIncome
        ? (isSelected
              ? const [Color(0xFF075C45), Color(0xFF087A58)]
              : const [Color(0xFF138365), Color(0xFF1FA67F)])
        : (isSelected
              ? const [Color(0xFF8F2638), Color(0xFFB73548)]
              : const [Color(0xFFC64F5D), Color(0xFFE06B79)]);

    final icon = isNetCard
        ? (currentNet >= 0 ? Icons.trending_up : Icons.trending_down)
        : (isIncome
              ? Icons.arrow_upward_rounded
              : Icons.arrow_downward_rounded);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: fill,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
