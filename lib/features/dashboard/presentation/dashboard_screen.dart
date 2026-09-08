import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../hub/presentation/widgets/notice_list_widgets.dart';
import '../../../shared/models/notice_model.dart';
import '../../../shared/models/submission_model.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/providers/lms_providers.dart';
import '../../../shared/providers/mission_providers.dart';
import '../../../shared/providers/qual_exam_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../curriculum/presentation/widgets/curriculum_dashboard_section.dart';
import '../../curriculum/providers/curriculum_providers.dart';
import '../../forms/presentation/form_tasks_screen.dart';
import '../../seating/providers/seating_providers.dart';
import '../../study_room/providers/curriculum_youtube_providers.dart';
import 'widgets/attendance_calendar_card.dart';
import 'widgets/dashboard_profile_header.dart';
import 'widgets/mission_progress_dashboard_card.dart';
import 'widgets/my_seating_dashboard_card.dart';
import 'widgets/qual_exam_schedule_section.dart';
import 'widgets/weekly_learning_recommend_section.dart';

/// 대시보드 — 프로필, 출석, 게시판, 주간학습, 승인
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);

    return currentUser.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (user) {
        if (user == null) return const SizedBox.shrink();
        return _DashboardBody(user: user);
      },
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(noticesStreamProvider);
    final submissions = ref.watch(mySubmissionsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(noticesStreamProvider);
        ref.invalidate(myAttendancesProvider);
        ref.invalidate(mySubmissionsProvider);
        ref.invalidate(formTasksWithStatusProvider);
        ref.invalidate(qualExamSchedulesProvider);
        ref.invalidate(publishedSeatingLayoutProvider);
        ref.invalidate(publishedSeatingAssignmentProvider);
        ref.invalidate(activeAlertPopupsProvider);
        ref.invalidate(curriculumMetaProvider);
        ref.invalidate(curriculumYoutubeRecommendationsProvider);
        ref.invalidate(missionProgressProvider);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 960;
          final mainColumn = _DashboardMainColumn(
            user: user,
            notices: notices,
          );
          final sidebar = _DashboardSidebar(
            user: user,
            submissions: submissions,
            compactCalendar: wide,
            onRetrySubmissions: () => ref.invalidate(mySubmissionsProvider),
          );

          if (!wide) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  mainColumn,
                  const SizedBox(height: 20),
                  sidebar,
                ],
              ),
            );
          }

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: mainColumn),
                const SizedBox(width: 20),
                SizedBox(width: 240, child: sidebar),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DashboardMainColumn extends StatelessWidget {
  const _DashboardMainColumn({
    required this.user,
    required this.notices,
  });

  final UserModel user;
  final AsyncValue<List<NoticeModel>> notices;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashboardProfileHeader(user: user),
        const SizedBox(height: 20),
        _NoticeSectionHeader(
          onViewAll: () => context.go(RoutePaths.board),
        ),
        notices.when(
          loading: () => const _ShimmerCard(),
          error: (e, _) => Text('오류: $e'),
          data: (list) => _NoticesPreview(
            notices: list.take(10).toList(),
            hasMore: list.length > 10,
          ),
        ),
        const SizedBox(height: 20),
        const WeeklyLearningRecommendSection(),
        const SizedBox(height: 20),
        const FormTasksDashboardSection(),
      ],
    );
  }
}

class _DashboardSidebar extends StatelessWidget {
  const _DashboardSidebar({
    required this.user,
    required this.submissions,
    this.compactCalendar = true,
    this.onRetrySubmissions,
  });

  final UserModel user;
  final AsyncValue<List<SubmissionModel>> submissions;
  final bool compactCalendar;
  final VoidCallback? onRetrySubmissions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AttendanceCalendarCard(user: user, compact: compactCalendar),
        const SizedBox(height: 20),
        const MissionProgressDashboardCard(compact: true),
        const SizedBox(height: 20),
        const MySeatingDashboardSection(),
        const CurriculumDashboardSection(),
        const SizedBox(height: 20),
        const QualExamScheduleSection(),
        const SizedBox(height: 20),
        const _SectionTitle('승인 현황', compact: true),
        submissions.when(
          loading: () => const _ShimmerCard(),
          error: (e, _) => InlineErrorCard(
            error: e,
            onRetry: onRetrySubmissions,
          ),
          data: (list) => _SubmissionsList(submissions: list),
        ),
      ],
    );
  }
}

class _NoticeSectionHeader extends StatelessWidget {
  const _NoticeSectionHeader({required this.onViewAll});

  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Text(
            '시스템 공지',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: onViewAll,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('더보기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticesPreview extends StatelessWidget {
  const _NoticesPreview({
    required this.notices,
    this.hasMore = false,
  });

  final List<NoticeModel> notices;
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    if (notices.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            '공지사항이 없습니다',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudentNoticeRowList(
          notices: notices,
          maxVisibleRows: 5,
          onTap: (notice) => NoticeDetailSheet.show(context, notice),
        ),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '이전 공지는 전체 보기에서 확인하세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textHint.withValues(alpha: 0.9),
              ),
            ),
          ),
      ],
    );
  }
}

class _SubmissionsList extends StatefulWidget {
  const _SubmissionsList({required this.submissions});
  final List<SubmissionModel> submissions;

  @override
  State<_SubmissionsList> createState() => _SubmissionsListState();
}

class _SubmissionsListState extends State<_SubmissionsList> {
  /// 한 칸에 보이는 최근 항목 수
  static const _visibleCount = 3;

  /// 항목 1개당 대략 높이 (패딩 + 뱃지 + 제목 + 날짜)
  static const _itemExtent = 86.0;

  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final submissions = widget.submissions;
    if (submissions.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(
              '제출 내역이 없습니다',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      );
    }

    final needsScroll = submissions.length > _visibleCount;
    final maxHeight = _visibleCount * _itemExtent;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: needsScroll ? maxHeight : double.infinity,
        ),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: needsScroll,
          child: ListView.separated(
            controller: _scrollController,
            shrinkWrap: !needsScroll,
            primary: false,
            physics: needsScroll
                ? const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  )
                : const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: submissions.length,
            separatorBuilder: (_, _) => const Divider(
              height: 1,
              thickness: 1,
              color: AppColors.border,
            ),
            itemBuilder: (context, index) {
              return _SubmissionTile(submission: submissions[index]);
            },
          ),
        ),
      ),
    );
  }
}

class _SubmissionTile extends StatelessWidget {
  const _SubmissionTile({required this.submission});

  final SubmissionModel submission;

  @override
  Widget build(BuildContext context) {
    final s = submission;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    s.typeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              StatusBadge(
                label: s.statusLabel,
                color: s.isApproved
                    ? AppColors.success
                    : s.isPending
                        ? AppColors.badgeLate
                        : AppColors.error,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            s.title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (s.submittedAt != null) ...[
            const SizedBox(height: 2),
            Text(
              AppDateUtils.formatDisplay(s.submittedAt!),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.compact = false});

  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: compact ? 14 : 16,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _ShimmerCard extends StatelessWidget {
  const _ShimmerCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: ShimmerBox(height: 60, borderRadius: 12),
      ),
    );
  }
}
