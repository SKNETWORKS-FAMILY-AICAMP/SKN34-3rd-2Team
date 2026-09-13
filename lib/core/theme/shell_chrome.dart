import 'package:flutter/material.dart';

import 'app_colors.dart';
import '../../shared/providers/side_rail_theme_provider.dart';

/// 상단 바 색. 본문 바탕을 따른다.
abstract final class ShellChrome {
  // 상단 바는 사이드바 색을 따라가지 않는다. 본문 바탕을 따른다.
  //
  // 예전에는 사이드바를 어둡게 하면 상단 바도 사이드바 팔레트 색으로 칠했다.
  // 사이드바 색을 바꿀 때마다 화면 위쪽 전체가 같이 바뀌어 산만했다. 이제
  // 사이드바 색은 사이드바에만 남고, 상단 바는 본문 바탕과 이어진다. 인자는 호출하는 곳을 건드리지 않으려고 남겨 두었다.

  /// 본문 바탕과 같은 색. 카드 색(surface)으로 칠하면 상단 바·사이드바·본문이
  /// 세 덩어리로 갈라져 보인다.
  static Color appBarBackground(bool isDark, [SideRailDarkPalette? palette]) =>
      AppColors.background;

  static Color appBarForeground(bool isDark) => AppColors.textPrimary;

  static Color appBarMuted(bool isDark) => AppColors.textSecondary;

  static Color appBarBorder(bool isDark) => AppColors.border;

  static Color chipFill(bool isDark) =>
      AppColors.surfaceVariant.withValues(alpha: 0.55);

  static Color chipBorder(bool isDark) => AppColors.border;

  /// 사이드바 바탕색. 사이드바 레일과 그 위 상단 바 칸이 같은 값을 쓴다.
  static Color railBackground(bool railDark, SideRailDarkPalette palette) =>
      railDark ? palette.background : AppColors.surface;

  /// 넓은 화면에서 상단 바 중 사이드바 위에 걸친 칸을 사이드바 색으로 칠한다.
  ///
  /// 상단 바는 화면 전체 폭으로 깔리므로, 그대로 두면 사이드바 머리 자리까지
  /// 상단 바 색이 차지해 사이드바가 로고 아래에서 끊겨 보인다.
  static Widget railCorner({
    required bool railDark,
    required SideRailDarkPalette palette,
    double width = 208,
  }) => Row(
    children: [
      Container(
        width: width,
        decoration: BoxDecoration(
          color: railBackground(railDark, palette),
          // 밝은 사이드바는 레일에 가장자리 선이 있다. 위 칸에도 이어 준다.
          border: railDark
              ? null
              : Border(right: BorderSide(color: AppColors.border)),
        ),
      ),
      const Expanded(child: SizedBox.shrink()),
    ],
  );

  /// 출결 폼 같은 상단 버튼 글씨. 버튼·링크처럼 고른 강조색을 따른다.
  static Color actionForeground(bool isDark, [SideRailDarkPalette? palette]) =>
      AppColors.primary;
}
