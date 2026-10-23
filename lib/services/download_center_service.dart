import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadItemDef {
  const DownloadItemDef(this.key, this.title, this.subtitle, this.icon);

  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
}

const downloadItemDefs = <DownloadItemDef>[
  DownloadItemDef(
    'playstore',
    'Google Play',
    'Get it on Google Play',
    Icons.shop_rounded,
  ),
  DownloadItemDef(
    'appstore',
    'App Store',
    'Download on the App Store',
    Icons.apple_rounded,
  ),
  DownloadItemDef(
    'apk',
    'Android APK',
    'Direct APK download',
    Icons.android_rounded,
  ),
  DownloadItemDef(
    'windows',
    'Windows',
    'Desktop app for Windows',
    Icons.desktop_windows_rounded,
  ),
  DownloadItemDef(
    'web',
    'Web app',
    'Open in your browser',
    Icons.language_rounded,
  ),
];

class DownloadItem {
  const DownloadItem({this.enabled = false, this.url = '', this.version = ''});

  final bool enabled;
  final String url;
  final String version;

  bool get isAvailable => enabled && url.startsWith('https://');

  Map<String, Object> toMap() => {
    'enabled': enabled,
    'url': url,
    'version': version,
  };

  factory DownloadItem.fromMap(Object? raw) {
    if (raw is! Map) return const DownloadItem();
    return DownloadItem(
      enabled: raw['enabled'] == true,
      url: raw['url']?.toString() ?? '',
      version: raw['version']?.toString() ?? '',
    );
  }
}

class DownloadCenter {
  const DownloadCenter({
    required this.title,
    required this.subtitle,
    required this.items,
  });

  factory DownloadCenter.defaults() => DownloadCenter(
    title: 'Get MJASI POS',
    subtitle:
        'Invoices, quotations and receipts on every device. Pick your platform and start in seconds.',
    items: {for (final d in downloadItemDefs) d.key: const DownloadItem()},
  );

  final String title;
  final String subtitle;
  final Map<String, DownloadItem> items;

  DownloadItem item(String key) => items[key] ?? const DownloadItem();
}

class DownloadCenterService {
  static final _doc = FirebaseFirestore.instance
      .collection('app_config')
      .doc('download_center');

  static Future<DownloadCenter> load() async {
    final defaults = DownloadCenter.defaults();
    final snapshot = await _doc.get();
    final data = snapshot.data();
    if (data == null) return defaults;
    final rawItems = data['items'];
    return DownloadCenter(
      title: data['title']?.toString() ?? defaults.title,
      subtitle: data['subtitle']?.toString() ?? defaults.subtitle,
      items: {
        for (final d in downloadItemDefs)
          d.key: DownloadItem.fromMap(rawItems is Map ? rawItems[d.key] : null),
      },
    );
  }

  static Future<void> save(DownloadCenter center) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in as a super admin.');
    for (final entry in center.items.entries) {
      final uri = Uri.tryParse(entry.value.url);
      if (entry.value.enabled &&
          (uri == null || uri.scheme != 'https' || uri.host.isEmpty)) {
        throw ArgumentError('An enabled link needs a valid HTTPS URL.');
      }
    }
    await _doc.set({
      'title': center.title,
      'subtitle': center.subtitle,
      'items': {for (final e in center.items.entries) e.key: e.value.toMap()},
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
    });
  }

  static final _stats = FirebaseFirestore.instance.collection('downloadStats');

  static Future<void> _bump(String metric) async {
    try {
      await _stats.doc(metric).set({
        'count': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Download stat skipped: $error');
    }
  }

  /// Counts one visit per browser per day.
  static Future<void> trackVisit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (prefs.getString('downloads_last_visit') == today) return;
      await prefs.setString('downloads_last_visit', today);
    } catch (_) {}
    await _bump('visits');
  }

  static Future<void> trackDownload(String key) => _bump('click_$key');

  /// Super Admin only. Returns metric -> count.
  static Future<Map<String, int>> loadStats() async {
    final snap = await _stats.get();
    return {
      for (final doc in snap.docs)
        doc.id: (doc.data()['count'] as num?)?.toInt() ?? 0,
    };
  }
}
