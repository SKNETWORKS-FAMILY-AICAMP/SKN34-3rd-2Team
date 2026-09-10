import 'package:flutter/material.dart';

import 'app_colors.dart';
import '../../shared/providers/side_rail_theme_provider.dart';

/// 확인용 — Mid Slate 상단바 크롬
abstract final class ShellChrome {
  static const midSlate = SideRailDarkPalette(
    id: 'mid_slate',
    label: '5 Mid Slate',
    background: Color(0xFF1E293B),
    border: Color(0xFF334155),
    accent: Color(0xFF00C2D4),
    muted: Color(0xFFCBD5E1),
  );

  static Color appBarBackground(bool isDark) =>
      isDark ? midSlate.background : AppColors.surface;

  static Color appBarForeground(bool isDark) =>
      isDark ? Colors.white : AppColors.textPrimary;

  static Color appBarMuted(bool isDark) =>
      isDark ? midSlate.muted : AppColors.textSecondary;

  static Color appBarBorder(bool isDark) =>
      isDark ? midSlate.border : AppColors.border;

  static Color chipFill(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.1)
      : AppColors.surfaceVariant.withValues(alpha: 0.55);

  static Color chipBorder(bool isDark) =>
      isDark ? Colors.white.withValues(alpha: 0.16) : AppColors.border;

  static Color actionForeground(bool isDark) =>
      isDark ? midSlate.accent : AppColors.primary;
}
