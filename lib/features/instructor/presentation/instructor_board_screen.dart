import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../../shared/providers/lms_providers.dart';
import '../../hub/presentation/widgets/board_ui.dart';
import '../../hub/presentation/widgets/notice_list_widgets.dart';

const _kBoardContentMaxWidth = 880.0;

/// 강사 — 게시물 작성 (공지 등록·본인 글 수정)
class InstructorBoardScreen extends ConsumerWidget {
  const InstructorBoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(noticesStreamProvider);
    final uid = ref.watch(currentUserSyncProvider)?.uid;
    final cohortName = ref.watch(effectiveCohortNameProvider);

    return ColoredBox(
      color: BoardUi.listBackground,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kBoardContentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '게시물관리',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${cohortName ?? '담당 기수'} · 본인이 등록한 글만 수정할 수 있습니다.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () =>
                          context.push(RoutePaths.instructorBoardCreate),
                      style: BoardUi.primaryButtonStyle(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('공지 작성'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(noticesStreamProvider),
                  child: notices.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => ErrorView(message: e.toString()),
                    data: (list) {
                      if (list.isEmpty) {
                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 100),
                            Center(
                              child: Text(
                                '등록된 공지가 없습니다.',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        );
                      }

                      return ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final notice = list[i];
                          final canEdit =
                              uid != null && notice.authorId == uid;
                          return NoticeCard(
                            notice: notice,
                            compact: true,
                            onTap: () =>
                                NoticeDetailSheet.show(context, notice),
                            trailing: canEdit
                                ? IconButton(
                                    tooltip: '수정',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                      color: AppColors.textHint,
                                    ),
                                    onPressed: () => context.push(
                                      RoutePaths.instructorBoardNoticeEditPath(
                                        notice.id,
                                      ),
                                    ),
                                  )
                                : null,
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
