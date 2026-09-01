import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../../seating/presentation/widgets/seat_grid.dart';
import '../../../seating/providers/seating_providers.dart';

/// 대시보드 — 미니 좌석 배치표 (탭 시 전체 화면)
class MySeatingDashboardCard extends ConsumerWidget {
  const MySeatingDashboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layoutAsync = ref.watch(publishedSeatingLayoutProvider);
    final assignmentAsync = ref.watch(publishedSeatingAssignmentProvider);
    final myUid = ref.watch(currentUserProvider).asData?.value?.uid;

    return layoutAsync.when(
      loading: () => const _SeatingCardShell(
        child: Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => _SeatingCardShell(
        onTap: () => context.go(RoutePaths.seating),
        child: Text(
          '불러오기 실패 · 탭하여 다시 보기',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary.withValues(alpha: 0.9),
          ),
        ),
      ),
      data: (layout) {
        return assignmentAsync.when(
          loading: () => const _SeatingCardShell(
            child: Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => _SeatingCardShell(
            onTap: () => context.go(RoutePaths.seating),
            child: Text(
              '불러오기 실패 · 탭하여 다시 보기',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary.withValues(alpha: 0.9),
              ),
            ),
          ),
          data: (assignment) {
            final isReady =
                layout != null && assignment != null && assignment.isPublished;

            if (!isReady) {
              return _SeatingCardShell(
                onTap: () => context.go(RoutePaths.seating),
                child: Column(
                  children: [
                    Icon(
                      Icons.event_seat_outlined,
                      size: 28,
                      color: AppColors.textHint.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '좌석 배치 확정 대기 중',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '확정되면 이곳에서 미리볼 수 있습니다',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              );
            }

            final mySeatId =
                myUid != null ? assignment.seatIdForUser(myUid) : null;
            final seatUserIds = assignment.assignments;
            final seatDisplayNames = assignment.seatNames.isNotEmpty
                ? assignment.seatNames
                : {
                    for (final e
                        in ref.watch(seatingAssignedStudentsProvider).entries)
                      e.key: e.value.displayName,
                  };

            return _SeatingCardShell(
              onTap: () => context.go(RoutePaths.seating),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (mySeatId != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F3FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF7C3AED)),
                      ),
                      child: Text(
                        '내 자리: $mySeatId번',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF5B21B6),
                        ),
                      ),
                    ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return SizedBox(
                        width: constraints.maxWidth,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topCenter,
                          child: SeatGrid(
                            layout: layout,
                            seatUserIds: seatUserIds,
                            seatDisplayNames: seatDisplayNames,
                            highlightUserId: myUid,
                            compact: true,
                            editable: false,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '탭하여 크게 보기',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textHint.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SeatingCardShell extends StatelessWidget {
  const _SeatingCardShell({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: child,
        ),
      ),
    );
  }
}
