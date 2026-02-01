import 'dart:convert';

import 'package:http/http.dart' as http;

class MusicApiClient {
  MusicApiClient({String? baseUrl}) : baseUrl = (baseUrl ?? _defaultBaseUrl);

  // Configure via: flutter run --dart-define=API_BASE_URL=http://<host>:8000
  static const _defaultBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://127.0.0.1:8000');

  final String baseUrl;

  Uri _uri(String path, Map<String, String> q) {
    final u = Uri.parse(baseUrl);
    return u.replace(
      path: u.path.endsWith('/') ? '${u.path.substring(0, u.path.length - 1)}$path' : '${u.path}$path',
      queryParameters: q,
    );
  }

  Future<ParseResult> parse({required String url, String quality = 'lossless'}) async {
    final resp = await http.get(
      _uri('/parse', {'url': url, 'quality': quality}),
      headers: const {'Accept': 'application/json'},
    );
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) {
      throw Exception(j['msg'] ?? 'parse failed');
    }
    final data = j['data'] as Map<String, dynamic>;
    return ParseResult.fromJson(data);
  }

  Future<List<SearchItem>> search({required String keyword, required String platform, int limit = 20}) async {
    final resp = await http.get(
      _uri('/search', {
        'keyword': keyword,
        'platform': platform,
        'limit': limit.toString(),
      }),
      headers: const {'Accept': 'application/json'},
    );
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) {
      throw Exception(j['msg'] ?? 'search failed');
    }
    final data = j['data'] as Map<String, dynamic>;
    final list = data['list'] as List<dynamic>? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(SearchItem.fromJson).toList();
  }
}

class ParseResult {
  ParseResult({required this.platform, required this.best, required this.qualities});

  final String platform;
  final QualityUrl best;
  final Map<String, QualityUrl> qualities;

  static ParseResult fromJson(Map<String, dynamic> j) {
    final platform = (j['platform'] as String?) ?? '';
    final bestJ = (j['best'] as Map?)?.cast<String, dynamic>() ?? const {};
    final best = QualityUrl.fromJson(bestJ);

    final q = <String, QualityUrl>{};
    final qualitiesJ = (j['qualities'] as Map?)?.cast<String, dynamic>() ?? const {};
    for (final e in qualitiesJ.entries) {
      if (e.value is Map) {
        q[e.key] = QualityUrl.fromJson((e.value as Map).cast<String, dynamic>());
      }
    }
    return ParseResult(platform: platform, best: best, qualities: q);
  }
}

class QualityUrl {
  QualityUrl({required this.url});

  final String url;

  static QualityUrl fromJson(Map<String, dynamic> j) {
    return QualityUrl(url: (j['url'] as String?) ?? '');
  }
}

class SearchItem {
  SearchItem({required this.name, required this.artist, required this.cover, required this.shareUrl});

  final String name;
  final String artist;
  final String cover;
  final String shareUrl;

  static SearchItem fromJson(Map<String, dynamic> j) {
    return SearchItem(
      name: (j['name'] as String?) ?? '',
      artist: (j['artist'] as String?) ?? '',
      cover: (j['cover'] as String?) ?? '',
      shareUrl: (j['share_url'] as String?) ?? '',
    );
  }
}
