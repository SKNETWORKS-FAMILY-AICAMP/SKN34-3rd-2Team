import '../../../core/routing/route_paths.dart';
import '../domain/onboarding_step.dart';
import 'admin_onboarding_keys.dart';

abstract final class AdminOnboarding {
  static const tourId = 'admin';
  static const version = 1;

  /// 약 12스텝: 대표 네비 10 + CTA 2 (전체 메뉴는 돌리지 않음)
  static const steps = <OnboardingStep>[
    OnboardingStep(
      id: 'nav_dashboard',
      title: '대시보드',
      body: '기수 운영 현황을 한눈에 보는 관리자 홈입니다.',
      targetId: AdminOnboardingTargets.navDashboard,
      route: RoutePaths.admin,
    ),
    OnboardingStep(
      id: 'nav_cohorts',
      title: '기수 관리',
      body: '기수를 만들고 기간·설정을 관리합니다.',
      targetId: AdminOnboardingTargets.navCohorts,
      route: RoutePaths.adminCohorts,
    ),
    OnboardingStep(
      id: 'nav_students',
      title: '학생 관리',
      body: '학생 계정을 등록·조회·수정합니다.',
      targetId: AdminOnboardingTargets.navStudents,
      route: RoutePaths.adminStudents,
    ),
    OnboardingStep(
      id: 'nav_attendance',
      title: '출석 관리',
      body: '기수별 당일 출석을 조회·수정하고 폼 반영을 확인합니다.',
      targetId: AdminOnboardingTargets.navAttendance,
      route: RoutePaths.adminAttendance,
    ),
    OnboardingStep(
      id: 'attendance_daily',
      title: '출결 공지',
      body: '매일 08:30 출결 폼 공지를 여기서 등록할 수 있습니다.',
      targetId: AdminOnboardingTargets.attendanceDailyNotice,
      route: RoutePaths.adminAttendance,
      skippableIfMissing: true,
    ),
    OnboardingStep(
      id: 'nav_seating',
      title: '좌석 배치',
      body: '좌석 레이아웃을 만들고 배정·게시합니다.',
      targetId: AdminOnboardingTargets.navSeating,
      route: RoutePaths.adminSeating,
    ),
    OnboardingStep(
      id: 'nav_assessments',
      title: '성취도 평가',
      body: '평가 목록을 관리하고 발행 상태를 확인합니다.',
      targetId: AdminOnboardingTargets.navAssessments,
      route: RoutePaths.adminAssessments,
    ),
    OnboardingStep(
      id: 'nav_resumes',
      title: '이력서',
      body: '학생 이력서 제출·검토 현황을 봅니다.',
      targetId: AdminOnboardingTargets.navResumes,
      route: RoutePaths.adminResumes,
    ),
    OnboardingStep(
      id: 'nav_board',
      title: '게시판',
      body: '공지·예약 공지·알림 팝업을 관리합니다.',
      targetId: AdminOnboardingTargets.navBoard,
      route: RoutePaths.adminBoard,
    ),
    OnboardingStep(
      id: 'board_create',
      title: '공지 작성',
      body: '공지 작성으로 새 공지를 등록할 수 있습니다.',
      targetId: AdminOnboardingTargets.boardCreate,
      route: RoutePaths.adminBoard,
      skippableIfMissing: true,
    ),
    OnboardingStep(
      id: 'nav_mileage',
      title: '마일리지',
      body: '상품·요청·수동 조정 등 마일리지를 운영합니다.',
      targetId: AdminOnboardingTargets.navMileage,
      route: RoutePaths.adminMileage,
    ),
    OnboardingStep(
      id: 'nav_ai',
      title: 'AI 품질',
      body: 'AI 기능 품질·로그를 점검하는 시스템 메뉴입니다.',
      targetId: AdminOnboardingTargets.navAiQuality,
      route: RoutePaths.adminAiQuality,
    ),
  ];
}
