import 'package:flutter/material.dart';
import 'dart:async';

import 'package:just_audio_background/just_audio_background.dart';

import 'api/api_config.dart';
import 'auth/auth_session.dart';
import 'audio/player_service.dart';
import 'app/root_gate.dart';

Future<void> main() async {
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConfig.instance.load();
  await AuthSession.instance.load();
  // Restore last playback snapshot (queue/index/position) and re-parse if needed.
  unawaited(PlayerService.instance.restoreState());
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Music',
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFFE04A3A),
        // Keep scaffold background transparent so the area behind
        // floating mini-player/nav can show page content.
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
      ),
      home: const RootGate(),
    );
  }
}
