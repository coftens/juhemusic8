import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../api/php_api_client.dart';
import '../audio/player_service.dart';
import '../player/now_playing_page.dart';
import '../player/widgets/marquee_text.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.onBackToHome});

  final VoidCallback? onBackToHome;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with SingleTickerProviderStateMixin {
  final _api = PhpApiClient();
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  late final AnimationController _hintCtrl;
  Timer? _hintTimer;
  List<String> _hintPool = const [];
  int _hintIndex = 0;
  String _hintText = '我怀念的 孙燕姿';
  String? _hintPrev;

  String _platform = 'all';
  bool _loading = false;
  String? _err;
  List<SearchItem> _results = const [];

  List<String> _history = const ['我怀念的'];
  List<String> _guess = const ['把回忆拼好给你', '红色高跟鞋', '爱情讯息', '演员', '我怀念的', '雨爱'];
  List<ChartItem> _hotChart = const [];
  List<ChartItem> _soaringChart = const [];
  List<ChartItem> _hotChartAll = const [];
  List<ChartItem> _soaringChartAll = const [];
  bool _loadingDiscover = true;

  List<SearchItem> _chartToQueue(List<ChartItem> items) {
    return [
      for (final c in items)
        SearchItem(
          platform: _platformFromShareUrl(c.shareUrl),
          name: c.title,
          artist: c.artist,
          shareUrl: c.shareUrl,
          coverUrl: '',
        ),
    ];
  }

  String _platformFromShareUrl(String url) {
    final u = url.toLowerCase();
    if (u.contains('music.163.com')) return 'wyy';
    if (u.contains('y.qq.com')) return 'qq';
    return 'qq';
  }

  Future<void> _playChart(List<ChartItem> items, {int startIndex = 0}) async {
    if (items.isEmpty) return;
    final q = _chartToQueue(items);
    startIndex = startIndex.clamp(0, q.length - 1);
    await PlayerService.instance.replaceQueueAndPlay(q, startIndex: startIndex);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NowPlayingPage(item: q[startIndex])));
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _hintCtrl.dispose();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _hintCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _hintPool = _buildHintPool();
    _hintText = _hintPool.isNotEmpty ? _hintPool.first : _hintText;
    _hintTimer = Timer.periodic(const Duration(seconds: 3), (_) => _rotateHint());
    _loadDiscover();
  }

  List<String> _buildHintPool() {
    final base = <String>[
      '我怀念的 孙燕姿',
      ..._guess,
    ];

    // Prefer discovered chart titles if available.
    final fromCharts = <String>[];
    for (final c in [..._hotChart, ..._soaringChart]) {
      final t = '${c.title} ${c.artist}'.trim();
      if (t.isNotEmpty) fromCharts.add(t);
    }

    final seen = <String>{};
    final out = <String>[];
    for (final s in [...fromCharts, ...base]) {
      final v = s.trim();
      if (v.isEmpty) continue;
      if (seen.add(v)) out.add(v);
    }
    return out;
  }

  void _rotateHint() {
    if (!mounted) return;
    if (_focus.hasFocus) return;
    if (_ctrl.text.trim().isNotEmpty) return;
    if (_hintPool.length <= 1) return;
    if (_hintCtrl.isAnimating) return;

    final next = _hintPool[(_hintIndex + 1) % _hintPool.length];
    setState(() {
      _hintPrev = _hintText;
      _hintIndex = (_hintIndex + 1) % _hintPool.length;
      _hintText = next;
    });
    _hintCtrl.forward(from: 0);
  }

  Future<void> _loadDiscover() async {
    setState(() {
      _loadingDiscover = true;
    });
    try {
      final hotAll = await _api.chart(source: 'all', type: 'hot', limit: 200);
      final soarAll = await _api.chart(source: 'all', type: 'soaring', limit: 200);
      if (!mounted) return;
      setState(() {
        _hotChartAll = hotAll;
        _soaringChartAll = soarAll;
        _hotChart = hotAll.take(50).toList();
        _soaringChart = soarAll.take(50).toList();
      });
      final pool = _buildHintPool();
      if (!mounted) return;
      if (pool.isNotEmpty) {
        setState(() {
          _hintPool = pool;
          if (!_hintPool.contains(_hintText)) {
            _hintIndex = 0;
            _hintText = _hintPool.first;
            _hintPrev = null;
          } else {
            _hintIndex = _hintPool.indexOf(_hintText);
          }
        });
      }
    } catch (_) {
      // ignore discover load errors
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingDiscover = false;
      });
    }
  }

  Future<void> _doSearch() async {
    var kw = _ctrl.text.trim();
    if (kw.isEmpty) {
      kw = _hintText.trim();
      if (kw.isEmpty) return;
      _ctrl.text = kw;
      _ctrl.selection = TextSelection.fromPosition(TextPosition(offset: kw.length));
    }

    setState(() {
      if (!_history.contains(kw)) {
        _history = [kw, ..._history].take(10).toList();
      }
    });

    setState(() {
      _loading = true;
      _err = null;
      _results = const [];
    });
    try {
      final res = await _api.search(keyword: kw, platform: _platform, limit: 20);
      if (!mounted) return;
      setState(() {
        final qq = res.where((e) => e.platform == 'qq').toList();
        final wyy = res.where((e) => e.platform == 'wyy').toList();
        final interleaved = <SearchItem>[];
        int i = 0;
        while (i < qq.length || i < wyy.length) {
          if (i < qq.length) interleaved.add(qq[i]);
          if (i < wyy.length) interleaved.add(wyy[i]);
          i++;
        }
        _results = interleaved;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final hasQuery = _ctrl.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                color: const Color(0xFFF2F3F4).withOpacity(0.85),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          if (_ctrl.text.isNotEmpty) {
                            setState(() {
                              _ctrl.clear();
                              _results = const [];
                              _err = null;
                              _loading = false;
                            });
                            _focus.unfocus();
                          } else {
                            widget.onBackToHome?.call();
                          }
                        },
                        icon: const Icon(Icons.chevron_left_rounded),
                        color: Colors.black87,
                      ),
                      Expanded(
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.search_rounded, color: Colors.black38),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _ctrl,
                                  focusNode: _focus,
                                  onChanged: (_) => setState(() {}),
                                  style: const TextStyle(color: Colors.black87),
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (_) => _doSearch(),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    hint: _RotatingHint(
                                      ctrl: _hintCtrl,
                                      prev: _hintPrev,
                                      text: _hintText,
                                      style: const TextStyle(color: Colors.black45),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: _loading ? null : _doSearch,
                        child: Text('搜索', style: theme.textTheme.titleMedium?.copyWith(color: Colors.black87, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                if (_err != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(_err!, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.redAccent)),
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      hasQuery
                          ? _ResultsList(
                              results: _results,
                              onTapIndex: (i) {
                                if (i < 0 || i >= _results.length) return;
                                final svc = PlayerService.instance;
                                final old = svc.snapshotQueue();
                                svc.insertAsNextThenPlay(_results[i], old);
                                Navigator.of(context).push(MaterialPageRoute(builder: (_) => NowPlayingPage(item: _results[i])));
                              },
                            )
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                              children: [
                                _IconGrid(),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Text('搜索历史', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                                    const Spacer(),
                                    IconButton(onPressed: () => setState(() => _history = const []), icon: const Icon(Icons.delete_outline_rounded), color: Colors.black45),
                                  ],
                                ),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    for (final h in _history)
                                      _Chip(
                                        label: h,
                                        onTap: () {
                                          _ctrl.text = h;
                                          _ctrl.selection = TextSelection.fromPosition(TextPosition(offset: h.length));
                                          _doSearch();
                                        },
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                Row(
                                  children: [
                                    Text('猜你喜欢', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                                    const Spacer(),
                                    IconButton(onPressed: _loadDiscover, icon: const Icon(Icons.refresh_rounded), color: Colors.black45),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                _GuessGrid(items: _guess, onTap: (s) {
                                  _ctrl.text = s;
                                  _ctrl.selection = TextSelection.fromPosition(TextPosition(offset: s.length));
                                  _doSearch();
                                }),
                                const SizedBox(height: 18),
                                if (_loadingDiscover)
                                  const Center(child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator()))
                                else
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _ChartCard(
                                          title: '热搜榜',
                                          list: _soaringChart,
                                          onPlayAll: () => _playChart(_soaringChartAll, startIndex: 0),
                                          onPlayIndex: (i) => _playChart(_soaringChartAll, startIndex: i),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _ChartCard(
                                          title: '热歌榜',
                                          list: _hotChart,
                                          onPlayAll: () => _playChart(_hotChartAll, startIndex: 0),
                                          onPlayIndex: (i) => _playChart(_hotChartAll, startIndex: i),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                      if (_loading)
                        Positioned.fill(
                          child: Container(
                            color: Colors.white.withOpacity(0.5),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFFE04A3A),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const items = [
      ('歌手', Icons.person_rounded),
      ('曲风', Icons.music_note_rounded),
      ('专区', Icons.grid_view_rounded),
      ('识曲', Icons.mic_rounded),
      ('听书', Icons.headphones_rounded),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final it in items)
          Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 6)),
                  ],
                ),
                child: Icon(it.$2, color: Colors.black87),
              ),
              const SizedBox(height: 6),
              Text(it.$1, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.black54, fontWeight: FontWeight.w700)),
            ],
          ),
      ],
    );
  }
}

class _RotatingHint extends StatelessWidget {
  const _RotatingHint({
    required this.ctrl,
    required this.prev,
    required this.text,
    required this.style,
  });

  final AnimationController ctrl;
  final String? prev;
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final cur = text.trim();
    if (cur.isEmpty) return const SizedBox.shrink();

    final p = (prev ?? '').trim();
    final a = CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic);

    return IgnorePointer(
      child: ClipRect(
        child: SizedBox(
          height: 20,
          child: AnimatedBuilder(
            animation: a,
            builder: (context, _) {
              final t = a.value;
              final showPrev = p.isNotEmpty && ctrl.isAnimating;

              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  if (showPrev)
                    Opacity(
                      opacity: 1.0 - t,
                      child: Transform.translate(
                        offset: Offset(0, -18 * t),
                        child: Text(p, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
                      ),
                    ),
                  Opacity(
                    opacity: showPrev ? t : 1.0,
                    child: Transform.translate(
                      offset: Offset(0, showPrev ? (18 * (1 - t)) : 0),
                      child: Text(cur, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black.withOpacity(0.05)),
        ),
        child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black87, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _GuessGrid extends StatelessWidget {
  const _GuessGrid({required this.items, required this.onTap});

  final List<String> items;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final left = <String>[];
    final right = <String>[];
    for (var i = 0; i < items.length; i++) {
      (i.isEven ? left : right).add(items[i]);
    }
    Widget col(List<String> items) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: InkWell(
                  onTap: () => onTap(s),
                  child: Text(s, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.black87, fontWeight: FontWeight.w700)),
                ),
              ),
          ],
        ),
      );
    }

    return Row(
      children: [
        col(left),
        const SizedBox(width: 16),
        col(right),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.list,
    required this.onPlayAll,
    required this.onPlayIndex,
  });

  final String title;
  final List<ChartItem> list;
  final VoidCallback onPlayAll;
  final ValueChanged<int> onPlayIndex;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // Limit display to top 10
    final displayList = list.take(10).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: list.isEmpty ? null : onPlayAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.black.withOpacity(0.06)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_arrow_rounded, size: 16, color: Colors.black87),
                      const SizedBox(width: 2),
                      Text('播放', style: t.labelMedium?.copyWith(color: Colors.black87, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < displayList.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onPlayIndex(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 26,
                        child: Text(
                          '${i + 1}',
                          style: t.titleMedium?.copyWith(
                            color: i < 3 ? const Color(0xFFE63946) : Colors.black54,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      // Platform indicator
                      Builder(builder: (_) {
                        final u = displayList[i].shareUrl;
                        final isWyy = u.contains('music.163.com');
                        final color = isWyy ? const Color(0xFFE63946) : const Color(0xFF2A9D8F);
                        return Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        );
                      }),
                      Expanded(
                        child: MarqueeText(
                          displayList[i].title,
                          style: t.titleMedium?.copyWith(color: Colors.black87, fontWeight: FontWeight.w700) ?? const TextStyle(),
                        ),
                      ),
                      const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.black38),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.results, required this.onTapIndex});

  final List<SearchItem> results;
  final ValueChanged<int> onTapIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (results.isEmpty) {
      return Center(child: Text('暂无结果', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black45)));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      itemCount: results.length,
      separatorBuilder: (_, __) => Divider(color: Colors.black.withOpacity(0.05)),
      itemBuilder: (context, i) {
        final it = results[i];
        return ListTile(
          onTap: () => onTapIndex(i),
          leading: _PlatformBadge(platform: it.platform),
          title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(it.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
          titleTextStyle: theme.textTheme.titleMedium?.copyWith(color: Colors.black87, fontWeight: FontWeight.w800),
          subtitleTextStyle: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
          trailing: const Icon(Icons.play_arrow_rounded, color: Colors.black38),
        );
      },
    );
  }
}

class _PlatformBadge extends StatelessWidget {
  const _PlatformBadge({required this.platform});

  final String platform;

  @override
  Widget build(BuildContext context) {
    final label = switch (platform) {
      'qq' => 'QQ',
      'wyy' => '网易',
      _ => platform,
    };
    final color = switch (platform) {
      'qq' => const Color(0xFF2A9D8F),
      'wyy' => const Color(0xFFE63946),
      _ => Colors.white54,
    };
    return Container(
      width: 46,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
