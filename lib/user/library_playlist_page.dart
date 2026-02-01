import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api/php_api_client.dart';
import '../audio/player_service.dart';
import '../player/widgets/marquee_text.dart';
import '../player/now_playing_page.dart';
import '../ui/dominant_color.dart';

class LibraryPlaylistPage extends StatefulWidget {
  const LibraryPlaylistPage({
    super.key,
    required this.title,
    required this.items,
  });

  final String title;
  final List<SearchItem> items;

  @override
  State<LibraryPlaylistPage> createState() => _LibraryPlaylistPageState();
}

class _LibraryPlaylistPageState extends State<LibraryPlaylistPage> {
  final _svc = PlayerService.instance;
  Color _dominantHeader = const Color(0xFFE9E0FF);

  @override
  void initState() {
    super.initState();
    _ensureDominantHeader();
  }

  String get _coverUrl {
    if (widget.items.isNotEmpty) {
      return widget.items.first.coverUrl;
    }
    return '';
  }

  Future<void> _ensureDominantHeader() async {
    final url = _coverUrl;
    if (url.isEmpty) return;
    try {
      final provider = ResizeImage(NetworkImage(url), width: 96);
      final c = await dominantColorFromImage(provider);
      if (!mounted) return;
      setState(() {
        _dominantHeader = c;
      });
    } catch (_) {
      // ignore
    }
  }

  ImageProvider _cover() {
    final url = _coverUrl;
    if (url.isEmpty) {
      return MemoryImage(_transparentPng);
    }
    return NetworkImage(url);
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
                onPressed: () {},
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (_coverUrl.isNotEmpty)
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
                              child: _coverUrl.isEmpty
                                  ? Container(color: Colors.white24, child: const Icon(Icons.music_note, color: Colors.white54, size: 48))
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
                                  '${widget.items.length} 首歌曲',
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
                        Text('自动添加到播放列表', style: t.bodySmall?.copyWith(color: Colors.black54, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: widget.items.isEmpty
                        ? null
                        : () {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => NowPlayingPage(item: widget.items[0])));
                            Future.microtask(() {
                              _svc.replaceQueueAndPlay(widget.items, startIndex: 0);
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

          if (widget.items.isEmpty)
            const SliverFillRemaining(child: Center(child: Text('暂无歌曲')))
          else
            SliverList.separated(
              itemCount: widget.items.length,
              separatorBuilder: (_, __) => Divider(color: Colors.black.withOpacity(0.06), height: 1),
              itemBuilder: (context, i) {
                final s = widget.items[i];
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
                  title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                  titleTextStyle: t.titleMedium?.copyWith(color: Colors.black87, fontWeight: FontWeight.w900),
                  subtitleTextStyle: t.bodyMedium?.copyWith(color: Colors.black54, fontWeight: FontWeight.w600),
                  trailing: const Icon(Icons.play_arrow_rounded, color: Colors.black38),
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NowPlayingPage(item: s)));
                    Future.microtask(() {
                      _svc.replaceQueueAndPlay(widget.items, startIndex: i);
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

final Uint8List _transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/6XnZt0AAAAASUVORK5CYII=',
);