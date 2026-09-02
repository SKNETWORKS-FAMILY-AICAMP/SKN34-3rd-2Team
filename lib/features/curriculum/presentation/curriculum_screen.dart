import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/providers/lms_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../study_room/presentation/widgets/study_room_layout.dart';
import '../models/curriculum_meta_model.dart';
import '../providers/curriculum_providers.dart';
import 'widgets/curriculum_day_card.dart';

/// 학생 — 커리큘럼 일수 목록
class CurriculumScreen extends ConsumerWidget {
  const CurriculumScreen({super.key});

  Future<void> _openFullPdf(BuildContext context, CurriculumMetaModel meta) async {
    final url = meta.fullPdfUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF를 열 수 없습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final cohortName = ref.watch(effectiveCohortNameProvider);
    final metaAsync = ref.watch(curriculumMetaProvider);
    final days = ref.watch(publishedCurriculumDaysProvider);
    final progress = ref.watch(curriculumProgressProvider).asData?.value;

    return userAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (user) {
        if (user == null) return const SizedBox.shrink();

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(curriculumMetaProvider);
            ref.invalidate(curriculumDaysProvider);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: studyRoomContentWrapper(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StudyRoomPageHeader(
                    user: user,
                    cohortName: cohortName,
                    subtitle: '수업일자별 커리큘럼을 확인하세요.',
                  ),
                  const SizedBox(height: 20),
                  metaAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => ErrorView(message: e.toString()),
                    data: (meta) {
                      if (meta == null || !meta.published) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Text(
                              '등록된 커리큘럼이 없습니다',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    meta.title.isNotEmpty ? meta.title : '커리큘럼',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  if (meta.startDate != null && meta.endDate != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      '${AppDateUtils.formatDisplay(meta.startDate!)} ~ ${AppDateUtils.formatDisplay(meta.endDate!)} · 총 ${meta.effectiveTotalDays > 0 ? meta.effectiveTotalDays : days.length}일',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                  if (meta.hasFullPdf) ...[
                                    const SizedBox(height: 12),
                                    OutlinedButton.icon(
                                      onPressed: () => _openFullPdf(context, meta),
                                      icon: const Icon(Icons.picture_as_pdf),
                                      label: Text(meta.fullPdfFileName ?? '전체 커리큘럼 PDF'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            '수업 일정',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 12),
                          if (days.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 32),
                              child: Center(
                                child: Text(
                                  '공개된 수업일이 없습니다',
                                  style: TextStyle(color: AppColors.textSecondary),
                                ),
                              ),
                            )
                          else
                            ...days.map(
                              (d) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: CurriculumDayCard(
                                  day: d,
                                  completed: progress?.isDayCompleted(d.id) ?? false,
                                  onTap: () => context.go(
                                    RoutePaths.curriculumDayPath(d.id),
                                  ),
                                ),
                              ),
                            ),
                        ],
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
