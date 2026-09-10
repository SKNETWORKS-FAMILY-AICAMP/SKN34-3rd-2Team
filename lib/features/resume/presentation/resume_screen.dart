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
        data: (list) => _ResumeBody(
          // 작성 중인 이력서는 아직 학생의 것이다. 요청해야 넘어온다.
          resumes: canReview
              ? list.where((r) => r.isVisibleToReviewer).toList()
              : list,
          canReview: canReview,
        ),
      ),
    );
  }
}

/// 통계 카드가 가리키는 묶음. 카드를 누르면 그 묶음만 목록에 남는다.
enum _ResumeFilter { all, writing, requested, approved }

class _ResumeBody extends ConsumerStatefulWidget {
  const _ResumeBody({required this.resumes, required this.canReview});
  final List<ResumeModel> resumes;
  final bool canReview;

  @override
  ConsumerState<_ResumeBody> createState() => _ResumeBodyState();
}

class _ResumeBodyState extends ConsumerState<_ResumeBody> {
  _ResumeFilter _filter = _ResumeFilter.all;

  bool _matches(ResumeModel r) => switch (_filter) {
        _ResumeFilter.all => true,
        _ResumeFilter.writing => !r.isFeedbackRequested && !r.isApproved,
        _ResumeFilter.requested => r.isFeedbackRequested,
        _ResumeFilter.approved => r.isApproved,
      };

  void _select(_ResumeFilter tapped) => setState(
        // 눌린 카드를 다시 누르면 전체로 돌아온다.
        () => _filter = _filter == tapped ? _ResumeFilter.all : tapped,
      );

  @override
  Widget build(BuildContext context) {
    final resumes = widget.resumes;
    final canReview = widget.canReview;
    final submitted = resumes.where((r) => r.isFeedbackRequested).length;
    final writing =
        resumes.where((r) => !r.isFeedbackRequested && !r.isApproved).length;
    final approved = resumes.where((r) => r.isApproved).length;
    final shown = resumes.where(_matches).toList();
    final baseResume = _registeredBaseResume(resumes);

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
                      _StatCard(
                        label: '전체',
                        value: '${resumes.length}',
                        selected: _filter == _ResumeFilter.all,
                        onTap: () => _select(_ResumeFilter.all),
                      ),
                      const SizedBox(width: 8),
                      if (!canReview) ...[
                        _StatCard(
                          label: '작성 중',
                          value: '$writing',
                          color: AppColors.warning,
                          selected: _filter == _ResumeFilter.writing,
                          onTap: () => _select(_ResumeFilter.writing),
                        ),
                        const SizedBox(width: 8),
                      ],
                      _StatCard(
                        label: '피드백 요청',
                        value: '$submitted',
                        color: AppColors.primary,
                        selected: _filter == _ResumeFilter.requested,
                        onTap: () => _select(_ResumeFilter.requested),
                      ),
                      const SizedBox(width: 8),
                      _StatCard(
                        label: '승인',
                        value: '$approved',
                        color: AppColors.success,
                        selected: _filter == _ResumeFilter.approved,
                        onTap: () => _select(_ResumeFilter.approved),
                      ),
                    ],
                  ),
                  if (!canReview) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _manageBaseResume(
                          context,
                          ref,
                          baseResume,
                          resumes,
                        ),
                        icon: Icon(
                          baseResume == null ? Icons.bookmark_add_outlined : Icons.bookmark,
                          size: 18,
                        ),
                        label: Text(
                          baseResume == null ? '기본 이력서 등록' : '기본 이력서 관리',
                        ),
                      ),
                    ),
                    if (baseResume != null) ...[
                      const SizedBox(height: 2),
                      TextButton.icon(
                        onPressed: () => _registerBaseResume(
                          context,
                          ref,
                          resumes,
                        ),
                        icon: const Icon(Icons.swap_horiz, size: 16),
                        label: const Text('기본 이력서 변경'),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      child: Text(
                        resumes.isEmpty
                            ? (canReview
                                ? '피드백을 요청한 이력서가 없습니다'
                                : '이력서가 없습니다')
                            : '이 묶음에 해당하는 이력서가 없습니다',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      itemCount: shown.length,
                      itemBuilder: (_, i) => _ResumeCard(
                        resume: shown[i],
                        canReview: canReview,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  ResumeModel? _registeredBaseResume(List<ResumeModel> resumes) {
    for (final resume in resumes) {
      if (resume.isBaseResume) return resume;
    }
    return null;
  }

  Future<void> _manageBaseResume(
    BuildContext context,
    WidgetRef ref,
    ResumeModel? baseResume,
    List<ResumeModel> resumes,
  ) async {
    if (baseResume != null) {
      context.go(RoutePaths.resumeEditPath(baseResume.id));
      return;
    }
    await _registerBaseResume(context, ref, resumes);
  }

  Future<void> _registerBaseResume(
    BuildContext context,
    WidgetRef ref,
    List<ResumeModel> resumes,
  ) async {
    const createNew = '__create_base_resume__';
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('기본 이력서 등록'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: Text(
              '공고별 첨삭은 여기서 등록한 기본 이력서를 복사해 진행합니다.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          for (final resume in resumes)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, resume.id),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(resume.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${resume.completedCount}/${resume.totalCount} 항목 작성',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, createNew),
            child: const Row(
              children: [
                Icon(Icons.add, size: 18),
                SizedBox(width: 8),
                Text('새 기본 이력서 작성'),
              ],
            ),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    final user = ref.read(currentUserSyncProvider)!;
    final cohortId = ref.read(effectiveCohortIdProvider)!;
    late final String id;
    if (choice == createNew) {
      id = await ref.read(lmsRepositoryProvider).createResume(
            cohortId: cohortId,
            userId: user.uid,
            title: '기본 이력서',
            isBaseResume: true,
          );
    } else {
      id = choice;
      await ref.read(lmsRepositoryProvider).setBaseResume(
            cohortId: cohortId,
            userId: user.uid,
            resumeId: id,
          );
    }
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
    this.selected = false,
    this.onTap,
  });

  final String label;
  final String value;
  final Color? color;

  /// 지금 이 묶음만 보고 있나. 테두리를 그 색으로 굵게 그려 알려 준다.
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppColors.textPrimary;
    return Expanded(
      child: Material(
        color: selected ? accent.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? accent : AppColors.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? accent : AppColors.textSecondary,
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
                            if (resume.isBaseResume) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '기본 이력서',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.success,
                                  ),
                                ),
                              ),
                            ],
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
                      if (!canReview && !resume.isApproved && !resume.isBaseResume)
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
                    resume: resume,
                    // 요청하지 않은 이력서에는 피드백을 남기지 않는다.
                    canReview: canReview && resume.acceptsFeedback,
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

/// 카드의 피드백 줄. **알리기만 한다.**
///
/// 예전에는 본문을 그대로 늘어놓아 피드백이 늘수록 카드가 길어졌다. 목록을 훑는
/// 화면인데 읽는 화면이 되어 버렸고, 무엇을 안 읽었는지도 알 수 없었다.
/// 이제 안 읽은 건수만 알리고 내용은 이력서 안의 종에서 읽는다.
class _FeedbackSection extends ConsumerWidget {
  const _FeedbackSection({required this.resume, required this.canReview});

  final ResumeModel resume;
  final bool canReview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(resumeFeedbackProvider(resume.id)).maybeWhen(
          data: (l) => l,
          orElse: () => const <ResumeFeedbackModel>[],
        );
    final total = items.isEmpty ? resume.feedbackCount : items.length;
    // 보는 사람 기준으로 센다. 검토자에게는 학생이 단 답글이 안 읽은 것이다.
    final unread = unreadFeedback(items, resume,
            asReviewer: canReview,
            viewerId: ref.watch(currentUserSyncProvider)?.uid)
        .length;

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
            const SizedBox(width: 10),
            Expanded(child: _summary(total, unread)),
            if (canReview)
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () => _addFeedback(context, ref),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('피드백 작성'),
              )
            else if (total > 0)
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                // 가는 곳은 카드를 누를 때와 같다. 다른 것은 도착 상태다 —
                // 종이 펼쳐진 채로 열려 신규 목록 앞에 바로 선다.
                onPressed: () => context.go(
                  RoutePaths.resumeEditPath(
                    resume.id,
                    cohortId: ref.read(effectiveCohortIdProvider),
                    openFeedback: true,
                  ),
                ),
                child: Text(unread > 0 ? '읽으러 가기' : '다시 보기'),
              ),
          ],
        ),
      ],
    );
  }

  /// 강사에게는 "신규"가 없다. 읽는 사람은 학생이다.
  Widget _summary(int total, int unread) {
    if (total == 0) {
      return Text(
        canReview ? '아직 남긴 피드백이 없습니다' : '아직 없습니다',
        style: const TextStyle(color: AppColors.textHint, fontSize: 12.5),
      );
    }
    if (unread == 0) {
      return Text(
        '$total건 · 모두 읽음',
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
      );
    }
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(right: 7),
          decoration: const BoxDecoration(
            color: AppColors.error,
            shape: BoxShape.circle,
          ),
        ),
        Text(
          '신규 $unread건',
          style: const TextStyle(
            color: AppColors.error,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          ' · 전체 $total건',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
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
          // 너비를 정해 준다. 안 그러면 AlertDialog 가 내용의 고유 크기를 재려 하는데,
          // 섹션 드롭다운이 LayoutBuilder 로 되어 있어 그 계산을 하지 못한다.
          // 레이아웃이 실패하면서 크기가 0이 되고, 마우스가 지날 때마다 히트 테스트
          // 오류가 매 프레임 쏟아진다.
          content: SizedBox(
            width: 360,
            child: Column(
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
                      resumeId: resume.id,
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
