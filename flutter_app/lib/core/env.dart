import 'package:flutter/foundation.dart';

/// Build-time config. Run with: flutter run --dart-define-from-file=env.json
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Deep link the auth e-mails (invite / password reset) return to on mobile.
  static const mobileAuthRedirect = 'com.equipmentportal.app://auth-callback';

  /// Public web address of the app (used in QR codes and invite links).
  static const _siteUrl = String.fromEnvironment('SITE_URL');
  static String get siteUrl {
    if (kIsWeb) return Uri.base.origin;
    return _siteUrl.isEmpty ? 'http://localhost:3000' : _siteUrl.replaceFirst(RegExp(r'/$'), '');
  }

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
