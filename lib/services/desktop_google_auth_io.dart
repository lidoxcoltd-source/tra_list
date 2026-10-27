import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// Provide a Google Cloud "Desktop app" OAuth client at build time:
// --dart-define=GOOGLE_DESKTOP_CLIENT_ID=... --dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=...
const _clientId = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
const _clientSecret = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET');

const bool desktopGoogleConfigured = _clientId != '';

String _randomString(int bytes) {
  final random = Random.secure();
  return base64UrlEncode(
    List<int>.generate(bytes, (_) => random.nextInt(256)),
  ).replaceAll('=', '');
}

/// Returns a Google ID token, or null if the user cancelled or timed out.
Future<String?> desktopGoogleIdToken() async {
  if (!desktopGoogleConfigured) {
    throw StateError('GOOGLE_DESKTOP_CLIENT_ID is not configured.');
  }
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  try {
    final redirectUri = 'http://127.0.0.1:${server.port}';
    final verifier = _randomString(48);
    final challenge = base64UrlEncode(
      sha256.convert(ascii.encode(verifier)).bytes,
    ).replaceAll('=', '');
    final state = _randomString(16);

    final authUri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': _clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': 'openid email profile',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
      'prompt': 'select_account',
    });
    if (!await launchUrl(authUri, mode: LaunchMode.externalApplication)) {
      throw StateError('Could not open the browser.');
    }

    final request = await server.first.timeout(
      const Duration(minutes: 3),
      onTimeout: () => throw TimeoutException('Google sign-in timed out'),
    );
    final params = request.uri.queryParameters;
    final ok = params['code'] != null && params['state'] == state;
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(
        '<html><body style="font-family:sans-serif;text-align:center;'
        'padding-top:60px"><h2>${ok ? 'Signed in' : 'Sign-in cancelled'}'
        '</h2><p>You can close this tab and return to MJASI POS.</p>'
        '</body></html>',
      );
    await request.response.close();
    if (!ok) return null;

    final response = await http.post(
      Uri.https('oauth2.googleapis.com', '/token'),
      body: {
        'code': params['code']!,
        'client_id': _clientId,
        if (_clientSecret.isNotEmpty) 'client_secret': _clientSecret,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      },
    );
    if (response.statusCode != 200) {
      throw StateError(
        'Google token exchange failed (${response.statusCode}).',
      );
    }
    final idToken = (jsonDecode(response.body) as Map)['id_token'] as String?;
    if (idToken == null) throw StateError('Google returned no ID token.');
    return idToken;
  } finally {
    await server.close(force: true);
  }
}
