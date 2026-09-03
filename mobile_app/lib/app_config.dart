import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _configuredBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');

  static String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl;
    }
    if (kIsWeb) {
      return 'http://localhost:8000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  static const int defaultUserId = int.fromEnvironment(
    'DEFAULT_USER_ID',
    defaultValue: 1,
  );

  static const String defaultUserEmail = String.fromEnvironment(
    'DEFAULT_USER_EMAIL',
    defaultValue: 'user@example.com',
  );
}
