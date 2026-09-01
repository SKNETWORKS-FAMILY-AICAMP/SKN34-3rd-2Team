import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/providers/qual_exam_providers.dart';
import '../../utils/qual_exam_utils.dart';
import 'qual_exam_timeline.dart';

/// 대시보드 — 다가오는 자격 시험 타임라인 (3건)
class QualExamScheduleSection extends ConsumerWidget {
  const QualExamScheduleSection({super.key});

  static const _previewCount = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules = ref.watch(qualExamSchedulesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '다가오는 자격 시험',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            TextButton(
              onPressed: () => context.go(RoutePaths.qualExams),
              child: const Text('전체 보기'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        schedules.when(
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
          error: (e, _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '시험 일정을 불러오지 못했습니다: $e',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
          data: (result) {
            final upcoming = QualExamUtils.prepareUpcoming(result.items);
            final preview = upcoming.take(_previewCount).toList();

            if (preview.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      '다가오는 시험 일정이 없습니다',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
              );
            }

            return Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
                child: QualExamTimeline(items: preview, compact: true),
              ),
            );
          },
        ),
      ],
    );
  }
}
