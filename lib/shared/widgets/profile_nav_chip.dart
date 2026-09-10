import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/shell_chrome.dart';
import '../models/user_model.dart';
import '../providers/profile_photo_providers.dart';
import '../providers/side_rail_theme_provider.dart';
import 'profile_avatar.dart';
import 'profile_avatar_editor.dart';

enum ProfileNavChipStyle { appBar, drawer }

/// AppBar / Drawer — 사진 + 이름 + 기수, 탭 시 마이페이지 이동
class ProfileNavChip extends ConsumerWidget {
  const ProfileNavChip({
    super.key,
    required this.user,
    required this.onTap,
    this.style = ProfileNavChipStyle.drawer,
  });

  final UserModel user;
  final VoidCallback onTap;
  final ProfileNavChipStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(profilePhotoPreviewProvider);
    final railDark = ref.watch(sideRailDarkModeProvider);

    return switch (style) {
      ProfileNavChipStyle.appBar => _AppBarProfileChip(
          user: user,
          preview: preview,
          onTap: onTap,
          isDark: railDark,
        ),
      ProfileNavChipStyle.drawer => _DrawerProfileHeader(
          user: user,
          preview: preview,
          onTap: onTap,
        ),
    };
  }
}

/// AppBar 우측 — 컴팩트 pill
class _AppBarProfileChip extends StatelessWidget {
  const _AppBarProfileChip({
    required this.user,
    required this.preview,
    required this.onTap,
    required this.isDark,
  });

  final UserModel user;
  final Uint8List? preview;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final showCohort = width >= 720;
    final textMaxWidth = showCohort ? 148.0 : 96.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          constraints: BoxConstraints(maxWidth: showCohort ? 220 : 160),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: ShellChrome.chipFill(isDark),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: ShellChrome.chipBorder(isDark)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (user.isStudent) ...[
                ProfileAvatar(
                  radius: 16,
                  userId: user.uid,
                  photoUrl: user.photoUrl,
                  photoStoragePath: user.photoStoragePath,
                  previewBytes: preview,
                ),
                const SizedBox(width: 8),
              ],
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: textMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                        color: ShellChrome.appBarForeground(isDark),
                      ),
                    ),
                    if (showCohort) ...[
                      const SizedBox(height: 1),
                      Text(
                        user.cohortName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: ShellChrome.appBarMuted(isDark),
                          height: 1.15,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Drawer 상단 — 전체 너비 프로필 카드
class _DrawerProfileHeader extends StatelessWidget {
  const _DrawerProfileHeader({
    required this.user,
    required this.preview,
    required this.onTap,
  });

  final UserModel user;
  final Uint8List? preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (user.isStudent) ...[
                ProfileAvatar(
                  radius: 28,
                  userId: user.uid,
                  photoUrl: user.photoUrl,
                  photoStoragePath: user.photoStoragePath,
                  previewBytes: preview,
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${user.displayName}님',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.cohortName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 13,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '마이페이지',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 마이페이지 / 대시보드 — 가로 프로필 요약 (사진 + 이름 + 기수)
class ProfileSummaryRow extends StatelessWidget {
  const ProfileSummaryRow({
    super.key,
    required this.user,
    this.avatarRadius = 32,
    this.showEditBadge = false,
  });

  final UserModel user;
  final double avatarRadius;
  final bool showEditBadge;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (user.isStudent) ...[
          showEditBadge
              ? ProfileAvatarEditor(
                  uid: user.uid,
                  photoUrl: user.photoUrl,
                  photoStoragePath: user.photoStoragePath,
                  radius: avatarRadius,
                )
              : ProfileAvatar(
                  radius: avatarRadius,
                  userId: user.uid,
                  photoUrl: user.photoUrl,
                  photoStoragePath: user.photoStoragePath,
                ),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${user.displayName}님',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                user.cohortName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
