import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/user_model.dart';
import '../../auth/providers/auth_providers.dart';
import '../../shell/widgets/app_shell_header.dart';

/// 관리자 Shell — Drawer 전용 (학생 Shell과 분리)
class AdminShellScreen extends ConsumerWidget {
  const AdminShellScreen({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentUser = ref.watch(currentUserProvider);
    final user = currentUser.value;

    return Scaffold(
      appBar: AppBar(
        title: const AppShellHeader(homePath: RoutePaths.admin),
      ),
      drawer: _AdminDrawer(user: user, currentLocation: location),
      body: child,
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
    final items = [
      _DrawerItem(Icons.dashboard, '관리자 대시보드', RoutePaths.admin),
      _DrawerItem(Icons.calendar_month, '기수 관리', RoutePaths.adminCohorts),
      _DrawerItem(Icons.groups, '학생 관리', RoutePaths.adminStudents),
      _DrawerItem(Icons.event_seat, '좌석 배치', RoutePaths.adminSeating),
      _DrawerItem(Icons.school_outlined, '커리큘럼 관리', RoutePaths.adminCurriculum),
      _DrawerItem(Icons.ballot_outlined, '설문 · 제출', RoutePaths.adminFormTasks),
      _DrawerItem(Icons.history, '기록실 관리', RoutePaths.adminRecords),
      _DrawerItem(Icons.description, '이력서 관리', RoutePaths.adminResumes),
      _DrawerItem(Icons.forum, '게시판 관리', RoutePaths.adminBoard),
      _DrawerItem(Icons.menu_book, '학습실 관리', RoutePaths.adminStudyRoom),
      _DrawerItem(Icons.card_giftcard, '마일리지 관리', RoutePaths.adminMileage),
      _DrawerItem(Icons.person, '마이페이지', RoutePaths.adminMyPage),
    ];

    final displayName = user?.displayName ?? '';
    final email = user?.email ?? '';

    return Drawer(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '관리자',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: items.map((item) {
                final selected = currentLocation == item.path ||
                    (item.path != RoutePaths.admin &&
                        currentLocation.startsWith(item.path));
                return ListTile(
                  leading: Icon(
                    item.icon,
                    color: selected ? AppColors.primary : null,
                  ),
                  title: Text(
                    item.label,
                    style: TextStyle(
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                      color: selected ? AppColors.primary : null,
                    ),
                  ),
                  selected: selected,
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
            leading: const Icon(Icons.logout),
            title: const Text('로그아웃'),
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

class _DrawerItem {
  const _DrawerItem(this.icon, this.label, this.path);
  final IconData icon;
  final String label;
  final String path;
}
