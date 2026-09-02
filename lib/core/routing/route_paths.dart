/// go_router 경로 상수
abstract final class RoutePaths {
  static const login = '/login';
  static const changePassword = '/change-password';

  // Shell 하위 경로
  static const dashboard = '/';
  static const resume = '/resume';
  static const studyRoom = '/study-room';
  static const curriculum = '/curriculum';
  static const board = '/board';
  static const records = '/records';
  static const recordsCreate = '/records/create';
  static const recordsCreateCert = '/records/create/certification';
  static const recordsCreateStudy = '/records/create/study';
  static const recordsCreateBlog = '/records/create/blog';
  static const mileage = '/mileage';
  static const mileageShop = '/mileage/shop';
  static const mileageCart = '/mileage/shop/cart';
  static const myPage = '/my-page';
  static const forms = '/forms';
  static const qualExams = '/qual-exams';
  static const resumeEdit = '/resume/:resumeId/edit';

  // Admin Shell
  static const admin = '/admin';
  static const adminRecords = '/admin/records';
  static const adminResumes = '/admin/resumes';
  static const adminBoard = '/admin/board';
  static const adminBoardNoticeCreate = '/admin/board/create';
  static const adminBoardScheduledCreate = '/admin/board/scheduled/create';
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
  static const adminCurriculum = '/admin/curriculum';
  static const adminMileage = '/admin/mileage';
  static const adminMileageProducts = '/admin/mileage/products';
  static const adminMileageProductsCreate = '/admin/mileage/products/create';
  static const adminMileageRequests = '/admin/mileage/requests';
  static const adminMileageAdjust = '/admin/mileage/adjust';
  static const adminMileageSettings = '/admin/mileage/settings';

  static String adminMileageProductEditPath(String productId) =>
      '/admin/mileage/products/$productId/edit';

  static String curriculumDayPath(String dayId) => '/curriculum/day/$dayId';
  static String adminCurriculumDayEditPath(String dayId) =>
      '/admin/curriculum/day/$dayId/edit';

  static String curriculumWeekPath(String weekId) => '/curriculum/week/$weekId';
  static String adminCurriculumWeekEditPath(String weekId) =>
      '/admin/curriculum/week/$weekId/edit';

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

  static String adminBoardNoticeEditPath(String noticeId) =>
      '/admin/board/$noticeId/edit';
  static String adminBoardScheduledEditPath(String scheduledId) =>
      '/admin/board/scheduled/$scheduledId/edit';

  static String adminStudyRoomPackagePath(String packageId) =>
      '/admin/study-room/$packageId';
  static const attendance = '/attendance';
  static const seating = '/seating';
}
