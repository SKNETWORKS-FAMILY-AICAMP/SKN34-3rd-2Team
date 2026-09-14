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
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../onboarding/domain/onboarding_target_registry.dart';
import '../../onboarding/instructor/instructor_onboarding_keys.dart';
import '../../../core/theme/app_space.dart';

const _kResumeContentMaxWidth = 1100.0;

/// 이 폭보다 좁으면 표 대신 두 줄짜리 목록으로 보여 준다. 칸 수가 달라 기준도 다르다.
/// 강사 표는 일곱 칸이라, 창을 반쯤 줄인 폭(780 안팎)에서 칸이 겹쳐 넘쳤다.
const _kStudentTableMinWidth = 760.0;
const _kReviewTableMinWidth = 960.0;

/// 이력서 관리 — 목록 + 작성 페이지 이동
///
/// 학생은 기본 이력서를 맨 위에 따로 두고 나머지를 표로 본다. 강사·관리자는
/// 학생 한 명을 한 줄로 본다. 예전에는 이력서마다 섹션 칩 11개와 피드백 줄이 달린
/// 큰 카드였고, 같은 상태를 글자와 배지로 두 번 적어 세 장만 돼도 화면을 넘었다.
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

/// 탭이 가리키는 묶음. 탭을 누르면 그 묶음만 목록에 남는다.
enum _ResumeFilter { all, writing, requested, approved }

class _ResumeBody extends ConsumerStatefulWidget {
  const _ResumeBody({required this.resumes, required this.canReview});
  final List<ResumeModel> resumes;
  final bool canReview;

  @override
  ConsumerState<_ResumeBody> createState() => _ResumeBodyState();
}

class _ResumeBodyState extends ConsumerState<_ResumeBody> {
  // 강사·관리자가 이 화면에 오는 까닭은 요청 온 이력서다. 그 묶음부터 연다.
  late _ResumeFilter _filter = widget.canReview
      ? _ResumeFilter.requested
      : _ResumeFilter.all;

  bool _matches(ResumeModel r) => switch (_filter) {
    _ResumeFilter.all => true,
    _ResumeFilter.writing => !r.isFeedbackRequested && !r.isApproved,
    _ResumeFilter.requested => r.isFeedbackRequested,
    _ResumeFilter.approved => r.isApproved,
  };

  @override
  Widget build(BuildContext context) {
    final resumes = widget.resumes;
    final canReview = widget.canReview;
    final counts = {
      _ResumeFilter.all: resumes.length,
      _ResumeFilter.writing: resumes
          .where((r) => !r.isFeedbackRequested && !r.isApproved)
          .length,
      _ResumeFilter.requested: resumes.where((r) => r.isFeedbackRequested).length,
      _ResumeFilter.approved: resumes.where((r) => r.isApproved).length,
    };
    const labels = {
      _ResumeFilter.all: '전체',
      _ResumeFilter.writing: '작성 중',
      _ResumeFilter.requested: '피드백 요청',
      _ResumeFilter.approved: '승인',
    };
    final tabs = canReview
        ? const [_ResumeFilter.requested, _ResumeFilter.approved, _ResumeFilter.all]
        : const [
            _ResumeFilter.all,
            _ResumeFilter.writing,
            _ResumeFilter.requested,
            _ResumeFilter.approved,
          ];
    final shown = resumes.where(_matches).toList()
      ..sort((a, b) => (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)));
    final baseResume = _registeredBaseResume(resumes);

    final String subtitle;
    if (!canReview) {
      subtitle = '기본 이력서로 AI 첨삭과 공고 추천을 받습니다.';
    } else if (ref.watch(isAdminProvider)) {
      subtitle = '상단 바에서 고른 기수의 이력서입니다. 피드백을 요청했거나 승인한 것만 보입니다.';
    } else {
      subtitle =
          '${ref.watch(effectiveCohortNameProvider) ?? '담당 기수'} · 피드백을 요청했거나 승인한 이력서만 보입니다.';
    }

    final List<Widget> content;
    if (canReview) {
      content = [
        if (shown.isEmpty)
          _EmptyNote(
            resumes.isEmpty ? '피드백을 요청한 이력서가 없습니다' : '이 묶음에 해당하는 이력서가 없습니다',
          )
        else
          AppSectionCard(
            padding: EdgeInsets.zero,
            child: _ReviewTable(resumes: shown),
          ),
      ];
    } else {
      final others = shown.where((r) => !r.isBaseResume).toList();
      final showBase = baseResume != null && _matches(baseResume);
      content = [
        if (baseResume == null && _filter == _ResumeFilter.all)
          _BaseResumeEmptyCard(
            onRegister: () => _registerBaseResume(context, ref, resumes),
          ),
        if (showBase)
          _BaseResumeCard(
            resume: baseResume,
            onChangeBase: () => _registerBaseResume(context, ref, resumes),
          ),
        if (others.isNotEmpty) ...[
          if (showBase || baseResume == null && _filter == _ResumeFilter.all)
            SizedBox(height: AppSpace.s(14)),
          AppSectionCard(
            padding: EdgeInsets.zero,
            child: _StudentTable(
              title: baseResume == null ? '이력서' : '다른 이력서',
              resumes: others,
            ),
          ),
        ],
        if (!showBase && others.isEmpty && !(baseResume == null && _filter == _ResumeFilter.all))
          _EmptyNote(resumes.isEmpty ? '이력서가 없습니다' : '이 묶음에 해당하는 이력서가 없습니다'),
      ];
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kResumeContentMaxWidth),
        child: ListView(
          padding: EdgeInsets.fromLTRB(AppSpace.s(20), AppSpace.s(16), AppSpace.s(20), AppSpace.s(24)),
          children: [
            const Text(
              '이력서 관리',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: AppSpace.s(4)),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            SizedBox(height: AppSpace.s(12)),
            // develop이 붙인 온보딩 안내 대상 표시를 그대로 둔다. 예전 숫자 카드 자리에
            // 이 탭 줄이 들어왔고, 안내 문구("피드백 요청을 누르면…")도 그대로 맞는다.
            KeyedSubtree(
              key: OnboardingTargetRegistry.keyOf(
                InstructorOnboardingTargets.resumesStats,
              ),
              child: _FilterTabs(
                tabs: [
                  for (final f in tabs)
                    (
                      label: labels[f]!,
                      count: counts[f]!,
                      selected: f == _filter,
                      color: switch (f) {
                        _ResumeFilter.all => AppColors.textPrimary,
                        _ResumeFilter.writing => AppColors.warning,
                        // 강조색을 회색 등으로 바꿔도 피드백 요청은 늘 파랑이다. 상태 색은 뜻이라 따라가지 않는다.
                        _ResumeFilter.requested => AppColors.info,
                        _ResumeFilter.approved => AppColors.success,
                      },
                    ),
                ],
                onSelect: (index) => setState(() => _filter = tabs[index]),
              ),
            ),
            SizedBox(height: AppSpace.s(16)),
            ...content,
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
          Padding(
            padding: EdgeInsets.fromLTRB(AppSpace.s(24), AppSpace.s(0), AppSpace.s(24), AppSpace.s(10)),
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
                  Text(
                    resume.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: AppSpace.s(2)),
                  Text(
                    '${resume.completedCount}/${resume.totalCount} 항목 작성',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, createNew),
            child: Row(
              children: [
                Icon(Icons.add, size: 18),
                SizedBox(width: AppSpace.s(8)),
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
      id = await ref
          .read(lmsRepositoryProvider)
          .createResume(
            cohortId: cohortId,
            userId: user.uid,
            title: '기본 이력서',
            isBaseResume: true,
          );
    } else {
      id = choice;
      await ref
          .read(lmsRepositoryProvider)
          .setBaseResume(
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

// ── 공통 조각 ──────────────────────────────────────────────────

void _openResume(BuildContext context, WidgetRef ref, ResumeModel resume, {String? section}) {
  context.go(
    RoutePaths.resumeEditPath(
      resume.id,
      section: section,
      cohortId: ref.read(effectiveCohortIdProvider),
    ),
  );
}

StatusBadge _statusBadge(ResumeModel resume) {
  if (resume.isApproved) return StatusBadge.success(resume.statusLabel);
  // StatusBadge.info는 강조색을 따라간다. 피드백 요청은 강조색과 상관없이 파랑으로 둔다.
  if (resume.isSubmitted) return StatusBadge(label: resume.statusLabel, color: AppColors.info);
  return StatusBadge.warning(resume.statusLabel);
}

/// 상태 탭. 숫자 카드 네 개가 차지하던 높이를 한 줄로 줄였다.
///
/// 처음에는 "전체 8"처럼 이름과 숫자를 한 글자 줄로 이어 붙이고 고른 탭만 파랗게 칠했다.
/// 고른 탭과 아닌 탭이 색 한 끗 차이라 구별이 안 됐고, 숫자도 이름에 묻혔다.
/// 숫자는 상태 색의 작은 배지로 떼고, 고른 탭은 글자를 진하게·배지를 채워·밑줄을 굵게 한다.
class _FilterTabs extends StatelessWidget {
  const _FilterTabs({required this.tabs, required this.onSelect});

  final List<({String label, int count, bool selected, Color color})> tabs;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              Semantics(
                selected: tabs[i].selected,
                button: true,
                child: InkWell(
                  onTap: () => onSelect(i),
                  child: Container(
                    padding: EdgeInsets.fromLTRB(AppSpace.s(4), AppSpace.s(10), AppSpace.s(4), AppSpace.s(9)),
                    margin: EdgeInsets.only(right: AppSpace.s(18)),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: tabs[i].selected ? AppColors.textPrimary : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tabs[i].label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: tabs[i].selected ? FontWeight.w700 : FontWeight.w500,
                            color: tabs[i].selected ? AppColors.textPrimary : AppColors.textSecondary,
                          ),
                        ),
                        SizedBox(width: AppSpace.s(6)),
                        Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          padding: EdgeInsets.symmetric(horizontal: AppSpace.s(7), vertical: AppSpace.s(2)),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: tabs[i].selected
                                ? tabs[i].color
                                : tabs[i].color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${tabs[i].count}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              // 색으로 채운 배지는 흰 숫자. 전체(글자색으로 채움)는 바탕색 숫자,
                              // 주황은 흰 글자가 안 읽혀 짙은 숫자.
                              color: !tabs[i].selected
                                  ? tabs[i].color
                                  : tabs[i].color == AppColors.textPrimary
                                  ? AppColors.surface
                                  : tabs[i].color == AppColors.warning
                                  ? const Color(0xFF1F2328)
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: AppSpace.s(48)),
    child: Center(
      child: Text(text, style: TextStyle(color: AppColors.textSecondary)),
    ),
  );
}

/// 채운 섹션 막대와 "4/11".
class _SectionProgress extends StatelessWidget {
  const _SectionProgress({required this.resume});
  final ResumeModel resume;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      // 칸이 좁으면 막대가 줄어든다. 폭을 64로 박아 두면 옆 칸으로 넘친다.
      Flexible(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 64, minWidth: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: resume.totalCount == 0 ? 0 : resume.completedCount / resume.totalCount,
              color: _complete ? AppColors.success : AppColors.primary,
              backgroundColor: AppColors.primaryLight,
            ),
          ),
        ),
      ),
      SizedBox(width: AppSpace.s(8)),
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${resume.completedCount}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _complete ? AppColors.success : AppColors.textPrimary,
              ),
            ),
            TextSpan(
              text: '/${resume.totalCount}',
              style: TextStyle(color: AppColors.textHint),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 12.5),
      ),
    ],
  );

  bool get _complete => resume.totalCount > 0 && resume.completedCount >= resume.totalCount;
}

/// 피드백 요약. **알리기만 한다.** 내용은 이력서 안의 종에서 읽는다.
///
/// 보는 사람 기준으로 센다. 학생에게는 강사가 남긴 글이, 검토자에게는 학생이 단 답글이
/// 안 읽은 것이다. 예전 카드는 승인된 이력서에서 검토자에게 학생용 문구("아직 없습니다")를
/// 보였다. 이제 문구는 이력서 상태가 아니라 보는 사람으로 고른다.
class _FeedbackSummary extends ConsumerWidget {
  const _FeedbackSummary({required this.resume, required this.asReviewer});

  final ResumeModel resume;
  final bool asReviewer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref
        .watch(resumeFeedbackProvider(resume.id))
        .maybeWhen(
          data: (l) => l,
          orElse: () => const <ResumeFeedbackModel>[],
        );
    final total = items.isEmpty ? resume.feedbackCount : items.length;
    final unread = unreadFeedback(
      items,
      resume,
      asReviewer: asReviewer,
      viewerId: ref.watch(currentUserSyncProvider)?.uid,
    ).length;
    final muted = TextStyle(color: AppColors.textSecondary, fontSize: 12.5);

    // 할 일이 없는 줄은 옅게, 읽을 것이 있는 줄만 빨갛게 해서 눈이 거기로 가게 한다.
    if (total == 0) {
      return Text(
        asReviewer ? '아직 남긴 피드백 없음' : '피드백 없음',
        style: TextStyle(color: AppColors.textHint, fontSize: 12.5),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    if (unread == 0) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$total건',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
            ),
            const TextSpan(text: ' · 모두 읽음'),
          ],
        ),
        style: muted,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          margin: EdgeInsets.only(right: AppSpace.s(6)),
          decoration: BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
        ),
        Flexible(
          child: Text(
            asReviewer ? '학생 답글 $unread' : '새 피드백 $unread',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        Flexible(
          child: Text(' · 전체 $total건', style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// 표 한 줄의 칸. 머리와 줄이 같은 비율을 쓴다.
class _TableRow extends StatelessWidget {
  const _TableRow({required this.flex, required this.cells, this.onTap, this.vertical = 10});

  final List<int> flex;
  final List<Widget> cells;
  final VoidCallback? onTap;
  final double vertical;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpace.s(20), vertical: AppSpace.s(vertical)),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              flex: flex[i],
              child: Padding(
                padding: EdgeInsets.only(right: i == cells.length - 1 ? 0 : AppSpace.s(8)),
                child: Align(
                  alignment: i == cells.length - 1 ? Alignment.centerRight : Alignment.centerLeft,
                  child: cells[i],
                ),
              ),
            ),
        ],
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}

Widget _headerText(String text) =>
    Text(text, style: TextStyle(fontSize: 11.5, color: AppColors.textHint));

// ── 학생 ──────────────────────────────────────────────────────

class _BaseResumeEmptyCard extends StatelessWidget {
  const _BaseResumeEmptyCard({required this.onRegister});
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) => AppSectionCard(
    padding: EdgeInsets.all(AppSpace.s(20)),
    child: Row(
      children: [
        Icon(Icons.bookmark_add_outlined, color: AppColors.primary),
        SizedBox(width: AppSpace.s(12)),
        Expanded(
          child: Text(
            '기본 이력서를 등록하면 AI 첨삭과 공고 추천을 받을 수 있습니다.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        SizedBox(width: AppSpace.s(12)),
        FilledButton(onPressed: onRegister, child: const Text('기본 이력서 등록')),
      ],
    ),
  );
}

/// 기본 이력서. 첨삭·추천이 이 이력서를 쓰므로 맨 위에 따로 둔다.
class _BaseResumeCard extends ConsumerWidget {
  const _BaseResumeCard({required this.resume, required this.onChangeBase});

  final ResumeModel resume;
  final VoidCallback onChangeBase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = TextStyle(fontSize: 12.5, color: AppColors.textSecondary);
    final remaining = [
      for (final key in AppConstants.resumeSections)
        if (!(resume.sections[key] ?? false)) key,
    ];

    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(Icons.bookmark, size: 15, color: AppColors.primary),
            SizedBox(width: AppSpace.s(4)),
            Text(
              '기본 이력서',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
            Text('  ·  AI 첨삭과 공고 추천에 쓰입니다', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
        SizedBox(height: AppSpace.s(6)),
        Wrap(
          spacing: AppSpace.s(10),
          runSpacing: AppSpace.s(4),
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              resume.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            _statusBadge(resume),
          ],
        ),
        SizedBox(height: AppSpace.s(6)),
        Wrap(
          spacing: AppSpace.s(6),
          runSpacing: AppSpace.s(2),
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (resume.updatedAt != null) ...[
              Text('마지막 수정', style: muted),
              Text(
                AppDateUtils.formatDetailDateTime(resume.updatedAt!),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              Text('·', style: muted),
            ],
            _FeedbackSummary(resume: resume, asReviewer: false),
          ],
        ),
      ],
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(
          onPressed: () => _openResume(context, ref, resume),
          child: const Text('이어서 작성'),
        ),
        PopupMenuButton<String>(
          tooltip: '기본 이력서 메뉴',
          icon: Icon(Icons.more_horiz, color: AppColors.textSecondary),
          onSelected: (_) => onChangeBase(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'change', child: Text('기본 이력서 변경')),
          ],
        ),
      ],
    );

    return AppSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(AppSpace.s(20), AppSpace.s(18), AppSpace.s(12), AppSpace.s(16)),
            child: LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth >= 560
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Expanded(child: head), actions],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [head, SizedBox(height: AppSpace.s(10)), actions],
                    ),
            ),
          ),
          Divider(height: 1, color: AppColors.divider),
          Padding(
            padding: EdgeInsets.fromLTRB(AppSpace.s(20), AppSpace.s(14), AppSpace.s(20), AppSpace.s(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 아주 좁은 화면에서는 막대 아래로 글자가 내려간다.
                Wrap(
                  spacing: AppSpace.s(10),
                  runSpacing: AppSpace.s(4),
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final key in AppConstants.resumeSections)
                          Container(
                            width: 18,
                            height: 6,
                            margin: const EdgeInsets.only(right: 3),
                            decoration: BoxDecoration(
                              color: (resume.sections[key] ?? false)
                                  ? AppColors.primary
                                  : AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                      ],
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${resume.completedCount}',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          ),
                          TextSpan(text: ' / ${resume.totalCount} 섹션 채움', style: muted),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: AppSpace.s(10)),
                if (remaining.isEmpty)
                  Text('모든 섹션을 채웠습니다.', style: muted)
                else
                  Wrap(
                    spacing: AppSpace.s(6),
                    runSpacing: AppSpace.s(6),
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('남은 섹션', style: muted),
                      for (final key in remaining)
                        ActionChip(
                          onPressed: () => _openResume(context, ref, resume, section: key),
                          avatar: Icon(Icons.add, size: 14, color: AppColors.primary),
                          label: Text(AppConstants.resumeSectionLabels[key] ?? key),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 기본 이력서가 아닌 이력서들. 한 이력서를 한 줄로 본다.
class _StudentTable extends ConsumerWidget {
  const _StudentTable({required this.title, required this.resumes});

  final String title;
  final List<ResumeModel> resumes;

  static const _flex = [3, 2, 2, 3, 2, 1];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget menu(ResumeModel resume) => PopupMenuButton<String>(
      tooltip: '이력서 메뉴',
      icon: Icon(Icons.more_horiz, color: AppColors.textSecondary),
      onSelected: (value) {
        if (value == 'open') _openResume(context, ref, resume);
        if (value == 'delete') {
          ref.read(lmsRepositoryProvider).deleteResume(ref.read(effectiveCohortIdProvider)!, resume.id);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'open', child: Text('열기')),
        // 승인된 이력서와 기본 이력서는 지우지 않는다. 예전 카드의 휴지통 조건과 같다.
        if (!resume.isApproved && !resume.isBaseResume)
          PopupMenuItem(
            value: 'delete',
            child: Text('삭제', style: TextStyle(color: AppColors.error)),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _kStudentTableMinWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(AppSpace.s(20), AppSpace.s(14), AppSpace.s(20), wide ? 0 : AppSpace.s(6)),
              child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            if (wide)
              _TableRow(
                flex: _flex,
                vertical: 8,
                cells: [
                  _headerText('제목'),
                  _headerText('상태'),
                  _headerText('채운 섹션'),
                  _headerText('피드백'),
                  _headerText('수정일'),
                  const SizedBox.shrink(),
                ],
              ),
            for (final resume in resumes) ...[
              Divider(height: 1, color: AppColors.divider),
              if (wide)
                _TableRow(
                  flex: _flex,
                  onTap: () => _openResume(context, ref, resume),
                  cells: [
                    Text(resume.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    _statusBadge(resume),
                    _SectionProgress(resume: resume),
                    _FeedbackSummary(resume: resume, asReviewer: false),
                    Text(
                      resume.updatedAt == null ? '—' : AppDateUtils.formatDisplay(resume.updatedAt!),
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                    menu(resume),
                  ],
                )
              else
                _NarrowRow(
                  onTap: () => _openResume(context, ref, resume),
                  title: Text(resume.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  details: [
                    (child: _statusBadge(resume), width: 104),
                    (child: _labeled('수정', _dateValue(resume)), width: 130),
                    (child: _labeled('섹션', _SectionProgress(resume: resume)), width: 150),
                    (child: _FeedbackSummary(resume: resume, asReviewer: false), width: null),
                  ],
                  trailing: menu(resume),
                ),
            ],
          ],
        );
      },
    );
  }
}

/// 좁은 화면의 세부 항목 하나. [width]가 있으면 그 폭을 차지해 줄끼리 세로로 맞는다.
typedef _Detail = ({Widget child, double? width});

/// 좁은 화면의 한 줄: 제목, 그 아래 상태·수정일·진행·피드백.
///
/// 처음에는 세부 항목을 간격 12로 왼쪽부터 붙여 늘어놓았다. 줄마다 글자 길이가 달라
/// 같은 항목이 위아래로 안 맞았고, 전부 같은 회색이라 무엇이 날짜이고 무엇이 피드백인지
/// 한눈에 안 들어왔다. 항목마다 폭을 정해 줄끼리 맞추고, 이름표는 옅게·값은 진하게 쓴다.
class _NarrowRow extends StatelessWidget {
  const _NarrowRow({required this.title, required this.details, required this.trailing, this.onTap});

  final Widget title;
  final List<_Detail> details;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.s(20), AppSpace.s(14), AppSpace.s(8), AppSpace.s(14)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                SizedBox(height: AppSpace.s(8)),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final fixed = details.fold<double>(0, (sum, d) => sum + (d.width ?? 0));
                    // 폭을 맞출 자리가 없으면(폰) 줄바꿈으로 흘린다.
                    if (constraints.maxWidth < fixed + 120) {
                      return Wrap(
                        spacing: AppSpace.s(16),
                        runSpacing: AppSpace.s(8),
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [for (final d in details) d.child],
                      );
                    }
                    return Row(
                      children: [
                        for (final d in details)
                          if (d.width != null)
                            SizedBox(
                              width: d.width,
                              child: Align(alignment: Alignment.centerLeft, child: d.child),
                            )
                          else
                            Expanded(child: Align(alignment: Alignment.centerLeft, child: d.child)),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          SizedBox(width: AppSpace.s(12)),
          trailing,
        ],
      ),
    ),
  );
}

/// 옅은 이름표와 진한 값. "수정 2026.09.14".
Widget _labeled(String label, Widget value) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.textHint)),
    SizedBox(width: AppSpace.s(6)),
    Flexible(child: value),
  ],
);

Widget _dateValue(ResumeModel r) => Text(
  r.updatedAt == null ? '—' : AppDateUtils.formatDisplay(r.updatedAt!),
  maxLines: 1,
  style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
);

// ── 강사·관리자 ────────────────────────────────────────────────

/// 학생 한 명을 한 줄로. 이름이 첫 칸이라 "OO님의 이력서"를 줄마다 되풀이하지 않는다.
class _ReviewTable extends ConsumerWidget {
  const _ReviewTable({required this.resumes});
  final List<ResumeModel> resumes;

  static const _flex = [2, 3, 2, 2, 2, 3, 3];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String studentName(ResumeModel r) {
      final name = r.content.basicInfo.name.trim();
      return name.isEmpty ? '이름 미입력' : name;
    }

    Widget actions(ResumeModel resume) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 요청 중이면 피드백을 남기러, 승인한 것은 읽으러 연다. 승인 버튼은 열린 화면에 있다.
        if (resume.acceptsFeedback)
          FilledButton(onPressed: () => _openResume(context, ref, resume), child: const Text('검토하기'))
        else
          OutlinedButton(onPressed: () => _openResume(context, ref, resume), child: const Text('보기')),
        PopupMenuButton<String>(
          tooltip: '이력서 메뉴',
          icon: Icon(Icons.more_horiz, color: AppColors.textSecondary),
          onSelected: (value) {
            if (value == 'feedback') _addFeedback(context, ref, resume);
            if (value == 'open') _openResume(context, ref, resume);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'open', child: Text('열기')),
            // 요청하지 않은 이력서에는 피드백을 남기지 않는다.
            if (resume.acceptsFeedback)
              const PopupMenuItem(value: 'feedback', child: Text('빠른 피드백 작성')),
          ],
        ),
      ],
    );

    Widget date(ResumeModel r) => Text(
      r.updatedAt == null ? '—' : AppDateUtils.formatDisplay(r.updatedAt!),
      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _kReviewTableMinWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              _TableRow(
                flex: _flex,
                vertical: 10,
                cells: [
                  _headerText('학생'),
                  _headerText('이력서'),
                  _headerText('상태'),
                  _headerText('수정일'),
                  _headerText('채운 섹션'),
                  _headerText('피드백'),
                  const SizedBox.shrink(),
                ],
              ),
            for (var i = 0; i < resumes.length; i++) ...[
              if (wide || i > 0) Divider(height: 1, color: AppColors.divider),
              if (wide)
                _TableRow(
                  flex: _flex,
                  onTap: () => _openResume(context, ref, resumes[i]),
                  cells: [
                    Text(studentName(resumes[i]), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(
                      resumes[i].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                    _statusBadge(resumes[i]),
                    date(resumes[i]),
                    _SectionProgress(resume: resumes[i]),
                    _FeedbackSummary(resume: resumes[i], asReviewer: true),
                    actions(resumes[i]),
                  ],
                )
              else
                _NarrowRow(
                  onTap: () => _openResume(context, ref, resumes[i]),
                  title: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: studentName(resumes[i]),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: '   ${resumes[i].title}',
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  details: [
                    (child: _statusBadge(resumes[i]), width: 104),
                    (child: _labeled('수정', _dateValue(resumes[i])), width: 130),
                    (child: _labeled('섹션', _SectionProgress(resume: resumes[i])), width: 150),
                    (child: _FeedbackSummary(resume: resumes[i], asReviewer: true), width: null),
                  ],
                  trailing: actions(resumes[i]),
                ),
            ],
          ],
        );
      },
    );
  }
}

Future<void> _addFeedback(BuildContext context, WidgetRef ref, ResumeModel resume) async {
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
              await ref
                  .read(lmsRepositoryProvider)
                  .addResumeFeedback(
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
