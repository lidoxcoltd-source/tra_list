import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'market_palette.dart';

final _photoCache = <String, Future<String>>{};

/// Profile photo stored on the public profile (Firebase Storage), which is
/// more reliable than the Google account photo that is often rate limited.
Future<String> _publicProfilePhoto(String uid) =>
    _photoCache.putIfAbsent(uid, () async {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('publicProfiles')
            .doc(uid)
            .get();
        return (snapshot.data()?['photoUrl'] ?? '').toString();
      } catch (_) {
        return '';
      }
    });

class MarketAvatar extends StatelessWidget {
  const MarketAvatar({
    super.key,
    required this.uid,
    required this.fallbackUrl,
    this.radius = 22,
  });

  final String uid;
  final String fallbackUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: uid.isEmpty ? Future.value('') : _publicProfilePhoto(uid),
      builder: (context, snapshot) {
        final stored = snapshot.data ?? '';
        final url = stored.startsWith('http') ? stored : fallbackUrl;
        return CircleAvatar(
          radius: radius,
          backgroundColor: MarketPalette.surfaceRaised,
          foregroundImage: url.startsWith('http') ? NetworkImage(url) : null,
          onForegroundImageError: url.startsWith('http') ? (_, _) {} : null,
          child: Icon(
            Icons.person_rounded,
            size: radius,
            color: MarketPalette.blue,
          ),
        );
      },
    );
  }
}
