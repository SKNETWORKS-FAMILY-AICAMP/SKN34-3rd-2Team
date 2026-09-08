import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/assessment_model.dart';
import 'assessment_thumbnail.dart';

class AssessmentStatusChip extends StatelessWidget {
  const AssessmentStatusChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (label) {
      '진행중' => (AppColors.success.withValues(alpha: 0.12), AppColors.success),
      '예정' => (AppColors.primaryLight, AppColors.primary),
      '종료' => (AppColors.surfaceVariant, AppColors.badgeClosed),
      _ => (AppColors.warning.withValues(alpha: 0.15), AppColors.badgeLate),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class AssessmentCompletedBadge extends StatelessWidget {
  const AssessmentCompletedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 13, color: Color(0xFF166534)),
          SizedBox(width: 3),
          Text(
            '완료',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF166534),
            ),
          ),
        ],
      ),
    );
  }
}

/// 가로형 카드 — 썸네일 작게, 본문 옆에 배치해 화면을 덜 채움.
class AssessmentCard extends StatelessWidget {
  const AssessmentCard({
    super.key,
    required this.assessment,
    required this.onTap,
    this.completed = false,
    this.score,
    this.onEdit,
    this.onDelete,
    this.onPublish,
    this.publishing = false,
  });

  final AssessmentModel assessment;
  final VoidCallback onTap;
  final bool completed;
  final int? score;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onPublish;
  final bool publishing;

  @override
  Widget build(BuildContext context) {
    final hasMenu = onEdit != null || onDelete != null;
    final showPublish =
        onPublish != null && !assessment.published && !completed;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 96,
                  height: 72,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AssessmentThumbnail(
                        key: ValueKey(
                          assessment.thumbnailPath ??
                              assessment.thumbnailUrl ??
                              assessment.id,
                        ),
                        url: assessment.thumbnailUrl,
                        storagePath: assessment.thumbnailPath,
                        title: assessment.title,
                        width: 96,
                        height: 72,
                      ),
                      Positioned(
                        top: 4,
                        left: 4,
                        child: AssessmentStatusChip(
                          label: assessment.statusLabel,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (assessment.tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: assessment.tags
                                .take(3)
                                .map(
                                  (t) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF3F4F6),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      t,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      Text(
                        assessment.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${assessment.questionCount}문제 · ${assessment.maxScore}점',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          if (completed) ...[
                            if (score != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text(
                                  '$score점',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            const AssessmentCompletedBadge(),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (showPublish) ...[
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: publishing ? null : onPublish,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: publishing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('발행'),
                  ),
                ],
                if (hasMenu)
                  PopupMenuButton<String>(
                    tooltip: '더보기',
                    onSelected: (value) {
                      if (value == 'edit') onEdit?.call();
                      if (value == 'delete') onDelete?.call();
                      if (value == 'publish') onPublish?.call();
                    },
                    itemBuilder: (context) => [
                      if (onEdit != null)
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('수정'),
                        ),
                      if (showPublish)
                        const PopupMenuItem(
                          value: 'publish',
                          child: Text('발행'),
                        ),
                      if (onDelete != null)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            '삭제',
                            style: TextStyle(color: AppColors.error),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
