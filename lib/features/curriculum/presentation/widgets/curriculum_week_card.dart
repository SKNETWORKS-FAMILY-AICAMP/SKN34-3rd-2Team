import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/curriculum_week_model.dart';

class CurriculumWeekCard extends StatelessWidget {
  const CurriculumWeekCard({
    super.key,
    required this.week,
    required this.onTap,
    this.completed = false,
    this.showUnpublished = false,
  });

  final CurriculumWeekModel week;
  final VoidCallback onTap;
  final bool completed;
  final bool showUnpublished;

  @override
  Widget build(BuildContext context) {
    final dateRange = _formatDateRange(week);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: completed
                      ? AppColors.success.withValues(alpha: 0.12)
                      : AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: completed
                    ? const Icon(Icons.check, color: AppColors.success, size: 22)
                    : Text(
                        '${week.weekNumber}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            week.title.isNotEmpty
                                ? week.title
                                : '${week.weekNumber}주차',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (showUnpublished && !week.published)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '비공개',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (dateRange.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        dateRange,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    if (week.summary.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        week.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateRange(CurriculumWeekModel week) {
    final start = week.startDate;
    final end = week.endDate;
    if (start == null || end == null) return '';
    String fmt(DateTime d) =>
        '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
    return '${fmt(start)} ~ ${fmt(end)}';
  }
}
