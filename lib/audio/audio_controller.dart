import 'dart:async';

import 'package:just_audio/just_audio.dart';

class AudioController {
  AudioController() {
    _subs.add(_player.positionStream.listen((p) => _position = p));
    _subs.add(_player.durationStream.listen((d) => _duration = d));
    _subs.add(_player.playerStateStream.listen((s) => _playing = s.playing));
  }

  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];

  String? _loadedUrl;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration? _duration;

  String? get loadedUrl => _loadedUrl;
  bool get playing => _playing;
  Duration get position => _position;
  Duration get duration => _duration ?? Duration.zero;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _player.dispose();
  }

  Future<void> loadUrl(String url) async {
    if (url.isEmpty) {
      throw ArgumentError('url is empty');
    }
    if (url == _loadedUrl) {
      return;
    }
    await _player.setUrl(url);
    _loadedUrl = url;
  }

  Future<void> play() => _player.play();

  Future<void> pause() => _player.pause();

  Future<void> toggle() async {
    if (_player.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration position) => _player.seek(position);
}
