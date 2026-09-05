import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/widgets/profile_avatar_editor.dart';
import 'skill_picker_dialog.dart';

/// 대시보드 프로필 카드 — 스킬 선택 (마일리지는 별도 3D 카드)
class DashboardProfileCard extends ConsumerWidget {
  const DashboardProfileCard({super.key, required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (user.isStudent) ...[
                  ProfileAvatarEditor(
                    uid: user.uid,
                    photoUrl: user.photoUrl,
                    photoStoragePath: user.photoStoragePath,
                    radius: 26,
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.cohortName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '${user.displayName}님',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => showSkillPickerDialog(
                context,
                ref,
                uid: user.uid,
                initialSkills: user.skills,
              ),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: user.skills.isEmpty
                    ? Row(
                        children: [
                          Icon(
                            Icons.add_circle_outline,
                            size: 16,
                            color: AppColors.textHint.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '탭하여 스킬을 선택해 주세요',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      )
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ...user.skills.take(6).map(
                                (s) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryLight,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Text(
                                    s,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ),
                          if (user.skills.length > 6)
                            Text(
                              '+${user.skills.length - 6}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
