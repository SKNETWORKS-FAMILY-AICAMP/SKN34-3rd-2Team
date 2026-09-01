import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/models/assessment_model.dart';
import '../../../shared/providers/lms_providers.dart';
import '../../auth/providers/auth_providers.dart';
import 'widgets/assessment_card.dart';
import 'widgets/study_room_layout.dart';

/// 학습실 — 성취도 평가 카드 목록 (학생)
class StudyRoomScreen extends ConsumerStatefulWidget {
  const StudyRoomScreen({super.key});

  @override
  ConsumerState<StudyRoomScreen> createState() => _StudyRoomScreenState();
}

class _StudyRoomScreenState extends ConsumerState<StudyRoomScreen> {
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
    final assessments = ref.watch(publishedAssessmentsProvider);
    final submissions = ref.watch(myAssessmentSubmissionsProvider);

    return userAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (user) {
        if (user == null) return const SizedBox.shrink();

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(publishedAssessmentsProvider);
            ref.invalidate(myAssessmentSubmissionsProvider);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: studyRoomContentWrapper(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StudyRoomPageHeader(user: user, cohortName: cohortName),
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
                      final submissionMap = submissions.maybeWhen(
                        data: (subs) => {
                          for (final s in subs) s.assessmentId: s,
                        },
                        orElse: () => <String, AssessmentSubmissionModel>{},
                      );

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
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Text(
                              '등록된 평가가 없습니다',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
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
                              final sub = submissionMap[a.id];
                              return AssessmentCard(
                                assessment: a,
                                completed: sub?.completed ?? false,
                                onTap: () => context.push(
                                  RoutePaths.studyRoomAssessmentPath(a.id),
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
