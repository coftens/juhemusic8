import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../audio/player_service.dart';
import 'now_playing_page.dart';

class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = PlayerService.instance;
    return AnimatedBuilder(
      animation: svc,
      builder: (context, _) {
        final it = svc.current;
        if (it == null) return const SizedBox.shrink();

        final durMs = svc.duration.inMilliseconds;
        final posMs = svc.position.inMilliseconds;
        final v = durMs <= 0 ? 0.0 : (posMs / durMs).clamp(0.0, 1.0);

        final ImageProvider cover = it.coverUrl.isEmpty ? MemoryImage(_transparentPng) : NetworkImage(it.coverUrl);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Material(
            color: Colors.transparent,
            elevation: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Material(
                color: Colors.white,
                elevation: 12,
                shadowColor: Colors.black.withOpacity(0.18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => NowPlayingPage(item: it)),
                    );
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(
                        value: v,
                        minHeight: 2,
                        backgroundColor: Colors.black.withOpacity(0.06),
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.black.withOpacity(0.55)),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: Image(image: cover, fit: BoxFit.cover),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    it.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          color: Colors.black87,
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    it.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Colors.black54,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => svc.toggle(),
                              icon: Icon(svc.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                              color: Colors.black87,
                            ),
                            IconButton(
                              onPressed: svc.hasNext ? () => svc.next() : null,
                              icon: const Icon(Icons.skip_next_rounded),
                              color: Colors.black87,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

final Uint8List _transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/6XnZt0AAAAASUVORK5CYII=',
);
