import 'package:flutter/material.dart';
import 'package:flutter_app/home/playlist_square_page.dart';


import '../api/php_api_client.dart';
import '../app/app_tabs.dart';
import '../audio/player_service.dart';
import '../player/now_playing_page.dart';
import '../playlist/playlist_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  static final ValueNotifier<int> tabRequest = ValueNotifier(0);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  final _api = PhpApiClient();
  
  late PageController _pageCtrl;
  int _activeIndex = 1; // 1: 推荐, 2: 歌单
  bool _loading = true;
  String? _err;

  List<_HomePlaylist> _playlists = const [];
  List<_HomeSong> _songs = const [];
  List<PlaylistSquareItem> _squarePlaylists = [];

  @override
  void initState() {
    super.initState();
    // 初始页面：推荐 (Index 0 for PageView corresponds to Tab 1)
    _pageCtrl = PageController(initialPage: 0); 
    HomePage.tabRequest.addListener(_handleRemoteTabChange);
    _load();
  }

  @override
  void dispose() {
    HomePage.tabRequest.removeListener(_handleRemoteTabChange);
    _pageCtrl.dispose();
    super.dispose();
  }

  void _handleRemoteTabChange() {
    final idx = HomePage.tabRequest.value;
    if (idx > 0) {
      // 这里的 idx 是 TopTabs 的索引 (1=Rec, 2=Sq)
      // 如果和当前不一样，或者需要强制切换
      if (_activeIndex != idx) {
        _onTabChanged(idx);
      }
      HomePage.tabRequest.value = 0; // Reset
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _err = null; });
    try {
      final qishuiSongs = await _api.getQishuiFeed(count: 6);
      final songs = qishuiSongs.map((item) => _HomeSong(
        mid: item.shareUrl,
        title: item.name,
        artist: item.artist,
        shareUrl: item.shareUrl,
        coverUrl: item.coverUrl,
        platform: item.platform,
      )).toList();
      
      final homeData = await _api.home();
      final squareData = await _api.getAllPlaylists();

      if (!mounted) return;
      setState(() {
        _playlists = homeData.playlists;
        _songs = songs;
        _squarePlaylists = squareData;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _err = e.toString(); });
    } finally {
      if (!mounted) return;
      setState(() { _loading = false; });
    }
  }

  void _onTabChanged(int index) {
    setState(() { _activeIndex = index; });
    // Tab 1 -> Page 0, Tab 2 -> Page 1
    final pageIndex = index - 1;
    if (pageIndex >= 0 && pageIndex <= 1 && _pageCtrl.hasClients) {
      _pageCtrl.animateToPage(
        pageIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F4),
      body: Stack(
        children: [
           // Static background gradient that stays behind header
           const _TopGradient(),
           SafeArea(
             child: NestedScrollView(
               headerSliverBuilder: (context, innerBoxIsScrolled) => [
                 SliverToBoxAdapter(
                   child: Padding(
                     padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                     child: Row(
                        children: [
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.menu_rounded),
                            color: Colors.black87,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _TopTabs(
                              active: _activeIndex,
                              onTabChanged: _onTabChanged,
                            ),
                          ),
                          IconButton(
                            onPressed: () { AppTabs.go(1); },
                            icon: const Icon(Icons.search_rounded),
                            color: Colors.black87,
                          ),
                        ],
                     ),
                   ),
                 ),
                 if (_loading)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(top: 120),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                 else if (_err != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 28, 16, 10),
                        child: Center(child: Text(_err!, style: TextStyle(color: Colors.redAccent))),
                      ),
                    ),
               ],
               body: _loading || _err != null 
                 ? const SizedBox()
                 : PageView(
                     controller: _pageCtrl,
                     onPageChanged: (i) {
                       setState(() { _activeIndex = i + 1; });
                     },
                     children: [
                       _KeepAliveWrapper(
                         child: _RecPageContent(
                           playlists: _playlists,
                           songs: _songs,
                           refresh: _load,
                         ),
                       ),
                       _KeepAliveWrapper(
                         child: _SqPageContent(
                           playlists: _squarePlaylists,
                           refresh: _load,
                         ),
                       ),
                     ],
                   ),
             ),
           ),
        ],
      ),
    );
  }
}

class _KeepAliveWrapper extends StatefulWidget {
  final Widget child;
  const _KeepAliveWrapper({required this.child});
  @override
  State<_KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<_KeepAliveWrapper> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _RecPageContent extends StatelessWidget {
  final List<_HomePlaylist> playlists;
  final List<_HomeSong> songs;
  final Future<void> Function() refresh;

  const _RecPageContent({required this.playlists, required this.songs, required this.refresh});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // NestedScrollView body needs a scrollable that supports PrimaryScrollController
    // CustomScrollView with key does this if we don't set controller manually.
    return RefreshIndicator(
      onRefresh: refresh,
      child: CustomScrollView(
        key: const PageStorageKey('rec_page'),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: _HeroCards(
                playlists: playlists.take(3).toList(),
                songs: songs,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: Row(
                children: [
                  Text(
                    songs.isEmpty ? '为你推荐' : '根据「${songs.first.title}」为你推荐',
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ),
          SliverList.separated(
            itemCount: songs.take(6).length,
            separatorBuilder: (_, __) => const SizedBox(height: 2),
            itemBuilder: (context, idx) {
              final s = songs[idx];
              return _SongRow(
                song: s,
                onTap: () async {
                   showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                  
                  try {
                    final api = PhpApiClient();
                    final qishuiList = await api.getQishuiFeed(count: 50);
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    
                    if (qishuiList.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无汽水音乐推荐')));
                      return;
                    }

                    final clickedItem = SearchItem(
                      platform: s.platform.isNotEmpty ? s.platform : 'qq',
                      name: s.title,
                      artist: s.artist,
                      shareUrl: s.shareUrl,
                      coverUrl: s.coverUrl,
                    );
                    
                    final dedupedList = qishuiList.where((e) => e.shareUrl != s.shareUrl).toList();
                    final playList = [clickedItem, ...dedupedList];
                    await PlayerService.instance.insertTopAndPlay(playList, 0);
                    
                    if (!context.mounted) return;
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NowPlayingPage(item: clickedItem)));
                  } catch (e) {
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败: $e')));
                  }
                },
              );
            },
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
              child: Row(
                children: [
                  Text('推荐歌单', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: Colors.black87)),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, color: Colors.black54),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 220,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, i) {
                  final p = playlists[i % playlists.length];
                  return _PlaylistCard(p: p);
                },
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemCount: playlists.isEmpty ? 0 : playlists.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _SqPageContent extends StatelessWidget {
  final List<PlaylistSquareItem> playlists;
  final Future<void> Function() refresh;

  const _SqPageContent({required this.playlists, required this.refresh});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: refresh,
      child: CustomScrollView(
        key: const PageStorageKey('sq_page'),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _SqBannerCard(),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 16,
                crossAxisSpacing: 12,
                childAspectRatio: 0.70, 
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = playlists[index];
                  return _SqPlaylistItem(item: item);
                },
                childCount: playlists.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}

class _TopGradient extends StatelessWidget {
  const _TopGradient();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        height: 220,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFF5A54),
              Color(0xFFFF8C7B),
              Color(0xFFF2F3F4),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
      ),
    );
  }
}

class _TopTabs extends StatelessWidget {
  const _TopTabs({required this.active, required this.onTabChanged});

  final int active;
  final ValueChanged<int> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final items = const ['心动', '推荐', '歌单', '播客', '听书', '午夜飞行'];
    final svc = PlayerService.instance;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: InkWell(
                onTap: () {
                  if (i == 0) {
                     // 心动: 保持原有逻辑
                     final cur = svc.current;
                     if (cur != null) {
                       Navigator.of(context).push(MaterialPageRoute(builder: (_) => NowPlayingPage(item: cur)));
                     } else {
                       Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NowPlayingPage()));
                     }
                  } else {
                    onTabChanged(i);
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      items[i],
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: i == active ? FontWeight.w800 : FontWeight.w500,
                        color: i == active ? Colors.black : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 6),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: i == active ? 22 : 0,
                      height: 2.2,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeroCards extends StatelessWidget {
  const _HeroCards({required this.playlists, required this.songs});

  final List<_HomePlaylist> playlists;
  final List<_HomeSong> songs;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: Row(
        children: [
          Expanded(
            child: _HeroCard(
              title: '每日推荐',
              subtitle: '今日限定好歌推荐',
              // Use the first song's cover from the daily songs list
              coverUrl: songs.isNotEmpty ? songs[0].coverUrl : (playlists.isNotEmpty ? playlists[0].coverUrl : ''),
              dark: true,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlaylistPage(
                      source: 'wyy',
                      id: 'daily_recommend',
                      title: '每日推荐',
                      // Pass the same cover url to the playlist page header
                      coverUrl: songs.isNotEmpty ? songs[0].coverUrl : '',
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _HeroCard(
              title: '雷达歌单',
              subtitle: '反复聆听你爱的歌',
              coverUrl: playlists.length > 1 ? playlists[1].coverUrl : '',
              dark: false,
              onTap: playlists.length > 1
                  ? () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PlaylistPage(
                            source: 'qq',
                            id: playlists[1].id,
                            title: playlists[1].title,
                            coverUrl: playlists[1].coverUrl,
                          ),
                        ),
                      );
                    }
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _HeroCard(
              title: '歌单推荐',
              subtitle: '主题曲指南',
              coverUrl: playlists.length > 2 ? playlists[2].coverUrl : '',
              dark: false,
              onTap: playlists.length > 2
                  ? () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PlaylistPage(
                            source: 'qq',
                            id: playlists[2].id,
                            title: playlists[2].title,
                            coverUrl: playlists[2].coverUrl,
                          ),
                        ),
                      );
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.dark,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String coverUrl;
  final bool dark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          Positioned.fill(
            child: coverUrl.isEmpty
                ? Container(color: dark ? Colors.black87 : const Color(0xFFE7E7E7))
                : Image.network(
                    coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: dark ? Colors.black87 : const Color(0xFFE7E7E7)),
                  ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(dark ? 0.25 : 0.10),
                    Colors.black.withOpacity(dark ? 0.62 : 0.30),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 14,
            top: 12,
            right: 14,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.titleLarge?.copyWith(
                color: dark ? Colors.white : Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 12,
            child: Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.bodyMedium?.copyWith(color: Colors.white70, fontWeight: FontWeight.w600),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 54,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.22),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap),
            ),
          ),
        ],
      ),
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({required this.song, required this.onTap});

  final _HomeSong song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 50,
          height: 50,
          child: song.coverUrl.isEmpty
              ? Container(color: Colors.black12)
              : Image.network(
                  song.coverUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: Colors.black12),
                ),
        ),
      ),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(color: Colors.black87, fontWeight: FontWeight.w700)),
      subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: Colors.black54)),
      trailing: const Icon(Icons.play_arrow_rounded, color: Colors.black45),
      onTap: onTap,
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.p});

  final _HomePlaylist p;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  p.coverUrl.isEmpty
                      ? Container(color: Colors.black12)
                      : Image.network(
                          p.coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: Colors.black12),
                        ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlaylistPage(
                              source: 'qq',
                              id: p.id,
                              title: p.title,
                              coverUrl: p.coverUrl,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            p.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.titleSmall?.copyWith(color: Colors.black87, fontWeight: FontWeight.w700, height: 1.2),
          ),
        ],
      ),
    );
  }
}

class HomeData {
  HomeData({required this.playlists, required this.songs});

  final List<_HomePlaylist> playlists;
  final List<_HomeSong> songs;
}

class _HomePlaylist {
  _HomePlaylist({required this.id, required this.title, required this.coverUrl});

  final String id;
  final String title;
  final String coverUrl;
}

class _HomeSong {
  _HomeSong({required this.mid, required this.title, required this.artist, required this.shareUrl, required this.coverUrl, this.platform = ''});

  final String mid;
  final String title;
  final String artist;
  final String shareUrl;
  final String coverUrl;
  final String platform;
}

extension HomeApi on PhpApiClient {
  Future<HomeData> home() async {
    final j = await rawGet('/home.php', const {});
    final code = (j['code'] as num?)?.toInt() ?? 500;
    if (code != 200) {
      throw Exception(j['msg'] ?? 'home failed');
    }
    final data = (j['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final sections = (data['sections'] as Map?)?.cast<String, dynamic>() ?? const {};
    final hotRecommend = (sections['hotRecommend'] as List?)?.cast<dynamic>() ?? const [];
    final newSonglist = (sections['newSonglist'] as List?)?.cast<dynamic>() ?? const [];

    final playlists = <_HomePlaylist>[];
    for (final it in hotRecommend) {
      if (it is! Map) continue;
      final m = it.cast<String, dynamic>();
      playlists.add(
        _HomePlaylist(
          id: (m['id'] as String?) ?? '',
          title: (m['title'] as String?) ?? '',
          coverUrl: (m['cover_url'] as String?) ?? '',
        ),
      );
    }

    final songs = <_HomeSong>[];
    for (final it in newSonglist) {
      if (it is! Map) continue;
      final m = it.cast<String, dynamic>();
      songs.add(
        _HomeSong(
          mid: (m['mid'] as String?) ?? '',
          title: (m['title'] as String?) ?? '',
          artist: (m['artist'] as String?) ?? '',
          shareUrl: (m['share_url'] as String?) ?? '',
          coverUrl: (m['cover_url'] as String?) ?? '',
          platform: (m['source'] as String?) ?? '',
        ),
      );
    }
    return HomeData(playlists: playlists, songs: songs);
  }
}

class _SqBannerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF9C27B0), Color(0xFF673AB7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            bottom: -20,
            child: Icon(Icons.music_note, size: 120, color: Colors.white.withOpacity(0.1)),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  '歌单新势力',
                  style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 2),
                ),
                const SizedBox(height: 8),
                const Text(
                  '「复古浪潮」主题歌单',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('点击查看 >', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SqPlaylistItem extends StatelessWidget {
  final PlaylistSquareItem item;

  const _SqPlaylistItem({required this.item});

  String _formatCount(int count) {
    if (count > 10000) return '${(count / 10000).toStringAsFixed(1)}万';
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PlaylistPage(
            source: item.source,
            id: item.id,
            title: item.title,
            coverUrl: item.coverUrl,
          ),
        ));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                Hero(
                  tag: 'sq_${item.id}',
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      image: DecorationImage(
                        image: NetworkImage(item.coverUrl),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 12),
                        const SizedBox(width: 2),
                        Text(
                          _formatCount(item.playCount),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.2),
          ),
        ],
      ),
    );
  }
}
