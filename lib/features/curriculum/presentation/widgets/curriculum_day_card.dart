import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../models/curriculum_day_model.dart';

String weekdayLabelKo(DateTime date) {
  const labels = ['월', '화', '수', '목', '금', '토', '일'];
  return labels[date.weekday - 1];
}

class CurriculumDayCard extends StatelessWidget {
  const CurriculumDayCard({
    super.key,
    required this.day,
    required this.onTap,
    this.completed = false,
    this.showUnpublished = false,
    this.compact = false,
  });

  final CurriculumDayModel day;
  final VoidCallback onTap;
  final bool completed;
  final bool showUnpublished;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        '${AppDateUtils.formatDisplay(day.classDate)} (${weekdayLabelKo(day.classDate)})';

    if (compact) {
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor:
              completed ? AppColors.success.withValues(alpha: 0.15) : AppColors.primaryLight,
          child: Text(
            '${day.dayNumber}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(day.subject.isNotEmpty ? day.subject : '${day.dayNumber}일차'),
        subtitle: Text(
          day.content.isNotEmpty ? day.content : dateLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: onTap,
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                        '${day.dayNumber}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
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
                            day.subject.isNotEmpty
                                ? day.subject
                                : '${day.dayNumber}일차',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (showUnpublished && !day.published)
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
                    const SizedBox(height: 4),
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (day.content.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        day.content,
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
}
