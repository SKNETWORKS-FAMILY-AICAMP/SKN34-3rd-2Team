import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/lms_providers.dart';
import '../../assessments/presentation/widgets/assessment_card.dart';
import '../../instructor/presentation/instructor_assessments_screen.dart';

/// 관리자 — 성취도평가 결과 조회
class AdminAssessmentsScreen extends ConsumerWidget {
  const AdminAssessmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assessments = ref.watch(assessmentsProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: assessments.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('등록된 평가가 없습니다.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final a = list[i];
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: AssessmentCard(
                    assessment: a,
                    onTap: () => context.push(
                      RoutePaths.adminAssessmentDetailPath(a.id),
                    ),
                    onPublish: a.published
                        ? null
                        : () => confirmAndPublishAssessment(
                              context: context,
                              ref: ref,
                              assessmentId: a.id,
                              title: a.title,
                            ),
                    onDelete: () => confirmAndDeleteAssessment(
                      context: context,
                      ref: ref,
                      assessmentId: a.id,
                      title: a.title,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
