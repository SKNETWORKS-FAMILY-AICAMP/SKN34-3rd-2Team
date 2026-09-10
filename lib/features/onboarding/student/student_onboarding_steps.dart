import '../../../core/routing/route_paths.dart';
import '../domain/onboarding_step.dart';
import 'student_onboarding_keys.dart';

abstract final class StudentOnboarding {
  static const tourId = 'student';
  static const version = 1;

  /// 약 13스텝: 네비 10 + CTA 3
  static const steps = <OnboardingStep>[
    OnboardingStep(
      id: 'nav_dashboard',
      title: '대시보드',
      body: '출석·공지·학습 현황을 한곳에서 확인합니다.',
      targetId: StudentOnboardingTargets.navDashboard,
      route: RoutePaths.dashboard,
    ),
    OnboardingStep(
      id: 'dashboard_calendar',
      title: '출석 캘린더',
      body: '이번 달 출석 상태를 캘린더에서 확인할 수 있습니다.',
      targetId: StudentOnboardingTargets.dashboardCalendar,
      route: RoutePaths.dashboard,
      skippableIfMissing: true,
    ),
    OnboardingStep(
      id: 'attendance_form',
      title: '출결 폼',
      body: '지각·조퇴·결석 등 예외 출결은 출결 폼으로 제출합니다.',
      targetId: StudentOnboardingTargets.attendanceForm,
      route: RoutePaths.dashboard,
    ),
    OnboardingStep(
      id: 'nav_resume',
      title: '이력서 관리',
      body: '이력서를 작성하고 피드백을 받는 메뉴입니다.',
      targetId: StudentOnboardingTargets.navResume,
      route: RoutePaths.resume,
    ),
    OnboardingStep(
      id: 'nav_study',
      title: '학습실',
      body: '주간 학습 자료와 과제를 확인합니다.',
      targetId: StudentOnboardingTargets.navStudyRoom,
      route: RoutePaths.studyRoom,
    ),
    OnboardingStep(
      id: 'nav_board',
      title: '게시판',
      body: '공지사항과 소통 피드를 확인합니다.',
      targetId: StudentOnboardingTargets.navBoard,
      route: RoutePaths.board,
    ),
    OnboardingStep(
      id: 'board_notices',
      title: '공지 목록',
      body: '중요 공지와 전체 공지를 여기서 확인하세요.',
      targetId: StudentOnboardingTargets.boardNotices,
      route: RoutePaths.board,
      skippableIfMissing: true,
    ),
    OnboardingStep(
      id: 'nav_seating',
      title: '자리 배치',
      body: '오늘 내 좌석 위치를 확인합니다.',
      targetId: StudentOnboardingTargets.navSeating,
      route: RoutePaths.seating,
    ),
    OnboardingStep(
      id: 'nav_forms',
      title: '설문 · 제출',
      body: '설문·제출 과제를 확인하고 응답합니다.',
      targetId: StudentOnboardingTargets.navForms,
      route: RoutePaths.forms,
    ),
    OnboardingStep(
      id: 'nav_qual',
      title: '자격 시험 일정',
      body: '자격증·시험 일정을 확인합니다.',
      targetId: StudentOnboardingTargets.navQualExams,
      route: RoutePaths.qualExams,
    ),
    OnboardingStep(
      id: 'nav_records',
      title: '기록실',
      body: '출석·학습 기록을 모아 봅니다.',
      targetId: StudentOnboardingTargets.navRecords,
      route: RoutePaths.records,
    ),
    OnboardingStep(
      id: 'nav_mileage',
      title: '마일리지',
      body: '적립·사용 내역과 상품을 확인합니다.',
      targetId: StudentOnboardingTargets.navMileage,
      route: RoutePaths.mileage,
    ),
    OnboardingStep(
      id: 'nav_assessments',
      title: '성취도평가',
      body: '공개된 평가에 응시하고 결과를 확인합니다.',
      targetId: StudentOnboardingTargets.navAssessments,
      route: RoutePaths.assessments,
    ),
  ];
}
