import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../providers/side_rail_theme_provider.dart';

class AppSideRailItem {
  const AppSideRailItem({
    required this.icon,
    required this.label,
    required this.path,
    this.itemKey,
  });

  final IconData icon;
  final String label;
  final String path;
  final Key? itemKey;
}

/// 사이드바 그룹 — [title]이 null이면 헤더 없이 항상 표시
class AppSideRailSection {
  const AppSideRailSection({
    required this.id,
    required this.items,
    this.title,
    this.initiallyExpanded = false,
  });

  final String id;
  final String? title;
  final List<AppSideRailItem> items;
  final bool initiallyExpanded;

  bool get isGroup => title != null && title!.isNotEmpty;
}

/// 사이드바 색 — 프로필 타일 등 자식이 `SideRailStyle.of(context)`로 참조
class SideRailStyle extends InheritedWidget {
  const SideRailStyle({
    super.key,
    required this.isDark,
    required this.background,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.selectedBg,
    required this.selectedFg,
    required this.danger,
    required this.avatarBg,
    required this.avatarFg,
    required super.child,
  });

  final bool isDark;
  final Color background;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color selectedBg;
  final Color selectedFg;
  final Color danger;
  final Color avatarBg;
  final Color avatarFg;

  static SideRailStyle of(BuildContext context) {
    final style =
        context.dependOnInheritedWidgetOfExactType<SideRailStyle>();
    assert(style != null, 'SideRailStyle not found above this widget');
    return style!;
  }

  static SideRailStyle? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SideRailStyle>();

  factory SideRailStyle.palette({
    required bool isDark,
    required Widget child,
    SideRailDarkPalette? darkPalette,
  }) {
    if (isDark) {
      final dark = darkPalette ?? kSideRailDarkPalettes.first;
      return SideRailStyle(
        isDark: true,
        background: dark.background,
        border: dark.border,
        textPrimary: Colors.white,
        textSecondary: dark.muted,
        selectedBg: dark.accent.withValues(alpha: 0.18),
        selectedFg: Colors.white,
        danger: const Color(0xFFFCA5A5),
        avatarBg: Colors.white.withValues(alpha: 0.14),
        avatarFg: Colors.white,
        child: child,
      );
    }
    return SideRailStyle(
      isDark: false,
      background: AppColors.surface,
      border: AppColors.border,
      textPrimary: AppColors.textPrimary,
      textSecondary: AppColors.textSecondary,
      selectedBg: AppColors.primaryLight,
      selectedFg: AppColors.primary,
      danger: AppColors.error,
      avatarBg: AppColors.primaryLight,
      avatarFg: AppColors.primary,
      child: child,
    );
  }

  @override
  bool updateShouldNotify(SideRailStyle oldWidget) =>
      isDark != oldWidget.isDark ||
      background != oldWidget.background ||
      selectedBg != oldWidget.selectedBg;
}

/// 와이드 레이아웃용 좌측 네비게이션 레일 (라이트/다크 토글)
class AppSideRail extends ConsumerWidget {
  const AppSideRail({
    super.key,
    this.items = const [],
    this.sections,
    required this.location,
    required this.onNavigate,
    this.onLogout,
    this.profile,
    this.isSelected,
    this.width = 208,
  });

  /// 평탄 목록 (기존 셸용). [sections]가 있으면 무시됨.
  final List<AppSideRailItem> items;

  /// 그룹 목록 (관리자 등)
  final List<AppSideRailSection>? sections;

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
    final roots = {'/', ''};
    if (roots.contains(path)) return location == path;
    return location.startsWith(path);
  }

  List<AppSideRailSection> get _resolvedSections {
    if (sections != null) return sections!;
    return [
      AppSideRailSection(id: 'all', items: items, initiallyExpanded: true),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(sideRailDarkModeProvider);
    final darkPalette = ref.watch(sideRailDarkPaletteProvider);

    return SideRailStyle.palette(
      isDark: isDark,
      darkPalette: darkPalette,
      child: Builder(
        builder: (context) {
          final style = SideRailStyle.of(context);
          return Container(
            width: width,
            decoration: BoxDecoration(
              color: style.background,
              border: Border(
                right: BorderSide(color: style.border),
              ),
            ),
            child: SafeArea(
              right: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: _RailThemeToggle(
                      isDark: isDark,
                      onToggle: () => ref
                          .read(sideRailDarkModeProvider.notifier)
                          .toggle(),
                    ),
                  ),
                  if (isDark)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: _RailPaletteSwitcher(
                        palette: darkPalette,
                        onCycle: () => ref
                            .read(sideRailDarkPaletteIndexProvider.notifier)
                            .cycle(),
                      ),
                    ),
                  Expanded(
                    child: _SideRailSectionList(
                      sections: _resolvedSections,
                      location: location,
                      isPathSelected: _selected,
                      onNavigate: onNavigate,
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
        },
      ),
    );
  }
}

class _SideRailSectionList extends StatefulWidget {
  const _SideRailSectionList({
    required this.sections,
    required this.location,
    required this.isPathSelected,
    required this.onNavigate,
  });

  final List<AppSideRailSection> sections;
  final String location;
  final bool Function(String path) isPathSelected;
  final ValueChanged<String> onNavigate;

  @override
  State<_SideRailSectionList> createState() => _SideRailSectionListState();
}

class _SideRailSectionListState extends State<_SideRailSectionList> {
  late Set<String> _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = {
      for (final s in widget.sections)
        if (!s.isGroup || s.initiallyExpanded || _sectionHasSelected(s)) s.id,
    };
  }

  @override
  void didUpdateWidget(covariant _SideRailSectionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      for (final s in widget.sections) {
        if (s.isGroup && _sectionHasSelected(s) && !_expanded.contains(s.id)) {
          _expanded = {..._expanded, s.id};
        }
      }
    }
  }

  bool _sectionHasSelected(AppSideRailSection section) =>
      section.items.any((i) => widget.isPathSelected(i.path));

  void _toggle(String id) {
    setState(() {
      if (_expanded.contains(id)) {
        _expanded = {..._expanded}..remove(id);
      } else {
        _expanded = {..._expanded, id};
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      children: [
        for (final section in widget.sections) ...[
          if (section.isGroup)
            _RailSectionHeader(
              title: section.title!,
              expanded: _expanded.contains(section.id),
              hasSelected: _sectionHasSelected(section),
              onTap: () => _toggle(section.id),
            ),
          if (!section.isGroup || _expanded.contains(section.id))
            for (final item in section.items)
              _RailNavTile(
                key: item.itemKey,
                icon: item.icon,
                label: item.label,
                selected: widget.isPathSelected(item.path),
                onTap: () => widget.onNavigate(item.path),
              ),
          if (section.isGroup) const SizedBox(height: 4),
        ],
      ],
    );
  }
}

class _RailSectionHeader extends StatelessWidget {
  const _RailSectionHeader({
    required this.title,
    required this.expanded,
    required this.hasSelected,
    required this.onTap,
  });

  final String title;
  final bool expanded;
  final bool hasSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = SideRailStyle.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      color: hasSelected
                          ? style.selectedFg
                          : style.textSecondary,
                    ),
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: style.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailThemeToggle extends StatelessWidget {
  const _RailThemeToggle({
    required this.isDark,
    required this.onToggle,
  });

  final bool isDark;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final style = SideRailStyle.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                size: 18,
                color: style.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isDark ? '밝은 사이드바' : '어두운 사이드바',
                  style: TextStyle(
                    color: style.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.swap_horiz_rounded,
                size: 16,
                color: style.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 다크 팔레트 후보 순환 (테스트용)
class _RailPaletteSwitcher extends StatelessWidget {
  const _RailPaletteSwitcher({
    required this.palette,
    required this.onCycle,
  });

  final SideRailDarkPalette palette;
  final VoidCallback onCycle;

  @override
  Widget build(BuildContext context) {
    final style = SideRailStyle.of(context);
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onCycle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: palette.background,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.accent, width: 2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  palette.label,
                  style: TextStyle(
                    color: style.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.palette_outlined,
                size: 16,
                color: palette.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailNavTile extends StatelessWidget {
  const _RailNavTile({
    super.key,
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
    final style = SideRailStyle.of(context);
    final Color iconColor;
    final Color textColor;
    if (danger) {
      iconColor = style.danger;
      textColor = style.danger;
    } else if (selected) {
      iconColor = style.selectedFg;
      textColor = style.selectedFg;
    } else {
      iconColor = style.textSecondary;
      textColor = style.textPrimary;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? style.selectedBg : Colors.transparent,
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

/// 사이드바 하단 프로필 — 반드시 `AppSideRail`의 `profile`로 넣어
/// `SideRailStyle` 아래에서 빌드되게 할 것.
class SideRailProfileTile extends StatelessWidget {
  const SideRailProfileTile({
    super.key,
    required this.label,
    required this.initial,
    required this.onTap,
    this.leading,
  });

  final String label;
  final String initial;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final style = SideRailStyle.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              leading ??
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: style.avatarBg,
                    child: Text(
                      initial,
                      style: TextStyle(
                        color: style.avatarFg,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: style.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
