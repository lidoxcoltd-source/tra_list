import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/home/models/home_models.dart';
import 'package:tra_list/jobs/controllers/debt_controller.dart';
import 'package:tra_list/theme/app_theme.dart';

class HomeDebtMetrics extends StatelessWidget {
  const HomeDebtMetrics({
    super.key,
    required this.debts,
    required this.wide,
    required this.onTapFilter,
  });

  final DebtController debts;
  final bool wide;
  final ValueChanged<DebtFilter> onTapFilter;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final metrics = [
        DebtMetric(
          'home_debt_receivable'.tr,
          'TZS ${debts.receivableBalance.toStringAsFixed(0)}',
          Icons.call_received_rounded,
          MjasiColors.success,
          MjasiColors.successBackground,
          DebtFilter.customerOwesShop,
        ),
        DebtMetric(
          'home_debt_payable'.tr,
          'TZS ${debts.payableBalance.toStringAsFixed(0)}',
          Icons.call_made_rounded,
          MjasiColors.warning,
          MjasiColors.warningBackground,
          DebtFilter.shopOwesOther,
        ),
        DebtMetric(
          'debt_overdue'.tr,
          debts.overdueCount.toString(),
          Icons.event_busy_outlined,
          MjasiColors.error,
          MjasiColors.errorBackground,
          DebtFilter.overdue,
        ),
      ];
      return LayoutBuilder(
        builder: (context, constraints) {
          const spacing = MjasiSpacing.sm;
          return Row(
            children: [
              for (var i = 0; i < metrics.length; i++) ...[
                if (i > 0) const SizedBox(width: spacing),
                Expanded(
                  child: HomeDebtMetricCard(
                    metric: metrics[i],
                    wide: wide,
                    compact: constraints.maxWidth < 500,
                    onTap: () => onTapFilter(metrics[i].filter),
                  ),
                ),
              ],
            ],
          );
        },
      );
    });
  }
}

class HomeDebtMetricCard extends StatelessWidget {
  const HomeDebtMetricCard({
    super.key,
    required this.metric,
    this.wide = false,
    this.compact = false,
    required this.onTap,
  });

  final DebtMetric metric;
  final bool wide;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: metric.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MjasiRadius.md),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MjasiRadius.md),
        child: Padding(
          padding: EdgeInsets.all(compact ? 8 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: compact
                        ? 24
                        : wide
                        ? 34
                        : 28,
                    height: compact
                        ? 24
                        : wide
                        ? 34
                        : 28,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .78),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      metric.icon,
                      size: compact
                          ? 13
                          : wide
                          ? 17
                          : 14,
                      color: metric.color,
                    ),
                  ),
                  const SizedBox(width: MjasiSpacing.xs),
                  Expanded(
                    child: Text(
                      metric.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: MjasiColors.textPrimary,
                        fontSize: compact
                            ? 9
                            : wide
                            ? 11.5
                            : 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: compact
                    ? 3
                    : wide
                    ? 10
                    : 6,
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  metric.value,
                  style: TextStyle(
                    color: metric.color,
                    fontSize: compact
                        ? 13
                        : wide
                        ? 19
                        : 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.35,
                    fontFeatures: const [FontFeature.tabularFigures()],
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
