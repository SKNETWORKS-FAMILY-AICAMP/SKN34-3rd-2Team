import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../core/constants/firestore_paths.dart';
import '../../core/errors/app_exception.dart';
import '../models/assessment_model.dart';
import '../models/inflearn_package_model.dart';
import '../models/cohort_model.dart';
import '../models/domain_models.dart';
import '../models/notice_model.dart';
import '../models/scheduled_notice_model.dart';
import '../models/form_task_model.dart';
import '../models/post_model.dart';
import '../models/resume_content.dart';
import '../models/resume_model.dart';
import '../models/submission_model.dart';
import '../models/todo_model.dart';
import '../models/user_model.dart';
import '../models/job_preferences.dart';

/// Firestore CRUD 통합 Repository — cohort 격리 쿼리 중앙화
class LmsRepository {
  LmsRepository(this._firestore);

  final FirebaseFirestore _firestore;

  /// cohorts/{cohortId}/{subcollection} 참조
  CollectionReference<Map<String, dynamic>> cohortSub(
    String cohortId,
    String subcollection,
  ) {
    return _firestore
        .collection('cohorts')
        .doc(cohortId)
        .collection(subcollection);
  }

  // ── TODO (users/{uid}/todos) ──

  Stream<List<TodoModel>> watchTodos(String uid) {
    return _firestore
        .collection(FirestorePaths.users)
        .doc(uid)
        .collection('todos')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(TodoModel.fromFirestore).toList());
  }

  Future<void> addTodo(String uid, String title) async {
    await _firestore
        .collection(FirestorePaths.users)
        .doc(uid)
        .collection('todos')
        .add(TodoModel(id: '', title: title, isCompleted: false).toFirestore());
  }

  Future<void> toggleTodo(String uid, TodoModel todo) async {
    await _firestore
        .collection(FirestorePaths.users)
        .doc(uid)
        .collection('todos')
        .doc(todo.id)
        .update({'isCompleted': !todo.isCompleted});
  }

  Future<void> deleteTodo(String uid, String todoId) async {
    await _firestore
        .collection(FirestorePaths.users)
        .doc(uid)
        .collection('todos')
        .doc(todoId)
        .delete();
  }

  // ── Posts ──

  Stream<List<PostModel>> watchPosts(String cohortId, {int limit = 20}) {
    return cohortSub(cohortId, 'posts')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(PostModel.fromFirestore).toList());
  }

  Future<void> createPost({
    required String cohortId,
    required String authorId,
    required String authorName,
    required String content,
  }) async {
    await cohortSub(cohortId, 'posts').add(
      PostModel(
        id: '',
        authorId: authorId,
        authorName: authorName,
        content: content,
      ).toFirestore(),
    );
  }

  Future<void> deletePost(String cohortId, String postId) async {
    await cohortSub(cohortId, 'posts').doc(postId).delete();
  }

  // ── Notices ──

  Stream<List<NoticeModel>> watchNotices(String cohortId) {
    return cohortSub(cohortId, 'notices')
        .orderBy('isFavorite', descending: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(NoticeModel.fromFirestore).toList());
  }

  Future<String> createNotice({
    required String cohortId,
    required NoticeModel notice,
    required String authorId,
    required String authorName,
  }) async {
    final ref = await cohortSub(cohortId, 'notices').add(
      notice.toFirestore(authorId: authorId, authorName: authorName),
    );
    return ref.id;
  }

  Future<void> updateNotice({
    required String cohortId,
    required NoticeModel notice,
    required String authorId,
    required String authorName,
  }) async {
    await cohortSub(cohortId, 'notices').doc(notice.id).update(
          notice.toFirestoreUpdate(
            authorId: authorId,
            authorName: authorName,
          ),
        );
  }

  Future<void> toggleNoticeFavorite({
    required String cohortId,
    required String noticeId,
    required bool isFavorite,
  }) async {
    await cohortSub(cohortId, 'notices').doc(noticeId).update({
      'isFavorite': isFavorite,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteNotice(String cohortId, String noticeId) async {
    await cohortSub(cohortId, 'notices').doc(noticeId).delete();
  }

  Stream<List<ScheduledNoticeModel>> watchScheduledNotices(String cohortId) {
    return cohortSub(cohortId, 'scheduledNotices')
        .orderBy('isActive', descending: true)
        .orderBy('nextPublishAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map(ScheduledNoticeModel.fromFirestore).toList());
  }

  Future<String> createScheduledNotice({
    required String cohortId,
    required ScheduledNoticeModel scheduled,
    required String authorId,
    required String authorName,
  }) async {
    final nextAt = computeNextPublishAt(
      repeatType: scheduled.repeatType,
      publishTime: scheduled.publishTime,
      publishAt: scheduled.publishAt,
      weekday: scheduled.weekday,
    );
    final ref = await cohortSub(cohortId, 'scheduledNotices').add(
      scheduled.toFirestore(
        authorId: authorId,
        authorName: authorName,
        nextPublishAt: nextAt,
        isCreate: true,
      ),
    );
    return ref.id;
  }

  Future<void> updateScheduledNotice({
    required String cohortId,
    required ScheduledNoticeModel scheduled,
    required String authorId,
    required String authorName,
  }) async {
    final nextAt = computeNextPublishAt(
      repeatType: scheduled.repeatType,
      publishTime: scheduled.publishTime,
      publishAt: scheduled.publishAt,
      weekday: scheduled.weekday,
    );
    await cohortSub(cohortId, 'scheduledNotices').doc(scheduled.id).update(
          scheduled.toFirestoreUpdate(
            authorId: authorId,
            authorName: authorName,
            nextPublishAt: nextAt,
          ),
        );
  }

  Future<void> toggleScheduledNoticeActive({
    required String cohortId,
    required String scheduledId,
    required bool isActive,
  }) async {
    await cohortSub(cohortId, 'scheduledNotices').doc(scheduledId).update({
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteScheduledNotice(String cohortId, String scheduledId) async {
    await cohortSub(cohortId, 'scheduledNotices').doc(scheduledId).delete();
  }

  // ── Submissions ──

  Stream<List<SubmissionModel>> watchMySubmissions(
    String cohortId,
    String userId,
  ) {
    return cohortSub(cohortId, 'submissions')
        .where('userId', isEqualTo: userId)
        .orderBy('submittedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(SubmissionModel.fromFirestore).toList());
  }

  Stream<List<SubmissionModel>> watchAllSubmissions(String cohortId) {
    return cohortSub(cohortId, 'submissions')
        .orderBy('submittedAt', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map(SubmissionModel.fromFirestore).toList());
  }

  Future<String> createSubmission({
    required String cohortId,
    required SubmissionModel submission,
  }) async {
    final ref = submission.id.isNotEmpty
        ? cohortSub(cohortId, 'submissions').doc(submission.id)
        : cohortSub(cohortId, 'submissions').doc();
    await ref.set(submission.toFirestore());
    return ref.id;
  }

  Future<void> reviewSubmission({
    required String cohortId,
    required String submissionId,
    required String status,
    String? reviewComment,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('reviewSubmission');
      await callable.call<Map<String, dynamic>>({
        'cohortId': cohortId,
        'submissionId': submissionId,
        'status': status,
        if (reviewComment != null && reviewComment.isNotEmpty)
          'comment': reviewComment,
      });
    } on FirebaseFunctionsException catch (e) {
      throw DataException(
        e.message ?? '제출물 검토에 실패했습니다.',
        code: e.code,
      );
    }
  }

  // ── Weekly Tasks & Progress ──

  Stream<WeeklyTaskModel?> watchCurrentWeeklyTask(String cohortId) {
    return cohortSub(cohortId, 'weeklyTasks')
        .orderBy('dueDate', descending: false)
        .limit(1)
        .snapshots()
        .map((s) => s.docs.isEmpty
            ? null
            : WeeklyTaskModel.fromFirestore(s.docs.first));
  }

  Stream<UserProgressModel?> watchUserProgress(String cohortId, String userId) {
    return cohortSub(cohortId, 'userProgress')
        .doc(userId)
        .snapshots()
        .map((doc) =>
            doc.exists ? UserProgressModel.fromFirestore(doc) : null);
  }

  // ── Cohort ──

  Stream<List<CohortModel>> watchCohorts() {
    return watchAllCohorts().map(
      (list) => list.where((c) => c.isSelectable).toList(),
    );
  }

  Stream<List<CohortModel>> watchAllCohorts() {
    return _firestore.collection('cohorts').snapshots().map((snap) {
      final list = snap.docs.map(CohortModel.fromFirestore).toList();
      list.sort((a, b) {
        final ta = a.termNumber ?? 0;
        final tb = b.termNumber ?? 0;
        if (ta != tb) return tb.compareTo(ta);
        return a.name.compareTo(b.name);
      });
      return list;
    });
  }

  Future<String> createCohort(CohortModel cohort) async {
    final id = cohort.cohortId.isNotEmpty
        ? cohort.cohortId
        : (cohort.termNumber != null
            ? 'cohort_${cohort.termNumber}'
            : _firestore.collection('cohorts').doc().id);
    final data = cohort.toFirestore(isCreate: true);
    await _firestore.collection('cohorts').doc(id).set(data);
    return id;
  }

  Future<void> updateCohort(CohortModel cohort) async {
    await _firestore.collection('cohorts').doc(cohort.cohortId).update(
          cohort.toFirestore(),
        );
  }

  Stream<List<CohortWithResumes>> watchAllCohortsWithResumes() {
    return _firestore.collection('cohorts').orderBy('name').snapshots().asyncExpand(
      (cohortSnap) {
        final cohorts = cohortSnap.docs
            .map(CohortModel.fromFirestore)
            .where((c) => c.isSelectable)
            .toList();
        if (cohorts.isEmpty) return Stream.value(<CohortWithResumes>[]);
        return _mergeCohortResumeStreams(cohorts);
      },
    );
  }

  Stream<List<CohortWithResumes>> _mergeCohortResumeStreams(
    List<CohortModel> cohorts,
  ) {
    late StreamController<List<CohortWithResumes>> controller;
    final latest = List<List<ResumeModel>?>.filled(cohorts.length, null);
    final subscriptions = <StreamSubscription<dynamic>>[];

    void emitIfReady() {
      if (latest.any((e) => e == null)) return;
      if (controller.isClosed) return;
      controller.add([
        for (var i = 0; i < cohorts.length; i++)
          CohortWithResumes(cohort: cohorts[i], resumes: latest[i]!),
      ]);
    }

    controller = StreamController<List<CohortWithResumes>>(
      onListen: () {
        for (var i = 0; i < cohorts.length; i++) {
          final cohort = cohorts[i];
          subscriptions.add(
            cohortSub(cohort.cohortId, 'resumes').snapshots().listen((snap) {
              latest[i] = snap.docs.map(ResumeModel.fromFirestore).toList();
              emitIfReady();
            }),
          );
        }
      },
      onCancel: () async {
        for (final sub in subscriptions) {
          await sub.cancel();
        }
      },
    );
    return controller.stream;
  }

  // ── Resume ──

  Stream<List<ResumeModel>> watchMyResumes(String cohortId, String userId) {
    return cohortSub(cohortId, 'resumes')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((s) => s.docs.map(ResumeModel.fromFirestore).toList());
  }

  Stream<List<ResumeModel>> watchCohortResumes(String cohortId) {
    return cohortSub(cohortId, 'resumes')
        .snapshots()
        .map((s) => s.docs.map(ResumeModel.fromFirestore).toList());
  }

  Future<String> createResume({
    required String cohortId,
    required String userId,
    required String title,
  }) async {
    final doc = await cohortSub(cohortId, 'resumes').add({
      ...ResumeModel(
        id: '',
        userId: userId,
        title: title,
        status: 'writing',
        sections: const {},
      ).toFirestore(isCreate: true),
    });
    return doc.id;
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

  Stream<ResumeModel?> watchResume(String cohortId, String resumeId) {
    return cohortSub(cohortId, 'resumes')
        .doc(resumeId)
        .snapshots()
        .map((doc) => doc.exists ? ResumeModel.fromFirestore(doc) : null);
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
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (title != null) updates['title'] = title;
    if (content != null) {
      updates['content'] = content.toMap();
      updates['sections'] = content.computeSections();
    }
    if (sections != null) updates['sections'] = sections;
    if (status != null) updates['status'] = status;
    if (incrementRevision) {
      updates['revisionCount'] = FieldValue.increment(1);
    }

    final docRef = cohortSub(cohortId, 'resumes').doc(resumeId);
    await docRef.update(updates);

    if (incrementRevision && content != null) {
      await docRef.collection('revisions').add({
        'title': title,
        'content': content.toMap(),
        'savedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> approveResume({
    required String cohortId,
    required String resumeId,
  }) async {
    await cohortSub(cohortId, 'resumes').doc(resumeId).update({
      'status': 'approved',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteResume(String cohortId, String resumeId) async {
    await cohortSub(cohortId, 'resumes').doc(resumeId).delete();
  }

  Stream<List<ResumeFeedbackModel>> watchResumeFeedback(
    String cohortId,
    String resumeId,
  ) {
    return cohortSub(cohortId, 'resumes')
        .doc(resumeId)
        .collection('feedback')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(ResumeFeedbackModel.fromFirestore).toList());
  }

  Future<void> addResumeFeedback({
    required String cohortId,
    required String resumeId,
    required ResumeFeedbackModel feedback,
    required String authorId,
    required String authorName,
  }) async {
    final batch = _firestore.batch();
    final feedbackRef = cohortSub(cohortId, 'resumes')
        .doc(resumeId)
        .collection('feedback')
        .doc();
    batch.set(
      feedbackRef,
      feedback.toFirestore(authorId: authorId, authorName: authorName),
    );
    batch.update(cohortSub(cohortId, 'resumes').doc(resumeId), {
      'feedbackCount': FieldValue.increment(1),
    });
    await batch.commit();
  }

  Future<void> markResumeFeedbackSeen({
    required String cohortId,
    required String resumeId,
    required int feedbackCount,
  }) async {
    await cohortSub(cohortId, 'resumes').doc(resumeId).update({
      'lastSeenFeedbackCount': feedbackCount,
    });
  }

  // ── Attendance ──

  Stream<List<AttendanceModel>> watchUserAttendances(
    String cohortId,
    String userId,
  ) {
    return cohortSub(cohortId, 'attendances')
        .where('userId', isEqualTo: userId)
        .orderBy('dateKey', descending: true)
        .limit(400)
        .snapshots()
        .map((s) => s.docs.map(AttendanceModel.fromFirestore).toList());
  }

  Stream<List<AttendanceModel>> watchMyAttendances(
    String cohortId,
    String userId,
  ) =>
      watchUserAttendances(cohortId, userId);

  Future<void> upsertAttendanceStatus({
    required String cohortId,
    required String userId,
    required String userDisplayName,
    required String dateKey,
    required String status,
  }) async {
    final docId = '${userId}_$dateKey';
    await cohortSub(cohortId, 'attendances').doc(docId).set(
      {
        'userId': userId,
        'userDisplayName': userDisplayName,
        'dateKey': dateKey,
        'status': status,
        'type': 'status',
        'timestamp': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> clearAttendanceStatus({
    required String cohortId,
    required String userId,
    required String dateKey,
  }) async {
    final docId = '${userId}_$dateKey';
    await cohortSub(cohortId, 'attendances').doc(docId).delete();
  }

  Stream<List<UserModel>> watchCohortStudents(String cohortId) {
    return _firestore
        .collection(FirestorePaths.users)
        .where('cohortId', isEqualTo: cohortId)
        .where('role', isEqualTo: 'student')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((s) => s.docs.map(UserModel.fromFirestore).toList());
  }

  Future<void> recordAttendance({
    required String cohortId,
    required String userId,
    required String userDisplayName,
    required String type,
    required String dateKey,
  }) async {
    await cohortSub(cohortId, 'attendances').add(
      AttendanceModel(
        id: '',
        userId: userId,
        type: type,
        dateKey: dateKey,
      ).toFirestore(userDisplayName: userDisplayName),
    );
  }

  // ── Mileage ──

  Stream<List<MileageTransactionModel>> watchMyMileageTransactions(
    String cohortId,
    String userId,
  ) {
    return cohortSub(cohortId, 'mileageTransactions')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots()
        .map((s) => s.docs.map(MileageTransactionModel.fromFirestore).toList());
  }

  // ── Schedule ──

  Stream<ScheduleModel?> watchSchedule(String cohortId, String dateKey) {
    return cohortSub(cohortId, 'schedules')
        .doc(dateKey)
        .snapshots()
        .map((doc) => doc.exists ? ScheduleModel.fromFirestore(doc) : null);
  }

  Stream<List<String>> watchScheduleDateKeys(String cohortId) {
    return cohortSub(cohortId, 'schedules')
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toList());
  }

  // ── Materials ──

  Stream<List<MaterialModel>> watchMaterials(String cohortId) {
    return cohortSub(cohortId, 'materials')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(MaterialModel.fromFirestore).toList());
  }

  // ── Assignments ──

  Stream<List<AssignmentModel>> watchAssignments(String cohortId) {
    return cohortSub(cohortId, 'assignments')
        .orderBy('dueDate', descending: false)
        .snapshots()
        .map((s) => s.docs.map(AssignmentModel.fromFirestore).toList());
  }

  Future<void> submitAssignment({
    required String cohortId,
    required String assignmentId,
    required String userId,
    required String userDisplayName,
    required String fileUrl,
    required String fileName,
    required int fileSizeBytes,
  }) async {
    await cohortSub(cohortId, 'assignments')
        .doc(assignmentId)
        .collection('submissions')
        .doc(userId)
        .set({
          'userId': userId,
          'userDisplayName': userDisplayName,
          'fileUrl': fileUrl,
          'fileName': fileName,
          'fileSizeBytes': fileSizeBytes,
          'submittedAt': FieldValue.serverTimestamp(),
          'status': 'submitted',
        });
  }

  // ── Inflearn Packages (학습실) ──

  Stream<List<InflearnPackageModel>> watchInflearnPackages(String cohortId) {
    return cohortSub(cohortId, 'inflearnPackages')
        .orderBy('sortOrder')
        .snapshots()
        .map((s) => s.docs.map(InflearnPackageModel.fromFirestore).toList());
  }

  Stream<List<InflearnPackageModel>> watchPublishedInflearnPackages(
    String cohortId,
  ) {
    return watchInflearnPackages(cohortId).map(
      (list) => list.where((p) => p.isPublished).toList(),
    );
  }

  Future<String> createInflearnPackage({
    required String cohortId,
    required InflearnPackageModel package,
  }) async {
    final ref = cohortSub(cohortId, 'inflearnPackages').doc();
    await ref.set(package.toFirestore(isCreate: true));
    return ref.id;
  }

  Future<void> updateInflearnPackage({
    required String cohortId,
    required String packageId,
    required Map<String, dynamic> updates,
  }) async {
    final normalized = Map<String, dynamic>.from(updates);
    if (normalized['publishedAt'] is DateTime) {
      normalized['publishedAt'] =
          Timestamp.fromDate(normalized['publishedAt'] as DateTime);
    }
    await cohortSub(cohortId, 'inflearnPackages').doc(packageId).update({
      ...normalized,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteInflearnPackage({
    required String cohortId,
    required String packageId,
  }) async {
    await cohortSub(cohortId, 'inflearnPackages').doc(packageId).delete();
  }

  // ── Assessments (성취도 평가) — deprecated, 유지 중 ──

  Stream<List<AssessmentModel>> watchAssessments(String cohortId) {
    return cohortSub(cohortId, 'assessments')
        .orderBy('startAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(AssessmentModel.fromFirestore).toList());
  }

  Stream<List<AssessmentModel>> watchPublishedAssessments(String cohortId) {
    return cohortSub(cohortId, 'assessments')
        .where('published', isEqualTo: true)
        .orderBy('startAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(AssessmentModel.fromFirestore).toList());
  }

  Future<String> createAssessment({
    required String cohortId,
    required AssessmentModel assessment,
  }) async {
    final ref = cohortSub(cohortId, 'assessments').doc();
    await ref.set(assessment.toFirestore());
    return ref.id;
  }

  Future<void> updateAssessment({
    required String cohortId,
    required String assessmentId,
    required Map<String, dynamic> updates,
  }) async {
    final normalized = Map<String, dynamic>.from(updates);
    if (normalized['startAt'] is DateTime) {
      normalized['startAt'] =
          Timestamp.fromDate(normalized['startAt'] as DateTime);
    }
    if (normalized['endAt'] is DateTime) {
      normalized['endAt'] = Timestamp.fromDate(normalized['endAt'] as DateTime);
    }
    await cohortSub(cohortId, 'assessments').doc(assessmentId).update({
      ...normalized,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> publishAssessment({
    required String cohortId,
    required String assessmentId,
  }) async {
    await cohortSub(cohortId, 'assessments').doc(assessmentId).update({
      'published': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<AssessmentSubmissionModel>> watchMyAssessmentSubmissions(
    String cohortId,
    String userId,
  ) {
    return cohortSub(cohortId, 'assessmentSubmissions')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((s) => s.docs.map(AssessmentSubmissionModel.fromFirestore).toList());
  }

  Stream<List<AssessmentSubmissionModel>> watchAssessmentSubmissions(
    String cohortId,
    String assessmentId,
  ) {
    return cohortSub(cohortId, 'assessmentSubmissions')
        .where('assessmentId', isEqualTo: assessmentId)
        .snapshots()
        .map((s) => s.docs.map(AssessmentSubmissionModel.fromFirestore).toList());
  }

  Future<void> submitAssessmentAnswer({
    required String cohortId,
    required String assessmentId,
    required String userId,
    required String userDisplayName,
    required String answerFileUrl,
    required String answerFileName,
  }) async {
    await cohortSub(cohortId, 'assessmentSubmissions')
        .doc('${assessmentId}_$userId')
        .set({
          'assessmentId': assessmentId,
          'userId': userId,
          'userDisplayName': userDisplayName,
          'completed': true,
          'answerFileUrl': answerFileUrl,
          'answerFileName': answerFileName,
          'submittedAt': FieldValue.serverTimestamp(),
        });
  }

  // ── Form Tasks (Google Form) ──

  Stream<List<FormTaskModel>> watchFormTasks(String cohortId) {
    return cohortSub(cohortId, 'formTasks')
        .where('published', isEqualTo: true)
        .orderBy('dueAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map(FormTaskModel.fromFirestore).toList());
  }

  Stream<List<FormTaskModel>> watchAllFormTasks(String cohortId) {
    return cohortSub(cohortId, 'formTasks')
        .orderBy('dueAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map(FormTaskModel.fromFirestore).toList());
  }

  Stream<FormTaskModel?> watchFormTask(String cohortId, String taskId) {
    return cohortSub(cohortId, 'formTasks')
        .doc(taskId)
        .snapshots()
        .map((doc) => doc.exists ? FormTaskModel.fromFirestore(doc) : null);
  }

  Stream<List<FormResponseModel>> watchFormTaskResponses(
    String cohortId,
    String taskId,
  ) {
    return cohortSub(cohortId, 'formTasks')
        .doc(taskId)
        .collection('responses')
        .orderBy('submittedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(FormResponseModel.fromFirestore).toList());
  }

  Stream<List<FormResponseModel>> watchMyFormResponses(
    String cohortId,
    String userId,
  ) {
    return _firestore
        .collectionGroup('responses')
        .where('cohortId', isEqualTo: cohortId)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((s) => s.docs.map(FormResponseModel.fromFirestore).toList());
  }

  Stream<List<FormTaskWithStatus>> watchFormTasksWithStatus(
    String cohortId,
    String userId,
  ) {
    return watchFormTasks(cohortId).asyncMap((tasks) async {
      if (tasks.isEmpty) return <FormTaskWithStatus>[];
      final results = await Future.wait(
        tasks.map((task) async {
          final doc = await cohortSub(cohortId, 'formTasks')
              .doc(task.id)
              .collection('responses')
              .doc(userId)
              .get();
          return FormTaskWithStatus(
            task: task,
            myResponse: doc.exists
                ? FormResponseModel.fromFirestore(doc)
                : null,
          );
        }),
      );
      return results;
    });
  }

  Future<String> createFormTask({
    required String cohortId,
    required FormTaskModel task,
    required String authorId,
  }) async {
    final doc = await cohortSub(cohortId, 'formTasks').add(
      task.copyWith(responseCount: 0).toFirestore(
            authorId: authorId,
            isCreate: true,
          ),
    );
    return doc.id;
  }

  Future<void> updateFormTask({
    required String cohortId,
    required String taskId,
    required FormTaskModel task,
    required String authorId,
  }) async {
    await cohortSub(cohortId, 'formTasks').doc(taskId).update(
          task.toFirestore(authorId: authorId),
        );
  }

  Future<void> deleteFormTask(String cohortId, String taskId) async {
    final responses = await cohortSub(cohortId, 'formTasks')
        .doc(taskId)
        .collection('responses')
        .get();
    final batch = _firestore.batch();
    for (final doc in responses.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(cohortSub(cohortId, 'formTasks').doc(taskId));
    await batch.commit();
  }

  // ── User Profile ──

  Future<void> updateProfile({
    required String uid,
    String? motto,
    List<String>? skills,
    Map<String, String>? socialLinks,
    String? birthDate,
    String? personalEmail,
    JobPreferences? jobPreferences,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (jobPreferences != null) updates['jobPreferences'] = jobPreferences.toMap();
    if (motto != null) updates['motto'] = motto;
    if (skills != null) updates['skills'] = skills;
    if (socialLinks != null) updates['socialLinks'] = socialLinks;
    if (birthDate != null) updates['birthDate'] = birthDate;
    if (personalEmail != null) {
      updates['personalEmail'] = personalEmail.trim().toLowerCase();
    }
    await _firestore.collection(FirestorePaths.users).doc(uid).update(updates);
  }

  Future<void> updatePersonalEmail({
    required String uid,
    required String personalEmail,
  }) async {
    final normalized = personalEmail.trim().toLowerCase();
    if (normalized.isEmpty) {
      throw const DataException('개인 이메일을 입력해 주세요.');
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,}$');
    if (!emailRegex.hasMatch(normalized)) {
      throw const DataException('올바른 이메일 형식이 아닙니다.');
    }

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('updatePersonalEmail');
      await callable.call<Map<String, dynamic>>({
        'personalEmail': normalized,
      });
    } on FirebaseFunctionsException catch (e) {
      throw DataException(
        e.message ?? '개인 이메일 저장에 실패했습니다.',
        code: e.code,
      );
    }
  }
}
