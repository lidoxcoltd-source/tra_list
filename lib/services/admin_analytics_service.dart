import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'super_admin_subscription_service.dart';

class BusinessRecord {
  const BusinessRecord({
    required this.businessId,
    required this.name,
    required this.email,
    required this.createdAt,
    required this.startDate,
    required this.expiry,
    required this.planAmount,
    required this.planDays,
    required this.trialActive,
    required this.disabled,
  });

  final String businessId;
  final String name;
  final String email;
  final DateTime? createdAt;
  final DateTime? startDate;
  final DateTime? expiry;
  final double planAmount;
  final int planDays;
  final bool trialActive;
  final bool disabled;

  bool isActive(DateTime now) => expiry != null && expiry!.isAfter(now);
  bool get everSubscribed => startDate != null || expiry != null;
  String get label =>
      name.isNotEmpty ? name : (email.isNotEmpty ? email : businessId);
}

class MonthBucket {
  MonthBucket(this.month);

  final DateTime month;
  int signups = 0;
  int subscriptions = 0;
  double revenue = 0;
}

class AdminAnalytics {
  AdminAnalytics._(this.records, this.planAmount, this.planDays, this.now);

  final List<BusinessRecord> records;
  final double planAmount;
  final int planDays;
  final DateTime now;

  factory AdminAnalytics.from(
    List<BusinessRecord> records,
    SubscriptionPlanSettings plan, {
    DateTime? now,
  }) => AdminAnalytics._(
    records,
    plan.amount.toDouble(),
    plan.durationDays,
    now ?? DateTime.now(),
  );

  int get total => records.length;
  int get active => records.where((r) => r.isActive(now)).length;
  int get trials =>
      records.where((r) => !r.isActive(now) && r.trialActive).length;
  int get expired =>
      records.where((r) => r.everSubscribed && !r.isActive(now)).length;
  int get neverPaid =>
      records.where((r) => !r.everSubscribed && !r.trialActive).length;
  int get disabled => records.where((r) => r.disabled).length;
  int get expiringSoon => records
      .where(
        (r) =>
            r.isActive(now) &&
            r.expiry!.isBefore(now.add(const Duration(days: 30))),
      )
      .length;
  int get newThisMonth => records
      .where(
        (r) =>
            r.createdAt != null &&
            r.createdAt!.year == now.year &&
            r.createdAt!.month == now.month,
      )
      .length;

  double _amountOf(BusinessRecord r) =>
      r.planAmount > 0 ? r.planAmount : planAmount;
  int _daysOf(BusinessRecord r) => r.planDays > 0 ? r.planDays : planDays;

  /// Sum of the latest plan price of every business that has ever subscribed.
  /// There is no payment ledger, so renewals before the latest one are not
  /// included.
  double get totalRevenue => records
      .where((r) => r.everSubscribed)
      .fold(0.0, (total, r) => total + _amountOf(r));

  /// Monthly recurring revenue from active subscriptions.
  double get monthlyRecurring => records
      .where((r) => r.isActive(now))
      .fold(0.0, (total, r) => total + _amountOf(r) / _daysOf(r) * 30);

  double get annualRecurring => monthlyRecurring * 12;

  /// Value of subscriptions that expire within 30 days and need renewing.
  double get renewalsAtRisk => records
      .where(
        (r) =>
            r.isActive(now) &&
            r.expiry!.isBefore(now.add(const Duration(days: 30))),
      )
      .fold(0.0, (total, r) => total + _amountOf(r));

  double get conversionRate =>
      total == 0 ? 0 : records.where((r) => r.everSubscribed).length / total;

  double get averageRevenuePerSubscriber {
    final paying = records.where((r) => r.everSubscribed).length;
    return paying == 0 ? 0 : totalRevenue / paying;
  }

  List<MonthBucket> months([int count = 6]) {
    final buckets = [
      for (var i = count - 1; i >= 0; i--)
        MonthBucket(DateTime(now.year, now.month - i)),
    ];
    MonthBucket? find(DateTime? date) {
      if (date == null) return null;
      for (final b in buckets) {
        if (b.month.year == date.year && b.month.month == date.month) return b;
      }
      return null;
    }

    for (final r in records) {
      find(r.createdAt)?.signups++;
      final bucket = find(r.startDate);
      if (bucket != null) {
        bucket.subscriptions++;
        bucket.revenue += _amountOf(r);
      }
    }
    return buckets;
  }

  List<BusinessRecord> get recentSignups {
    final list = records.where((r) => r.createdAt != null).toList()
      ..sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
    return list.take(8).toList();
  }

  List<BusinessRecord> get nextExpiries {
    final list = records.where((r) => r.isActive(now)).toList()
      ..sort((a, b) => a.expiry!.compareTo(b.expiry!));
    return list.take(8).toList();
  }
}

class UsageStats {
  UsageStats(this.entries, this.now);

  final List<ActivityEntry> entries;
  final DateTime now;

  int _within(Duration d) => entries
      .where(
        (e) => e.lastActiveAt != null && now.difference(e.lastActiveAt!) <= d,
      )
      .length;

  int get everUsed => entries.length;
  int get onlineNow => _within(const Duration(minutes: 5));
  int get today => _within(const Duration(hours: 24));
  int get week => _within(const Duration(days: 7));
  int get month => _within(const Duration(days: 30));
  int get totalOpens => entries.fold(0, (a, e) => a + e.opens);
  int get newThisWeek => entries
      .where(
        (e) =>
            e.firstSeenAt != null &&
            now.difference(e.firstSeenAt!) <= const Duration(days: 7),
      )
      .length;

  Map<String, int> get byPlatform {
    final map = <String, int>{};
    for (final e in entries) {
      if (e.lastActiveAt != null &&
          now.difference(e.lastActiveAt!) <= const Duration(days: 30)) {
        map[e.platform] = (map[e.platform] ?? 0) + 1;
      }
    }
    return map;
  }

  Map<String, int> get byVersion {
    final map = <String, int>{};
    for (final e in entries) {
      map[e.appVersion] = (map[e.appVersion] ?? 0) + 1;
    }
    return map;
  }
}

class ActivityEntry {
  const ActivityEntry({
    required this.uid,
    required this.platform,
    required this.appVersion,
    required this.opens,
    required this.firstSeenAt,
    required this.lastActiveAt,
  });

  final String uid;
  final String platform;
  final String appVersion;
  final int opens;
  final DateTime? firstSeenAt;
  final DateTime? lastActiveAt;
}

class AdminAnalyticsService {
  static final _firestore = FirebaseFirestore.instance;

  static Future<UsageStats> loadUsage() async {
    final snapshot = await _firestore.collection('appActivity').get();
    final entries = [
      for (final doc in snapshot.docs)
        ActivityEntry(
          uid: doc.id,
          platform: doc.data()['platform']?.toString() ?? 'unknown',
          appVersion: doc.data()['appVersion']?.toString() ?? 'unknown',
          opens: (doc.data()['opens'] as num?)?.toInt() ?? 0,
          firstSeenAt: _asDate(doc.data()['firstSeenAt']),
          lastActiveAt: _asDate(doc.data()['lastActiveAt']),
        ),
    ];
    return UsageStats(entries, DateTime.now());
  }

  static DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String _role(Object? value) => (value?.toString() ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  static Future<AdminAnalytics> load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in as a super admin.');
    final own = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('profile')
        .doc('company')
        .get();
    if (_role(own.data()?['role']) != 'superadmin') {
      throw StateError('Only a super admin can view analytics.');
    }

    final profiles = await _firestore.collectionGroup('profile').get();
    final companies = profiles.docs.where(
      (p) =>
          p.id == 'company' &&
          p.reference.path.split('/').length == 4 &&
          p.reference.path.startsWith('users/') &&
          _role(p.data()['role']) != 'superadmin',
    );

    final now = DateTime.now();
    final trialGlobal = await SuperAdminSubscriptionService.loadTrialSettings();
    final records = await Future.wait(
      companies.map((profile) async {
        final id = profile.reference.parent.parent!.id;
        final results = await Future.wait([
          _firestore.collection('subscriptions').doc(id).get(),
          _firestore.collection('accountAccess').doc(id).get(),
        ]);
        final sub = results[0].data() ?? const <String, dynamic>{};
        final data = profile.data();
        return BusinessRecord(
          businessId: id,
          name: data['name']?.toString().trim() ?? '',
          email: data['email']?.toString().trim() ?? '',
          createdAt: _asDate(data['createdAt']),
          startDate: _asDate(sub['startDate']),
          expiry: _asDate(sub['expiry']) ?? _asDate(sub['expiryDate']),
          planAmount: (sub['planAmount'] as num?)?.toDouble() ?? 0,
          planDays: (sub['planDurationDays'] as num?)?.toInt() ?? 0,
          trialActive: TrialSettings.runningEnd(sub, trialGlobal, now) != null,
          disabled: results[1].data()?['disabled'] == true,
        );
      }),
    );

    final plan = await SuperAdminSubscriptionService.loadPlanSettings();
    return AdminAnalytics.from(records, plan, now: now);
  }
}
