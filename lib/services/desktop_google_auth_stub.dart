const bool desktopGoogleConfigured = false;

/// Returns a Google ID token, or null if the user cancelled.
Future<String?> desktopGoogleIdToken() async =>
    throw UnsupportedError('Desktop Google sign-in is not available here.');
