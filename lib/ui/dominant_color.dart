import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

Future<Color> dominantColorFromImage(
  ImageProvider provider, {
  Color fallback = const Color(0xFFE9E0FF),
  double minLuminance = 0.08,
  double maxLuminance = 0.92,
}) async {
  final c = Completer<Color>();
  late final ImageStreamListener l;

  void done(Color color) {
    if (!c.isCompleted) c.complete(color);
  }

  l = ImageStreamListener(
    (info, _) async {
      try {
        final img = info.image;
        final bd = await img.toByteData(format: ImageByteFormat.rawRgba);
        if (bd == null) {
          done(fallback);
          return;
        }

        final bytes = bd.buffer.asUint8List();
        final w = img.width;
        final h = img.height;

        final step = math.max(1, (math.min(w, h) / 48).floor());

        int validCount = 0;
        int validR = 0;
        int validG = 0;
        int validB = 0;

        int totalCount = 0;
        int totalR = 0;
        int totalG = 0;
        int totalB = 0;

        for (var y = 0; y < h; y += step) {
          for (var x = 0; x < w; x += step) {
            final i = (y * w + x) * 4;
            if (i + 2 >= bytes.length) continue;
            final r = bytes[i];
            final g = bytes[i + 1];
            final b = bytes[i + 2];
            
            totalR += r;
            totalG += g;
            totalB += b;
            totalCount++;

            // Convert to simple saturation/lightness estimate
            final max = math.max(r, math.max(g, b));
            final min = math.min(r, math.min(g, b));
            final delta = max - min;
            final lum = (max + min) / (2 * 255.0);
            
            // Ignore near-black or near-white
            if (lum < 0.1 || lum > 0.9) continue;
            
            // Ignore grayscale (low saturation)
            final sat = (lum > 0.5) ? (delta / (2 * 255.0 - max - min)) : (delta / (max + min));
            if (sat < 0.15) continue;

            validR += r;
            validG += g;
            validB += b;
            validCount++;
          }
        }

        Color finalColor;
        if (validCount > totalCount * 0.05) {
          // If we found enough vibrant pixels, use their average
          finalColor = Color.fromARGB(255, (validR / validCount).round(), (validG / validCount).round(), (validB / validCount).round());
        } else {
          // Otherwise (e.g. B&W image), fall back to total average
          if (totalCount == 0) {
             done(fallback);
             return;
          }
          finalColor = Color.fromARGB(255, (totalR / totalCount).round(), (totalG / totalCount).round(), (totalB / totalCount).round());
        }

        // Final sanity check: if result is still extremely dark/bright, fallback
        final fLum = finalColor.computeLuminance();
        if (fLum < 0.05 || fLum > 0.95) {
          finalColor = fallback;
        }
        done(finalColor);
      } catch (_) {
        done(fallback);
      }
    },
    onError: (_, __) => done(fallback),
  );

  final stream = provider.resolve(const ImageConfiguration());
  stream.addListener(l);
  final res = await c.future;
  stream.removeListener(l);
  return res;
}
