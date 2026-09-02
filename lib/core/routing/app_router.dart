import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/curriculum/presentation/admin_curriculum_day_form_screen.dart';
import '../../features/curriculum/presentation/admin_curriculum_screen.dart';
import '../../features/curriculum/presentation/admin_curriculum_week_form_screen.dart';
import '../../features/curriculum/presentation/curriculum_day_screen.dart';
import '../../features/curriculum/presentation/curriculum_screen.dart';
import '../../features/curriculum/presentation/curriculum_week_screen.dart';
import '../../features/admin/presentation/admin_cohort_form_screen.dart';
import '../../features/admin/presentation/admin_cohorts_screen.dart';
import '../../features/admin/presentation/admin_inflearn_package_form_screen.dart';
import '../../features/admin/presentation/admin_form_tasks_screen.dart';
import '../../features/admin/presentation/admin_dashboard_screen.dart';
import '../../features/admin/presentation/admin_board_screen.dart';
import '../../features/admin/presentation/admin_notice_form_screen.dart';
import '../../features/admin/presentation/admin_scheduled_notice_form_screen.dart';
import '../../features/admin/presentation/admin_student_create_screen.dart';
import '../../features/admin/presentation/admin_student_detail_screen.dart';
import '../../features/admin/presentation/admin_student_edit_screen.dart';
import '../../features/admin/presentation/admin_students_screen.dart';
import '../../features/admin/presentation/admin_study_room_screen.dart';
import '../../features/admin/presentation/admin_mileage_hub_screen.dart';
import '../../features/admin/presentation/admin_mileage_products_screen.dart';
import '../../features/admin/presentation/admin_mileage_product_form_screen.dart';
import '../../features/admin/presentation/admin_mileage_settings_screen.dart';
import '../../features/admin/presentation/admin_purchase_requests_screen.dart';
import '../../features/admin/presentation/admin_mileage_adjust_screen.dart';
import '../../features/admin/shell/admin_shell_screen.dart';
import '../../features/auth/presentation/change_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/dashboard/presentation/qual_exam_schedules_screen.dart';
import '../../features/forms/presentation/form_tasks_screen.dart';
import '../../features/hub/presentation/board_screen.dart';
import '../../features/mileage/presentation/mileage_screen.dart';
import '../../features/mileage/presentation/mileage_shop_screen.dart';
import '../../features/mileage/presentation/mileage_cart_screen.dart';
import '../../features/my_page/presentation/my_page_screen.dart';
import '../../features/records/presentation/record_blog_form_screen.dart';
import '../../features/records/presentation/record_cert_form_screen.dart';
import '../../features/records/presentation/record_study_form_screen.dart';
import '../../features/records/presentation/record_type_select_screen.dart';
import '../../features/records/presentation/records_screen.dart';
import '../../features/resume/presentation/resume_edit_screen.dart';
import '../../features/resume/presentation/resume_screen.dart';
import '../../features/seating/presentation/admin_seating_screen.dart';
import '../../features/seating/presentation/seating_screen.dart';
import '../../features/shell/main_shell_screen.dart';
import '../../features/study_room/presentation/study_room_screen.dart';
import 'route_paths.dart';

/// Auth 상태 변화 시 go_router redirect 재실행용
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(this._ref) {
    _ref.listen(sessionUidProvider, (_, _) => notifyListeners());
    _ref.listen(currentUserProvider, (_, _) => notifyListeners());
  }

  final Ref _ref;
}

bool _isAdminRoute(String location) => location.startsWith('/admin');

String? _adminRedirectForStudentRoute(String location) {
  return switch (location) {
    RoutePaths.dashboard => RoutePaths.admin,
    RoutePaths.records || RoutePaths.recordsCreate ||
    RoutePaths.recordsCreateCert || RoutePaths.recordsCreateStudy ||
    RoutePaths.recordsCreateBlog =>
      RoutePaths.adminRecords,
    RoutePaths.resume => RoutePaths.adminResumes,
    RoutePaths.board => RoutePaths.adminBoard,
    RoutePaths.studyRoom => RoutePaths.adminStudyRoom,
    RoutePaths.curriculum => RoutePaths.adminCurriculum,
    RoutePaths.forms => RoutePaths.adminFormTasks,
    RoutePaths.seating => RoutePaths.adminSeating,
    RoutePaths.myPage => RoutePaths.adminMyPage,
    RoutePaths.mileage => RoutePaths.adminMileage,
    RoutePaths.adminStudents => RoutePaths.adminStudents,
    RoutePaths.adminFormTasks => RoutePaths.adminFormTasks,
    _ => null,
  };
}

/// go_router Provider — authState + role 기반 redirect
final appRouterProvider = Provider<GoRouter>((ref) {
  final sessionUid = ref.watch(sessionUidProvider);
  final currentUser = ref.watch(currentUserProvider);
  final refresh = _RouterRefresh(ref);

  return GoRouter(
    initialLocation: RoutePaths.dashboard,
    debugLogDiagnostics: true,
    refreshListenable: refresh,
    redirect: (context, state) {
      final isLoggedIn = sessionUid.value != null;
      final isLoggingIn = state.matchedLocation == RoutePaths.login;
      final isChangingPassword =
          state.matchedLocation == RoutePaths.changePassword;
      final location = state.matchedLocation;
      final isAdminRoute = _isAdminRoute(location);
      final isResumeEdit = location.startsWith('/resume/') &&
          location.endsWith('/edit');

      if (sessionUid.isLoading) return null;

      if (!isLoggedIn) {
        return isLoggingIn ? null : RoutePaths.login;
      }

      if (isLoggingIn) {
        final user = currentUser.value;
        if (user != null && user.mustChangePassword) {
          return RoutePaths.changePassword;
        }
        return user?.isAdmin == true ? RoutePaths.admin : RoutePaths.dashboard;
      }

      final user = currentUser.value;
      if (user != null && user.mustChangePassword && !isChangingPassword) {
        return RoutePaths.changePassword;
      }

      if (user != null && !user.mustChangePassword && isChangingPassword) {
        return user.isAdmin ? RoutePaths.admin : RoutePaths.dashboard;
      }

      if (currentUser.isLoading) return null;

      if (user != null) {
        if (user.isAdmin) {
          if (!isAdminRoute && !isChangingPassword && !isResumeEdit) {
            final adminPath = _adminRedirectForStudentRoute(location);
            if (adminPath != null) return adminPath;
          }
        } else if (isAdminRoute) {
          return RoutePaths.dashboard;
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: RoutePaths.login,
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: RoutePaths.changePassword,
        builder: (_, _) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: '/resume/:resumeId/edit',
        pageBuilder: (_, state) => NoTransitionPage(
          child: ResumeEditScreen(
            resumeId: state.pathParameters['resumeId']!,
            initialSection: state.uri.queryParameters['section'],
            cohortId: state.uri.queryParameters['cohortId'],
          ),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShellScreen(child: child),
        routes: [
          GoRoute(
            path: RoutePaths.dashboard,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: DashboardScreen(),
            ),
          ),
          GoRoute(
            path: RoutePaths.resume,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: ResumeScreen(),
            ),
          ),
          GoRoute(
            path: RoutePaths.studyRoom,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: StudyRoomScreen(),
            ),
          ),
          GoRoute(
            path: RoutePaths.curriculum,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: CurriculumScreen(),
            ),
            routes: [
              GoRoute(
                path: 'day/:dayId',
                pageBuilder: (_, state) => NoTransitionPage(
                  child: CurriculumDayScreen(
                    dayId: state.pathParameters['dayId']!,
                  ),
                ),
              ),
              GoRoute(
                path: 'week/:weekId',
                pageBuilder: (_, state) => NoTransitionPage(
                  child: CurriculumWeekScreen(
                    weekId: state.pathParameters['weekId']!,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: RoutePaths.board,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: BoardScreen(),
            ),
          ),
          GoRoute(
            path: RoutePaths.records,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: RecordsScreen(),
            ),
          ),
          GoRoute(
            path: RoutePaths.recordsCreate,
            builder: (_, _) => const RecordTypeSelectScreen(),
          ),
          GoRoute(
            path: RoutePaths.recordsCreateCert,
            builder: (_, _) => const RecordCertFormScreen(),
          ),
          GoRoute(
            path: RoutePaths.recordsCreateStudy,
            builder: (_, _) => const RecordStudyFormScreen(),
          ),
          GoRoute(
            path: RoutePaths.recordsCreateBlog,
            builder: (_, _) => const RecordBlogFormScreen(),
          ),
          GoRoute(
            path: RoutePaths.mileage,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: MileageScreen(),
            ),
            routes: [
              GoRoute(
                path: 'shop',
                builder: (_, _) => const MileageShopScreen(),
                routes: [
                  GoRoute(
                    path: 'cart',
                    builder: (_, _) => const MileageCartScreen(),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: RoutePaths.forms,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: FormTasksScreen(),
            ),
          ),
          GoRoute(
            path: RoutePaths.qualExams,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: QualExamSchedulesScreen(),
            ),
          ),
          GoRoute(
            path: RoutePaths.seating,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: SeatingScreen(),
            ),
          ),
          GoRoute(
            path: RoutePaths.myPage,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: MyPageScreen(),
            ),
          ),
        ],
      ),
      ShellRoute(
        builder: (context, state, child) => AdminShellScreen(child: child),
        routes: [
          GoRoute(
            path: RoutePaths.admin,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: AdminDashboardScreen(),
            ),
          ),
          GoRoute(
            path: RoutePaths.adminRecords,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: RecordsScreen(),
            ),
          ),
          GoRoute(
            path: RoutePaths.adminResumes,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: ResumeScreen(),
            ),
          ),
          GoRoute(
            path: RoutePaths.adminBoard,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: AdminBoardScreen(),
            ),
            routes: [
              GoRoute(
                path: 'create',
                builder: (_, _) => const AdminNoticeFormScreen(),
              ),
              GoRoute(
                path: 'scheduled/create',
                builder: (_, _) => const AdminScheduledNoticeFormScreen(),
              ),
              GoRoute(
                path: 'scheduled/:scheduledId/edit',
                builder: (_, state) => AdminScheduledNoticeFormScreen(
                  scheduledId: state.pathParameters['scheduledId'],
                ),
              ),
              GoRoute(
                path: ':noticeId/edit',
                builder: (_, state) => AdminNoticeFormScreen(
                  noticeId: state.pathParameters['noticeId'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: RoutePaths.adminStudyRoom,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: AdminStudyRoomScreen(),
            ),
            routes: [
              GoRoute(
                path: 'create',
                builder: (_, _) => const AdminInflearnPackageFormScreen(),
              ),
              GoRoute(
                path: ':packageId',
                builder: (_, state) => AdminInflearnPackageFormScreen(
                  packageId: state.pathParameters['packageId'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: RoutePaths.adminStudents,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: AdminStudentsScreen(),
            ),
            routes: [
              GoRoute(
                path: 'create',
                builder: (_, _) => const AdminStudentCreateScreen(),
              ),
              GoRoute(
                path: ':studentUid',
                builder: (_, state) => AdminStudentDetailScreen(
                  studentUid: state.pathParameters['studentUid']!,
                ),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (_, state) => AdminStudentEditScreen(
                      studentUid: state.pathParameters['studentUid']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: RoutePaths.adminCohorts,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: AdminCohortsScreen(),
            ),
            routes: [
              GoRoute(
                path: 'create',
                builder: (_, _) => const AdminCohortFormScreen(),
              ),
              GoRoute(
                path: ':cohortId/edit',
                builder: (_, state) => AdminCohortFormScreen(
                  cohortId: state.pathParameters['cohortId'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: RoutePaths.adminFormTasks,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: AdminFormTasksScreen(),
            ),
            routes: [
              GoRoute(
                path: 'create',
                builder: (_, _) => const AdminFormTaskFormScreen(),
              ),
              GoRoute(
                path: ':taskId',
                builder: (_, state) => AdminFormTaskDetailScreen(
                  taskId: state.pathParameters['taskId']!,
                ),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (_, state) => AdminFormTaskFormScreen(
                      taskId: state.pathParameters['taskId'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: RoutePaths.adminSeating,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: AdminSeatingScreen(),
            ),
          ),
          GoRoute(
            path: RoutePaths.adminCurriculum,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: AdminCurriculumScreen(),
            ),
            routes: [
              GoRoute(
                path: 'day/:dayId/edit',
                builder: (_, state) => AdminCurriculumDayFormScreen(
                  dayId: state.pathParameters['dayId']!,
                ),
              ),
              GoRoute(
                path: 'week/:weekId/edit',
                builder: (_, state) => AdminCurriculumWeekFormScreen(
                  weekId: state.pathParameters['weekId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: RoutePaths.adminMyPage,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: MyPageScreen(),
            ),
          ),
          GoRoute(
            path: RoutePaths.adminMileage,
            pageBuilder: (_, _) => const NoTransitionPage(
              child: AdminMileageHubScreen(),
            ),
            routes: [
              GoRoute(
                path: 'products',
                pageBuilder: (_, _) => const NoTransitionPage(
                  child: AdminMileageProductsScreen(),
                ),
                routes: [
                  GoRoute(
                    path: 'create',
                    builder: (_, _) => const AdminMileageProductFormScreen(),
                  ),
                  GoRoute(
                    path: ':productId/edit',
                    builder: (_, state) => AdminMileageProductFormScreen(
                      productId: state.pathParameters['productId'],
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'requests',
                pageBuilder: (_, _) => const NoTransitionPage(
                  child: AdminPurchaseRequestsScreen(),
                ),
              ),
              GoRoute(
                path: 'adjust',
                pageBuilder: (_, _) => const NoTransitionPage(
                  child: AdminMileageAdjustScreen(),
                ),
              ),
              GoRoute(
                path: 'settings',
                pageBuilder: (_, _) => const NoTransitionPage(
                  child: AdminMileageSettingsScreen(),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
