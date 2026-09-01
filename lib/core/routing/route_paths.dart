/// go_router 경로 상수
abstract final class RoutePaths {
  static const login = '/login';
  static const changePassword = '/change-password';

  // Shell 하위 경로
  static const dashboard = '/';
  static const resume = '/resume';
  static const studyRoom = '/study-room';
  static const board = '/board';
  static const records = '/records';
  static const recordsCreate = '/records/create';
  static const recordsCreateCert = '/records/create/certification';
  static const recordsCreateStudy = '/records/create/study';
  static const recordsCreateBlog = '/records/create/blog';
  static const mileage = '/mileage';
  static const myPage = '/my-page';
  static const forms = '/forms';
  static const qualExams = '/qual-exams';
  static const resumeEdit = '/resume/:resumeId/edit';

  // Admin Shell
  static const admin = '/admin';
  static const adminRecords = '/admin/records';
  static const adminResumes = '/admin/resumes';
  static const adminBoard = '/admin/board';
  static const adminStudyRoom = '/admin/study-room';
  static const adminMyPage = '/admin/my-page';
  static const adminStudyRoomCreate = '/admin/study-room/create';
  static const adminStudents = '/admin/students';
  static const adminStudentsCreate = '/admin/students/create';
  static const adminCohorts = '/admin/cohorts';
  static const adminCohortsCreate = '/admin/cohorts/create';
  static const adminFormTasks = '/admin/form-tasks';
  static const adminFormTasksCreate = '/admin/form-tasks/create';
  static const adminSeating = '/admin/seating';

  static String adminStudentDetailPath(String uid) => '/admin/students/$uid';
  static String adminStudentEditPath(String uid) => '/admin/students/$uid/edit';
  static String adminFormTaskDetailPath(String taskId) =>
      '/admin/form-tasks/$taskId';
  static String adminFormTaskEditPath(String taskId) =>
      '/admin/form-tasks/$taskId/edit';
  static String adminCohortEditPath(String cohortId) =>
      '/admin/cohorts/$cohortId/edit';

  static String resumeEditPath(
    String resumeId, {
    String? section,
    String? cohortId,
  }) {
    final path = '/resume/$resumeId/edit';
    final params = <String, String>{};
    if (section != null && section.isNotEmpty) params['section'] = section;
    if (cohortId != null && cohortId.isNotEmpty) params['cohortId'] = cohortId;
    if (params.isEmpty) return path;
    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    return '$path?$query';
  }

  static String adminStudyRoomPackagePath(String packageId) =>
      '/admin/study-room/$packageId';
  static const attendance = '/attendance';
  static const seating = '/seating';
}
