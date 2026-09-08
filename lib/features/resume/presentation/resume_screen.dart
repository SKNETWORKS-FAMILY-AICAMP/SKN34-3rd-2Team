import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/models/resume_model.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../../shared/providers/lms_providers.dart';

const _kResumeContentMaxWidth = 1100.0;

/// 이력서 관리 — 목록 + 작성 페이지 이동
class ResumeScreen extends ConsumerWidget {
  const ResumeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canReview = ref.watch(canReviewResumesProvider);
    final resumes = canReview
        ? ref.watch(cohortResumesProvider)
        : ref.watch(myResumesProvider);

    return ColoredBox(
      color: AppColors.background,
      child: resumes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(message: e.toString()),
        data: (list) => _ResumeBody(resumes: list, canReview: canReview),
      ),
    );
  }
}

class _ResumeBody extends ConsumerWidget {
  const _ResumeBody({required this.resumes, required this.canReview});
  final List<ResumeModel> resumes;
  final bool canReview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final submitted = resumes.where((r) => r.status == 'submitted').length;
    final writing = resumes.where((r) => r.status == 'writing').length;
    final approved = resumes.where((r) => r.isApproved).length;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kResumeContentMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    canReview ? '이력서관리' : '이력서 관리',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    canReview
                        ? '${ref.watch(effectiveCohortNameProvider) ?? '담당 기수'} · 제출·피드백을 확인합니다.'
                        : '이력서 작성 현황과 피드백을 관리합니다.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _StatCard(label: '전체', value: '${resumes.length}'),
                      const SizedBox(width: 8),
                      _StatCard(
                        label: '작성 중',
                        value: '$writing',
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 8),
                      _StatCard(
                        label: '제출 요청',
                        value: '$submitted',
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      _StatCard(
                        label: '승인',
                        value: '$approved',
                        color: AppColors.success,
                      ),
                    ],
                  ),
                  if (!canReview) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _createResume(context, ref),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('새 이력서 작성'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: resumes.isEmpty
                  ? const Center(
                      child: Text(
                        '이력서가 없습니다',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      itemCount: resumes.length,
                      itemBuilder: (_, i) => _ResumeCard(
                        resume: resumes[i],
                        canReview: canReview,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createResume(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserSyncProvider)!;
    final cohortId = ref.read(effectiveCohortIdProvider)!;
    final id = await ref.read(lmsRepositoryProvider).createResume(
          cohortId: cohortId,
          userId: user.uid,
          title: '새 이력서',
        );
    if (context.mounted) {
      context.go(RoutePaths.resumeEditPath(id));
    }
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: color ?? AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResumeCard extends ConsumerWidget {
  const _ResumeCard({required this.resume, required this.canReview});
  final ResumeModel resume;
  final bool canReview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              final cohortId = ref.read(effectiveCohortIdProvider);
              context.go(
                RoutePaths.resumeEditPath(
                  resume.id,
                  cohortId: cohortId,
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              resume.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${resume.completedCount}/${resume.totalCount} · ${resume.statusLabel}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: resume.isApproved
                              ? AppColors.success.withValues(alpha: 0.12)
                              : resume.isSubmitted
                                  ? AppColors.primary.withValues(alpha: 0.1)
                                  : AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          resume.statusLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: resume.isApproved
                                ? AppColors.success
                                : resume.isSubmitted
                                    ? AppColors.primary
                                    : AppColors.warning,
                          ),
                        ),
                      ),
                      if (!canReview && !resume.isApproved)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () =>
                              ref.read(lmsRepositoryProvider).deleteResume(
                                    ref.read(effectiveCohortIdProvider)!,
                                    resume.id,
                                  ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      value: resume.totalCount == 0
                          ? 0
                          : resume.completedCount / resume.totalCount,
                      color: AppColors.primary,
                      backgroundColor: AppColors.primaryLight,
                    ),
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final key
                                in AppConstants.resumeSections) ...[
                              if (key != AppConstants.resumeSections.first)
                                const SizedBox(width: 4),
                              _SectionChip(
                                label:
                                    AppConstants.resumeSectionLabels[key] ??
                                        key,
                                done: resume.sections[key] ?? false,
                                onTap: () {
                                  final cohortId =
                                      ref.read(effectiveCohortIdProvider);
                                  context.go(
                                    RoutePaths.resumeEditPath(
                                      resume.id,
                                      section: key,
                                      cohortId: cohortId,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  if (resume.updatedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        AppDateUtils.formatDisplay(resume.updatedAt!),
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  _FeedbackSection(
                    resumeId: resume.id,
                    canReview: canReview,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionChip extends StatelessWidget {
  const _SectionChip({
    required this.label,
    required this.done,
    required this.onTap,
  });

  final String label;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (done) ...[
                const Icon(Icons.check, size: 12, color: AppColors.success),
                const SizedBox(width: 3),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackSection extends ConsumerWidget {
  const _FeedbackSection({required this.resumeId, required this.canReview});
  final String resumeId;
  final bool canReview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedback = ref.watch(resumeFeedbackProvider(resumeId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text(
              '피드백',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const Spacer(),
            if (canReview)
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () => _addFeedback(context, ref),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('피드백 작성'),
              ),
          ],
        ),
        feedback.when(
          loading: () => const SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (e, _) => Text('오류: $e'),
          data: (list) {
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: Text(
                  '피드백이 없습니다',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              );
            }
            return Column(
              children: list
                  .map(
                    (f) => ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.comment, size: 16),
                      title: Text(
                        AppConstants.resumeSectionLabels[f.sectionKey] ??
                            f.sectionKey,
                        style: const TextStyle(fontSize: 12),
                      ),
                      subtitle: Text(
                        f.content,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Future<void> _addFeedback(BuildContext context, WidgetRef ref) async {
    String sectionKey = AppConstants.resumeSections.first;
    final contentCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('피드백 작성'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppDropdownField<String>(
                value: sectionKey,
                decoration: const InputDecoration(labelText: '섹션'),
                items: [
                  for (final k in AppConstants.resumeSections)
                    AppDropdownItem(
                      value: k,
                      label: AppConstants.resumeSectionLabels[k] ?? k,
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => sectionKey = v);
                },
              ),
              TextField(
                controller: contentCtrl,
                decoration: const InputDecoration(labelText: '피드백 내용'),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () async {
                final user = ref.read(currentUserSyncProvider)!;
                await ref.read(lmsRepositoryProvider).addResumeFeedback(
                      cohortId: ref.read(cohortIdProvider)!,
                      resumeId: resumeId,
                      feedback: ResumeFeedbackModel(
                        id: '',
                        sectionKey: sectionKey,
                        content: contentCtrl.text,
                        authorName: user.displayName,
                      ),
                      authorId: user.uid,
                      authorName: user.displayName,
                    );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('등록'),
            ),
          ],
        ),
      ),
    );
  }
}
