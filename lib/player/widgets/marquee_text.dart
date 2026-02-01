import 'dart:math' as math;

import 'package:flutter/material.dart';

class MarqueeText extends StatefulWidget {
  const MarqueeText(
    this.text, {
    super.key,
    required this.style,
    this.gap = 28,
    this.speedPxPerSec = 28,
    this.pause = const Duration(milliseconds: 650),
  });

  final String text;
  final TextStyle style;
  final double gap;
  final double speedPxPerSec;
  final Duration pause;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  double _textW = 0;
  double _boxW = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _sync() {
    if (_boxW <= 0 || _textW <= 0) return;
    final overflow = _textW - _boxW;
    if (overflow <= 2) {
      _ctrl.stop();
      _ctrl.value = 0;
      return;
    }
    final dist = overflow + widget.gap;
    final seconds = math.max(2.0, dist / widget.speedPxPerSec);
    _ctrl.duration = Duration(milliseconds: (seconds * 1000).round());
    if (!_ctrl.isAnimating) {
      _loop();
    }
  }

  Future<void> _loop() async {
    while (mounted) {
      _ctrl.value = 0;
      await Future<void>.delayed(widget.pause);
      if (!mounted) return;
      await _ctrl.forward();
      if (!mounted) return;
      await Future<void>.delayed(widget.pause);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _boxW = c.maxWidth;
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        _textW = tp.width;
        WidgetsBinding.instance.addPostFrameCallback((_) => _sync());

        return ClipRect(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final overflow = _textW - _boxW;
              if (overflow <= 2) {
                return Text(widget.text, style: widget.style, maxLines: 1, overflow: TextOverflow.ellipsis);
              }
              final x = -(_ctrl.value * (overflow + widget.gap));
              return Transform.translate(
                offset: Offset(x, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.text, style: widget.style, maxLines: 1),
                    SizedBox(width: widget.gap),
                    Text(widget.text, style: widget.style, maxLines: 1),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
