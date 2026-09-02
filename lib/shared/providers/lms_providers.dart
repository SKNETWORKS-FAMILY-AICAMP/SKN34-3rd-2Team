import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart';
import '../models/assessment_model.dart';
import '../models/inflearn_package_model.dart';
import '../models/cohort_model.dart';
import '../models/domain_models.dart';
import '../models/form_task_model.dart';
import '../models/notice_model.dart';
import '../models/scheduled_notice_model.dart';
import '../models/post_model.dart';
import '../models/resume_model.dart';
import '../models/submission_model.dart';
import '../models/todo_model.dart';
import '../models/user_model.dart';
import '../demo/demo_accounts.dart';
import '../demo/demo_lms_repository.dart';
import '../providers/cohort_providers.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../providers/firebase_providers.dart';
import '../data/lms_repository.dart';
import '../../features/admin/data/scheduled_notice_admin_service.dart';
import 'package:cloud_functions/cloud_functions.dart';

final scheduledNoticeAdminServiceProvider =
    Provider<ScheduledNoticeAdminService>((ref) {
  return ScheduledNoticeAdminService(
    FirebaseFunctions.instanceFor(region: 'asia-northeast3'),
  );
});

final lmsRepositoryProvider = Provider<dynamic>((ref) {
  final uid = ref.watch(sessionUidProvider).value;
  if (DemoConfig.enabled && uid != null && DemoAccounts.isDemoUid(uid)) {
    return demoLmsRepository;
  }
  return LmsRepository(ref.watch(firestoreProvider));
});

final todosStreamProvider = StreamProvider.autoDispose<List<TodoModel>>((ref) {
  final user = ref.watch(currentUserSyncProvider);
  if (user == null) return Stream.value([]);
  return ref.watch(lmsRepositoryProvider).watchTodos(user.uid);
});

final postsStreamProvider = StreamProvider.autoDispose<List<PostModel>>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value([]);
  return ref.watch(lmsRepositoryProvider).watchPosts(cohortId);
});

final noticesStreamProvider =
    StreamProvider.autoDispose<List<NoticeModel>>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value([]);
  return ref.watch(lmsRepositoryProvider).watchNotices(cohortId);
});

final scheduledNoticesProvider =
    StreamProvider.autoDispose<List<ScheduledNoticeModel>>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  final isAdmin = ref.watch(isAdminProvider);
  if (cohortId == null || !isAdmin) return Stream.value([]);
  return ref.watch(lmsRepositoryProvider).watchScheduledNotices(cohortId);
});

final mySubmissionsProvider =
    StreamProvider.autoDispose<List<SubmissionModel>>((ref) {
  final user = ref.watch(currentUserSyncProvider);
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (user == null || cohortId == null) return Stream.value([]);
  return ref
      .watch(lmsRepositoryProvider)
      .watchMySubmissions(cohortId, user.uid);
});

final allSubmissionsProvider =
    StreamProvider.autoDispose<List<SubmissionModel>>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  final isAdmin = ref.watch(isAdminProvider);
  if (cohortId == null || !isAdmin) return Stream.value([]);
  return ref.watch(lmsRepositoryProvider).watchAllSubmissions(cohortId);
});

final myResumesProvider = StreamProvider.autoDispose<List<ResumeModel>>((ref) {
  final user = ref.watch(currentUserSyncProvider);
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (user == null || cohortId == null) return Stream.value([]);
  return ref.watch(lmsRepositoryProvider).watchMyResumes(cohortId, user.uid);
});

final cohortResumesProvider =
    StreamProvider.autoDispose<List<ResumeModel>>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  final isAdmin = ref.watch(isAdminProvider);
  if (cohortId == null || !isAdmin) return Stream.value([]);
  return ref.watch(lmsRepositoryProvider).watchCohortResumes(cohortId);
});

final weeklyTaskProvider = StreamProvider.autoDispose<WeeklyTaskModel?>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value(null);
  return ref.watch(lmsRepositoryProvider).watchCurrentWeeklyTask(cohortId);
});

final userProgressProvider =
    StreamProvider.autoDispose<UserProgressModel?>((ref) {
  final user = ref.watch(currentUserSyncProvider);
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (user == null || cohortId == null) return Stream.value(null);
  return ref
      .watch(lmsRepositoryProvider)
      .watchUserProgress(cohortId, user.uid);
});

final myAttendancesProvider =
    StreamProvider.autoDispose<List<AttendanceModel>>((ref) {
  final user = ref.watch(currentUserSyncProvider);
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (user == null || cohortId == null) return Stream.value([]);
  return ref
      .watch(lmsRepositoryProvider)
      .watchUserAttendances(cohortId, user.uid);
});

/// 관리자 출석 관리 대상 학생 uid
final adminAttendanceTargetUserIdProvider =
    NotifierProvider<_AdminAttendanceTarget, String?>(
  _AdminAttendanceTarget.new,
);

class _AdminAttendanceTarget extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? uid) => state = uid;
}

final cohortStudentsProvider =
    StreamProvider.autoDispose<List<UserModel>>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  final isAdmin = ref.watch(isAdminProvider);
  if (cohortId == null || !isAdmin) return Stream.value([]);
  return ref.watch(lmsRepositoryProvider).watchCohortStudents(cohortId);
});

final attendanceStatusMapProvider = StreamProvider.autoDispose
    .family<Map<String, String>, String>((ref, userId) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value({});
  return ref
      .watch(lmsRepositoryProvider)
      .watchUserAttendances(cohortId, userId)
      .map((list) {
    final map = <String, String>{};
    for (final a in list) {
      final s = a.dayStatus;
      if (s != null) map[a.dateKey] = s;
    }
    return map;
  });
});

final todayScheduleProvider = StreamProvider.autoDispose<ScheduleModel?>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value(null);
  final dateKey = AppDateUtils.toDateKey(DateTime.now());
  return ref.watch(lmsRepositoryProvider).watchSchedule(cohortId, dateKey);
});

final scheduleDateKeysProvider =
    StreamProvider.autoDispose<List<String>>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value([]);
  return ref.watch(lmsRepositoryProvider).watchScheduleDateKeys(cohortId);
});

final materialsProvider =
    StreamProvider.autoDispose<List<MaterialModel>>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value([]);
  return ref.watch(lmsRepositoryProvider).watchMaterials(cohortId);
});

final assignmentsProvider =
    StreamProvider.autoDispose<List<AssignmentModel>>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value([]);
  return ref.watch(lmsRepositoryProvider).watchAssignments(cohortId);
});

final inflearnPackagesProvider =
    StreamProvider.autoDispose<List<InflearnPackageModel>>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value([]);
  return ref.watch(lmsRepositoryProvider).watchInflearnPackages(cohortId);
});

final publishedInflearnPackagesProvider =
    StreamProvider.autoDispose<List<InflearnPackageModel>>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value([]);
  return ref
      .watch(lmsRepositoryProvider)
      .watchPublishedInflearnPackages(cohortId);
});

final assessmentsProvider =
    StreamProvider.autoDispose<List<AssessmentModel>>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value([]);
  return ref.watch(lmsRepositoryProvider).watchAssessments(cohortId);
});

final publishedAssessmentsProvider =
    StreamProvider.autoDispose<List<AssessmentModel>>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value([]);
  return ref.watch(lmsRepositoryProvider).watchPublishedAssessments(cohortId);
});

final myAssessmentSubmissionsProvider = StreamProvider.autoDispose<
    List<AssessmentSubmissionModel>>((ref) {
  final user = ref.watch(currentUserSyncProvider);
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (user == null || cohortId == null) return Stream.value([]);
  return ref
      .watch(lmsRepositoryProvider)
      .watchMyAssessmentSubmissions(cohortId, user.uid);
});

/// 선택된 캘린더 날짜의 시간표
final selectedScheduleProvider = StreamProvider.autoDispose
    .family<ScheduleModel?, DateTime>((ref, date) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value(null);
  final dateKey = AppDateUtils.toDateKey(date);
  return ref.watch(lmsRepositoryProvider).watchSchedule(cohortId, dateKey);
});

final resumeFeedbackProvider = StreamProvider.autoDispose
    .family<List<ResumeFeedbackModel>, String>((ref, resumeId) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value([]);
  return ref
      .watch(lmsRepositoryProvider)
      .watchResumeFeedback(cohortId, resumeId);
});

final resumeDetailProvider = StreamProvider.autoDispose
    .family<ResumeModel?, String>((ref, resumeId) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value(null);
  return ref.watch(lmsRepositoryProvider).watchResume(cohortId, resumeId);
});

final cohortsStreamProvider =
    StreamProvider.autoDispose<List<CohortModel>>((ref) {
  final isAdmin = ref.watch(isAdminProvider);
  if (!isAdmin) return Stream.value([]);
  return ref.watch(lmsRepositoryProvider).watchCohorts();
});

final allCohortsAdminProvider =
    StreamProvider.autoDispose<List<CohortModel>>((ref) {
  final isAdmin = ref.watch(isAdminProvider);
  if (!isAdmin) return Stream.value([]);
  return ref.watch(lmsRepositoryProvider).watchAllCohorts();
});

final effectiveCohortNameProvider = Provider<String?>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return null;

  final cohortsAsync = ref.watch(cohortsStreamProvider);
  final matched = switch (cohortsAsync) {
    AsyncData(:final value) =>
      value.where((c) => c.cohortId == cohortId).firstOrNull,
    _ => null,
  };
  if (matched != null) return matched.name;

  final user = ref.watch(currentUserSyncProvider);
  if (user?.cohortId == cohortId) return user?.cohortName;
  return cohortId;
});

final adminCohortsWithResumesProvider =
    StreamProvider.autoDispose<List<CohortWithResumes>>((ref) {
  final isAdmin = ref.watch(isAdminProvider);
  if (!isAdmin) return Stream.value([]);
  return ref.watch(lmsRepositoryProvider).watchAllCohortsWithResumes();
});

final formTasksWithStatusProvider =
    StreamProvider.autoDispose<List<FormTaskWithStatus>>((ref) {
  final user = ref.watch(currentUserSyncProvider);
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (user == null || cohortId == null) return Stream.value([]);
  return ref
      .watch(lmsRepositoryProvider)
      .watchFormTasksWithStatus(cohortId, user.uid);
});

final allFormTasksAdminProvider =
    StreamProvider.autoDispose<List<FormTaskModel>>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  final isAdmin = ref.watch(isAdminProvider);
  if (cohortId == null || !isAdmin) return Stream.value([]);
  return ref.watch(lmsRepositoryProvider).watchAllFormTasks(cohortId);
});

final formTaskDetailProvider = StreamProvider.autoDispose
    .family<FormTaskModel?, String>((ref, taskId) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value(null);
  return ref.watch(lmsRepositoryProvider).watchFormTask(cohortId, taskId);
});

final formTaskResponsesProvider = StreamProvider.autoDispose
    .family<List<FormResponseModel>, String>((ref, taskId) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value([]);
  return ref
      .watch(lmsRepositoryProvider)
      .watchFormTaskResponses(cohortId, taskId);
});
