import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/models/resume_model.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../../shared/providers/lms_providers.dart';

/// 이력서 관리 — 목록 + 작성 페이지 이동
class ResumeScreen extends ConsumerWidget {
  const ResumeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final resumes = isAdmin
        ? ref.watch(cohortResumesProvider)
        : ref.watch(myResumesProvider);

    return resumes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (list) => _ResumeBody(resumes: list, isAdmin: isAdmin),
    );
  }
}

class _ResumeBody extends ConsumerWidget {
  const _ResumeBody({required this.resumes, required this.isAdmin});
  final List<ResumeModel> resumes;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final submitted = resumes.where((r) => r.status == 'submitted').length;
    final writing = resumes.where((r) => r.status == 'writing').length;
    final approved = resumes.where((r) => r.isApproved).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '이력서 관리',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              if (isAdmin) ...[
                const SizedBox(height: 4),
                Text(
                  ref.watch(effectiveCohortNameProvider) ?? '',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ] else
                const Text(
                  '이력서 작성 현황과 피드백을 관리합니다.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _StatCard(label: '전체', value: '${resumes.length}'),
                  _StatCard(label: '작성 중', value: '$writing', color: AppColors.warning),
                  _StatCard(label: '제출 요청', value: '$submitted', color: AppColors.primary),
                  _StatCard(label: '승인', value: '$approved', color: AppColors.success),
                ],
              ),
              if (!isAdmin) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _createResume(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('새 이력서 작성'),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: resumes.isEmpty
              ? const Center(child: Text('이력서가 없습니다'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: resumes.length,
                  itemBuilder: (_, i) =>
                      _ResumeCard(resume: resumes[i], isAdmin: isAdmin),
                ),
        ),
      ],
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
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResumeCard extends ConsumerWidget {
  const _ResumeCard({required this.resume, required this.isAdmin});
  final ResumeModel resume;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
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
          padding: const EdgeInsets.all(16),
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
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${resume.completedCount}/${resume.totalCount} · ${resume.statusLabel}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Chip(
                    label: Text(
                      resume.statusLabel,
                      style: const TextStyle(fontSize: 11),
                    ),
                    backgroundColor: resume.isApproved
                        ? AppColors.success.withValues(alpha: 0.15)
                        : resume.isSubmitted
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : AppColors.warning.withValues(alpha: 0.15),
                  ),
                  if (!isAdmin && !resume.isApproved)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => ref.read(lmsRepositoryProvider).deleteResume(
                            ref.read(effectiveCohortIdProvider)!,
                            resume.id,
                          ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: resume.totalCount == 0
                    ? 0
                    : resume.completedCount / resume.totalCount,
                color: AppColors.primary,
                backgroundColor: AppColors.primaryLight,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: AppConstants.resumeSections.map((key) {
                  final done = resume.sections[key] ?? false;
                  final label = AppConstants.resumeSectionLabels[key] ?? key;
                  return ActionChip(
                    label: Text(label, style: const TextStyle(fontSize: 10)),
                    avatar: done
                        ? const Icon(Icons.check, size: 14, color: AppColors.success)
                        : null,
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      final cohortId = ref.read(effectiveCohortIdProvider);
                      context.go(
                        RoutePaths.resumeEditPath(
                          resume.id,
                          section: key,
                          cohortId: cohortId,
                        ),
                      );
                    },
                  );
                }).toList(),
              ),
              if (resume.updatedAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    AppDateUtils.formatDisplay(resume.updatedAt!),
                    style: const TextStyle(color: AppColors.textHint, fontSize: 12),
                  ),
                ),
              _FeedbackSection(resumeId: resume.id, isAdmin: isAdmin),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackSection extends ConsumerWidget {
  const _FeedbackSection({required this.resumeId, required this.isAdmin});
  final String resumeId;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedback = ref.watch(resumeFeedbackProvider(resumeId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('피드백', style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            if (isAdmin)
              TextButton.icon(
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
              return const Text(
                '피드백이 없습니다',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              );
            }
            return Column(
              children: list
                  .map(
                    (f) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.comment, size: 18),
                      title: Text(
                        AppConstants.resumeSectionLabels[f.sectionKey] ??
                            f.sectionKey,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(f.content),
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
              DropdownButtonFormField<String>(
                initialValue: sectionKey,
                decoration: const InputDecoration(labelText: '섹션'),
                items: AppConstants.resumeSections
                    .map(
                      (k) => DropdownMenuItem(
                        value: k,
                        child: Text(AppConstants.resumeSectionLabels[k] ?? k),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => sectionKey = v!),
              ),
              TextField(
                controller: contentCtrl,
                decoration: const InputDecoration(labelText: '피드백 내용'),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
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
