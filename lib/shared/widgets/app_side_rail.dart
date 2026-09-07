import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class AppSideRailItem {
  const AppSideRailItem({
    required this.icon,
    required this.label,
    required this.path,
  });

  final IconData icon;
  final String label;
  final String path;
}

/// 와이드 레이아웃용 좌측 다크블루 네비게이션 레일 (아이콘 + 라벨)
class AppSideRail extends StatelessWidget {
  const AppSideRail({
    super.key,
    required this.items,
    required this.location,
    required this.onNavigate,
    this.onLogout,
    this.profile,
    this.isSelected,
    this.width = 208,
  });

  final List<AppSideRailItem> items;
  final String location;
  final ValueChanged<String> onNavigate;
  final VoidCallback? onLogout;
  final Widget? profile;

  /// null이면 path 일치 / startsWith 기본 규칙
  final bool Function(String location, String path)? isSelected;

  final double width;

  bool _selected(String path) {
    if (isSelected != null) return isSelected!(location, path);
    if (location == path) return true;
    // 루트 경로는 exact만
    final roots = {'/', ''};
    if (roots.contains(path)) return location == path;
    return location.startsWith(path);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      color: AppColors.sidebar,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                children: [
                  for (final item in items)
                    _RailNavTile(
                      icon: item.icon,
                      label: item.label,
                      selected: _selected(item.path),
                      onTap: () => onNavigate(item.path),
                    ),
                ],
              ),
            ),
            if (profile != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: profile,
              ),
            if (onLogout != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                child: _RailNavTile(
                  icon: Icons.logout_rounded,
                  label: '로그아웃',
                  selected: false,
                  onTap: onLogout!,
                  danger: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RailNavTile extends StatelessWidget {
  const _RailNavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color iconColor;
    final Color textColor;
    if (danger) {
      iconColor = const Color(0xFFFCA5A5);
      textColor = const Color(0xFFFCA5A5);
    } else if (selected) {
      iconColor = Colors.white;
      textColor = Colors.white;
    } else {
      iconColor = AppColors.sidebarIconInactive;
      textColor = AppColors.sidebarIconInactive;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? Colors.white.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
