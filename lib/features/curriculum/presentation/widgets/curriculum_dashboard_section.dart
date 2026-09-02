import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../models/curriculum_day_model.dart';
import '../../models/curriculum_progress_model.dart';
import '../../models/curriculum_week_model.dart';
import '../../providers/curriculum_providers.dart';
import 'curriculum_day_card.dart';
import 'curriculum_link_chip.dart';

/// 대시보드 — 오늘 수업 / 커리큘럼 섹션
class CurriculumDashboardSection extends ConsumerWidget {
  const CurriculumDashboardSection({super.key});

  static const _previewCount = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = ref.watch(curriculumMetaProvider);
    final currentDay = ref.watch(currentCurriculumDayProvider);
    final currentWeek = ref.watch(currentCurriculumWeekProvider);
    final progressRatio = ref.watch(curriculumProgressRatioProvider);
    final progress = ref.watch(curriculumProgressProvider).asData?.value;
    final days = ref.watch(publishedCurriculumDaysProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                days.isNotEmpty ? '오늘 수업' : '이번 주 커리큘럼',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            TextButton(
              onPressed: () => context.go(RoutePaths.curriculum),
              child: const Text('전체 보기'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        meta.when(
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
                '커리큘럼을 불러오지 못했습니다: $e',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
          data: (metaData) {
            if (metaData == null || !metaData.published) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      '등록된 커리큘럼이 없습니다',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
              );
            }

            if (currentDay != null) {
              return _DayPreviewCard(
                day: currentDay,
                progress: progress,
                progressRatio: progressRatio,
                onDetail: () => context.go(RoutePaths.curriculumDayPath(currentDay.id)),
              );
            }

            if (currentWeek != null) {
              return _WeekFallbackCard(
                week: currentWeek,
                progressRatio: progressRatio,
              );
            }

            return const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    '다가오는 수업이 없습니다',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _DayPreviewCard extends StatelessWidget {
  const _DayPreviewCard({
    required this.day,
    required this.progress,
    required this.progressRatio,
    required this.onDetail,
  });

  final CurriculumDayModel day;
  final CurriculumProgressModel? progress;
  final double progressRatio;
  final VoidCallback onDetail;

  @override
  Widget build(BuildContext context) {
    final completed = progress?.isDayCompleted(day.id) ?? false;
    final linkPreview = day.links.take(CurriculumDashboardSection._previewCount).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${day.dayNumber}일차',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                const Spacer(),
                if (completed)
                  const Icon(Icons.check_circle, color: AppColors.success, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              day.subject.isNotEmpty ? day.subject : '${day.dayNumber}일차',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              '${AppDateUtils.formatDisplay(day.classDate)} (${weekdayLabelKo(day.classDate)})',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            if (day.content.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                day.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progressRatio,
                minHeight: 6,
                backgroundColor: AppColors.divider,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '진행률 ${(progressRatio * 100).round()}%',
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            if (linkPreview.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: linkPreview
                    .map((l) => CurriculumLinkTile(link: l, compact: true))
                    .toList(),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onDetail, child: const Text('수업 상세 보기')),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekFallbackCard extends StatelessWidget {
  const _WeekFallbackCard({
    required this.week,
    required this.progressRatio,
  });

  final CurriculumWeekModel week;
  final double progressRatio;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${week.weekNumber}주차', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (week.title.isNotEmpty) Text(week.title),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progressRatio),
          ],
        ),
      ),
    );
  }
}
