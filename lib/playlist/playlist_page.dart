import 'package:flutter/material.dart';

import '../api/php_api_client.dart';
import '../audio/player_service.dart';
import '../player/widgets/marquee_text.dart';
import '../player/now_playing_page.dart';
import '../storage/user_library.dart';
import '../ui/dominant_color.dart';

class PlaylistPage extends StatefulWidget {
  const PlaylistPage({
    super.key,
    required this.source,
    required this.id,
    required this.title,
    required this.coverUrl,
  });

  final String source;
  final String id;
  final String title;
  final String coverUrl;

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  final _api = PhpApiClient();
  final _svc = PlayerService.instance;

  bool _loading = true;
  String? _err;
  PlaylistDetail? _detail;
  List<SearchItem> _queue = const [];
  bool _isFavorite = false;

  Color _dominantHeader = const Color(0xFFE9E0FF);

  @override
  void initState() {
    super.initState();
    _load();
    _ensureDominantHeader();
    _checkFavorite();
  }

  Future<void> _checkFavorite() async {
    final fav = await UserLibrary.instance.isPlaylistFavorite(widget.source, widget.id);
    if (mounted) setState(() => _isFavorite = fav);
  }

  Future<void> _toggleFavorite() async {
    final info = PlaylistInfo(
      id: 0,
      platform: widget.source,
      externalId: widget.id,
      name: widget.title,
      coverUrl: widget.coverUrl,
      trackCount: _detail?.list.length ?? 0,
    );
    await UserLibrary.instance.togglePlaylistFavorite(info);
    if (mounted) _checkFavorite();
  }

  @override
  void didUpdateWidget(covariant PlaylistPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverUrl != widget.coverUrl) {
      _ensureDominantHeader();
    }
  }

  Future<void> _ensureDominantHeader() async {
    if (widget.coverUrl.isEmpty) return;
    try {
      final provider = ResizeImage(NetworkImage(widget.coverUrl), width: 96);
      final c = await dominantColorFromImage(provider);
      if (!mounted) return;
      setState(() {
        _dominantHeader = c;
      });
    } catch (_) {
      // ignore
    }
  }

  Future<void> _load() async {
    print('PlaylistPage loading: source=${widget.source}, id=${widget.id}');
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final d = await _api.playlist(source: widget.source, id: widget.id, limit: 200);
      print('PlaylistPage API Response: ${d.list.length} tracks');
      if (!mounted) return;
      setState(() {
        _detail = d;
        _queue = [
          for (final s in d.list)
            SearchItem(
              platform: widget.source,
              name: s.title,
              artist: s.artist,
              shareUrl: s.shareUrl,
              coverUrl: s.coverUrl,
            ),
        ];
      });
    } catch (e, s) {
      print('PlaylistPage Error: $e\n$s');
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

  ImageProvider _cover() {
    if (widget.coverUrl.isEmpty) {
      return const AssetImage('');
    }
    return NetworkImage(widget.coverUrl);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cover = _cover();
    const appBg = Color(0xFFF2F3F4);
    final domTop = _dominantHeader;
    final domMid = Color.lerp(domTop, Colors.white, 0.12) ?? domTop;
    final barFg = domTop.computeLuminance() > 0.75 ? Colors.black87 : Colors.white;

    return Scaffold(
      backgroundColor: appBg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 270,
            backgroundColor: domTop,
            foregroundColor: barFg,
            elevation: 0,
            title: MarqueeText(
              widget.title,
              style: (t.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
                color: barFg,
                fontWeight: FontWeight.w800,
              ),
              speedPxPerSec: 32,
            ),
            actions: [
              IconButton(
                onPressed: _toggleFavorite,
                icon: Icon(_isFavorite ? Icons.star_rounded : Icons.star_outline_rounded),
                color: _isFavorite ? const Color(0xFFFFC107) : barFg,
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.coverUrl.isNotEmpty)
                    Image(
                      image: cover,
                      fit: BoxFit.cover,
                      color: Colors.black.withOpacity(0.25),
                      colorBlendMode: BlendMode.darken,
                    )
                  else
                    Container(color: domTop),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x66000000),
                          Color(0x00000000),
                        ],
                        stops: [0.0, 0.5],
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          domTop,
                          domMid,
                          appBg,
                        ],
                        stops: const [0.0, 0.62, 1.0],
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 96, 16, 18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: SizedBox(
                              width: 112,
                              height: 112,
                              child: widget.coverUrl.isEmpty
                                  ? Container(color: Colors.white24)
                                  : Image(image: cover, fit: BoxFit.cover),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                MarqueeText(
                                  widget.title,
                                  style: (t.headlineSmall ?? const TextStyle(fontSize: 22)).copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    height: 1.1,
                                  ),
                                  speedPxPerSec: 34,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _detail == null ? '' : '${_detail!.list.length} 首歌曲',
                                  style: t.bodyMedium?.copyWith(color: Colors.white70, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(color: Color(0xFFE04A3A), shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('播放全部', style: t.titleLarge?.copyWith(color: Colors.black87, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text('替换当前播放列表', style: t.bodySmall?.copyWith(color: Colors.black54, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: _queue.isEmpty
                        ? null
                        : () {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => NowPlayingPage(item: _queue[0])));
                            Future.microtask(() {
                              _svc.replaceQueueAndPlay(_queue, startIndex: 0);
                            });
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.06),
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('播放'),
                  ),
                ],
              ),
            ),
          ),

          if (_loading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (_err != null)
            SliverFillRemaining(
              child: Center(child: Text(_err!, style: t.bodyMedium?.copyWith(color: Colors.redAccent))),
            )
          else if (_detail == null)
            const SliverFillRemaining(child: Center(child: Text('空')))
          else
            SliverList.separated(
              itemCount: _detail!.list.length,
              separatorBuilder: (_, __) => Divider(color: Colors.black.withOpacity(0.06), height: 1),
              itemBuilder: (context, i) {
                final s = _detail!.list[i];
                final item = (i >= 0 && i < _queue.length)
                    ? _queue[i]
                    : SearchItem(
                        platform: widget.source,
                        name: s.title,
                        artist: s.artist,
                        shareUrl: s.shareUrl,
                        coverUrl: s.coverUrl,
                      );

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 54,
                      height: 54,
                      child: s.coverUrl.isEmpty
                          ? Container(color: Colors.black12)
                          : Image.network(
                              s.coverUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(color: Colors.black12),
                            ),
                    ),
                  ),
                  title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                  titleTextStyle: t.titleMedium?.copyWith(color: Colors.black87, fontWeight: FontWeight.w900),
                  subtitleTextStyle: t.bodyMedium?.copyWith(color: Colors.black54, fontWeight: FontWeight.w600),
                  trailing: const Icon(Icons.play_arrow_rounded, color: Colors.black38),
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NowPlayingPage(item: item)));
                    Future.microtask(() {
                      _svc.replaceQueueAndPlay(_queue, startIndex: i);
                    });
                  },
                );
              },
            ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 26)),
        ],
      ),
    );
  }
}
