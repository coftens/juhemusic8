import 'dart:async';

import 'package:flutter/material.dart';

import '../api/php_api_client.dart';
import '../audio/player_service.dart';
import '../widgets/cached_cover_image.dart';

class LyricsPage extends StatefulWidget {
  const LyricsPage({
    super.key,
    required this.item,
    required this.cover,
  });

  final SearchItem item;
  final ImageProvider cover;

  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> {
  final _api = PhpApiClient();
  final _scroll = ScrollController();
  final _svc = PlayerService.instance;

  StreamSubscription<Duration>? _posSub;

  late SearchItem _item;
  late ImageProvider _cover;
  late String _shareUrl;

  bool _loading = true;
  String? _err;

  List<_LyricLine> _lines = const [];
  Map<int, String> _transByMs = const {};
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _cover = widget.cover;
    _shareUrl = widget.item.shareUrl;

    _load();
    _posSub = _svc.positionStream.listen(_onPos);
    _svc.addListener(_onSvc);
  }

  @override
  void dispose() {
    _svc.removeListener(_onSvc);
    _posSub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onSvc() {
    final cur = _svc.current;
    if (cur == null) return;
    if (cur.shareUrl == _shareUrl) return;

    _shareUrl = cur.shareUrl;
    _item = cur;
    _cover = cur.coverUrl.isEmpty ? _cover : cachedImageProvider(cur.coverUrl);
    _activeIndex = 0;
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final r = await _api.lyrics(_shareUrl);
      final lines = _parseLrc(r.lyricLrc);
      final trans = _parseLrcToMap(r.transLrc);
      if (!mounted) return;
      setState(() {
        _lines = lines;
        _transByMs = trans;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  void _onPos(Duration pos) {
    if (_lines.isEmpty) return;
    // 缓冲时暂停歌词滚动，防止歌词抢跑
    if (_svc.isBuffering) return;
    
    final ms = pos.inMilliseconds;
    final idx = _findActiveIndex(ms);
    if (idx == _activeIndex) return;
    _activeIndex = idx;

    if (_scroll.hasClients) {
      const itemExtent = 56.0;
      final target = (idx - 4).clamp(0, _lines.length).toDouble() * itemExtent;
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
    if (mounted) setState(() {});
  }

  int _findActiveIndex(int ms) {
    var lo = 0;
    var hi = _lines.length - 1;
    var ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final t = _lines[mid].ms;
      if (t <= ms) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: const Color(0xFFE7E7E7),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    color: Colors.black87,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          _item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleMedium?.copyWith(color: Colors.black87, fontWeight: FontWeight.w900),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _item.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall?.copyWith(color: Colors.black54, fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    color: Colors.black54,
                  ),
                ],
              ),
            ),
            if (_loading)
              const LinearProgressIndicator(minHeight: 2)
            else
              const SizedBox(height: 2),
            Expanded(
              child: _err != null
                  ? Center(child: Text(_err!, style: t.bodyMedium?.copyWith(color: Colors.redAccent)))
                  : _lines.isEmpty
                      ? Center(
                          child: Text(
                            '暂无歌词（可能是纯音乐或平台未提供）',
                            style: t.bodyMedium?.copyWith(color: Colors.black54, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(18, 26, 18, 26),
                          itemExtent: 56,
                          itemCount: _lines.length,
                          itemBuilder: (context, i) {
                            final active = (i == _activeIndex);
                            final line = _lines[i];
                            final trans = _transByMs[line.ms] ?? '';
                            return _LyricRow(
                              text: line.text,
                              trans: trans,
                              active: active,
                            );
                          },
                        ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _LyricRow extends StatelessWidget {
  const _LyricRow({required this.text, required this.trans, required this.active});

  final String text;
  final String trans;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final base = active ? Colors.black87 : Colors.black45;
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 160),
        style: t.titleMedium!.copyWith(
          color: base,
          fontWeight: active ? FontWeight.w900 : FontWeight.w600,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (trans.isNotEmpty)
              Text(
                trans,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall?.copyWith(
                  color: active ? Colors.black54 : Colors.black38,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LyricLine {
  const _LyricLine(this.ms, this.text);

  final int ms;
  final String text;
}

final _timeRe = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]');

List<_LyricLine> _parseLrc(String input) {
  final lines = <_LyricLine>[];
  for (final raw in input.split(RegExp(r'\r?\n'))) {
    final matches = _timeRe.allMatches(raw).toList();
    if (matches.isEmpty) continue;
    final text = raw.replaceAll(_timeRe, '').trim();
    if (text.isEmpty) continue;
    for (final m in matches) {
      final mm = int.parse(m.group(1)!);
      final ss = int.parse(m.group(2)!);
      final frac = m.group(3);
      final ms = frac == null
          ? 0
          : frac.length == 1
              ? int.parse(frac) * 100
              : frac.length == 2
                  ? int.parse(frac) * 10
                  : int.parse(frac.padRight(3, '0').substring(0, 3));
      final t = (mm * 60 + ss) * 1000 + ms;
      lines.add(_LyricLine(t, text));
    }
  }
  lines.sort((a, b) => a.ms.compareTo(b.ms));
  return lines;
}

Map<int, String> _parseLrcToMap(String input) {
  final out = <int, String>{};
  for (final l in _parseLrc(input)) {
    out[l.ms] = l.text;
  }
  return out;
}
