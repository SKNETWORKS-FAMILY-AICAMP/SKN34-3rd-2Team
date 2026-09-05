import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/route_paths.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/profile_nav_chip.dart';
import '../auth/providers/auth_providers.dart';
import 'widgets/alert_popup_host.dart';
import 'widgets/app_shell_header.dart';

/// 메인 Shell — Drawer(전체 메뉴)
class MainShellScreen extends ConsumerWidget {
  const MainShellScreen({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final user = currentUser.value;

    return Scaffold(
      appBar: AppBar(
        title: const AppShellHeader(),
        actions: [
          if (user != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ProfileNavChip(
                  user: user,
                  style: ProfileNavChipStyle.appBar,
                  onTap: () => context.go(RoutePaths.myPage),
                ),
              ),
            ),
        ],
      ),
      drawer: _AppDrawer(user: user),
      body: AlertPopupHost(child: child),
    );
  }
}

class _AppDrawer extends ConsumerWidget {
  const _AppDrawer({this.user});

  final UserModel? user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menuItems = [
      _DrawerItem(Icons.dashboard, '대시보드', RoutePaths.dashboard),
      _DrawerItem(Icons.description, '이력서 관리', RoutePaths.resume),
      _DrawerItem(Icons.menu_book, '학습실', RoutePaths.studyRoom),
      _DrawerItem(Icons.forum, '게시판', RoutePaths.board),
      _DrawerItem(Icons.event_seat, '자리 배치', RoutePaths.seating),
      _DrawerItem(Icons.ballot_outlined, '설문 · 제출', RoutePaths.forms),
      _DrawerItem(Icons.workspace_premium_outlined, '자격 시험 일정', RoutePaths.qualExams),
      _DrawerItem(Icons.history, '기록실', RoutePaths.records),
      _DrawerItem(Icons.card_giftcard, '마일리지', RoutePaths.mileage),
      _DrawerItem(Icons.quiz_outlined, '성취도평가', RoutePaths.assessments),
      _DrawerItem(Icons.person, '마이페이지', RoutePaths.myPage),
    ];

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
                  ? ProfileNavChip(
                      user: user!,
                      style: ProfileNavChipStyle.drawer,
                      onTap: () {
                        Navigator.pop(context);
                        context.go(RoutePaths.myPage);
                      },
                    )
                  : const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('게스트'),
                    ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: menuItems.map((item) {
                final isSelected =
                    GoRouterState.of(context).matchedLocation == item.path;
                return ListTile(
                  leading: Icon(
                    item.icon,
                    color: isSelected ? AppColors.primary : null,
                  ),
                  title: Text(
                    item.label,
                    style: TextStyle(
                      color: isSelected ? AppColors.primary : null,
                      fontWeight: isSelected ? FontWeight.w600 : null,
                    ),
                  ),
                  selected: isSelected,
                  selectedTileColor: AppColors.primaryLight.withValues(alpha: 0.5),
                  onTap: () {
                    Navigator.pop(context);
                    context.go(item.path);
                  },
                );
              }).toList(),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.error),
            title: const Text('로그아웃', style: TextStyle(color: AppColors.error)),
            onTap: () async {
              Navigator.pop(context);
              await ref.read(authRepositoryProvider).signOut();
            },
          ),
          const SizedBox(height: 8),
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
