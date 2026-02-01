import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api/music_api_client.dart';
import '../audio/audio_controller.dart';
import 'vinyl_player_page.dart';

class VinylPlayerDemoPage extends StatefulWidget {
  const VinylPlayerDemoPage({super.key});

  @override
  State<VinylPlayerDemoPage> createState() => _VinylPlayerDemoPageState();
}

class _VinylPlayerDemoPageState extends State<VinylPlayerDemoPage> {
  static const _duration = Duration(minutes: 3, seconds: 31);
  static const _tick = Duration(seconds: 1);

  final _audio = AudioController();
  final _api = MusicApiClient();

  Timer? _timer;

  String _quality = 'lossless';
  Map<String, String> _qualities = const {
    'standard': 'standard',
    'exhigh': 'exhigh',
    'lossless': 'lossless',
  };

  final String _shareUrl = 'https://y.qq.com/n/ryqq_v2/songDetail/003cSLOO35W3yP';
  String? _streamUrl;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audio.dispose();
    super.dispose();
  }

  void _syncTimer() {
    // Keep a lightweight UI tick so the progress bar moves smoothly even if
    // just_audio streams are briefly delayed.
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  Future<void> _ensureStreamUrl() async {
    if (_streamUrl != null) return;
    try {
      final r = await _api.parse(url: _shareUrl, quality: _quality);
      _qualities = {
        for (final q in r.qualities.keys) q: q,
      };
      final picked = r.qualities[_quality]?.url.isNotEmpty == true
          ? r.qualities[_quality]!.url
          : r.best.url;
      if (picked.isEmpty) {
        throw Exception('empty stream url');
      }
      _streamUrl = picked;
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      rethrow;
    }
  }

  Future<void> _switchQuality(String q) async {
    setState(() {
      _quality = q;
      _streamUrl = null;
    });
    if (_audio.playing) {
      await _togglePlay();
      await _togglePlay();
    }
  }

  Future<void> _togglePlay() async {
    try {
      if (!_audio.playing) {
        await _ensureStreamUrl();
        await _audio.loadUrl(_streamUrl!);
      }
      await _audio.toggle();
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Play failed: ${_lastError ?? e.toString()}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use a local in-memory image by default to keep widget tests offline-safe.
    final cover = MemoryImage(_demoCoverBytes);

    final position = _audio.position;
    final duration = _audio.duration == Duration.zero ? _duration : _audio.duration;

    return VinylPlayerPage(
      title: '孤身',
      artist: '徐秉龙',
      shareUrl: _shareUrl,
      cover: cover,
      playing: _audio.playing,
      position: position,
      duration: duration,
      selectedQuality: _quality,
      availableQualities: _qualities,
      qualitiesLoading: false,
      favorite: false,
      onToggleFavorite: () {},
      onTogglePlay: _togglePlay,
      onPrev: () {
        _audio.seek(Duration.zero);
        setState(() {});
      },
      onNext: () {
        _audio.seek(duration);
        _audio.pause();
        setState(() {});
      },
      onOpenQueue: () {},
      onSeek: (d) {
        _audio.seek(d);
        setState(() {});
      },
      onSelectQuality: (q) {
        _switchQuality(q);
      },
    );
  }
}

final Uint8List _demoCoverBytes = base64Decode(
  // 1x1 PNG (transparent)
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/6XnZt0AAAAASUVORK5CYII=',
);
