import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/providers/lms_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../study_room/presentation/widgets/assessment_card.dart';
import '../../study_room/presentation/widgets/study_room_layout.dart';

/// 관리자 학습실 — 성취도 평가 목록 + 생성
class AdminStudyRoomScreen extends ConsumerStatefulWidget {
  const AdminStudyRoomScreen({super.key});

  @override
  ConsumerState<AdminStudyRoomScreen> createState() =>
      _AdminStudyRoomScreenState();
}

class _AdminStudyRoomScreenState extends ConsumerState<AdminStudyRoomScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final cohortName = ref.watch(effectiveCohortNameProvider);
    final assessments = ref.watch(assessmentsProvider);

    return userAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (user) {
        if (user == null) return const SizedBox.shrink();

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(assessmentsProvider),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: studyRoomContentWrapper(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: StudyRoomPageHeader(
                          user: user,
                          cohortName: cohortName,
                          subtitle: '성취도 평가를 생성하고 관리하세요.',
                          showProfile: false,
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: () =>
                            context.push(RoutePaths.adminStudyRoomCreate),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('평가 생성'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  StudyRoomSearchBar(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                  const SizedBox(height: 20),
                  assessments.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => ErrorView(message: e.toString()),
                    data: (list) {
                      final filtered = list
                          .where(
                            (a) =>
                                _query.isEmpty ||
                                a.title
                                    .toLowerCase()
                                    .contains(_query.toLowerCase()),
                          )
                          .toList();

                      if (filtered.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Column(
                            children: [
                              const Text(
                                '등록된 평가가 없습니다',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () => context
                                    .push(RoutePaths.adminStudyRoomCreate),
                                icon: const Icon(Icons.add),
                                label: const Text('첫 평가 만들기'),
                              ),
                            ],
                          ),
                        );
                      }

                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final crossAxisCount =
                              constraints.maxWidth >= 720 ? 2 : 1;
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: crossAxisCount == 2 ? 0.85 : 1.1,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final a = filtered[i];
                              return AssessmentCard(
                                assessment: a,
                                completed: false,
                                showDraft: true,
                                onTap: () => context.push(
                                  RoutePaths.adminStudyRoomAssessmentPath(a.id),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
