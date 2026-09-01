import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/cohort_status.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/models/cohort_model.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../../shared/providers/lms_providers.dart';

/// 관리자 — 기수 목록 / 선택 / 상태 관리
class AdminCohortsScreen extends ConsumerStatefulWidget {
  const AdminCohortsScreen({super.key});

  @override
  ConsumerState<AdminCohortsScreen> createState() => _AdminCohortsScreenState();
}

class _AdminCohortsScreenState extends ConsumerState<AdminCohortsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cohorts = ref.watch(allCohortsAdminProvider);
    final selectedId = ref.watch(effectiveCohortIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('기수 관리'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '진행중'),
            Tab(text: '예정'),
            Tab(text: '종료'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: () => context.push(RoutePaths.adminCohortsCreate),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('기수 생성'),
            ),
          ),
        ],
      ),
      body: cohorts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(message: e.toString()),
        data: (list) {
          return TabBarView(
            controller: _tabController,
            children: [
              _CohortList(
                cohorts: list
                    .where((c) => c.status == CohortStatus.active)
                    .toList(),
                selectedId: selectedId,
                emptyMessage: '진행 중인 기수가 없습니다',
              ),
              _CohortList(
                cohorts: list
                    .where((c) => c.status == CohortStatus.upcoming)
                    .toList(),
                selectedId: selectedId,
                emptyMessage: '예정된 기수가 없습니다',
              ),
              _CohortList(
                cohorts: list
                    .where((c) => c.status == CohortStatus.archived)
                    .toList(),
                selectedId: selectedId,
                emptyMessage: '종료된 기수가 없습니다',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CohortList extends ConsumerWidget {
  const _CohortList({
    required this.cohorts,
    required this.selectedId,
    required this.emptyMessage,
  });

  final List<CohortModel> cohorts;
  final String? selectedId;
  final String emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (cohorts.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(allCohortsAdminProvider),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: cohorts.length,
        itemBuilder: (_, i) {
          final c = cohorts[i];
          final isSelected = c.cohortId == selectedId;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected ? AppColors.primary : AppColors.border,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => context.push(
                    RoutePaths.adminCohortEditPath(c.cohortId),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      _StatusChip(status: c.status),
                                      if (isSelected) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryLight,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            '현재 선택',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    c.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    c.periodLabel,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${c.studentCount}명',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Text(
                                  '학생',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (c.isSelectable && !isSelected)
                              OutlinedButton(
                                onPressed: () {
                                  selectCohort(ref, c.cohortId);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('「${c.name}」 기수를 선택했습니다'),
                                    ),
                                  );
                                },
                                child: const Text('이 기수로 전환'),
                              ),
                            OutlinedButton(
                              onPressed: () => context.push(
                                RoutePaths.adminCohortEditPath(c.cohortId),
                              ),
                              child: const Text('수정'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final CohortStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      CohortStatus.active => AppColors.success,
      CohortStatus.upcoming => AppColors.info,
      CohortStatus.archived => AppColors.textSecondary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
