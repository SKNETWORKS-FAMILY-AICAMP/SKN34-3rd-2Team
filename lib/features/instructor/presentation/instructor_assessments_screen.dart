import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/lms_providers.dart';
import '../../assessments/presentation/widgets/assessment_card.dart';

/// 강사 — 평가 목록
class InstructorAssessmentsScreen extends ConsumerWidget {
  const InstructorAssessmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assessments = ref.watch(assessmentsProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(RoutePaths.instructorAssessmentsCreate),
        icon: const Icon(Icons.add),
        label: const Text('평가 만들기'),
      ),
      body: assessments.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('아직 만든 평가가 없습니다.'));
          }
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final a = list[i];
                  return AssessmentCard(
                    assessment: a,
                    onTap: () => context.push(
                      RoutePaths.instructorAssessmentDetailPath(a.id),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
