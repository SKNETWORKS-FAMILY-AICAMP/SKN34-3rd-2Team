import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/cohort_status.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/cohort_model.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../../shared/providers/lms_providers.dart';

/// AppBar — PLAYDATA 홈 이동 + 관리자 기수 선택
class AppShellHeader extends ConsumerWidget {
  const AppShellHeader({super.key, this.homePath = RoutePaths.dashboard});

  final String homePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);

    return Row(
      children: [
        InkWell(
          onTap: () => context.go(homePath),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(
                    Icons.school,
                    color: AppColors.textPrimary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  AppConstants.appName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        if (isAdmin) ...[
          const SizedBox(width: 12),
          const Flexible(child: _CohortSelector()),
        ],
      ],
    );
  }
}

class _CohortSelector extends ConsumerWidget {
  const _CohortSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cohortsAsync = ref.watch(cohortsStreamProvider);
    final effectiveId = ref.watch(effectiveCohortIdProvider);

    return cohortsAsync.when(
      loading: () => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (cohorts) {
        if (cohorts.isEmpty || effectiveId == null) {
          return const SizedBox.shrink();
        }

        final selected = cohorts.firstWhere(
          (c) => c.cohortId == effectiveId,
          orElse: () => cohorts.first,
        );

        return Align(
          alignment: Alignment.centerLeft,
          child: MenuAnchor(
            style: MenuStyle(
              backgroundColor: const WidgetStatePropertyAll(AppColors.surface),
              elevation: const WidgetStatePropertyAll(6),
              shadowColor: WidgetStatePropertyAll(
                Colors.black.withValues(alpha: 0.08),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.border),
                ),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(vertical: 6),
              ),
            ),
            builder: (context, controller, _) {
              return _CohortTrigger(
                label: _cohortLabel(selected),
                isOpen: controller.isOpen,
                onPressed: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
              );
            },
            menuChildren: [
              for (final cohort in cohorts)
                _CohortMenuItem(
                  label: _cohortLabel(cohort),
                  selected: cohort.cohortId == selected.cohortId,
                  onPressed: () => selectCohort(ref, cohort.cohortId),
                ),
            ],
          ),
        );
      },
    );
  }
}

String _cohortLabel(CohortModel cohort) => cohort.status == CohortStatus.active
    ? cohort.name
    : '${cohort.name} (${cohort.statusLabel})';

class _CohortTrigger extends StatelessWidget {
  const _CohortTrigger({
    required this.label,
    required this.isOpen,
    required this.onPressed,
  });

  final String label;
  final bool isOpen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360, minHeight: 36),
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CohortMenuItem extends StatelessWidget {
  const _CohortMenuItem({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MenuItemButton(
      onPressed: onPressed,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (selected) return AppColors.primaryLight;
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return AppColors.surfaceVariant;
          }
          return Colors.transparent;
        }),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
      leadingIcon: SizedBox(
        width: 18,
        child: selected
            ? const Icon(Icons.check, size: 16, color: AppColors.textPrimary)
            : null,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
