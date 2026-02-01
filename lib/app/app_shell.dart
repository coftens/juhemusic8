import 'package:flutter/material.dart';

import '../api/api_config.dart';
import 'app_tabs.dart';
import '../home/home_page.dart';
import '../player/mini_player_bar.dart';
import '../search/search_page.dart';
import '../user/me_page.dart';
import 'setup_page.dart';
import 'widgets/juhe_bottom_nav.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _idx;

  void _syncFromNotifier() {
    final v = AppTabs.index.value;
    if (v != _idx && mounted) {
      setState(() => _idx = v);
    }
  }

  @override
  void initState() {
    super.initState();
    _idx = widget.initialTab.clamp(0, 3);
    AppTabs.index.value = _idx;
    AppTabs.index.addListener(_syncFromNotifier);
  }

  @override
  void dispose() {
    AppTabs.index.removeListener(_syncFromNotifier);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ApiConfig.instance.isConfigured) {
      return const SetupPage();
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F4), // Base background
      body: Stack(
        children: [
          // 1. Bottom Layer: Content
          Positioned.fill(
            child: IndexedStack(
              index: _idx == 1 ? 0 : _idx,
              children: [
                const HomePage(),
                const SizedBox(), // Placeholder for search index
                const _NotesStub(),
                const MePage(),
              ],
            ),
          ),

          // 2. Search Overlay (if active)
          if (_idx == 1)
            Positioned.fill(
              child: SearchPage(
                onBackToHome: () {
                  AppTabs.go(0);
                },
              ),
            ),

          // 3. Top Layer: Floating Pills
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: false, // Ensure children still receive touches
              child: Container(
                color: Colors.transparent, // Explicitly transparent
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const MiniPlayerBar(),
                    const SizedBox(height: 10),
                    JuheBottomNav(
                      index: _idx,
                      onSelect: (i) {
                        setState(() => _idx = i);
                        AppTabs.go(i);
                      },
                    ),
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

class _NotesStub extends StatelessWidget {
  const _NotesStub();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF2F3F4),
      body: Center(child: Text('笔记（待实现）')),
    );
  }
}
