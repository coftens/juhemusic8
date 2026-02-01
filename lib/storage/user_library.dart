import 'dart:convert';
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/php_api_client.dart';

class UserLibrary {
  UserLibrary._();

  static final instance = UserLibrary._();

  final _api = PhpApiClient();

  static const _kRecents = 'recents_v2';
  static const _kFavorites = 'favorites_v2';
  static const _kPlaylists = 'playlists_v2';

  Future<List<SearchItem>> getRecents() async {
    try {
      final list = await _api.recents();
      unawaited(_cacheItems(_kRecents, list));
      return list;
    } catch (_) {
      final sp = await SharedPreferences.getInstance();
      return _decodeItems(sp.getString(_kRecents) ?? '[]');
    }
  }

  Future<List<SearchItem>> getFavorites() async {
    try {
      final list = await _api.favorites();
      unawaited(_cacheItems(_kFavorites, list));
      return list;
    } catch (_) {
      final sp = await SharedPreferences.getInstance();
      return _decodeItems(sp.getString(_kFavorites) ?? '[]');
    }
  }

  Future<List<PlaylistInfo>> getPlaylists() async {
    try {
      final list = await _api.userPlaylists();
      unawaited(_cachePlaylists(list));
      return list;
    } catch (_) {
      final sp = await SharedPreferences.getInstance();
      return _decodePlaylists(sp.getString(_kPlaylists) ?? '[]');
    }
  }

  Future<void> addRecent(SearchItem item) async {
    try {
      await _api.addRecent(item);
    } catch (_) {}
    // sync local cache
    final sp = await SharedPreferences.getInstance();
    final list = _decodeItems(sp.getString(_kRecents) ?? '[]');
    final next = [
      item,
      for (final it in list)
        if (it.shareUrl != item.shareUrl) it,
    ].take(30).toList();
    await sp.setString(_kRecents, _encodeItems(next));
  }

  Future<bool> isFavorite(String shareUrl) async {
    final sp = await SharedPreferences.getInstance();
    final list = _decodeItems(sp.getString(_kFavorites) ?? '[]');
    return list.any((e) => e.shareUrl == shareUrl);
  }

  Future<void> toggleFavorite(SearchItem item) async {
    final fav = await isFavorite(item.shareUrl);
    try {
      if (fav) {
        await _api.removeFavorite(item);
      } else {
        await _api.addFavorite(item);
      }
    } catch (_) {}

    final sp = await SharedPreferences.getInstance();
    final list = _decodeItems(sp.getString(_kFavorites) ?? '[]');
    final next = fav ? [for (final it in list) if (it.shareUrl != item.shareUrl) it] : [item, ...list].take(200).toList();
    await sp.setString(_kFavorites, _encodeItems(next));
  }

  Future<bool> isPlaylistFavorite(String platform, String externalId) async {
    final sp = await SharedPreferences.getInstance();
    final list = _decodePlaylists(sp.getString(_kPlaylists) ?? '[]');
    return list.any((p) => p.platform == platform && p.externalId == externalId);
  }

  Future<void> togglePlaylistFavorite(PlaylistInfo item) async {
    final fav = await isPlaylistFavorite(item.platform, item.externalId);
    try {
      if (fav) {
        await _api.removeFavoritePlaylist(platform: item.platform, externalId: item.externalId);
      } else {
        await _api.addFavoritePlaylist(
          platform: item.platform,
          externalId: item.externalId,
          name: item.name,
          coverUrl: item.coverUrl,
          trackCount: item.trackCount,
        );
      }
    } catch (_) {}

    final sp = await SharedPreferences.getInstance();
    final list = _decodePlaylists(sp.getString(_kPlaylists) ?? '[]');
    List<PlaylistInfo> next;
    if (fav) {
      next = list.where((p) => !(p.platform == item.platform && p.externalId == item.externalId)).toList();
    } else {
      next = [item, ...list];
    }
    await sp.setString(_kPlaylists, _encodePlaylists(next));
  }

  Future<void> _cacheItems(String key, List<SearchItem> list) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(key, _encodeItems(list));
  }

  Future<void> _cachePlaylists(List<PlaylistInfo> list) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kPlaylists, _encodePlaylists(list));
  }

  static List<SearchItem> _decodeItems(String raw) {
    try {
      final arr = jsonDecode(raw);
      if (arr is! List) return const [];
      return arr
          .whereType<Map>()
          .map((m) => SearchItem(
                platform: (m['platform'] as String?) ?? '',
                name: (m['name'] as String?) ?? '',
                artist: (m['artist'] as String?) ?? '',
                shareUrl: (m['share_url'] as String?) ?? '',
                coverUrl: (m['cover_url'] as String?) ?? '',
              ))
          .where((e) => e.shareUrl.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static String _encodeItems(List<SearchItem> list) {
    final arr = [
      for (final it in list)
        {
          'platform': it.platform,
          'name': it.name,
          'artist': it.artist,
          'shareUrl': it.shareUrl,
          'coverUrl': it.coverUrl,
        }
    ];
    return jsonEncode(arr);
  }

  static List<PlaylistInfo> _decodePlaylists(String raw) {
    try {
      final arr = jsonDecode(raw);
      if (arr is! List) return const [];
      return arr.whereType<Map>().map((m) => PlaylistInfo(
        id: (m['id'] as num?)?.toInt() ?? 0,
        platform: (m['platform'] as String?) ?? 'local',
        externalId: (m['external_id'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
        coverUrl: (m['cover_url'] as String?) ?? '',
        trackCount: (m['track_count'] as num?)?.toInt() ?? 0,
      )).toList();
    } catch (_) {
      return const [];
    }
  }

  static String _encodePlaylists(List<PlaylistInfo> list) {
    final arr = [
      for (final p in list)
        {
          'id': p.id,
          'platform': p.platform,
          'external_id': p.externalId,
          'name': p.name,
          'cover_url': p.coverUrl,
          'track_count': p.trackCount,
        }
    ];
    return jsonEncode(arr);
  }
}
