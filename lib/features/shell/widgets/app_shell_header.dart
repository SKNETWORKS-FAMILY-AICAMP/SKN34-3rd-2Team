import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/cohort_status.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../shared/models/cohort_model.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../../shared/providers/lms_providers.dart';
import '../../../shared/providers/side_rail_theme_provider.dart';
import '../../../core/theme/shell_chrome.dart';

/// AppBar — PLAYDATA 홈 이동 + 관리자 기수 선택
class AppShellHeader extends ConsumerWidget {
  const AppShellHeader({super.key, this.homePath = RoutePaths.dashboard});

  final String homePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final railDark = ref.watch(sideRailDarkModeProvider);

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
                  width: 36,
                  height: 36,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/brand/playdata.jpg',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  AppConstants.appName,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: ShellChrome.appBarForeground(railDark),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isAdmin) ...[
          const SizedBox(width: 12),
          Flexible(child: _CohortSelector(isDark: railDark)),
        ],
      ],
    );
  }
}

class _CohortSelector extends ConsumerStatefulWidget {
  const _CohortSelector({required this.isDark});

  final bool isDark;

  @override
  ConsumerState<_CohortSelector> createState() => _CohortSelectorState();
}

class _CohortSelectorState extends ConsumerState<_CohortSelector> {
  final _anchorKey = GlobalKey();
  double _width = 0;

  void _measure() {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final next = box.size.width;
    if ((next - _width).abs() > 0.5) {
      setState(() => _width = next);
    }
  }

  @override
  Widget build(BuildContext context) {
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

        final menuWidth = _menuWidth(context, cohorts, _width);

        return Align(
          alignment: Alignment.centerLeft,
          child: MenuAnchor(
            crossAxisUnconstrained: true,
            style: AppMenuStyles.matchedPanel(menuWidth),
            alignmentOffset: const Offset(0, 2),
            builder: (context, controller, _) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _measure();
              });
              return KeyedSubtree(
                key: _anchorKey,
                child: _CohortTrigger(
                  label: _cohortLabel(selected),
                  isOpen: controller.isOpen,
                  isDark: widget.isDark,
                  onPressed: () {
                    if (controller.isOpen) {
                      controller.close();
                    } else {
                      controller.open();
                    }
                  },
                ),
              );
            },
            menuChildren: [
              for (final cohort in cohorts)
                MenuItemButton(
                  onPressed: () => selectCohort(ref, cohort.cohortId),
                  style: ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size(menuWidth, 40)),
                    maximumSize: WidgetStatePropertyAll(Size(menuWidth, 64)),
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      final selectedItem =
                          cohort.cohortId == selected.cohortId;
                      if (selectedItem) return AppColors.primaryLight;
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
                    child: cohort.cohortId == selected.cohortId
                        ? const Icon(Icons.check,
                            size: 16, color: AppColors.primary)
                        : null,
                  ),
                  child: Text(
                    _cohortLabel(cohort),
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: cohort.cohortId == selected.cohortId
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

double _menuWidth(
  BuildContext context,
  List<CohortModel> cohorts,
  double triggerWidth,
) {
  const style = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  var textWidth = 0.0;
  for (final cohort in cohorts) {
    final painter = TextPainter(
      text: TextSpan(text: _cohortLabel(cohort), style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();
    if (painter.width > textWidth) textWidth = painter.width;
  }

  // 체크 아이콘 + 항목 패딩 + 메뉴 내부 여백. 글자 끝이 잘리지 않게 넉넉히.
  final content = textWidth + 18 + 28 + 48;
  final screen = MediaQuery.sizeOf(context).width - 24;
  final floor = triggerWidth > 0 ? triggerWidth : 180.0;
  return content.clamp(floor, screen);
}

String _cohortLabel(CohortModel cohort) => cohort.status == CohortStatus.active
    ? cohort.name
    : '${cohort.name} (${cohort.statusLabel})';

class _CohortTrigger extends StatelessWidget {
  const _CohortTrigger({
    required this.label,
    required this.isOpen,
    required this.isDark,
    required this.onPressed,
  });

  final String label;
  final bool isOpen;
  final bool isDark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark
          ? Colors.white.withValues(alpha: 0.1)
          : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ShellChrome.appBarBorder(isDark)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ShellChrome.appBarForeground(isDark),
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 18,
                color: ShellChrome.appBarMuted(isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
