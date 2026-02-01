import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'qishui_decrypt.dart';

class LocalMusicProxy {
  static HttpServer? _server;
  static int port = 0;
  static final _client = http.Client();
  
  // Cache for decrypted bytes to avoid re-downloading on retries
  static final Map<String, Uint8List> _decryptedCache = {};

  static Future<void> ensureStarted() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = _server!.port;
    debugPrint('[Proxy] Proxy started on port $port');
    
    _server!.listen(_handleRequest);
  }

  static Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path != '/qishui') {
      request.response.statusCode = 404;
      await request.response.close();
      return;
    }

    final url = request.uri.queryParameters['url'];
    final spadeA = request.uri.queryParameters['spade_a'];
    
    if (url == null || spadeA == null) {
      request.response.statusCode = 400;
      await request.response.close();
      return;
    }

    if (_decryptedCache.containsKey(url)) {
      debugPrint('[Proxy] Serving from cache: $url');
      final data = _decryptedCache[url]!;
      request.response.headers.contentType = ContentType('audio', 'mp4');
      request.response.headers.contentLength = data.length;
      request.response.headers.add('Accept-Ranges', 'bytes');
      request.response.add(data);
      await request.response.close();
      return;
    }

    debugPrint('[Proxy] Fetching and Decrypting: $url');

    try {
      final resp = await _client.get(Uri.parse(url));
      if (resp.statusCode != 200) {
        request.response.statusCode = resp.statusCode;
        await request.response.close();
        return;
      }

      // Perform decryption
      final encrypted = resp.bodyBytes;
      final decrypted = await QishuiDecrypt.decryptAudio(encrypted, spadeA);
      
      // Store in cache (limit size to 2 songs to save RAM)
      if (_decryptedCache.length >= 2) _decryptedCache.remove(_decryptedCache.keys.first);
      _decryptedCache[url] = decrypted;

      request.response.headers.contentType = ContentType('audio', 'mp4');
      request.response.headers.contentLength = decrypted.length;
      request.response.headers.add('Accept-Ranges', 'bytes');
      
      request.response.add(decrypted);
      await request.response.close();
      debugPrint('[Proxy] Success: ${decrypted.length} bytes served.');
    } catch (e) {
      debugPrint('[Proxy] Error: $e');
      if (request.response.connectionInfo != null) {
        try {
          request.response.statusCode = 500;
          await request.response.close();
        } catch (_) {}
      }
    }
  }

  static String getProxyUrl(String originalUrl, String spadeA) {
    return 'http://127.0.0.1:$port/qishui?url=${Uri.encodeComponent(originalUrl)}&spade_a=${Uri.encodeComponent(spadeA)}';
  }
}