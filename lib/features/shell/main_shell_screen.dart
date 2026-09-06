import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/route_paths.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/models/user_model.dart';
import '../../shared/providers/profile_photo_providers.dart';
import '../../shared/widgets/app_side_rail.dart';
import '../../shared/widgets/profile_avatar.dart';
import '../../shared/widgets/profile_nav_chip.dart';
import '../auth/providers/auth_providers.dart';
import 'widgets/alert_popup_host.dart';
import 'widgets/app_shell_header.dart';

/// 메인 Shell — 와이드: 좌측 아이콘+텍스트 레일 / 좁은 화면: Drawer
class MainShellScreen extends ConsumerWidget {
  const MainShellScreen({super.key, required this.child});

  final Widget child;

  static const _railBreakpoint = 900.0;

  static const _navItems = [
    AppSideRailItem(
      icon: Icons.dashboard_rounded,
      label: '대시보드',
      path: RoutePaths.dashboard,
    ),
    AppSideRailItem(
      icon: Icons.description_rounded,
      label: '이력서 관리',
      path: RoutePaths.resume,
    ),
    AppSideRailItem(
      icon: Icons.menu_book_rounded,
      label: '학습실',
      path: RoutePaths.studyRoom,
    ),
    AppSideRailItem(
      icon: Icons.forum_rounded,
      label: '게시판',
      path: RoutePaths.board,
    ),
    AppSideRailItem(
      icon: Icons.event_seat_rounded,
      label: '자리 배치',
      path: RoutePaths.seating,
    ),
    AppSideRailItem(
      icon: Icons.ballot_outlined,
      label: '설문 · 제출',
      path: RoutePaths.forms,
    ),
    AppSideRailItem(
      icon: Icons.workspace_premium_outlined,
      label: '자격 시험 일정',
      path: RoutePaths.qualExams,
    ),
    AppSideRailItem(
      icon: Icons.history_rounded,
      label: '기록실',
      path: RoutePaths.records,
    ),
    AppSideRailItem(
      icon: Icons.card_giftcard_rounded,
      label: '마일리지',
      path: RoutePaths.mileage,
    ),
    AppSideRailItem(
      icon: Icons.quiz_outlined,
      label: '성취도평가',
      path: RoutePaths.assessments,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final user = currentUser.value;
    final wide = MediaQuery.sizeOf(context).width >= _railBreakpoint;
    final location = GoRouterState.of(context).matchedLocation;
    final preview = ref.watch(profilePhotoPreviewProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const AppShellHeader(),
        automaticallyImplyLeading: !wide,
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
      drawer: wide ? null : _AppDrawer(user: user),
      body: Row(
        children: [
          if (wide)
            AppSideRail(
              items: _navItems,
              location: location,
              onNavigate: (path) => context.go(path),
              onLogout: () => ref.read(authRepositoryProvider).signOut(),
              profile: user == null
                  ? null
                  : _RailProfileTile(
                      user: user,
                      previewBytes: preview,
                      onTap: () => context.go(RoutePaths.myPage),
                    ),
            ),
          Expanded(child: AlertPopupHost(child: child)),
        ],
      ),
    );
  }
}

class _RailProfileTile extends StatelessWidget {
  const _RailProfileTile({
    required this.user,
    required this.onTap,
    this.previewBytes,
  });

  final UserModel user;
  final VoidCallback onTap;
  final Uint8List? previewBytes;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: ProfileAvatar(
                  radius: 14,
                  userId: user.uid,
                  photoUrl: user.photoUrl,
                  photoStoragePath: user.photoStoragePath,
                  previewBytes: previewBytes,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  user.displayName.isNotEmpty ? user.displayName : '마이페이지',
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
    );
  }
}

class _AppDrawer extends ConsumerWidget {
  const _AppDrawer({this.user});

  final UserModel? user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menuItems = [
      ...MainShellScreen._navItems,
      const AppSideRailItem(
        icon: Icons.person_rounded,
        label: '마이페이지',
        path: RoutePaths.myPage,
      ),
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: menuItems.map((item) {
                final isSelected =
                    GoRouterState.of(context).matchedLocation == item.path;
                return ListTile(
                  leading: Icon(
                    item.icon,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  title: Text(
                    item.label,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      fontWeight: isSelected ? FontWeight.w600 : null,
                    ),
                  ),
                  selected: isSelected,
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
          const Divider(),
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
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
