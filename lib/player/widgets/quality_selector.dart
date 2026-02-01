import 'package:flutter/material.dart';

class QualitySelector extends StatelessWidget {
  const QualitySelector({
    super.key,
    required this.selected,
    required this.available,
    required this.onSelected,
  });

  final String selected;
  final List<String> available;
  final ValueChanged<String> onSelected;

  String _label(String q) {
    // Unified quality mapping for QQ and WYY
    // WYY: jymaster(母带), jyeffect(环绕), sky(沉浸), hires(Hi-Res), lossless(无损)
    // QQ: atmos_51(臻品音质2.0), atmos_2(臻品全景声2.0), master(臻品母带3.0), flac(SQ无损), 320(HQ高品质), 128(标准音质)
    switch (q) {
      // WYY high quality
      case 'jymaster':
        return '母带';
      case 'jyeffect':
        return '环绕';
      case 'sky':
        return '沉浸';
      case 'hires':
        return 'Hi-Res';
      case 'lossless':
        return '无损';

      // QQ high quality (app display order)
      case 'atmos_51':
        return '5.1';
      case 'atmos_2':
        return '全景';
      case 'master':
        return '母带';
      case 'flac':
        return 'SQ无损';
      case '320':
        return 'HQ';
      case 'ogg_320':
        return 'OGG';
      case 'aac_192':
        return 'AAC';
      case 'ogg_192':
        return 'OGG';
      case '128':
        return '标准音质';
      case 'aac_96':
        return 'AAC';

      // Other formats (both platforms)
      case 'exhigh':
        return '极高';
      case 'standard':
        return '标准';
      default:
        return '标准';
    }
  }
 
  @override
  Widget build(BuildContext context) {
    if (available.isEmpty) {
      return const SizedBox.shrink();
    }
    final text = Theme.of(context).textTheme;
    final priority = <String>[
      // WYY
      'jymaster',
      'sky',
      'jyeffect',
      'hires',
      // QQ (app display order: 臻品音质/臻品全景声/臻品母带/SQ无损/HQ高品质/OGG高品质/AAC高品质/OGG标准/标准)
      'atmos_51',
      'atmos_2',
      'master',
      'flac',
      '320',
      'ogg_320',
      'aac_192',
      'ogg_192',
      '128',
      'aac_96',
      // common
      'lossless',
      'exhigh',
      'standard',
    ];

    final ordered = priority.where(available.contains).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final q in ordered)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _Pill(
                label: _label(q),
                active: q == selected,
                onTap: () => onSelected(q),
                text: text,
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.active,
    required this.onTap,
    required this.text,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final bg = active ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.06);
    final br = active ? Colors.white24 : Colors.white10;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: br),
        ),
        child: Text(
          label,
          style: text.labelLarge?.copyWith(
            color: active ? Colors.white : Colors.white60,
            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
