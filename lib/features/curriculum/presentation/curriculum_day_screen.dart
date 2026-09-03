import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../auth/providers/auth_providers.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../data/curriculum_repository.dart';
import '../providers/curriculum_providers.dart';
import 'widgets/curriculum_day_card.dart';
import 'widgets/curriculum_link_chip.dart';
import 'widgets/curriculum_pdf_tile.dart';

/// 학생 — 일수 상세
class CurriculumDayScreen extends ConsumerStatefulWidget {
  const CurriculumDayScreen({super.key, required this.dayId});

  final String dayId;

  @override
  ConsumerState<CurriculumDayScreen> createState() => _CurriculumDayScreenState();
}

class _CurriculumDayScreenState extends ConsumerState<CurriculumDayScreen> {
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
    await ref.read(curriculumRepositoryProvider).setLastViewedDay(
          cohortId: cohortId,
          userId: uid,
          dayId: widget.dayId,
        );
  }

  Future<void> _toggleComplete(bool completed) async {
    final cohortId = ref.read(effectiveCohortIdProvider);
    final uid = ref.read(currentUserProvider).asData?.value?.uid;
    if (cohortId == null || uid == null) return;

    await ref.read(curriculumRepositoryProvider).toggleDayCompleted(
          cohortId: cohortId,
          userId: uid,
          dayId: widget.dayId,
          completed: completed,
        );
  }

  @override
  Widget build(BuildContext context) {
    final dayAsync = ref.watch(curriculumDayProvider(widget.dayId));
    final progress = ref.watch(curriculumProgressProvider).asData?.value;
    final isCompleted = progress?.isDayCompleted(widget.dayId) ?? false;

    return dayAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (day) {
        if (day == null || !day.published) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => context.go(RoutePaths.curriculum),
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
                const Text('수업일을 찾을 수 없습니다.'),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
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
                      '${day.dayNumber}일차',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              CurriculumDayCard(
                day: day,
                completed: isCompleted,
                onTap: () {},
              ),
              const SizedBox(height: 16),
              Text(
                '${AppDateUtils.formatDisplay(day.classDate)} (${weekdayLabelKo(day.classDate)})',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (day.subject.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('교과목', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(day.subject),
              ],
              if (day.content.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('내용', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(day.content),
              ],
              if (day.links.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text(
                  '연결된 학습',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                ...day.links.map((l) => CurriculumLinkTile(link: l)),
              ],
              if (day.attachments.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text(
                  '첨부 자료',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                ...day.attachments.map((a) => CurriculumPdfTile(attachment: a)),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _toggleComplete(!isCompleted),
                icon: Icon(isCompleted ? Icons.check_circle : Icons.check_circle_outline),
                label: Text(isCompleted ? '완료 취소' : '오늘 수업 완료'),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      isCompleted ? AppColors.secondary : AppColors.success,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
