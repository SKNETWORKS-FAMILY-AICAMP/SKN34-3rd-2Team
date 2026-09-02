import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../hub/presentation/widgets/notice_list_widgets.dart';
import '../../../shared/models/notice_model.dart';
import '../../../shared/models/submission_model.dart';
import '../../../shared/models/todo_model.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/providers/lms_providers.dart';
import '../../../shared/providers/qual_exam_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../curriculum/presentation/widgets/curriculum_dashboard_section.dart';
import '../../forms/presentation/form_tasks_screen.dart';
import '../../seating/providers/seating_providers.dart';
import 'widgets/attendance_calendar_card.dart';
import 'widgets/dashboard_profile_header.dart';
import 'widgets/my_seating_dashboard_card.dart';
import 'widgets/qual_exam_schedule_section.dart';
import 'widgets/resume_dashboard_section.dart';

/// 대시보드 — 프로필, 출석, 이력서, 게시판, 주간학습, TODO, 승인
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _todoController = TextEditingController();

  @override
  void dispose() {
    _todoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);

    return currentUser.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (user) {
        if (user == null) return const SizedBox.shrink();
        return _DashboardBody(
          user: user,
          todoController: _todoController,
        );
      },
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({
    required this.user,
    required this.todoController,
  });

  final UserModel user;
  final TextEditingController todoController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(noticesStreamProvider);
    final weeklyTask = ref.watch(weeklyTaskProvider);
    final userProgress = ref.watch(userProgressProvider);
    final todos = ref.watch(todosStreamProvider);
    final submissions = ref.watch(mySubmissionsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(noticesStreamProvider);
        ref.invalidate(todosStreamProvider);
        ref.invalidate(myResumesProvider);
        ref.invalidate(adminCohortsWithResumesProvider);
        ref.invalidate(myAttendancesProvider);
        ref.invalidate(mySubmissionsProvider);
        ref.invalidate(formTasksWithStatusProvider);
        ref.invalidate(qualExamSchedulesProvider);
        ref.invalidate(publishedSeatingLayoutProvider);
        ref.invalidate(publishedSeatingAssignmentProvider);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 960;
          final mainColumn = _DashboardMainColumn(
            user: user,
            notices: notices,
            weeklyTask: weeklyTask,
            userProgress: userProgress,
          );
          final sidebar = _DashboardSidebar(
            user: user,
            todos: todos,
            todoController: todoController,
            submissions: submissions,
            compactCalendar: wide,
            onRetrySubmissions: () => ref.invalidate(mySubmissionsProvider),
          );

          if (!wide) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  mainColumn,
                  const SizedBox(height: 16),
                  sidebar,
                ],
              ),
            );
          }

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: mainColumn),
                const SizedBox(width: 16),
                SizedBox(width: 320, child: sidebar),
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
    required this.weeklyTask,
    required this.userProgress,
  });

  final UserModel user;
  final AsyncValue<List<NoticeModel>> notices;
  final AsyncValue<dynamic> weeklyTask;
  final AsyncValue<dynamic> userProgress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashboardProfileHeader(user: user),
        const SizedBox(height: 16),
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
        const SizedBox(height: 16),
        const ResumeDashboardSection(),
        const SizedBox(height: 16),
        const FormTasksDashboardSection(),
        const SizedBox(height: 16),
        const CurriculumDashboardSection(),
        const SizedBox(height: 16),
        const QualExamScheduleSection(),
        const SizedBox(height: 16),
        const _SectionTitle('이번 주 필수 학습'),
        weeklyTask.when(
          loading: () => const _ShimmerCard(),
          error: (e, _) => Text('오류: $e'),
          data: (task) => userProgress.when(
            loading: () => const _ShimmerCard(),
            error: (e, _) => Text('오류: $e'),
            data: (progress) =>
                _WeeklyLearningCard(task: task, progress: progress),
          ),
        ),
      ],
    );
  }
}

class _DashboardSidebar extends StatelessWidget {
  const _DashboardSidebar({
    required this.user,
    required this.todos,
    required this.todoController,
    required this.submissions,
    this.compactCalendar = true,
    this.onRetrySubmissions,
  });

  final UserModel user;
  final AsyncValue<List<TodoModel>> todos;
  final TextEditingController todoController;
  final AsyncValue<List<SubmissionModel>> submissions;
  final bool compactCalendar;
  final VoidCallback? onRetrySubmissions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AttendanceCalendarCard(user: user, compact: compactCalendar),
        const SizedBox(height: 16),
        const MySeatingDashboardSection(),
        const _SectionTitle('TODO', compact: true),
        _TodoSection(
          todos: todos,
          controller: todoController,
          uid: user.uid,
        ),
        const SizedBox(height: 16),
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
            '공지',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Spacer(),
          TextButton(
            onPressed: onViewAll,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('전체 보기', style: TextStyle(fontSize: 13)),
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
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
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

class _WeeklyLearningCard extends StatelessWidget {
  const _WeeklyLearningCard({this.task, this.progress});
  final dynamic task;
  final dynamic progress;

  @override
  Widget build(BuildContext context) {
    if (task == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('등록된 필수 학습이 없습니다')),
        ),
      );
    }

    final percent = progress?.progressPercent ?? 0.0;
    final completed = progress?.completedCount ?? 0;
    final total = task.totalCount;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(
                    value: percent / 100,
                    strokeWidth: 6,
                    color: AppColors.primary,
                    backgroundColor: AppColors.primaryLight,
                  ),
                ),
                Text('${percent.toInt()}%'),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'D-${task.daysRemaining}',
                          style: const TextStyle(
                            color: AppColors.warning,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          task.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$completed / $total 완료',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodoSection extends ConsumerWidget {
  const _TodoSection({
    required this.todos,
    required this.controller,
    required this.uid,
  });

  final AsyncValue<List<TodoModel>> todos;
  final TextEditingController controller;
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 6, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '새 할 일 추가...',
                      hintStyle: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textHint,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                    onSubmitted: (value) async {
                      if (value.trim().isEmpty) return;
                      await ref
                          .read(lmsRepositoryProvider)
                          .addTodo(uid, value.trim());
                      controller.clear();
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, size: 22),
                  color: AppColors.primary,
                  padding: const EdgeInsets.only(left: 4),
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () async {
                    final value = controller.text.trim();
                    if (value.isEmpty) return;
                    await ref.read(lmsRepositoryProvider).addTodo(uid, value);
                    controller.clear();
                  },
                ),
              ],
            ),
            todos.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (e, _) => Text(
                '오류: $e',
                style: const TextStyle(fontSize: 12),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      '예정된 일정이 없습니다',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                }
                return Column(
                  children: list.map((todo) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            color: AppColors.textSecondary,
                            onPressed: () => ref
                                .read(lmsRepositoryProvider)
                                .deleteTodo(uid, todo.id),
                          ),
                          Expanded(
                            child: Text(
                              todo.title,
                              style: TextStyle(
                                fontSize: 13,
                                decoration: todo.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: todo.isCompleted
                                    ? AppColors.textHint
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: Checkbox(
                              value: todo.isCompleted,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              side: const BorderSide(
                                color: AppColors.border,
                                width: 1.5,
                              ),
                              onChanged: (_) => ref
                                  .read(lmsRepositoryProvider)
                                  .toggleTodo(uid, todo),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmissionsList extends StatelessWidget {
  const _SubmissionsList({required this.submissions});
  final List<SubmissionModel> submissions;

  @override
  Widget build(BuildContext context) {
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
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: submissions
            .take(5)
            .map(
              (s) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E8FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        s.typeLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF7C3AED),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.title,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (s.submittedAt != null)
                            Text(
                              AppDateUtils.formatDisplay(s.submittedAt!),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      s.statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: s.isApproved
                            ? AppColors.success
                            : s.isPending
                                ? AppColors.warning
                                : AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: compact ? 14 : 16,
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
