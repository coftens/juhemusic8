import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig extends ChangeNotifier {
  ApiConfig._();

  static final instance = ApiConfig._();

  static const _kPhpBaseUrlKey = 'php_api_base_url';

  static const defaultPhpBaseUrl = String.fromEnvironment(
    'PHP_API_BASE_URL',
    defaultValue: 'http://8.159.155.226:27172',
  );

  String _phpBaseUrl = '';

  String get phpBaseUrl => _phpBaseUrl.isNotEmpty ? _phpBaseUrl : defaultPhpBaseUrl;

  bool get isConfigured => phpBaseUrl.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _phpBaseUrl = (prefs.getString(_kPhpBaseUrlKey) ?? '').trim();
    notifyListeners();
  }

  Future<void> setPhpBaseUrl(String url) async {
    final next = url.trim();
    if (next.isEmpty) {
      throw ArgumentError('empty');
    }
    final u = Uri.tryParse(next);
    if (u == null || !u.hasScheme || u.host.isEmpty) {
      throw ArgumentError('invalid');
    }
    if (u.scheme != 'http' && u.scheme != 'https') {
      throw ArgumentError('scheme');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPhpBaseUrlKey, next);
    _phpBaseUrl = next;
    notifyListeners();
  }
}
