import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../study_room/presentation/widgets/study_room_layout.dart';
import '../data/curriculum_repository.dart';
import '../providers/curriculum_providers.dart';
import 'widgets/curriculum_link_chip.dart';
import 'widgets/curriculum_pdf_tile.dart';

/// 학생 — 주차 상세
class CurriculumWeekScreen extends ConsumerStatefulWidget {
  const CurriculumWeekScreen({super.key, required this.weekId});

  final String weekId;

  @override
  ConsumerState<CurriculumWeekScreen> createState() =>
      _CurriculumWeekScreenState();
}

class _CurriculumWeekScreenState extends ConsumerState<CurriculumWeekScreen> {
  bool _viewRecorded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordView());
  }

  Future<void> _recordView() async {
    if (_viewRecorded) return;
    final cohortId = ref.read(effectiveCohortIdProvider);
    final uid = ref.read(currentUserProvider).asData?.value?.uid;
    if (cohortId == null || uid == null) return;
    _viewRecorded = true;
    await ref.read(curriculumRepositoryProvider).setLastViewedWeek(
          cohortId: cohortId,
          userId: uid,
          weekId: widget.weekId,
        );
  }

  Future<void> _toggleComplete(bool completed) async {
    final cohortId = ref.read(effectiveCohortIdProvider);
    final uid = ref.read(currentUserProvider).asData?.value?.uid;
    if (cohortId == null || uid == null) return;

    await ref.read(curriculumRepositoryProvider).toggleWeekCompleted(
          cohortId: cohortId,
          userId: uid,
          weekId: widget.weekId,
          completed: completed,
        );
  }

  @override
  Widget build(BuildContext context) {
    final weekAsync = ref.watch(curriculumWeekProvider(widget.weekId));
    final progress = ref.watch(curriculumProgressProvider).asData?.value;
    final isCompleted = progress?.isWeekCompleted(widget.weekId) ?? false;

    return weekAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (week) {
        if (week == null || !week.published) {
          return studyRoomContentWrapper(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => context.go(RoutePaths.curriculum),
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('주차를 찾을 수 없습니다.'),
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          child: studyRoomContentWrapper(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => context.go(RoutePaths.curriculum),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Expanded(
                      child: Text(
                        '${week.weekNumber}주차',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  week.title.isNotEmpty ? week.title : '${week.weekNumber}주차',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                if (week.startDate != null && week.endDate != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${AppDateUtils.formatDisplay(week.startDate!)} ~ ${AppDateUtils.formatDisplay(week.endDate!)}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
                if (week.summary.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(week.summary),
                ],
                if (week.topics.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text(
                    '학습 주제',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  ...week.topics.map(
                    (t) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.title,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if (t.description.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                t.description,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                            if (t.tags.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                children: t.tags
                                    .map(
                                      (tag) => Chip(
                                        label: Text(tag, style: const TextStyle(fontSize: 11)),
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                if (week.links.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text(
                    '연결된 학습',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  ...week.links.map((l) => CurriculumLinkTile(link: l)),
                ],
                if (week.attachments.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text(
                    '첨부 자료',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  ...week.attachments.map((a) => CurriculumPdfTile(attachment: a)),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _toggleComplete(!isCompleted),
                  icon: Icon(isCompleted ? Icons.check_circle : Icons.check_circle_outline),
                  label: Text(isCompleted ? '완료 취소' : '이번 주 완료'),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        isCompleted ? AppColors.secondary : AppColors.success,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}
