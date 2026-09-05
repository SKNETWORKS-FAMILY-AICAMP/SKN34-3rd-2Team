import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/profile_nav_chip.dart';
import '../../auth/providers/auth_providers.dart';
import '../../shell/widgets/app_shell_header.dart';

class _NavItem {
  const _NavItem(this.icon, this.label, this.path);
  final IconData icon;
  final String label;
  final String path;
}

const _kInstructorNavItems = [
  _NavItem(Icons.fact_check_outlined, '출결관리', RoutePaths.instructor),
  _NavItem(Icons.description, '이력서관리', RoutePaths.instructorResumes),
  _NavItem(Icons.forum, '게시물관리', RoutePaths.instructorBoard),
  _NavItem(Icons.quiz_outlined, '성취도평가', RoutePaths.instructorAssessments),
  _NavItem(Icons.table_chart_outlined, '커리큘럼', RoutePaths.instructorCurriculum),
  _NavItem(Icons.person, '마이페이지', RoutePaths.instructorMyPage),
];

bool _isNavSelected(String location, String path) {
  if (path == RoutePaths.instructor) {
    return location == path;
  }
  return location == path || location.startsWith(path);
}

/// 강사 Shell — 상단 탭으로 출결 / 이력서 / 게시물 / 마이페이지 노출
class InstructorShellScreen extends ConsumerWidget {
  const InstructorShellScreen({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentUser = ref.watch(currentUserProvider);
    final user = currentUser.value;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const AppShellHeader(homePath: RoutePaths.instructor),
        actions: [
          if (user != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ProfileNavChip(
                  user: user,
                  style: ProfileNavChipStyle.appBar,
                  onTap: () => context.go(RoutePaths.instructorMyPage),
                ),
              ),
            ),
          IconButton(
            tooltip: '로그아웃',
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            icon: const Icon(Icons.logout, size: 20),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InstructorTopNav(currentLocation: location),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _InstructorTopNav extends StatelessWidget {
  const _InstructorTopNav({required this.currentLocation});

  final String currentLocation;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 16,
                vertical: 8,
              ),
              child: Row(
                children: [
                  for (final item in _kInstructorNavItems) ...[
                    if (item != _kInstructorNavItems.first)
                      SizedBox(width: compact ? 4 : 6),
                    _NavChip(
                      icon: item.icon,
                      label: item.label,
                      selected: _isNavSelected(currentLocation, item.path),
                      compact: compact,
                      onTap: () => context.go(item.path),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NavChip extends StatelessWidget {
  const _NavChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.textPrimary;
    final bg = selected ? AppColors.primary : AppColors.surfaceVariant;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 14,
            vertical: compact ? 8 : 10,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 16 : 18, color: fg),
              SizedBox(width: compact ? 6 : 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: compact ? 13 : 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
