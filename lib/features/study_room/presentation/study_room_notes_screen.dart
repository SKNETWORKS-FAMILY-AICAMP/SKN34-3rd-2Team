import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/providers/lms_providers.dart';
import '../../auth/providers/auth_providers.dart';
import 'widgets/study_room_layout.dart';

class StudyRoomNotesScreen extends ConsumerWidget {
  const StudyRoomNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final cohortName = ref.watch(effectiveCohortNameProvider);
    final sources = ref.watch(activeStudySourcesProvider);

    return userAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (user) {
        if (user == null) return const SizedBox.shrink();
        return SingleChildScrollView(
          child: studyRoomContentWrapper(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => context.go(RoutePaths.studyRoom),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('학습실'),
                  ),
                ),
                StudyRoomPageHeader(
                  user: user,
                  cohortName: cohortName,
                  title: '공부방',
                  subtitle: '수업 저장소를 고르고, 날짜·폴더·파일만 정리하세요.',
                ),
                const SizedBox(height: 20),
                sources.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => ErrorView(message: e.toString()),
                  data: (list) {
                    if (list.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: Text(
                            '등록된 수업 저장소가 없습니다',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final source in list) ...[
                          _SourceCard(
                            title: source.title,
                            repo: source.repoLabel,
                            prefixes: source.prefixSummary,
                            onTap: () => context.go(
                              RoutePaths.studyRoomNoteSource(source.id),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.title,
    required this.repo,
    required this.prefixes,
    required this.onTap,
  });

  final String title;
  final String repo;
  final String prefixes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(repo, style: const TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(
                      prefixes,
                      style: const TextStyle(fontSize: 12, color: AppColors.textHint),
                    ),
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
