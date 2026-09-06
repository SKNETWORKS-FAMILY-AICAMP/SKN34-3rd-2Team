import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// 게시판 UI 공통 색상·스타일
abstract final class BoardUi {
  static const favorite = Color(0xFFF59E0B);
  static const favoriteBadgeBg = Color(0xFFFEF3C7);
  static const favoriteBadgeText = Color(0xFFB45309);
  static const favoriteBorder = Color(0xFFFDE68A);
  static const discordChipBg = AppColors.primaryLight;
  static const discordChipText = AppColors.primary;
  static const activeBadgeBg = Color(0xFFDCFCE7);
  static const activeBadgeText = AppColors.success;
  static const listBackground = AppColors.background;

  static BoxDecoration cardDecoration({
    bool isFavorite = false,
    bool isDiscord = false,
  }) {
    return BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: isFavorite
            ? favoriteBorder
            : isDiscord
                ? AppColors.primary.withValues(alpha: 0.35)
                : AppColors.border,
      ),
      boxShadow: const [
        BoxShadow(
          color: AppColors.shadow,
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    );
  }

  static ButtonStyle primaryButtonStyle() {
    return FilledButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
    );
  }
}

/// 게시판 탭 바 (밑줄 스타일)
class BoardTabBar extends StatelessWidget {
  const BoardTabBar({
    super.key,
    required this.tabs,
    required this.controller,
  });

  final List<String> tabs;
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: List.generate(tabs.length, (i) {
              final selected = controller.index == i;
              return GestureDetector(
                onTap: () => controller.animateTo(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: selected ? AppColors.primary : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    tabs[i],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? AppColors.textPrimary
                          : AppColors.textHint,
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class BoardMetaChip extends StatelessWidget {
  const BoardMetaChip({
    super.key,
    required this.label,
    this.variant = BoardMetaChipVariant.neutral,
  });

  final String label;
  final BoardMetaChipVariant variant;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (variant) {
      BoardMetaChipVariant.neutral => (
          AppColors.primaryLight,
          AppColors.textSecondary,
        ),
      BoardMetaChipVariant.favorite => (
          BoardUi.favoriteBadgeBg,
          BoardUi.favoriteBadgeText,
        ),
      BoardMetaChipVariant.discord => (
          BoardUi.discordChipBg,
          BoardUi.discordChipText,
        ),
      BoardMetaChipVariant.active => (
          BoardUi.activeBadgeBg,
          BoardUi.activeBadgeText,
        ),
      BoardMetaChipVariant.schedule => (
          AppColors.surfaceVariant,
          AppColors.textSecondary,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

enum BoardMetaChipVariant { neutral, favorite, discord, active, schedule }

class BoardScheduleChip extends StatelessWidget {
  const BoardScheduleChip({
    super.key,
    required this.icon,
    required this.label,
    this.variant = BoardMetaChipVariant.schedule,
  });

  final IconData icon;
  final String label;
  final BoardMetaChipVariant variant;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (variant) {
      BoardMetaChipVariant.favorite => (
          BoardUi.favoriteBadgeBg,
          BoardUi.favoriteBadgeText,
        ),
      BoardMetaChipVariant.active => (
          BoardUi.activeBadgeBg,
          BoardUi.activeBadgeText,
        ),
      _ => (AppColors.surfaceVariant, AppColors.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: fg),
          ),
        ],
      ),
    );
  }
}
