import 'dart:convert';

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_config.dart';

class AuthUser {
  AuthUser({required this.id, required this.username, required this.avatarUrl});

  final int id;
  final String username;
  final String avatarUrl;

  AuthUser copyWith({String? avatarUrl}) {
    return AuthUser(
      id: id,
      username: username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

  static AuthUser? fromJson(Map<String, dynamic> j) {
    final id = (j['id'] as num?)?.toInt() ?? 0;
    final username = (j['username'] as String?) ?? '';
    final avatarUrl = (j['avatar_url'] as String?) ?? '';
    if (id <= 0 || username.isEmpty) return null;
    return AuthUser(id: id, username: username, avatarUrl: avatarUrl);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'avatar_url': avatarUrl,
      };
}

class AuthSession extends ChangeNotifier {
  AuthSession._();

  static final instance = AuthSession._();

  static const _kAccess = 'auth.access_token.v1';
  static const _kRefresh = 'auth.refresh_token.v1';
  static const _kDevice = 'auth.device_id.v1';
  static const _kUser = 'auth.user.v1';

  String _accessToken = '';
  String _refreshToken = '';
  String _deviceId = '';
  AuthUser? _user;

  String get accessToken => _accessToken;
  String get refreshToken => _refreshToken;
  String get deviceId => _deviceId;
  AuthUser? get user => _user;
  bool get isAuthed => _accessToken.isNotEmpty && _refreshToken.isNotEmpty;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    _accessToken = (sp.getString(_kAccess) ?? '').trim();
    _refreshToken = (sp.getString(_kRefresh) ?? '').trim();
    _deviceId = (sp.getString(_kDevice) ?? '').trim();
    final rawUser = (sp.getString(_kUser) ?? '').trim();
    if (rawUser.isNotEmpty) {
      try {
        final j = jsonDecode(rawUser);
        if (j is Map) {
          _user = AuthUser.fromJson(j.cast<String, dynamic>());
        }
      } catch (_) {
        // ignore
      }
    }
    if (_deviceId.isEmpty) {
      _deviceId = '${DateTime.now().millisecondsSinceEpoch}-${Object().hashCode}';
      await sp.setString(_kDevice, _deviceId);
    }
    notifyListeners();
  }

  Future<void> setAuth({required String accessToken, required String refreshToken, required AuthUser user}) async {
    final sp = await SharedPreferences.getInstance();
    _accessToken = accessToken.trim();
    _refreshToken = refreshToken.trim();
    _user = user;
    await sp.setString(_kAccess, _accessToken);
    await sp.setString(_kRefresh, _refreshToken);
    await sp.setString(_kUser, jsonEncode(user.toJson()));
    notifyListeners();
  }

  Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    _accessToken = '';
    _refreshToken = '';
    _user = null;
    await sp.remove(_kAccess);
    await sp.remove(_kRefresh);
    await sp.remove(_kUser);
    notifyListeners();
  }

  void updateAvatarUrl(String url) {
    final u = _user;
    if (u == null) return;
    _user = u.copyWith(avatarUrl: url);
    unawaited(_persistUser());
    notifyListeners();
  }

  Future<void> _persistUser() async {
    final u = _user;
    if (u == null) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kUser, jsonEncode(u.toJson()));
  }

  Uri _uri(String path) {
    final b = ApiConfig.instance.phpBaseUrl.trim();
    final u = Uri.parse(b);
    final prefix = u.path.endsWith('/') ? u.path.substring(0, u.path.length - 1) : u.path;
    return u.replace(path: '$prefix$path');
  }

  Future<bool> refresh() async {
    final r = _refreshToken.trim();
    if (r.isEmpty) return false;
    try {
      final resp = await http.post(
        _uri('/api/auth_refresh.php'),
        headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'refresh_token': r, 'device_id': _deviceId}),
      );
      if (resp.statusCode != 200) return false;
      final j = jsonDecode(resp.body);
      if (j is! Map) return false;
      final code = (j['code'] as num?)?.toInt() ?? 500;
      if (code != 200) return false;
      final data = (j['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      final tokens = (data['tokens'] as Map?)?.cast<String, dynamic>() ?? const {};
      final access = (tokens['access_token'] as String?) ?? '';
      final refresh = (tokens['refresh_token'] as String?) ?? '';
      if (access.isEmpty || refresh.isEmpty) return false;
      final sp = await SharedPreferences.getInstance();
      _accessToken = access;
      _refreshToken = refresh;
      await sp.setString(_kAccess, _accessToken);
      await sp.setString(_kRefresh, _refreshToken);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }
}
