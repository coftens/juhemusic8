import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/php_api_client.dart';
import '../storage/user_library.dart';

class PlayerService extends ChangeNotifier {
  PlayerService._();
  static final instance = PlayerService._();

  final _api = PhpApiClient();
  AudioPlayer? _player;
  late final ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: []);
  Stream<Duration> get positionStream => _player?.positionStream ?? const Stream.empty();
  bool _isInitializing = false;
  final _subs = <StreamSubscription<dynamic>>[];

  SearchItem? _current;
  String _quality = 'lossless';
  String _prefWyy = 'lossless';
  String _prefQq = 'lossless';
  Map<String, String> _qualities = const {};

  List<SearchItem> _queue = const [];
  int _index = 0;

  String _playMode = 'sequence'; 
  List<int> _order = const [];
  int _orderPos = 0;

  bool _isSyncing = false;
  bool _isSwitching = false;
  static const _silentPlaceholder = 'about:blank';

  bool _loadingRecommendations = false;
  Completer<void>? _replenishCompleter;
  bool _qualitiesLoading = false;

  bool _autoAppendEnabled = true;
  int _queueStamp = 0;

  Duration _savedPosition = Duration.zero;
  Duration _savedDuration = Duration.zero;
  bool _savedWasPlaying = false;

  Timer? _persistTimer;
  DateTime _lastPersistAt = DateTime.fromMillisecondsSinceEpoch(0);
 
  Timer? _heartbeatTimer;
  int _accumulatedSeconds = 0;

  bool _isFavorite = false;

  static const List<String> _wyyQualityPriority = ['jymaster', 'sky', 'jyeffect', 'hires', 'lossless', 'exhigh', 'standard'];
  static const List<String> _qqQualityPriority = ['atmos_51', 'atmos_2', 'master', 'hires', 'flac', '320', 'aac_192', 'ogg_320', 'ogg_192', '128', 'aac_96'];
  static const List<String> _qishuiQualityPriority = ['sky', 'lossless', 'exhigh', 'standard'];
  static const _qOrder = ['jymaster', 'sky', 'jyeffect', 'hires', 'atmos_51', 'atmos_2', 'master', 'flac', 'lossless', 'exhigh', '320', 'aac_192', 'ogg_320', 'ogg_192', '128', 'standard', 'aac_96'];

  void _ensurePlayer() {
    if (_player != null || _isInitializing) return;
    _isInitializing = true;
    final p = AudioPlayer();
    _player = p;
    
    // 初始化播放列表 (添加错误处理)
    // 关键修复：设置 preload 为 false，防止播放器在同步 bad placeholder 时立即崩溃
    unawaited(p.setAudioSource(_playlist, preload: false).catchError((e) {
      debugPrint('[Player] setAudioSource error (idle/placeholder): $e');
    }));
    
    _subs.add(p.positionStream.listen((pos) { _savedPosition = pos; notifyListeners(); }));
    _subs.add(p.durationStream.listen((dur) { _savedDuration = dur ?? _savedDuration; notifyListeners(); }));
    _subs.add(p.playerStateStream.listen(_onPlayerState));
    _subs.add(p.processingStateStream.listen((_) => notifyListeners()));
    
    // 监听索引变化逻辑将在此处理 URL 解析
    _subs.add(p.currentIndexStream.listen(_onIndexChanged));
    
    _isInitializing = false;
  }

  void _onIndexChanged(int? index) {
    if (_isSyncing || index == null || index < 0 || index >= _queue.length) return;
    
    if (_index != index) {
      debugPrint('[Index] System triggered index change: $_index -> $index');
      _index = index;
      _current = _queue[index];
      _orderPos = _order.indexOf(index);
      
      notifyListeners();
      
      // 只有在没有进行中的手动切换时，才响应系统自动跳转
      if (!_isSwitching && !_urlCache.containsKey(_current!.shareUrl)) {
        debugPrint('[Index] Lazy parsing for: ${_current!.name}');
        unawaited(playItem(_current!, autoPlay: true, failOnSkip: false));
      }
    }
  }

  void _onPlayerState(PlayerState s) {
    notifyListeners();
    debugPrint('[State] st=${s.processingState}, play=${s.playing}');
    
    // 移除原有的 ProcessingState.completed 逻辑，因为 ConcatenatingAudioSource 会自动处理
    
    // Update buffering state
    final isBuf = s.processingState == ProcessingState.buffering || s.processingState == ProcessingState.loading;
    if (_buffering != isBuf) {
      _buffering = isBuf;
      notifyListeners();
    }

    _savedWasPlaying = s.playing;
    _schedulePersist();
    if (s.playing) _startHeartbeat(); else _stopHeartbeat();
  }
  
  bool _buffering = false;

  void _startHeartbeat() {
    if (_heartbeatTimer != null) return;
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _accumulatedSeconds++;
      if (_accumulatedSeconds >= 30) {
        _accumulatedSeconds = 0;
        unawaited(_api.listeningHeartbeat(deltaSeconds: 30));
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (_accumulatedSeconds > 5) {
      unawaited(_api.listeningHeartbeat(deltaSeconds: _accumulatedSeconds));
    }
    _accumulatedSeconds = 0;
  }

  String? _loadingShareUrl;
  final Map<String, String> _urlCache = {};

  Future<void> playItem(SearchItem item, {String? quality, Duration? initialPosition, bool autoPlay = true, bool failOnSkip = true}) async {
    // 如果已经在解析中，则跳过
    if (_loadingShareUrl == item.shareUrl && _urlCache.containsKey(item.shareUrl) && quality == null) return;
    
    _loadingShareUrl = item.shareUrl;
    _isSwitching = true; 
    _ensurePlayer();

    debugPrint('[Perf] playItem start: ${item.name} (quality=$quality)');

    int idx = -1;
    try {
      idx = _queue.indexWhere((e) => e.shareUrl == item.shareUrl);
      if (idx < 0) {
        // 不在队列中，插入到当前播放项或末尾
        final insertPos = _queue.isEmpty ? 0 : (_index + 1).clamp(0, _queue.length);
        _queue = [..._queue.sublist(0, insertPos), item, ..._queue.sublist(insertPos)];
        // 这里不需要立即同步，因为后面 _rebuildOrder 会同步
        idx = insertPos;
        await _rebuildOrder(startIndex: idx);
      } else {
        _index = idx;
        _orderPos = _order.indexOf(idx);
      }

      _current = item;
      _isFavorite = await UserLibrary.instance.isFavorite(item.shareUrl);
      _qualitiesLoading = true;
      notifyListeners();

      debugPrint('[Perf] Parsing URL: ${item.shareUrl}');
      final r = await _api.parse(url: item.shareUrl, quality: quality ?? _quality);
      
      _current = SearchItem(
        platform: r.platform,
        name: item.name,
        artist: item.artist,
        shareUrl: item.shareUrl,
        coverUrl: r.coverUrl.isNotEmpty ? r.coverUrl : item.coverUrl,
        lyrics: item.lyrics,
      );
      
      debugPrint('[Perf] Parse result: platform=${r.platform}, best=${r.best.url}, qualities=${r.qualities.length}');
      
      _qualities = {for (final e in r.qualities.entries) e.key: e.value.url};
      _qualitiesLoading = false;
      _quality = _getEffectiveQuality(r.platform, quality ?? _quality);
      
      final picked = _qualities[_quality] ?? r.best.url;
      if (picked.isEmpty) throw Exception('No playable URL');
      _urlCache[item.shareUrl] = picked;

      final Map<String, String> headers = {};
      if (r.platform == 'qq') {
        headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
        headers['Referer'] = 'https://y.qq.com/';
      }

      // 更新播放列表中的对应项
      final source = _createAudioSource(_current!, url: picked, headers: headers);
      
      try {
        if (idx < _playlist.length) {
          final child = _playlist.children[idx];
          final currentTag = child is UriAudioSource ? child.tag as MediaItem? : null;
          final currentUri = child is UriAudioSource ? child.uri.toString() : '';
          
          if (currentTag?.id == item.shareUrl && currentUri == picked) {
             debugPrint('[Playlist] Item already accurate, skip patching.');
          } else {
             // 如果播放器因为之前的占位符进入了错误状态，直接全量 setAudioSource 可能会更稳
             // 但这里我们先尝试 removeAt/insert 并增加异常捕获
             await _playlist.removeAt(idx).catchError((e) => debugPrint('[Playlist] removeAt error: $e'));
             await _playlist.insert(idx, source).catchError((e) => debugPrint('[Playlist] insert error: $e'));
          }
        } else {
          await _playlist.add(source).catchError((e) => debugPrint('[Playlist] add error: $e'));
        }
      } catch (e) {
        debugPrint('[Playlist] Modification warning (handled): $e');
      }

      // 强制重新加载/定位
      try {
        await _player!.seek(initialPosition ?? Duration.zero, index: idx);
      } catch (e) {
        debugPrint('[Playlist] Seek error: $e');
      }
      
      if (autoPlay) {
        unawaited(_player!.play().catchError((e) => debugPrint('[Playlist] Play error: $e')));
      }

      if (_autoAppendEnabled && idx >= _queue.length - 1) {
        unawaited(_loadRecommendations(autoPlayIfEnded: false));
      }

    } catch (e) {
      debugPrint('[Perf] playItem Error: $e');
      
      // 某些错误（如 aborted）可能是系统正在快速切歌导致的，忽略它们
      if (e.toString().contains('abort') || e.toString().contains('interrupted')) {
        debugPrint('[Perf] Ignoring non-fatal error: $e');
        return;
      }

      notifyListeners();

      if (!failOnSkip) {
        debugPrint('[Perf] failOnSkip is false, stopping here.');
        return;
      }
      
      // 只有在确定失败（不是因为解析快或者是切歌干扰）时才尝试跳过
      if (hasNext && autoPlay && _index == idx) {
        debugPrint('[Perf] Verified fatal error for current track, failing over to next song...');
        // 延迟一下再切，防止陷入快速跳歌死循环
        Future.delayed(const Duration(milliseconds: 2000), () {
           if (_index == idx && playing) next();
        });
      }
    } finally {
      await Future.delayed(const Duration(milliseconds: 100));
      _loadingShareUrl = null;
      _isSwitching = false;
      _qualitiesLoading = false;
      notifyListeners();
      _schedulePersist();
    }
  }

  // 移除旧的 _handleTrackCompleted 系统回调，现在由 ConcatenatingAudioSource 自动驱动

  int _retryCount = 0;

  // 移除旧的 _handleTrackCompleted 系统回调，现在由 ConcatenatingAudioSource 自动驱动

  Future<void> _loadRecommendations({required bool autoPlayIfEnded}) async {
    debugPrint('[Replenish] === Called ===');
    debugPrint('[Replenish] _autoAppendEnabled=$_autoAppendEnabled');
    debugPrint('[Replenish] _replenishCompleter=${_replenishCompleter != null ? "BUSY" : "NULL"}');
    
    if (!_autoAppendEnabled || _replenishCompleter != null) {
      debugPrint('[Replenish] Skipped: autoAppend=$_autoAppendEnabled, busy=${_replenishCompleter != null}');
      return _replenishCompleter?.future;
    }
    
    _replenishCompleter = Completer<void>();
    _loadingRecommendations = true;
    notifyListeners();
    
    try {
      debugPrint('[Replenish] Starting feed fetch...');
      List<SearchItem> finalRecs = [];
      
      // Step 1: Try Qishui Feed
      try {
        debugPrint('[Replenish] Requesting Qishui feed (count=15)...');
        final qishuiRecs = await _api.getQishuiFeed(count: 15);
        debugPrint('[Replenish] Qishui API returned ${qishuiRecs.length} songs');
        
        final existing = _queue.map((e) => e.shareUrl).toSet();
        debugPrint('[Replenish] Current queue size: ${_queue.length}');
        
        finalRecs = qishuiRecs.where((e) => !existing.contains(e.shareUrl)).toList();
        debugPrint('[Replenish] After dedup: ${finalRecs.length} new songs from Qishui');
        
        if (finalRecs.isNotEmpty) {
          for (var i = 0; i < finalRecs.length && i < 3; i++) {
            debugPrint('[Replenish]   - ${finalRecs[i].name} by ${finalRecs[i].artist}');
          }
        }
      } catch (e) {
        debugPrint('[Replenish] Qishui feed ERROR: $e');
      }

      // Step 2: Fallback to similar recommendations
      if (finalRecs.isEmpty && _current != null) {
        debugPrint('[Replenish] Qishui empty, trying similar songs...');
        try {
          final songId = _extractSongId(_current!);
          debugPrint('[Replenish] Current song: ${_current!.name} (${_current!.platform}, id=$songId)');
          
          final simRecs = await _api.getRecommendations(songId: songId, source: _current!.platform);
          debugPrint('[Replenish] Similar API returned ${simRecs.length} songs');
          
          final existing = _queue.map((e) => e.shareUrl).toSet();
          finalRecs = simRecs.where((e) => !existing.contains(e.shareUrl)).take(8).toList();
          debugPrint('[Replenish] After dedup: ${finalRecs.length} new similar songs');
        } catch (e) {
          debugPrint('[Replenish] Similar songs ERROR: $e');
        }
      }

      // Step 3: Append to queue
      if (finalRecs.isNotEmpty) {
        final oldLen = _queue.length;
        _queue = [..._queue, ...finalRecs];
        final nextIndices = [for (var i = oldLen; i < _queue.length; i++) i];
        if (_playMode == 'shuffle') nextIndices.shuffle();
        _order = [..._order, ...nextIndices];
        
        debugPrint('[Replenish] SUCCESS! Added ${finalRecs.length} songs to queue');
        debugPrint('[Replenish] Queue size: $oldLen -> ${_queue.length}');
        debugPrint('[Replenish] Order size: ${_order.length}');
        
        notifyListeners();
      } else {
        debugPrint('[Replenish] FAILED: No new songs to add');
      }
    } catch (e) {
      debugPrint('[Replenish] FATAL ERROR: $e');
    } finally {
      _loadingRecommendations = false;
      _replenishCompleter!.complete();
      _replenishCompleter = null;
      notifyListeners();
      debugPrint('[Replenish] === Completed ===');
    }
  }

  String _extractSongId(SearchItem item) {
    final raw = item.shareUrl;
    if (item.platform == 'wyy') {
      final m = RegExp(r'\bid=(\d+)').firstMatch(raw);
      return m?.group(1) ?? raw;
    }
    if (item.platform == 'qq') {
      final m = RegExp(r'songDetail\/([0-9A-Za-z]+)').firstMatch(raw);
      return m?.group(1) ?? raw;
    }
    return raw;
  }

  String _getEffectiveQuality(String platform, String pref) {
    final list = platform == 'wyy' ? _wyyQualityPriority : (platform == 'qq' ? _qqQualityPriority : (platform == 'qishui' ? _qishuiQualityPriority : _wyyQualityPriority));
    return _findBestMatch(pref, list);
  }

  String _findBestMatch(String pref, List<String> priority) {
    if (priority.contains(pref)) return pref;
    if (priority.contains('lossless')) return 'lossless';
    return priority.last;
  }

  Future<void> _rebuildOrder({int startIndex = 0}) async {
    if (_queue.isEmpty) return;
    final n = _queue.length;
    startIndex = startIndex.clamp(0, n - 1);
    if (_playMode == 'shuffle') {
      final rest = [for (var i = 0; i < n; i++) if (i != startIndex) i]..shuffle();
      _order = [startIndex, ...rest];
      _orderPos = 0;
    } else {
      _order = [for (var i = 0; i < n; i++) i];
      _orderPos = startIndex;
    }
    
    // 同步到原生播放列表
    await _syncPlaylist();
  }

  Future<void> _syncPlaylist() async {
    _isSyncing = true;
    final sources = _queue.map((item) {
      final cachedUrl = _urlCache[item.shareUrl];
      return _createAudioSource(item, url: cachedUrl);
    }).toList();
    
    try {
      await _playlist.clear();
      await _playlist.addAll(sources);
      debugPrint('[Playlist] Synced ${sources.length} items to native playlist.');
    } catch (e) {
      debugPrint('[Playlist] Sync Error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  AudioSource _createAudioSource(SearchItem item, {String? url, Map<String, String>? headers}) {
    final mediaItem = MediaItem(
      id: item.shareUrl,
      title: item.name,
      artist: item.artist,
      artUri: item.coverUrl.isNotEmpty ? Uri.tryParse(item.coverUrl) : null,
      extras: {'platform': item.platform},
    );
    
    // 如果没有真实 URL，先用一个占位符，但在标签中提供元数据，让系统能显示标题
    return AudioSource.uri(
      Uri.parse(url ?? _silentPlaceholder),
      tag: mediaItem,
      headers: headers,
    );
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 2), () {
      unawaited(persistState());
      _lastPersistAt = DateTime.now();
    });
  }

  Future<void> persistState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final q = [for (final it in _queue) {
        'platform': it.platform,
        'name': it.name,
        'artist': it.artist,
        'share_url': it.shareUrl,
        'cover_url': it.coverUrl
      }];
      await prefs.setString('player.queue', jsonEncode(q));
      await prefs.setInt('player.index', _index);
      await prefs.setString('player.playMode', _playMode);
      await prefs.setString('player.quality', _quality);
      await prefs.setInt('player.positionMs', _player?.position.inMilliseconds ?? 0);
      await prefs.setBool('player.wasPlaying', _player?.playing ?? false);
    } catch (_) {}
  }

  Future<void> restoreState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = (prefs.getString('player.queue') ?? '').trim();
    if (raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final restored = <SearchItem>[];
      for (final v in decoded) {
        if (v is Map) {
          final m = v.cast<String, dynamic>();
          // 兼容性修复：将旧的驼峰字段转换为 SearchItem.fromJson 期望的下划线字段
          if (!m.containsKey('share_url') && m.containsKey('shareUrl')) {
            m['share_url'] = m['shareUrl'];
          }
          if (!m.containsKey('cover_url') && m.containsKey('coverUrl')) {
            m['cover_url'] = m['coverUrl'];
          }
          restored.add(SearchItem.fromJson(m));
        }
      }
      if (restored.isEmpty) return;
      _queue = restored;
      _index = (prefs.getInt('player.index') ?? 0).clamp(0, _queue.length - 1);
      _playMode = prefs.getString('player.playMode') ?? 'sequence';
      _quality = prefs.getString('player.quality') ?? 'lossless';
      _current = _queue[_index];
      _rebuildOrder(startIndex: _index);
      notifyListeners();
    } catch (e) {
      debugPrint('[Player] restoreState failed: $e');
    }
  }

  // UI Interface
  bool get hasNext => _orderPos < _order.length - 1;
  bool get hasPrev => _orderPos > 0;
  bool get playing => _player?.playing ?? false;
  SearchItem? get current => _current;
  List<SearchItem> get queue => _queue;
  int get index => _index;
  String get playMode => _playMode;
  String get quality => _quality;
  Map<String, String> get qualities => _qualities;
  bool get qualitiesLoading => _qualitiesLoading;
  Duration get position => _savedPosition;
  Duration get duration => _savedDuration;
  bool get isFavorite => _isFavorite;
  bool get isBuffering => _buffering;

  Future<void> next() async {
    _ensurePlayer();
    try {
      if (_player!.hasNext) {
         await _player!.seekToNext();
      } else if (_autoAppendEnabled) {
         debugPrint('[Player] Manual next at end of queue, triggering replenish...');
         await _loadRecommendations(autoPlayIfEnded: false);
         if (_player!.hasNext) await _player!.seekToNext();
      }
    } catch (e) {
      debugPrint('[Player] Next Error: $e');
    }
  }
  Future<void> prev() async {
    _ensurePlayer();
    try {
      if (_player!.hasPrevious) { 
        await _player!.seekToPrevious(); 
      } else {
        await _player?.seek(Duration.zero);
      }
    } catch (e) {
      debugPrint('[Player] Prev Error: $e');
    }
  }
  Future<void> jumpTo(int i) async {
    _ensurePlayer();
    try {
      await _player!.seek(Duration.zero, index: i);
    } catch (e) {
      debugPrint('[Player] JumpTo Error: $e');
    }
  }
  Future<void> toggle() async {
    _ensurePlayer(); // 确保播放器已初始化
    if (_player == null) return;
    
    debugPrint('[Player] toggle: state=${_player!.processingState}, playing=${_player!.playing}, current=${_current?.name}');
    
    if (_player!.processingState == ProcessingState.idle && _current != null) {
      // 恢复播放：如果是 idle 状态（如重启后），重新加载当前歌曲
      debugPrint('[Player] toggle: resuming from idle state');
      await playItem(_current!).catchError((e) => debugPrint('[Player] toggle resume error: $e'));
      return;
    }
    try {
      if (_player!.playing == true) await _player?.pause(); else await _player?.play();
    } catch (e) {
      debugPrint('[Player] toggle error: $e');
    }
    notifyListeners();
  }
  Future<void> setPlayMode(String m) async { 
    _playMode = m; 
    await _rebuildOrder(startIndex: _index); 
    notifyListeners(); 
  }
  
  Future<void> setQueue(List<SearchItem> q, {int startIndex = 0}) async { 
    _queue = q; 
    _index = startIndex; 
    await _rebuildOrder(startIndex: _index); 
    notifyListeners(); 
    _schedulePersist(); 
  }
  
  Future<void> clearQueue() async { 
    if (_current != null) { 
      _queue = [_current!]; 
      _index = 0; 
      await _rebuildOrder(startIndex: 0); 
      _autoAppendEnabled = true; 
      notifyListeners(); 
    } 
  }
  List<SearchItem> snapshotQueue() => List.from(_queue);
  Future<void> seek(Duration d) async {
    try {
      await _player?.seek(d);
    } catch (e) {
      debugPrint('[Player] Seek Error: $e');
    }
  }
  Future<void> setQuality(String q) async {
    _quality = q;
    if (_current == null) return;
    
    debugPrint('[Quality] Switching to $q...');
    
    // 1. 保存当前状态
    final savedPosition = _player?.position ?? Duration.zero;
    final wasPlaying = _player?.playing ?? false;
    
    debugPrint('[Quality] Saved position: $savedPosition, wasPlaying: $wasPlaying');
    
    try {
      // 2. 切换音质（传入播放进度和状态）
      await playItem(
        _current!, 
        quality: q, 
        initialPosition: savedPosition, 
        autoPlay: wasPlaying
      );
      
      // 3 & 4. playItem 内部已处理恢复，无需这里手动 seek/play
      
      debugPrint('[Quality] Switch completed successfully');
    } catch (e) {
      debugPrint('[Quality] Switch failed: $e');
      rethrow;
    }
  }
  Future<void> toggleFavoriteCurrent() async {
    if (_current == null) return;
    if (await UserLibrary.instance.isFavorite(_current!.shareUrl)) { await _api.removeFavorite(_current!); _isFavorite = false; }
    else { await _api.addFavorite(_current!); _isFavorite = true; }
    notifyListeners();
  }

  Future<void> replaceQueueAndPlay(List<SearchItem> items, {int startIndex = 0, String? quality}) async {
    if (items.isEmpty) return;
    
    // 🔥 重要优化：在进行全量同步前，先解析目标项并存入缓存
    // 这样 _syncPlaylist 生成的原生列表第一项就已经是真实 URL，避免 Source Error
    final targetItem = items[startIndex.clamp(0, items.length - 1)];
    try {
      debugPrint('[Perf] Pre-parsing target item for sync: ${targetItem.name}');
      final r = await _api.parse(url: targetItem.shareUrl, quality: quality ?? _quality);
      _urlCache[targetItem.shareUrl] = r.best.url;
    } catch (e) {
      debugPrint('[Perf] Pre-parsing failed: $e');
    }

    _queue = items;
    _index = startIndex.clamp(0, items.length - 1);
    await _rebuildOrder(startIndex: _index);
    await playItem(_queue[_index], quality: quality);
  }

  Future<void> insertAsNextThenPlay(SearchItem first, List<SearchItem> tail, {String? quality}) async {
    final newList = [first, ..._queue.where((e) => e.shareUrl != first.shareUrl)];
    await replaceQueueAndPlay(newList, startIndex: 0, quality: quality);
  }

  /// 插入歌曲到播放列表顶部并播放
  /// 如果当前队列>100首，先清空
  Future<void> insertTopAndPlay(List<SearchItem> items, int playIndex) async {
    if (items.isEmpty) {
      debugPrint('[Player] insertTopAndPlay: empty list');
      return;
    }
    
    // 🔥 重要优化：全量同步前先解析
    final targetItem = items[playIndex];
    try {
      debugPrint('[Perf] Pre-parsing target item for top-play: ${targetItem.name}');
      final r = await _api.parse(url: targetItem.shareUrl, quality: _quality);
      _urlCache[targetItem.shareUrl] = r.best.url;
    } catch (e) {
      debugPrint('[Perf] Pre-parsing failed: $e');
    }

    debugPrint('[Player] insertTopAndPlay: ${items.length} songs, playIndex=$playIndex, currentQueue=${_queue.length}');
    
    // 1. 检查队列长度，如果>100首则清空
    if (_queue.length > 100) {
      debugPrint('[Player] Queue exceeds 100 songs (${_queue.length}), clearing...');
      await clearQueue();
    }
    
    // 2. 插入到顶部
    final currentQueueSnapshot = List<SearchItem>.from(_queue);
    _queue = [...items, ...currentQueueSnapshot];
    
    // 3. 重建播放顺序
    await _rebuildOrder(startIndex: playIndex);
    
    // 4. 播放指定的歌曲（现在索引是playIndex，因为插入在顶部）
    _index = playIndex;
    _orderPos = _order.indexOf(_index);
    
    debugPrint('[Player] Playing from top: index=$_index, queueSize=${_queue.length}');
    await playItem(_queue[_index], failOnSkip: false);
    
    notifyListeners();
    _schedulePersist();
  }

  Future<void> playFromList(List<SearchItem> items, int startIndex, {String? quality}) async {
    await replaceQueueAndPlay(items, startIndex: startIndex, quality: quality);
  }
}