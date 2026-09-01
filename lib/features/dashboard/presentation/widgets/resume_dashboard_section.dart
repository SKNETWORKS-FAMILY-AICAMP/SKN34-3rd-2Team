import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../shared/models/cohort_model.dart';
import '../../../../shared/models/resume_model.dart';
import '../../../../shared/providers/cohort_providers.dart';
import '../../../../shared/providers/lms_providers.dart';

/// 대시보드 — 이력서 요약 섹션
class ResumeDashboardSection extends ConsumerWidget {
  const ResumeDashboardSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('이력서'),
        if (isAdmin)
          ref.watch(adminCohortsWithResumesProvider).when(
                loading: () => const _ResumeCardsShimmer(),
                error: (e, _) => Text('오류: $e'),
                data: (groups) => _AdminCohortGroups(groups: groups),
              )
          else
            ref.watch(myResumesProvider).when(
                  loading: () => const _ResumeCardsShimmer(),
                  error: (e, _) => Text('오류: $e'),
                  data: (list) => _ResumeCardRow(
                    resumes: list,
                    showFeedbackBadge: true,
                    onTap: (resume) {
                      final cohortId = ref.read(effectiveCohortIdProvider);
                      context.go(
                        RoutePaths.resumeEditPath(
                          resume.id,
                          cohortId: cohortId,
                        ),
                      );
                    },
                  ),
              ),
      ],
    );
  }
}

class _AdminCohortGroups extends ConsumerWidget {
  const _AdminCohortGroups({required this.groups});

  final List<CohortWithResumes> groups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (groups.isEmpty) {
      return const Text(
        '등록된 기수가 없습니다.',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groups.map((group) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${group.cohort.name} (${group.resumes.length}건)',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              if (group.resumes.isEmpty)
                const Text(
                  '이력서 없음',
                  style: TextStyle(color: AppColors.textHint, fontSize: 13),
                )
              else
                _ResumeCardRow(
                  resumes: group.resumes,
                  onTap: (_) {
                    selectCohort(ref, group.cohort.cohortId);
                    context.go(RoutePaths.resume);
                  },
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ResumeCardRow extends StatelessWidget {
  const _ResumeCardRow({
    required this.resumes,
    required this.onTap,
    this.showFeedbackBadge = false,
  });

  final List<ResumeModel> resumes;
  final ValueChanged<ResumeModel> onTap;
  final bool showFeedbackBadge;

  @override
  Widget build(BuildContext context) {
    if (resumes.isEmpty) {
      return const Text(
        '이력서가 없습니다.',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }

    return SizedBox(
      height: 148,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: resumes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _ResumeSummaryCard(
          resume: resumes[i],
          showFeedbackBadge: showFeedbackBadge,
          onTap: () => onTap(resumes[i]),
        ),
      ),
    );
  }
}

class _ResumeSummaryCard extends StatelessWidget {
  const _ResumeSummaryCard({
    required this.resume,
    required this.onTap,
    this.showFeedbackBadge = false,
  });

  final ResumeModel resume;
  final VoidCallback onTap;
  final bool showFeedbackBadge;

  @override
  Widget build(BuildContext context) {
    final progress = resume.totalCount == 0
        ? 0.0
        : resume.completedCount / resume.totalCount;

    return SizedBox(
      width: 220,
      height: showFeedbackBadge && resume.feedbackCount > 0 ? 164 : 148,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        resume.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    _StatusBadge(label: resume.statusLabel, resume: resume),
                  ],
                ),
                if (showFeedbackBadge && resume.feedbackCount > 0) ...[
                  const SizedBox(height: 8),
                  _FeedbackBadge(resume: resume),
                ],
                const Spacer(),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    color: AppColors.primary,
                    backgroundColor: AppColors.primaryLight,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '섹션 ${resume.completedCount}/${resume.totalCount} 완료',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (resume.updatedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    AppDateUtils.formatDisplay(resume.updatedAt!),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedbackBadge extends StatelessWidget {
  const _FeedbackBadge({required this.resume});

  final ResumeModel resume;

  @override
  Widget build(BuildContext context) {
    final unread = resume.unreadFeedbackCount;
    final isNew = unread > 0;
    final label = isNew ? '새 피드백 $unread' : '피드백 ${resume.feedbackCount}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isNew
            ? AppColors.error.withValues(alpha: 0.12)
            : AppColors.textHint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 12,
            color: isNew ? AppColors.error : AppColors.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isNew ? AppColors.error : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.resume});

  final String label;
  final ResumeModel resume;

  @override
  Widget build(BuildContext context) {
    final bg = resume.isApproved
        ? AppColors.success.withValues(alpha: 0.15)
        : resume.isSubmitted
            ? AppColors.primary.withValues(alpha: 0.12)
            : AppColors.warning.withValues(alpha: 0.15);
    final fg = resume.isApproved
        ? AppColors.success
        : resume.isSubmitted
            ? AppColors.primary
            : AppColors.warning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ResumeCardsShimmer extends StatelessWidget {
  const _ResumeCardsShimmer();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 164,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 2,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, _) => const SizedBox(
          width: 220,
          child: Card(
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }
}
