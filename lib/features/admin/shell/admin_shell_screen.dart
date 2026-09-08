import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/widgets/app_side_rail.dart';
import '../../../shared/widgets/profile_nav_chip.dart';
import '../../auth/providers/auth_providers.dart';
import '../../shell/widgets/app_shell_header.dart';

const _kAdminNavItems = [
  AppSideRailItem(
    icon: Icons.dashboard_rounded,
    label: '관리자 대시보드',
    path: RoutePaths.admin,
  ),
  AppSideRailItem(
    icon: Icons.calendar_month_rounded,
    label: '기수 관리',
    path: RoutePaths.adminCohorts,
  ),
  AppSideRailItem(
    icon: Icons.groups_rounded,
    label: '학생 관리',
    path: RoutePaths.adminStudents,
  ),
  AppSideRailItem(
    icon: Icons.fact_check_outlined,
    label: '출석관리',
    path: RoutePaths.adminAttendance,
  ),
  AppSideRailItem(
    icon: Icons.event_available_outlined,
    label: '자리 확인',
    path: RoutePaths.adminSeatPresence,
  ),
  AppSideRailItem(
    icon: Icons.badge_outlined,
    label: '강사 관리',
    path: RoutePaths.adminInstructors,
  ),
  AppSideRailItem(
    icon: Icons.event_seat_rounded,
    label: '좌석 배치',
    path: RoutePaths.adminSeating,
  ),
  AppSideRailItem(
    icon: Icons.ballot_outlined,
    label: '설문 · 제출',
    path: RoutePaths.adminFormTasks,
  ),
  AppSideRailItem(
    icon: Icons.history_rounded,
    label: '기록실 관리',
    path: RoutePaths.adminRecords,
  ),
  AppSideRailItem(
    icon: Icons.description_rounded,
    label: '이력서 관리',
    path: RoutePaths.adminResumes,
  ),
  AppSideRailItem(
    icon: Icons.forum_rounded,
    label: '게시판 관리',
    path: RoutePaths.adminBoard,
  ),
  AppSideRailItem(
    icon: Icons.menu_book_rounded,
    label: '학습실 관리',
    path: RoutePaths.adminStudyRoom,
  ),
  AppSideRailItem(
    icon: Icons.card_giftcard_rounded,
    label: '마일리지 관리',
    path: RoutePaths.adminMileage,
  ),
  AppSideRailItem(
    icon: Icons.quiz_outlined,
    label: '성취도평가',
    path: RoutePaths.adminAssessments,
  ),
  AppSideRailItem(
    icon: Icons.analytics_outlined,
    label: 'AI 품질',
    path: RoutePaths.adminAiQuality,
  ),
  AppSideRailItem(
    icon: Icons.person_rounded,
    label: '마이페이지',
    path: RoutePaths.adminMyPage,
  ),
];

bool _isAdminNavSelected(String location, String path) {
  if (path == RoutePaths.admin) return location == path;
  return location == path || location.startsWith(path);
}

/// 관리자 Shell — 와이드: 좌측 레일 / 좁음: Drawer
class AdminShellScreen extends ConsumerWidget {
  const AdminShellScreen({super.key, required this.child});

  final Widget child;

  static const _railBreakpoint = 900.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentUser = ref.watch(currentUserProvider);
    final user = currentUser.value;
    final wide = MediaQuery.sizeOf(context).width >= _railBreakpoint;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const AppShellHeader(homePath: RoutePaths.admin),
        automaticallyImplyLeading: !wide,
        actions: [
          if (user != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ProfileNavChip(
                  user: user,
                  style: ProfileNavChipStyle.appBar,
                  onTap: () => context.go(RoutePaths.adminMyPage),
                ),
              ),
            ),
        ],
      ),
      drawer: wide
          ? null
          : _AdminDrawer(user: user, currentLocation: location),
      body: Row(
        children: [
          if (wide)
            AppSideRail(
              items: _kAdminNavItems,
              location: location,
              isSelected: _isAdminNavSelected,
              onNavigate: (path) => context.go(path),
              onLogout: () => ref.read(authRepositoryProvider).signOut(),
              profile: user == null
                  ? null
                  : Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () => context.go(RoutePaths.adminMyPage),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.2),
                                child: Text(
                                  user.displayName.isNotEmpty
                                      ? user.displayName[0]
                                      : 'A',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  user.displayName.isNotEmpty
                                      ? user.displayName
                                      : '마이페이지',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _AdminDrawer extends ConsumerWidget {
  const _AdminDrawer({
    required this.currentLocation,
    this.user,
  });

  final UserModel? user;
  final String currentLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: user != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              '관리자',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ProfileNavChip(
                          user: user!,
                          style: ProfileNavChipStyle.drawer,
                          onTap: () {
                            Navigator.pop(context);
                            context.go(RoutePaths.adminMyPage);
                          },
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: _kAdminNavItems.map((item) {
                final selected =
                    _isAdminNavSelected(currentLocation, item.path);
                return ListTile(
                  leading: Icon(
                    item.icon,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  title: Text(
                    item.label,
                    style: TextStyle(
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  selected: selected,
                  selectedTileColor: AppColors.primaryLight,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    context.go(item.path);
                  },
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.error),
            title: const Text(
              '로그아웃',
              style: TextStyle(color: AppColors.error),
            ),
            onTap: () async {
              Navigator.pop(context);
              await ref.read(authRepositoryProvider).signOut();
            },
          ),
        ],
      ),
    );
  }
}
