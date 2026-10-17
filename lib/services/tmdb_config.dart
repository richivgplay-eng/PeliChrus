import 'package:flutter/foundation.dart';

class TmdbConfig {
  static const String _configuredApiBaseUrl = String.fromEnvironment(
    'PELICHRUS_API_BASE_URL',
  );
  static String get apiBaseUrl {
    if (_configuredApiBaseUrl.isNotEmpty) {
      return _configuredApiBaseUrl;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }

  static const String securityNotice =
      'Las solicitudes pasan por el backend. El token de TMDB nunca se incluye en la aplicación cliente.';
}
