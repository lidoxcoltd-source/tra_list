import 'package:flutter/material.dart';
import 'package:tra_list/jobs/controllers/debt_controller.dart';

enum FinancePeriod { today, yesterday, thisWeek, thisMonth, customDay }

enum HomeDestination { dashboard, explore, reports, chat }

class StaffStat {
  StaffStat(this.name, {this.uid = '', this.photoUrl = ''});
  final String uid;
  final String name;
  final String photoUrl;
  double income = 0;
  double expense = 0;
  int count = 0;
  double sales = 0;
  int saleCount = 0;
  double unitsSold = 0;
}

class BusinessRecommendation {
  const BusinessRecommendation({
    required this.titleKey,
    required this.descriptionKey,
    required this.icon,
    required this.color,
  });

  final String titleKey;
  final String descriptionKey;
  final IconData icon;
  final Color color;
}

class DebtMetric {
  const DebtMetric(
    this.label,
    this.value,
    this.icon,
    this.color,
    this.background,
    this.filter,
  );

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;
  final DebtFilter filter;
}
