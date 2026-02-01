import '../api/php_api_client.dart';

import 'auth_session.dart';

class AuthApi {
  AuthApi._();

  static final instance = AuthApi._();

  final _api = PhpApiClient();

  Future<void> register({required String username, required String password}) async {
    final sess = AuthSession.instance;
    final j = await _api.rawPostJson('/api/auth_register.php', {
      'username': username,
      'password': password,
      'device_id': sess.deviceId,
    });
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) throw Exception(j['msg'] ?? 'register failed');
    final data = (j['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final user = AuthUser.fromJson((data['user'] as Map?)?.cast<String, dynamic>() ?? const {});
    final tokens = (data['tokens'] as Map?)?.cast<String, dynamic>() ?? const {};
    final access = (tokens['access_token'] as String?) ?? '';
    final refresh = (tokens['refresh_token'] as String?) ?? '';
    if (user == null || access.isEmpty || refresh.isEmpty) throw Exception('invalid auth payload');
    await sess.setAuth(accessToken: access, refreshToken: refresh, user: user);
  }

  Future<void> login({required String username, required String password}) async {
    final sess = AuthSession.instance;
    final j = await _api.rawPostJson('/api/auth_login.php', {
      'username': username,
      'password': password,
      'device_id': sess.deviceId,
    });
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) throw Exception(j['msg'] ?? 'login failed');
    final data = (j['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final user = AuthUser.fromJson((data['user'] as Map?)?.cast<String, dynamic>() ?? const {});
    final tokens = (data['tokens'] as Map?)?.cast<String, dynamic>() ?? const {};
    final access = (tokens['access_token'] as String?) ?? '';
    final refresh = (tokens['refresh_token'] as String?) ?? '';
    if (user == null || access.isEmpty || refresh.isEmpty) throw Exception('invalid auth payload');
    await sess.setAuth(accessToken: access, refreshToken: refresh, user: user);
  }

  Future<void> logout() async {
    final sess = AuthSession.instance;
    final r = sess.refreshToken;
    try {
      if (r.isNotEmpty) {
        await _api.rawPostJson('/api/auth_logout.php', {
          'refresh_token': r,
        });
      }
    } finally {
      await sess.clear();
    }
  }
}
