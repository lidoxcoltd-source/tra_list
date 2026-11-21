import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/ai_models_ui.dart';
import 'package:tra_list/theme/app_theme.dart';
import 'daily_business_brief_service.dart';
import 'daily_brief_route_observer.dart';
import 'daily_brief_weather_service.dart';
import 'stock_models.dart';
import 'stock_ui.dart';

class DailyBusinessBriefCard extends StatefulWidget {
  const DailyBusinessBriefCard({super.key});

  @override
  State<DailyBusinessBriefCard> createState() => _DailyBusinessBriefCardState();
}

class _DailyBusinessBriefCardState extends State<DailyBusinessBriefCard>
    with RouteAware {
  final _service = DailyBusinessBriefService();
  final _weatherService = DailyBriefWeatherService();
  DailyBusinessBrief? _brief;
  DailyBriefWeather? _weather;
  Object? _weatherError;
  Object? _error;
  bool _loading = true;
  int _request = 0;
  PageRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _generate();
    });
  }

  @override
  void dispose() {
    _request++;
    dailyBriefRouteObserver.unsubscribe(this);
    _weatherService.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is! PageRoute<dynamic> || route == _route) return;
    if (_route != null) dailyBriefRouteObserver.unsubscribe(this);
    _route = route;
    dailyBriefRouteObserver.subscribe(this, route);
  }

  @override
  void didPopNext() {
    unawaited(_generate());
  }

  Future<void> _generate() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });

    DailyBriefWeather? weather;
    Object? weatherError;
    try {
      weather = await _weatherService.fetch();
    } catch (error) {
      weatherError = error;
      debugPrint('Daily brief weather unavailable: $error');
    }
    if (!mounted || request != _request) return;
    setState(() {
      _weather = weather;
      _weatherError = weatherError;
    });

    try {
      final result = await _service.generate(
        now: DateTime.now(),
        language: Get.locale?.languageCode == 'sw' ? 'sw' : 'en',
        weather: weather,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _brief = result;
        _loading = false;
        _error = null;
      });
    } catch (error, stackTrace) {
      debugPrint('Daily business brief failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => StockCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: kStockLight,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: kStockBlue,
                size: 21,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'stk_daily_brief'.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MjasiColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    _timeLabel(DateTime.now()),
                    style: const TextStyle(
                      color: MjasiColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            AiModelPickerButton(onModelSelected: _generate),
            IconButton(
              tooltip: 'stk_daily_brief_retry'.tr,
              onPressed: _loading ? null : _generate,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_weather != null) _weatherSummary(_weather!),
        if (_weatherError != null) _weatherUnavailable(_weatherError!),
        if (_weather != null || _weatherError != null)
          const SizedBox(height: 10),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: SizedBox(
                width: 23,
                height: 23,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          )
        else if (_error != null)
          _errorMessage()
        else if (_brief != null) ...[
          _facts(_brief!.facts),
          const SizedBox(height: 10),
          Text(
            _brief!.answer,
            style: const TextStyle(
              color: MjasiColors.textPrimary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ],
    ),
  );

  String _timeLabel(DateTime now) {
    final key = switch (now.hour) {
      >= 5 && < 12 => 'stk_day_morning',
      >= 12 && < 17 => 'stk_day_afternoon',
      _ => 'stk_day_evening',
    };
    return key.tr;
  }

  Widget _weatherSummary(DailyBriefWeather weather) {
    final language = Get.locale?.languageCode ?? 'en';
    final tips = weather.practicalTips(language);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFDCEBFA)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.wb_cloudy_outlined,
            color: kStockBlue,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${'stk_daily_brief_weather'.tr} · ${weather.conditionLabel(language)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MjasiColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  weather.explanation(language),
                  style: const TextStyle(
                    color: MjasiColors.textSecondary,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
                Text(
                  'stk_weather_actions'.tr,
                  style: const TextStyle(
                    color: MjasiColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                for (final tip in tips)
                  Text(
                    tip,
                    style: const TextStyle(
                      color: kStockNavy,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _weatherUnavailable(Object error) {
    final code = error is DailyBriefWeatherException
        ? error.code.split(':').first
        : 'weather_unavailable';
    final message = switch (code) {
      'location_services_off' => 'stk_weather_location_off'.tr,
      'location_permission_settings' => 'stk_weather_permission_settings'.tr,
      'location_permission_denied' => 'stk_weather_permission_denied'.tr,
      _ => 'stk_weather_unavailable'.tr,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: MjasiColors.warningBackground,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: kStockWarn, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: MjasiColors.textPrimary,
                fontSize: 11,
              ),
            ),
          ),
          if (code == 'location_permission_settings')
            IconButton(
              tooltip: 'stk_weather_open_settings'.tr,
              onPressed: () async {
                await _weatherService.openAppSettings();
              },
              icon: const Icon(Icons.settings_outlined, size: 18),
            )
          else if (code == 'location_services_off')
            IconButton(
              tooltip: 'stk_weather_open_settings'.tr,
              onPressed: () async {
                await _weatherService.openLocationSettings();
              },
              icon: const Icon(Icons.settings_outlined, size: 18),
            ),
        ],
      ),
    );
  }

  Widget _facts(Map<String, dynamic> facts) {
    final overdueDebts = _integer(facts['overdueDebtCount']);
    final dueDebts = _integer(facts['debtsDueTodayCount']);
    final overdueTasks = _integer(facts['overdueTaskCount']);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 7.0;
        final width = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            _metric(
              width,
              'stk_daily_brief_income'.tr,
              'TZS ${formatMoney(_number(facts['income']))}',
              kStockOk,
            ),
            _metric(
              width,
              'stk_daily_brief_expenses'.tr,
              'TZS ${formatMoney(_number(facts['expenses']))}',
              kStockWarn,
            ),
            _metric(
              width,
              'stk_daily_brief_debts'.tr,
              '$overdueDebts / $dueDebts',
              overdueDebts > 0 ? kStockBad : kStockBlue,
            ),
            _metric(
              width,
              'stk_daily_brief_stock_tasks'.tr,
              '${_integer(facts['stockIssueCount'])} / ${_integer(facts['openTaskCount'])}',
              _integer(facts['stockIssueCount']) > 0 || overdueTasks > 0
                  ? kStockWarn
                  : kStockOk,
            ),
          ],
        );
      },
    );
  }

  Widget _metric(double width, String label, String value, Color color) =>
      SizedBox(
        width: width,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MjasiColors.textSecondary,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _errorMessage() => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: MjasiColors.errorBackground,
      borderRadius: BorderRadius.circular(11),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: kStockBad, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'stk_daily_brief_error'.tr,
            style: const TextStyle(
              color: MjasiColors.textPrimary,
              fontSize: 12,
            ),
          ),
        ),
        TextButton(
          onPressed: _generate,
          child: Text('stk_daily_brief_retry'.tr),
        ),
      ],
    ),
  );

  static double _number(dynamic value) =>
      value is num && value.isFinite ? value.toDouble() : 0;

  static int _integer(dynamic value) =>
      value is num && value.isFinite ? value.toInt() : 0;
}
