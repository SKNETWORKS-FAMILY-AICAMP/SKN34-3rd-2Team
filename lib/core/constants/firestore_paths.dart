/// Firestore Collection / Document 경로 상수
/// 모든 Repository는 이 클래스의 경로만 사용하여 쿼리합니다.
abstract final class FirestorePaths {
  // ── 전역 ──
  static const users = 'users';
  static const studentIntakes = 'studentIntakes';

  // ── 기수 루트 ──
  static String cohort(String cohortId) => 'cohorts/$cohortId';

  // ── 기수 하위 Subcollection ──
  static String schedules(String cohortId) =>
      '${cohort(cohortId)}/schedules';
  static String seating(String cohortId) => '${cohort(cohortId)}/seating';
  static String attendances(String cohortId) =>
      '${cohort(cohortId)}/attendances';
  static String notices(String cohortId) => '${cohort(cohortId)}/notices';
  static String posts(String cohortId) => '${cohort(cohortId)}/posts';
  static String qna(String cohortId) => '${cohort(cohortId)}/qna';
  static String materials(String cohortId) => '${cohort(cohortId)}/materials';
  static String assignments(String cohortId) =>
      '${cohort(cohortId)}/assignments';
  static String resumes(String cohortId) => '${cohort(cohortId)}/resumes';
  static String mileageTransactions(String cohortId) =>
      '${cohort(cohortId)}/mileageTransactions';
  static String weeklyTasks(String cohortId) =>
      '${cohort(cohortId)}/weeklyTasks';
  static String userProgress(String cohortId) =>
      '${cohort(cohortId)}/userProgress';
  static String submissions(String cohortId) =>
      '${cohort(cohortId)}/submissions';
  static String assessments(String cohortId) =>
      '${cohort(cohortId)}/assessments';
  static String assessmentSubmissions(String cohortId) =>
      '${cohort(cohortId)}/assessmentSubmissions';
  static String inflearnPackages(String cohortId) =>
      '${cohort(cohortId)}/inflearnPackages';

  // ── 유저 하위 Subcollection ──
  static String userTodos(String uid) => 'users/$uid/todos';

  // ── 시스템 캐시 (국가자격 시험일정 등) ──
  static const systemCache = 'systemCache';
  static String qualExamSchedules(int year) =>
      '$systemCache/qualExamSchedules_$year';
}
