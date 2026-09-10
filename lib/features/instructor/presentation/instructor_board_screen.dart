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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BoardPageHeader(
            title: '게시판 관리',
            subtitle:
                '${cohortName ?? '담당 기수'} · 본인이 등록한 글만 수정할 수 있습니다.',
            action: FilledButton.icon(
              onPressed: () =>
                  context.push(RoutePaths.instructorBoardCreate),
              style: BoardUi.primaryButtonStyle(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('공지 작성'),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: BoardUi.contentMaxWidth),
                child: RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(noticesStreamProvider),
                  child: notices.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => ErrorView(
                      message: e.toString(),
                      onRetry: () => ref.invalidate(noticesStreamProvider),
                    ),
                    data: (list) {
                      if (list.isEmpty) {
                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 48),
                            EmptyView(
                              message: '등록된 공지가 없습니다.',
                              icon: Icons.campaign_outlined,
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
                                    icon: Icon(
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
            ),
          ),
        ],
      ),
    );
  }
}
