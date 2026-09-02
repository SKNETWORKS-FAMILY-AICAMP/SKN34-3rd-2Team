import 'dart:async';

import '../../core/constants/cohort_status.dart';
import '../models/assessment_model.dart';
import '../models/inflearn_package_model.dart';
import '../models/cohort_model.dart';
import '../models/domain_models.dart';
import '../models/notice_model.dart';
import '../models/form_task_model.dart';
import '../models/post_model.dart';
import '../models/resume_content.dart';
import '../models/resume_model.dart';
import '../models/submission_model.dart';
import '../models/todo_model.dart';
import '../models/user_model.dart';
import 'demo_accounts.dart';
import 'demo_session.dart';

/// Firebase 대신 메모리 데이터를 제공하는 Demo Repository
class DemoLmsRepository {
  DemoLmsRepository() {
    _seed();
    _emit();
  }

  final _todoController = StreamController<List<TodoModel>>.broadcast();
  final _postController = StreamController<List<PostModel>>.broadcast();
  final _submissionController =
      StreamController<List<SubmissionModel>>.broadcast();
  final _assessmentController =
      StreamController<List<AssessmentModel>>.broadcast();
  final _inflearnPackageController =
      StreamController<List<InflearnPackageModel>>.broadcast();
  final _assessmentSubmissionController =
      StreamController<List<AssessmentSubmissionModel>>.broadcast();

  late List<TodoModel> _todos;
  late List<PostModel> _posts;
  late List<NoticeModel> _notices;
  late List<SubmissionModel> _submissions;
  late List<ResumeModel> _resumes;
  late List<AttendanceModel> _attendances;
  late List<MileageTransactionModel> _mileageTx;
  late List<AssessmentModel> _assessments;
  late List<InflearnPackageModel> _inflearnPackages;
  late List<AssessmentSubmissionModel> _assessmentSubmissions;
  late List<FormTaskModel> _formTasks;
  final Map<String, List<FormResponseModel>> _formResponses = {};

  void _seed() {
    _todos = [];
    _posts = [];
    _notices = [];
    _submissions = [];
    _resumes = [];
    _attendances = [];
    _mileageTx = [];
    _assessments = [
      AssessmentModel(
        id: 'a1',
        title: '34기 2차 성취도평가',
        tags: const ['데이터 분석', '머신러닝/딥러닝'],
        questionCount: 25,
        maxScore: 100,
        startAt: DateTime(2026, 7, 1),
        endAt: DateTime(2026, 8, 15),
        published: true,
        createdAt: DateTime(2026, 6, 20),
      ),
      AssessmentModel(
        id: 'a2',
        title: '34기 1차 성취도평가',
        tags: const ['Python', '기초'],
        questionCount: 25,
        maxScore: 100,
        startAt: DateTime(2026, 5, 1),
        endAt: DateTime(2026, 6, 30),
        published: true,
        createdAt: DateTime(2026, 4, 20),
      ),
    ];
    _inflearnPackages = [
      InflearnPackageModel(
        id: 'pkg1',
        title: '프로그래밍과 데이터 기초 예복습',
        subject: '프로그래밍과 데이터 기초',
        type: InflearnPackageType.review,
        summary:
            '첫번째 교과목 예복습에 필요한 6개 강의입니다. 파이썬 기초를 반복 학습해 주세요.',
        isPublished: true,
        sortOrder: 1,
        publishedAt: DateTime(2026, 7, 4),
        units: const [
          InflearnUnitModel(
            name: 'Python',
            courses: [
              InflearnCourseModel(
                title: '단 60분! 파이썬 핵심 개념 초압축 강의',
                url: 'https://www.inflearn.com',
              ),
              InflearnCourseModel(
                title: '문과생도, 비전공자도, 누구나 배울 수 있는 파이썬(Python)!',
                url: 'https://www.inflearn.com',
              ),
            ],
          ),
          InflearnUnitModel(
            name: 'Data base',
            courses: [
              InflearnCourseModel(
                title: 'Do it! SQL 입문',
                url: 'https://www.inflearn.com',
              ),
              InflearnCourseModel(
                title: '초보자를 위한 BigQuery(SQL) 입문',
                url: 'https://www.inflearn.com',
              ),
            ],
          ),
          InflearnUnitModel(
            name: 'Web Crawling',
            courses: [
              InflearnCourseModel(
                title: '[신규 개정판] 이것이 진짜 크롤링이다 - 기본편',
                url: 'https://www.inflearn.com',
              ),
              InflearnCourseModel(
                title: '[Python 실전] 웹크롤링과 데이터분석',
                url: 'https://www.inflearn.com',
              ),
            ],
          ),
        ],
      ),
      InflearnPackageModel(
        id: 'pkg2',
        title: 'LLM 미리보기',
        subject: 'LLM',
        type: InflearnPackageType.bonus,
        summary: '다가올 LLM 교과목 예습용 강의입니다.',
        isPublished: true,
        sortOrder: 3,
        publishedAt: DateTime(2026, 7, 4),
        courses: const [
          InflearnCourseModel(
            title: '입문자를 위한 LangChain 기초',
            url: 'https://www.inflearn.com',
          ),
          InflearnCourseModel(
            title: 'TypeScript로 시작하는 LangChain - LLM & RAG 입문',
            url: 'https://www.inflearn.com',
          ),
        ],
      ),
    ];
    _assessmentSubmissions = [
      AssessmentSubmissionModel(
        id: 'a1_${DemoAccounts.studentUid}',
        assessmentId: 'a1',
        userId: DemoAccounts.studentUid,
        userDisplayName: DemoAccounts.student.displayName,
        completed: true,
        submittedAt: DateTime(2026, 8, 10),
      ),
    ];
    _formTasks = [
      FormTaskModel(
        id: 'form1',
        title: '34기 OT 참여 설문',
        description: '온보딩 설문입니다. 노션 가이드를 참고해 작성해 주세요.',
        formUrl: 'https://docs.google.com/forms/d/e/example/viewform',
        notionGuideUrl: 'https://notion.so/example-guide',
        dueAt: DateTime.now().add(const Duration(days: 7)),
        published: true,
        createdAt: DateTime.now(),
      ),
    ];
    _formResponses.clear();
  }

  void _emit() {
    if (!_todoController.isClosed) _todoController.add(List.from(_todos));
    if (!_postController.isClosed) _postController.add(List.from(_posts));
    if (!_submissionController.isClosed) {
      _submissionController.add(List.from(_submissions));
    }
    if (!_assessmentController.isClosed) {
      _assessmentController.add(List.from(_assessments));
    }
    if (!_inflearnPackageController.isClosed) {
      _inflearnPackageController.add(List.from(_inflearnPackages));
    }
    if (!_assessmentSubmissionController.isClosed) {
      _assessmentSubmissionController.add(List.from(_assessmentSubmissions));
    }
  }

  Stream<List<TodoModel>> watchTodos(String uid) => _todoController.stream;

  Future<void> addTodo(String uid, String title) async {
    _todos.insert(
      0,
      TodoModel(
        id: 't${_todos.length}',
        title: title,
        isCompleted: false,
        createdAt: DateTime.now(),
      ),
    );
    _emit();
  }

  Future<void> toggleTodo(String uid, TodoModel todo) async {
    final i = _todos.indexWhere((t) => t.id == todo.id);
    if (i >= 0) {
      _todos[i] = TodoModel(
        id: todo.id,
        title: todo.title,
        isCompleted: !todo.isCompleted,
        createdAt: todo.createdAt,
      );
      _emit();
    }
  }

  Future<void> deleteTodo(String uid, String todoId) async {
    _todos.removeWhere((t) => t.id == todoId);
    _emit();
  }

  Stream<List<PostModel>> watchPosts(String cohortId, {int limit = 20}) =>
      _postController.stream;

  Future<void> createPost({
    required String cohortId,
    required String authorId,
    required String authorName,
    required String content,
  }) async {
    _posts.insert(
      0,
      PostModel(
        id: 'p${_posts.length}',
        authorId: authorId,
        authorName: authorName,
        content: content,
        createdAt: DateTime.now(),
      ),
    );
    _emit();
  }

  Future<void> deletePost(String cohortId, String postId) async {
    _posts.removeWhere((p) => p.id == postId);
    _emit();
  }

  Stream<List<NoticeModel>> watchNotices(String cohortId) async* {
    yield _notices;
  }

  Future<String> createNotice({
    required String cohortId,
    required NoticeModel notice,
    required String authorId,
    required String authorName,
  }) async {
    _notices.insert(
      0,
      NoticeModel(
        id: 'n${_notices.length}',
        title: notice.title,
        content: notice.content,
        authorName: authorName,
        isFavorite: notice.isFavorite,
        createdAt: DateTime.now(),
      ),
    );
    return 'n${_notices.length - 1}';
  }

  Stream<List<SubmissionModel>> watchMySubmissions(
    String cohortId,
    String userId,
  ) {
    return _submissionController.stream
        .map((list) => list.where((s) => s.userId == userId).toList());
  }

  Stream<List<SubmissionModel>> watchAllSubmissions(String cohortId) {
    return _submissionController.stream;
  }

  Future<String> createSubmission({
    required String cohortId,
    required SubmissionModel submission,
  }) async {
    final id = submission.id.isNotEmpty
        ? submission.id
        : 'sub${_submissions.length}';
    _submissions.insert(
      0,
      SubmissionModel(
        id: id,
        userId: submission.userId,
        userDisplayName: submission.userDisplayName,
        title: submission.title,
        type: submission.type,
        status: submission.status,
        submittedAt: DateTime.now(),
        certType: submission.certType,
        fileUrls: submission.fileUrls,
        startAt: submission.startAt,
        endAt: submission.endAt,
        weekNumber: submission.weekNumber,
        weekLabel: submission.weekLabel,
        link: submission.link,
      ),
    );
    _emit();
    return id;
  }

  Future<void> reviewSubmission({
    required String cohortId,
    required String submissionId,
    required String status,
    String? reviewComment,
  }) async {
    final i = _submissions.indexWhere((s) => s.id == submissionId);
    if (i < 0) return;
    final s = _submissions[i];
    _submissions[i] = SubmissionModel(
      id: s.id,
      userId: s.userId,
      userDisplayName: s.userDisplayName,
      title: s.title,
      type: s.type,
      status: status,
      submittedAt: s.submittedAt,
      reviewComment: reviewComment,
      certType: s.certType,
      fileUrls: s.fileUrls,
      startAt: s.startAt,
      endAt: s.endAt,
      weekNumber: s.weekNumber,
      weekLabel: s.weekLabel,
      link: s.link,
    );
    _emit();
  }

  Stream<WeeklyTaskModel?> watchCurrentWeeklyTask(String cohortId) async* {
    yield null;
  }

  Stream<UserProgressModel?> watchUserProgress(
    String cohortId,
    String userId,
  ) async* {
    yield null;
  }

  static final _demoCohorts = [
    CohortModel(
      cohortId: 'cohort_34',
      name: 'SK네트웍스 Family AI 캠프 34기',
      termNumber: 34,
      status: CohortStatus.active,
      studentCount: 1,
      startDate: DateTime(2026, 5, 1),
      endDate: DateTime(2026, 12, 31),
    ),
    CohortModel(
      cohortId: 'cohort_35',
      name: 'SK네트웍스 Family AI 캠프 35기',
      termNumber: 35,
      status: CohortStatus.upcoming,
      studentCount: 0,
      startDate: DateTime(2027, 1, 1),
      endDate: DateTime(2027, 8, 31),
    ),
  ];

  Stream<List<CohortModel>> watchCohorts() async* {
    yield _demoCohorts.where((c) => c.isSelectable).toList();
  }

  Stream<List<CohortModel>> watchAllCohorts() async* {
    yield List.from(_demoCohorts);
  }

  Future<String> createCohort(CohortModel cohort) async {
    _demoCohorts.insert(0, cohort);
    return cohort.cohortId;
  }

  Future<void> updateCohort(CohortModel cohort) async {
    final i = _demoCohorts.indexWhere((c) => c.cohortId == cohort.cohortId);
    if (i >= 0) _demoCohorts[i] = cohort;
  }

  Stream<List<CohortWithResumes>> watchAllCohortsWithResumes() async* {
    yield [
      CohortWithResumes(cohort: _demoCohorts[0], resumes: List.from(_resumes)),
      CohortWithResumes(cohort: _demoCohorts[1], resumes: const []),
    ];
  }

  Stream<List<ResumeModel>> watchMyResumes(String cohortId, String userId) async* {
    yield _resumes.where((r) => r.userId == userId).toList();
  }

  Stream<List<ResumeModel>> watchCohortResumes(String cohortId) async* {
    yield _resumes;
  }

  Future<String> createResume({
    required String cohortId,
    required String userId,
    required String title,
  }) async {
    final id = 'r${_resumes.length}';
    _resumes.add(
      ResumeModel(
        id: id,
        userId: userId,
        title: title,
        status: 'writing',
        sections: const {},
      ),
    );
    return id;
  }

  Future<void> updateResumeSections({
    required String cohortId,
    required String resumeId,
    required Map<String, bool> sections,
    required String status,
  }) async {
    await updateResume(
      cohortId: cohortId,
      resumeId: resumeId,
      sections: sections,
      status: status,
    );
  }

  Stream<ResumeModel?> watchResume(String cohortId, String resumeId) async* {
    yield _findResume(resumeId);
  }

  ResumeModel? _findResume(String resumeId) {
    try {
      return _resumes.firstWhere((r) => r.id == resumeId);
    } catch (_) {
      return null;
    }
  }

  Future<void> updateResume({
    required String cohortId,
    required String resumeId,
    String? title,
    ResumeContent? content,
    Map<String, bool>? sections,
    String? status,
    bool incrementRevision = false,
  }) async {
    final i = _resumes.indexWhere((r) => r.id == resumeId);
    if (i < 0) return;
    final current = _resumes[i];
    final newContent = content ?? current.content;
    _resumes[i] = current.copyWith(
      title: title,
      content: newContent,
      sections: sections ?? newContent.computeSections(),
      status: status,
      revisionCount: incrementRevision
          ? current.revisionCount + 1
          : current.revisionCount,
    );
  }

  Future<void> approveResume({
    required String cohortId,
    required String resumeId,
  }) async {
    await updateResume(
      cohortId: cohortId,
      resumeId: resumeId,
      status: 'approved',
    );
  }

  Future<void> deleteResume(String cohortId, String resumeId) async {
    _resumes.removeWhere((r) => r.id == resumeId);
  }

  Stream<List<ResumeFeedbackModel>> watchResumeFeedback(
    String cohortId,
    String resumeId,
  ) async* {
    yield [];
  }

  Future<void> addResumeFeedback({
    required String cohortId,
    required String resumeId,
    required ResumeFeedbackModel feedback,
    required String authorId,
    required String authorName,
  }) async {
    final i = _resumes.indexWhere((r) => r.id == resumeId);
    if (i < 0) return;
    final current = _resumes[i];
    _resumes[i] = current.copyWith(
      feedbackCount: current.feedbackCount + 1,
    );
  }

  Future<void> markResumeFeedbackSeen({
    required String cohortId,
    required String resumeId,
    required int feedbackCount,
  }) async {
    final i = _resumes.indexWhere((r) => r.id == resumeId);
    if (i < 0) return;
    _resumes[i] = _resumes[i].copyWith(lastSeenFeedbackCount: feedbackCount);
  }

  Stream<List<AttendanceModel>> watchUserAttendances(
    String cohortId,
    String userId,
  ) async* {
    yield _attendances.where((a) => a.userId == userId).toList();
  }

  Stream<List<AttendanceModel>> watchMyAttendances(
    String cohortId,
    String userId,
  ) async* {
    yield _attendances.where((a) => a.userId == userId).toList();
  }

  Stream<List<UserModel>> watchCohortStudents(String cohortId) async* {
    yield [
      DemoAccounts.student,
    ];
  }

  Future<void> upsertAttendanceStatus({
    required String cohortId,
    required String userId,
    required String userDisplayName,
    required String dateKey,
    required String status,
  }) async {
    final i = _attendances.indexWhere(
      (a) => a.userId == userId && a.dateKey == dateKey,
    );
    if (i >= 0) {
      final cur = _attendances[i];
      _attendances[i] = AttendanceModel(
        id: cur.id,
        userId: userId,
        type: 'status',
        dateKey: dateKey,
        status: status,
        userDisplayName: userDisplayName,
        timestamp: DateTime.now(),
      );
    } else {
      _attendances.insert(
        0,
        AttendanceModel(
          id: 'a${_attendances.length}',
          userId: userId,
          type: 'status',
          dateKey: dateKey,
          status: status,
          userDisplayName: userDisplayName,
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  Future<void> clearAttendanceStatus({
    required String cohortId,
    required String userId,
    required String dateKey,
  }) async {
    _attendances.removeWhere(
      (a) => a.userId == userId && a.dateKey == dateKey,
    );
  }

  Future<void> recordAttendance({
    required String cohortId,
    required String userId,
    required String userDisplayName,
    required String type,
    required String dateKey,
  }) async {
    _attendances.insert(
      0,
      AttendanceModel(
        id: 'a${_attendances.length}',
        userId: userId,
        type: type,
        dateKey: dateKey,
        timestamp: DateTime.now(),
      ),
    );
  }

  Stream<List<MileageTransactionModel>> watchMyMileageTransactions(
    String cohortId,
    String userId,
  ) async* {
    yield _mileageTx.where((t) => t.userId == userId).toList();
  }

  Stream<ScheduleModel?> watchSchedule(String cohortId, String dateKey) async* {
    yield null;
  }

  Stream<List<String>> watchScheduleDateKeys(String cohortId) async* {
    yield [];
  }

  Stream<List<MaterialModel>> watchMaterials(String cohortId) async* {
    yield [];
  }

  Stream<List<AssignmentModel>> watchAssignments(String cohortId) async* {
    yield [];
  }

  Stream<List<InflearnPackageModel>> watchInflearnPackages(String cohortId) {
    return _inflearnPackageController.stream;
  }

  Stream<List<InflearnPackageModel>> watchPublishedInflearnPackages(
    String cohortId,
  ) {
    return _inflearnPackageController.stream
        .map((list) => list.where((p) => p.isPublished).toList());
  }

  Future<String> createInflearnPackage({
    required String cohortId,
    required InflearnPackageModel package,
  }) async {
    final id = 'pkg${_inflearnPackages.length}';
    _inflearnPackages.insert(
      0,
      InflearnPackageModel(
        id: id,
        title: package.title,
        subject: package.subject,
        type: package.type,
        summary: package.summary,
        units: package.units,
        courses: package.courses,
        isPublished: package.isPublished,
        sortOrder: package.sortOrder,
        publishedAt: package.publishedAt,
      ),
    );
    _emit();
    return id;
  }

  Future<void> updateInflearnPackage({
    required String cohortId,
    required String packageId,
    required Map<String, dynamic> updates,
  }) async {
    final i = _inflearnPackages.indexWhere((p) => p.id == packageId);
    if (i < 0) return;
    final p = _inflearnPackages[i];

    List<InflearnUnitModel>? units;
    if (updates['units'] is List) {
      units = (updates['units'] as List)
          .map((u) => InflearnUnitModel.fromMap(u as Map<String, dynamic>))
          .toList();
    }
    List<InflearnCourseModel>? courses;
    if (updates['courses'] is List) {
      courses = (updates['courses'] as List)
          .map((c) => InflearnCourseModel.fromMap(c as Map<String, dynamic>))
          .toList();
    }

    _inflearnPackages[i] = p.copyWith(
      title: updates['title'] as String? ?? p.title,
      subject: updates['subject'] as String? ?? p.subject,
      type: updates['type'] != null
          ? InflearnPackageType.fromString(updates['type'] as String)
          : p.type,
      summary: updates.containsKey('summary')
          ? updates['summary'] as String?
          : p.summary,
      units: units ?? p.units,
      courses: courses ?? p.courses,
      isPublished: updates['isPublished'] as bool? ?? p.isPublished,
      sortOrder: (updates['sortOrder'] as num?)?.toInt() ?? p.sortOrder,
      publishedAt: updates['publishedAt'] is DateTime
          ? updates['publishedAt'] as DateTime
          : p.publishedAt,
    );
    _emit();
  }

  Future<void> deleteInflearnPackage({
    required String cohortId,
    required String packageId,
  }) async {
    _inflearnPackages.removeWhere((p) => p.id == packageId);
    _emit();
  }

  Stream<List<AssessmentModel>> watchAssessments(String cohortId) {
    return _assessmentController.stream;
  }

  Stream<List<AssessmentModel>> watchPublishedAssessments(String cohortId) {
    return _assessmentController.stream
        .map((list) => list.where((a) => a.published).toList());
  }

  Future<String> createAssessment({
    required String cohortId,
    required AssessmentModel assessment,
  }) async {
    final id = 'a${_assessments.length}';
    _assessments.insert(
      0,
      AssessmentModel(
        id: id,
        title: assessment.title,
        tags: assessment.tags,
        questionCount: assessment.questionCount,
        maxScore: assessment.maxScore,
        startAt: assessment.startAt,
        endAt: assessment.endAt,
        problemFileUrl: assessment.problemFileUrl,
        problemFileName: assessment.problemFileName,
        published: assessment.published,
        createdAt: DateTime.now(),
      ),
    );
    _emit();
    return id;
  }

  Future<void> updateAssessment({
    required String cohortId,
    required String assessmentId,
    required Map<String, dynamic> updates,
  }) async {
    final i = _assessments.indexWhere((a) => a.id == assessmentId);
    if (i < 0) return;
    final a = _assessments[i];
    _assessments[i] = AssessmentModel(
      id: a.id,
      title: updates['title'] as String? ?? a.title,
      tags: updates['tags'] as List<String>? ?? a.tags,
      questionCount: updates['questionCount'] as int? ?? a.questionCount,
      maxScore: updates['maxScore'] as int? ?? a.maxScore,
      startAt: updates['startAt'] as DateTime? ?? a.startAt,
      endAt: updates['endAt'] as DateTime? ?? a.endAt,
      problemFileUrl: updates['problemFileUrl'] as String? ?? a.problemFileUrl,
      problemFileName:
          updates['problemFileName'] as String? ?? a.problemFileName,
      published: updates['published'] as bool? ?? a.published,
      createdAt: a.createdAt,
    );
    _emit();
  }

  Future<void> publishAssessment({
    required String cohortId,
    required String assessmentId,
  }) async {
    await updateAssessment(
      cohortId: cohortId,
      assessmentId: assessmentId,
      updates: {'published': true},
    );
  }

  Stream<List<AssessmentSubmissionModel>> watchMyAssessmentSubmissions(
    String cohortId,
    String userId,
  ) {
    return _assessmentSubmissionController.stream
        .map((list) => list.where((s) => s.userId == userId).toList());
  }

  Stream<List<AssessmentSubmissionModel>> watchAssessmentSubmissions(
    String cohortId,
    String assessmentId,
  ) {
    return _assessmentSubmissionController.stream
        .map((list) => list.where((s) => s.assessmentId == assessmentId).toList());
  }

  Future<void> submitAssessmentAnswer({
    required String cohortId,
    required String assessmentId,
    required String userId,
    required String userDisplayName,
    required String answerFileUrl,
    required String answerFileName,
  }) async {
    final id = '${assessmentId}_$userId';
    _assessmentSubmissions.removeWhere((s) => s.id == id);
    _assessmentSubmissions.add(
      AssessmentSubmissionModel(
        id: id,
        assessmentId: assessmentId,
        userId: userId,
        userDisplayName: userDisplayName,
        completed: true,
        answerFileUrl: answerFileUrl,
        answerFileName: answerFileName,
        submittedAt: DateTime.now(),
      ),
    );
    _emit();
  }

  Future<void> submitAssignment({
    required String cohortId,
    required String assignmentId,
    required String userId,
    required String userDisplayName,
    required String fileUrl,
    required String fileName,
    required int fileSizeBytes,
  }) async {}

  Future<void> updateProfile({
    required String uid,
    String? motto,
    List<String>? skills,
    Map<String, String>? socialLinks,
    String? birthDate,
    String? personalEmail,
  }) async {
    final session = DemoSession.instance;
    if (session.currentUser?.uid != uid) return;
    session.updateCurrentUser(
      session.currentUser!.copyWith(
        motto: motto,
        skills: skills,
        socialLinks: socialLinks,
        birthDate: birthDate,
        personalEmail: personalEmail,
      ),
    );
  }

  Future<void> updatePersonalEmail({
    required String uid,
    required String personalEmail,
  }) async {
    await updateProfile(uid: uid, personalEmail: personalEmail.trim().toLowerCase());
  }

  Stream<List<FormTaskModel>> watchFormTasks(String cohortId) async* {
    final list = _formTasks.where((t) => t.published).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    yield list;
  }

  Stream<List<FormTaskModel>> watchAllFormTasks(String cohortId) async* {
    yield List.from(_formTasks)
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  }

  Stream<FormTaskModel?> watchFormTask(String cohortId, String taskId) async* {
    try {
      yield _formTasks.firstWhere((t) => t.id == taskId);
    } catch (_) {
      yield null;
    }
  }

  Stream<List<FormResponseModel>> watchFormTaskResponses(
    String cohortId,
    String taskId,
  ) async* {
    yield List.from(_formResponses[taskId] ?? []);
  }

  Stream<List<FormResponseModel>> watchMyFormResponses(
    String cohortId,
    String userId,
  ) async* {
    final all = _formResponses.values.expand((list) => list);
    yield all
        .where((r) => r.cohortId == cohortId && r.userId == userId)
        .toList();
  }

  Stream<List<FormTaskWithStatus>> watchFormTasksWithStatus(
    String cohortId,
    String userId,
  ) async* {
    final tasks = _formTasks.where((t) => t.published).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    yield tasks.map((task) {
      FormResponseModel? response;
      for (final r in _formResponses[task.id] ?? const []) {
        if (r.userId == userId) {
          response = r;
          break;
        }
      }
      return FormTaskWithStatus(task: task, myResponse: response);
    }).toList();
  }

  Future<String> createFormTask({
    required String cohortId,
    required FormTaskModel task,
    required String authorId,
  }) async {
    final id = 'form${_formTasks.length + 1}';
    _formTasks.add(
      FormTaskModel(
        id: id,
        title: task.title,
        description: task.description,
        formUrl: task.formUrl,
        notionGuideUrl: task.notionGuideUrl,
        dueAt: task.dueAt,
        published: task.published,
        createdAt: DateTime.now(),
      ),
    );
    return id;
  }

  Future<void> updateFormTask({
    required String cohortId,
    required String taskId,
    required FormTaskModel task,
    required String authorId,
  }) async {
    final i = _formTasks.indexWhere((t) => t.id == taskId);
    if (i >= 0) {
      final prev = _formTasks[i];
      _formTasks[i] = FormTaskModel(
        id: taskId,
        title: task.title,
        description: task.description,
        formUrl: task.formUrl,
        notionGuideUrl: task.notionGuideUrl,
        dueAt: task.dueAt,
        published: task.published,
        responseCount: prev.responseCount,
        createdAt: prev.createdAt,
        updatedAt: DateTime.now(),
      );
    }
  }

  Future<void> deleteFormTask(String cohortId, String taskId) async {
    _formTasks.removeWhere((t) => t.id == taskId);
    _formResponses.remove(taskId);
  }
}

/// 싱글톤 — 앱 전체에서 동일 데이터 공유
DemoLmsRepository? _demoLmsInstance;
DemoLmsRepository get demoLmsRepository =>
    _demoLmsInstance ??= DemoLmsRepository();
