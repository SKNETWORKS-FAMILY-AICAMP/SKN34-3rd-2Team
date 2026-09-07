import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';

/// 이력서 섹션 sticky 탭 — 탭 시 해당 섹션으로 스크롤
class ResumeSectionNav extends StatelessWidget {
  const ResumeSectionNav({
    super.key,
    required this.sections,
    required this.completedSections,
    required this.selectedKey,
    required this.onSelected,
  });

  final List<String> sections;
  final Map<String, bool> completedSections;
  final String? selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (_, i) {
          final key = sections[i];
          final label = AppConstants.resumeSectionLabels[key] ?? key;
          final done = completedSections[key] ?? false;
          final selected = selectedKey == key;
          return InkWell(
            onTap: () => onSelected(key),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? AppColors.primaryLight : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (done)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.check, size: 12, color: AppColors.success),
                    ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      color: selected ? AppColors.primary : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class ResumeProgressHeader extends StatelessWidget {
  const ResumeProgressHeader({
    super.key,
    required this.completed,
    required this.total,
    required this.revisionCount,
    required this.statusLabel,
  });

  final int completed;
  final int total;
  final int revisionCount;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$completed/$total 완료 · $statusLabel',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const Spacer(),
              if (revisionCount > 0)
                Text(
                  'v$revisionCount',
                  style: const TextStyle(color: AppColors.textHint, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: total == 0 ? 0 : completed / total,
            color: AppColors.primary,
            backgroundColor: AppColors.primaryLight,
          ),
        ],
      ),
    );
  }
}
