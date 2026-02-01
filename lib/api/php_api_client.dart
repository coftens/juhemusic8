import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import '../auth/auth_session.dart';

class PhpApiClient {
  PhpApiClient({String? baseUrl}) : _overrideBaseUrl = baseUrl;

  // Prefer user-configured base url (SharedPreferences) then dart-define.
  // Example: http://<public-ip>:27172
  final String? _overrideBaseUrl;

  String get baseUrl => (_overrideBaseUrl ?? ApiConfig.instance.phpBaseUrl).trim();

  Uri _uri(String path, Map<String, String> q) {
    final b = baseUrl;
    if (b.isEmpty) {
      throw Exception('PHP_API_BASE_URL not configured');
    }
    final u = Uri.parse(b);
    final prefix = u.path.endsWith('/') ? u.path.substring(0, u.path.length - 1) : u.path;
    return u.replace(path: '$prefix$path', queryParameters: q);
  }

  http.Client get httpClient => http.Client();

  Future<Uint8List> rawGetBinary(String url) async {
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    return resp.bodyBytes;
  }

  Future<Map<String, dynamic>> rawGet(String path, Map<String, String> q) async {
    final sess = AuthSession.instance;
    final headers = <String, String>{'Accept': 'application/json'};
    if (sess.isAuthed) {
      headers['Authorization'] = 'Bearer ${sess.accessToken}';
    }
    final resp = await http.get(_uri(path, q), headers: headers);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code == 401 && sess.isAuthed) {
      final ok = await sess.refresh();
      if (ok) {
        final headers2 = <String, String>{'Accept': 'application/json'};
        headers2['Authorization'] = 'Bearer ${sess.accessToken}';
        final resp2 = await http.get(_uri(path, q), headers: headers2);
        if (resp2.statusCode != 200) {
          throw Exception('HTTP ${resp2.statusCode}');
        }
        return jsonDecode(resp2.body) as Map<String, dynamic>;
      }
    }
    return j;
  }

  Future<Map<String, dynamic>> rawPostJson(String path, Map<String, dynamic> body) async {
    final sess = AuthSession.instance;
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (sess.isAuthed) {
      headers['Authorization'] = 'Bearer ${sess.accessToken}';
    }
    final resp = await http.post(_uri(path, const {}), headers: headers, body: jsonEncode(body));
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code == 401 && sess.isAuthed) {
      final ok = await sess.refresh();
      if (ok) {
        headers['Authorization'] = 'Bearer ${sess.accessToken}';
        final resp2 = await http.post(_uri(path, const {}), headers: headers, body: jsonEncode(body));
        if (resp2.statusCode != 200) throw Exception('HTTP ${resp2.statusCode}');
        return jsonDecode(resp2.body) as Map<String, dynamic>;
      }
    }
    return j;
  }

  Future<String> uploadAvatar(String filePath) async {
    final sess = AuthSession.instance;
    final u = _uri('/api/me_avatar.php', const {});
    final req = http.MultipartRequest('POST', u)
      ..headers['Authorization'] = 'Bearer ${sess.accessToken}'
      ..files.add(await http.MultipartFile.fromPath('avatar', filePath));

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code == 401 && sess.isAuthed) {
      final ok = await sess.refresh();
      if (ok) {
        final req2 = http.MultipartRequest('POST', u)
          ..headers['Authorization'] = 'Bearer ${sess.accessToken}'
          ..files.add(await http.MultipartFile.fromPath('avatar', filePath));
        final streamed2 = await req2.send();
        final resp2 = await http.Response.fromStream(streamed2);
        if (resp2.statusCode != 200) throw Exception('HTTP ${resp2.statusCode}');
        final j2 = jsonDecode(resp2.body) as Map<String, dynamic>;
        final code2 = (j2['code'] as num?)?.toInt() ?? 500;
        if (code2 != 200) throw Exception(j2['msg'] ?? 'upload failed');
        final data2 = (j2['data'] as Map?)?.cast<String, dynamic>() ?? const {};
        return (data2['avatar_url'] as String?) ?? '';
      }
    }

    if (code != 200) throw Exception(j['msg'] ?? 'upload failed');
    final data = (j['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    return (data['avatar_url'] as String?) ?? '';
  }

  Future<List<SearchItem>> search({
    required String keyword,
    String platform = 'all',
    int limit = 20,
  }) async {
    final j = await rawGet('/search.php', {
      'keyword': keyword,
      'platform': platform,
      'limit': limit.toString(),
    });
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) {
      throw Exception(j['msg'] ?? 'search failed');
    }
    final data = j['data'] as Map<String, dynamic>;
    final list = data['list'] as List<dynamic>? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(SearchItem.fromJson).toList();
  }

  Future<ParseResult> parse({
    required String url,
    String quality = 'lossless',
  }) async {
    final j = await rawGet('/parse.php', {
      'url': url,
      'quality': quality,
    });
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) {
      throw Exception(j['msg'] ?? 'parse failed');
    }
    final data = j['data'] as Map<String, dynamic>;
    return ParseResult.fromJson(data);
  }

  Future<List<ChartItem>> chart({required String source, required String type, int limit = 20}) async {
    final reqLimit = limit;
    if (reqLimit < 1) limit = 1;
    if (reqLimit > 200) limit = 200;

    // Backward-compatible: older servers only support source=qq|wyy.
    if (source == 'all') {
      try {
        final j = await rawGet('/chart.php', {
          'source': source,
          'type': type,
          'limit': limit.toString(),
        });
        final code = (j['code'] as num?)?.toInt() ?? 500;
        if (code == 200) {
          final data = (j['data'] as Map?)?.cast<String, dynamic>() ?? const {};
          final list = (data['list'] as List?)?.cast<dynamic>() ?? const [];
          return list.whereType<Map>().map((m) => ChartItem.fromJson(m.cast<String, dynamic>())).toList();
        }
      } catch (_) {
        // fall back to two-source merge
      }

      final qq = await chart(source: 'qq', type: type, limit: limit);
      final wyy = await chart(source: 'wyy', type: type, limit: limit);
      final seen = <String>{};
      final out = <ChartItem>[];
      for (final it in [...qq, ...wyy]) {
        if (it.shareUrl.isEmpty) continue;
        if (seen.add(it.shareUrl)) {
          out.add(it);
          if (out.length >= limit) break;
        }
      }
      return out;
    }

    final j = await rawGet('/chart.php', {
      'source': source,
      'type': type,
      'limit': limit.toString(),
    });
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) {
      throw Exception(j['msg'] ?? 'chart failed');
    }
    final data = (j['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final list = (data['list'] as List?)?.cast<dynamic>() ?? const [];
    return list.whereType<Map>().map((m) => ChartItem.fromJson(m.cast<String, dynamic>())).toList();
  }

  Future<LyricsResult> lyrics(String shareUrl) async {
    final j = await rawGet('/lyrics.php', {'url': shareUrl});
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) {
      throw Exception(j['msg'] ?? 'lyrics failed');
    }
    final data = (j['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    return LyricsResult.fromJson(data);
  }

  Future<PlaylistDetail> playlist({required String source, required String id, int limit = 200}) async {
    final j = await rawGet('/playlist.php', {
      'source': source,
      'id': id,
      'limit': limit.toString(),
    });
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) {
      throw Exception(j['msg'] ?? 'playlist failed');
    }
    final data = (j['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PlaylistDetail.fromJson(data);
  }

  Future<List<PlaylistSquareItem>> getAllPlaylists() async {
    final j = await rawGet('/api/all_playlists.php', {});
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) throw Exception(j['msg'] ?? 'get all playlists failed');
    final data = (j['data'] as List?)?.cast<dynamic>() ?? const [];
    return data.map((e) => PlaylistSquareItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<SearchItem>> getRecommendations({
    required String songId,
    required String source,
  }) async {
    final j = await rawGet('/api/get_recommendations.php', {
      'song_id': songId,
      'source': source,
    });
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) {
      throw Exception('recommendations failed');
    }
    final data = (j['data'] as List?)?.cast<dynamic>() ?? const [];
    final out = <SearchItem>[];
    for (final it in data) {
      if (it is! Map) continue;
      final m = it.cast<String, dynamic>();
      final id = (m['id'] as String?) ?? '';
      final platform = (m['source'] as String?) ?? source;
      final name = (m['name'] as String?) ?? '';
      final artist = (m['artist'] as String?) ?? '';
      final cover = (m['cover'] as String?) ?? '';
      if (id.isEmpty || name.isEmpty) continue;
      final shareUrl = switch (platform) {
        'wyy' => 'https://music.163.com/song?id=$id',
        'qq' => 'https://y.qq.com/n/ryqq_v2/songDetail/$id',
        _ => id,
      };
      out.add(
        SearchItem(
          platform: platform,
          name: name,
          artist: artist,
          shareUrl: shareUrl,
          coverUrl: cover,
        ),
      );
    }
    return out;
  }

  Future<List<SearchItem>> getQishuiFeed({int count = 20}) async {
    final j = await rawGet('/api/qishui_feed.php', {'count': count.toString()});
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) throw Exception('Qishui feed failed');
    final data = (j['data'] as List?)?.cast<dynamic>() ?? const [];
    return data.whereType<Map>().map((m) => SearchItem.fromJson(m.cast<String, dynamic>())).toList();
  }

  Future<AuthUser> me() async {
    final j = await rawGet('/api/auth_me.php', const {});
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) throw Exception(j['msg'] ?? 'me failed');
    final data = (j['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final u = AuthUser.fromJson(data);
    if (u == null) throw Exception('invalid user');
    return u;
  }

  Future<List<SearchItem>> favorites() async {
    final j = await rawGet('/api/user_favorites.php', const {});
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) throw Exception(j['msg'] ?? 'favorites failed');
    final data = (j['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final list = (data['list'] as List?)?.cast<dynamic>() ?? const [];
    return list.whereType<Map>().map((m) => SearchItem.fromJson(m.cast<String, dynamic>())).toList();
  }

  Future<void> addFavorite(SearchItem it) async {
    final j = await rawPostJson('/api/user_favorites.php', {
      'platform': it.platform,
      'share_url': it.shareUrl,
      'name': it.name,
      'artist': it.artist,
      'cover_url': it.coverUrl,
    });
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) throw Exception(j['msg'] ?? 'favorite add failed');
  }

  Future<void> removeFavorite(SearchItem it) async {
    // backend supports DELETE, but http package makes it annoying to send JSON;
    // use query-string via rawGet to a DELETE-like endpoint later. For now POST a marker.
    final u = _uri('/api/user_favorites.php', {
      'platform': it.platform,
      'share_url': it.shareUrl,
    });
    final sess = AuthSession.instance;
    final headers = <String, String>{'Accept': 'application/json'};
    if (sess.isAuthed) headers['Authorization'] = 'Bearer ${sess.accessToken}';
    final resp = await http.delete(u, headers: headers);
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) throw Exception(j['msg'] ?? 'favorite remove failed');
  }

  Future<List<SearchItem>> recents({int limit = 30}) async {
    final j = await rawGet('/api/user_recents.php', {'limit': limit.toString()});
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) throw Exception(j['msg'] ?? 'recents failed');
    final data = (j['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final list = (data['list'] as List?)?.cast<dynamic>() ?? const [];
    return list.whereType<Map>().map((m) => SearchItem.fromJson(m.cast<String, dynamic>())).toList();
  }

  Future<void> addRecent(SearchItem it) async {
    final j = await rawPostJson('/api/user_recents.php', {
      'platform': it.platform,
      'share_url': it.shareUrl,
      'name': it.name,
      'artist': it.artist,
      'cover_url': it.coverUrl,
    });
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) throw Exception(j['msg'] ?? 'recent add failed');
  }

  Future<void> listeningHeartbeat({required int deltaSeconds}) async {
    final j = await rawPostJson('/api/listening_heartbeat.php', {
      'delta_seconds': deltaSeconds,
    });
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) throw Exception(j['msg'] ?? 'heartbeat failed');
  }

  Future<List<PlaylistInfo>> userPlaylists() async {
    final j = await rawGet('/api/user_playlists.php', const {});
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) throw Exception(j['msg'] ?? 'get playlists failed');
    final data = (j['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final list = (data['list'] as List?)?.cast<dynamic>() ?? const [];
    return list.whereType<Map>().map((m) => PlaylistInfo.fromJson(m.cast<String, dynamic>())).toList();
  }

  Future<void> addFavoritePlaylist({
    required String platform,
    required String externalId,
    required String name,
    required String coverUrl,
    int trackCount = 0,
  }) async {
    final j = await rawPostJson('/api/user_playlists.php', {
      'platform': platform,
      'external_id': externalId,
      'name': name,
      'cover_url': coverUrl,
      'track_count': trackCount,
    });
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) throw Exception(j['msg'] ?? 'add playlist failed');
  }

  Future<void> removeFavoritePlaylist({
    required String platform,
    required String externalId,
  }) async {
    final u = _uri('/api/user_playlists.php', {
      'platform': platform,
      'external_id': externalId,
    });
    final sess = AuthSession.instance;
    final headers = <String, String>{'Accept': 'application/json'};
    if (sess.isAuthed) headers['Authorization'] = 'Bearer ${sess.accessToken}';
    final resp = await http.delete(u, headers: headers);
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) throw Exception(j['msg'] ?? 'remove playlist failed');
  }
}

class ChartItem {
  ChartItem({required this.title, required this.artist, required this.shareUrl});

  final String title;
  final String artist;
  final String shareUrl;

  static ChartItem fromJson(Map<String, dynamic> j) {
    return ChartItem(
      title: (j['title'] as String?) ?? '',
      artist: (j['artist'] as String?) ?? '',
      shareUrl: (j['share_url'] as String?) ?? (j['original_share_url'] as String?) ?? '',
    );
  }
}

class LyricsResult {
  LyricsResult({required this.source, required this.songKey, required this.lyricLrc, required this.transLrc});

  final String source;
  final String songKey;
  final String lyricLrc;
  final String transLrc;

  static LyricsResult fromJson(Map<String, dynamic> j) {
    return LyricsResult(
      source: (j['source'] as String?) ?? '',
      songKey: (j['song_key'] as String?) ?? '',
      lyricLrc: (j['lyric_lrc'] as String?) ?? '',
      transLrc: (j['trans_lrc'] as String?) ?? '',
    );
  }
}

class PlaylistDetail {
  PlaylistDetail({required this.source, required this.id, required this.title, required this.coverUrl, required this.list});

  final String source;
  final String id;
  final String title;
  final String coverUrl;
  final List<PlaylistTrack> list;

  static PlaylistDetail fromJson(Map<String, dynamic> j) {
    final rawList = (j['list'] as List?)?.cast<dynamic>() ?? const [];
    final list = <PlaylistTrack>[];
    for (final item in rawList) {
      try {
        if (item is Map) {
          list.add(PlaylistTrack.fromJson(item.cast<String, dynamic>()));
        }
      } catch (_) {
        // ignore invalid items
      }
    }
    return PlaylistDetail(
      source: (j['source'] as String?) ?? '',
      id: (j['id'] as String?) ?? '',
      title: (j['title'] as String?) ?? '',
      coverUrl: (j['cover_url'] as String?) ?? '',
      list: list,
    );
  }
}

class PlaylistTrack {
  PlaylistTrack({required this.title, required this.artist, required this.shareUrl, required this.coverUrl});

  final String title;
  final String artist;
  final String shareUrl;
  final String coverUrl;

  static PlaylistTrack fromJson(Map<String, dynamic> j) {
    return PlaylistTrack(
      title: (j['title'] as String?) ?? '',
      artist: (j['artist'] as String?) ?? '',
      shareUrl: (j['share_url'] as String?) ?? '',
      coverUrl: (j['cover_url'] as String?) ?? '',
    );
  }
}

class PlaylistInfo {
  PlaylistInfo({
    required this.id,
    required this.platform,
    required this.externalId,
    required this.name,
    required this.coverUrl,
    required this.trackCount,
  });

  final int id;
  final String platform;
  final String externalId;
  final String name;
  final String coverUrl;
  final int trackCount;

  static PlaylistInfo fromJson(Map<String, dynamic> j) {
    return PlaylistInfo(
      id: (j['id'] as num?)?.toInt() ?? 0,
      platform: (j['platform'] as String?) ?? 'local',
      externalId: (j['external_id'] as String?) ?? '',
      name: (j['name'] as String?) ?? '',
      coverUrl: (j['cover_url'] as String?) ?? '',
      trackCount: (j['track_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class SearchItem {
  SearchItem({
    required this.platform,
    required this.name,
    required this.artist,
    required this.shareUrl,
    required this.coverUrl,
    this.lyrics = '',
  });

  final String platform;
  final String name;
  final String artist;
  final String shareUrl;
  final String coverUrl;
  final String lyrics;

  static SearchItem fromJson(Map<String, dynamic> j) {
    final hosted = (j['hosted_cover_url'] as String?) ?? '';
    final original = (j['original_cover_url'] as String?) ?? '';
    final coverUrl = hosted.isNotEmpty ? hosted : ((j['cover_url'] as String?) ?? original);
    return SearchItem(
      platform: (j['platform'] as String?) ?? '',
      name: (j['name'] as String?) ?? '',
      artist: (j['artist'] as String?) ?? '',
      shareUrl: (j['share_url'] as String?) ?? '',
      coverUrl: coverUrl,
      lyrics: (j['lyrics'] as String?) ?? '',
    );
  }
}

class ParseResult {
  ParseResult({
    required this.platform,
    required this.best,
    required this.qualities,
    required this.coverUrl,
    this.spadeA = '',
  });

  final String platform;
  final QualityUrl best;
  final Map<String, QualityUrl> qualities;
  final String coverUrl;
  final String spadeA;

  static ParseResult fromJson(Map<String, dynamic> j) {
    final platform = (j['platform'] as String?) ?? '';
    final bestJ = (j['best'] as Map?)?.cast<String, dynamic>() ?? const {};
    final best = QualityUrl.fromJson(bestJ);

    final qualities = <String, QualityUrl>{};
    final qj = (j['qualities'] as Map?)?.cast<String, dynamic>() ?? const {};
    for (final e in qj.entries) {
      if (e.value is Map) {
        final m = (e.value as Map).cast<String, dynamic>();
        final url = (m['url'] as String?) ?? '';
        final sa = (m['spade_a'] as String?) ?? '';
        if (url.isNotEmpty) {
          qualities[e.key] = QualityUrl(url: url, spadeA: sa);
        }
      }
    }

    final hosted = (j['hosted_cover_url'] as String?) ?? '';
    final original = (j['original_cover_url'] as String?) ?? '';
    final coverUrl = hosted.isNotEmpty ? hosted : original;
    final mainSpadeA = (j['spade_a'] as String?) ?? '';

    return ParseResult(
      platform: platform,
      best: best,
      qualities: qualities,
      coverUrl: coverUrl,
      spadeA: mainSpadeA,
    );
  }
}

class PlaylistSquareItem {
  final String source;
  final String id;
  final String title;
  final String coverUrl;
  final int playCount;

  PlaylistSquareItem({
    required this.source,
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.playCount,
  });

  factory PlaylistSquareItem.fromJson(Map<String, dynamic> json) {
    return PlaylistSquareItem(
      source: (json['source'] as String?) ?? '',
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      coverUrl: (json['cover_url'] as String?) ?? '',
      playCount: (json['play_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class QualityUrl {
  QualityUrl({required this.url, this.spadeA = ''});

  final String url;
  final String spadeA;

  static QualityUrl fromJson(Map<String, dynamic> j) {
    return QualityUrl(
      url: (j['url'] as String?) ?? '',
      spadeA: (j['spade_a'] as String?) ?? '',
    );
  }
}
