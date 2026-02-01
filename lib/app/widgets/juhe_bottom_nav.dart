import 'package:flutter/material.dart';

class JuheBottomNav extends StatelessWidget {
  const JuheBottomNav({
    super.key,
    required this.index,
    required this.onSelect,
  });

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.white.withOpacity(0.96),
        elevation: 12,
        shadowColor: Colors.black.withOpacity(0.12),
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              _NavSlot(i: 0, label: '首页', icon: Icons.home_outlined, iconSelected: Icons.home, index: index, onSelect: onSelect),
              _NavSlot(i: 1, label: '搜索', icon: Icons.search_outlined, iconSelected: Icons.search, index: index, onSelect: onSelect),
              _NavSlot(i: 2, label: '笔记', icon: Icons.edit_note_outlined, iconSelected: Icons.edit_note, index: index, onSelect: onSelect),
              _NavSlot(i: 3, label: '我的', icon: Icons.person_outline, iconSelected: Icons.person, index: index, onSelect: onSelect),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavSlot extends StatelessWidget {
  const _NavSlot({
    required this.i,
    required this.label,
    required this.icon,
    required this.iconSelected,
    required this.index,
    required this.onSelect,
  });

  final int i;
  final String label;
  final IconData icon;
  final IconData iconSelected;
  final int index;
  final ValueChanged<int> onSelect;

  static const _active = Color(0xFFE04A3A);
  static const _activeBg = Color(0xFFFFE6E2);

  @override
  Widget build(BuildContext context) {
    final selected = index == i;

    final fg = selected ? _active : Colors.black54;
    final bg = selected ? _activeBg : Colors.transparent;
    final shadow = selected
        ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ]
        : const <BoxShadow>[];

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onSelect(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            boxShadow: shadow,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? iconSelected : icon, color: fg, size: 22),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          label,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: fg,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.2,
                              ),
                        ),
                      )
                    : const SizedBox(width: 0, height: 0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
