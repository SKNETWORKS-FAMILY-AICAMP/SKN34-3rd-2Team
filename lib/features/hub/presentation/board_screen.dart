import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/models/post_model.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../../shared/providers/lms_providers.dart';
import 'widgets/board_ui.dart';
import 'widgets/notice_list_widgets.dart';

/// 게시판 — 공지 + 소통 피드 탭 (학생용)
class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _postController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _postController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: BoardUi.listBackground,
      child: Column(
        children: [
          BoardTabBar(
            controller: _tabController,
            tabs: const ['공지사항', '소통 피드'],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                const _NoticesTab(),
                _FeedTab(controller: _postController),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticesTab extends ConsumerWidget {
  const _NoticesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(noticesStreamProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(noticesStreamProvider),
      child: notices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(message: e.toString()),
        data: (list) {
          if (list.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.campaign_outlined,
                        size: 40,
                        color: AppColors.textHint,
                      ),
                      SizedBox(height: 12),
                      Text(
                        '공지사항이 없습니다',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          final favorites = list.where((n) => n.isFavorite).toList();
          final regular = list.where((n) => !n.isFavorite).toList();

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                children: [
                  if (favorites.isNotEmpty) ...[
                    const _SectionHeader(
                      icon: Icons.star_rounded,
                      iconColor: BoardUi.favorite,
                      title: '중요 공지',
                    ),
                    const SizedBox(height: 8),
                    StudentNoticeRowList(
                      notices: favorites,
                      onTap: (notice) =>
                          NoticeDetailSheet.show(context, notice),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (regular.isNotEmpty) ...[
                    const _SectionHeader(
                      icon: Icons.campaign_outlined,
                      title: '전체 공지',
                    ),
                    const SizedBox(height: 8),
                    StudentNoticeRowList(
                      notices: regular,
                      onTap: (notice) =>
                          NoticeDetailSheet.show(context, notice),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor ?? AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _FeedTab extends ConsumerWidget {
  const _FeedTab({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(postsStreamProvider);
    final user = ref.watch(currentUserSyncProvider);

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: '무엇이든 물어보세요...',
                    hintStyle: const TextStyle(color: AppColors.textHint),
                    filled: true,
                    fillColor: BoardUi.listBackground,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send_rounded, color: AppColors.primary),
                onPressed: user == null
                    ? null
                    : () async {
                        final content = controller.text.trim();
                        if (content.isEmpty) return;
                        await ref.read(lmsRepositoryProvider).createPost(
                          cohortId: ref.read(effectiveCohortIdProvider)!,
                          authorId: user.uid,
                          authorName: user.displayName,
                          content: content,
                        );
                        controller.clear();
                      },
              ),
            ],
          ),
        ),
        Expanded(
          child: posts.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(message: e.toString()),
            data: (list) {
              if (list.isEmpty) {
                return const Center(
                  child: Text(
                    '게시글이 없습니다',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                itemCount: list.length,
                itemBuilder: (_, i) => _PostTile(post: list[i], ref: ref),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.post, required this.ref});
  final PostModel post;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserSyncProvider);
    final canDelete =
        user != null && (user.uid == post.authorId || user.isAdmin);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoardUi.cardDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.primaryLight,
                  child: Text(
                    post.authorName.isNotEmpty ? post.authorName[0] : '?',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  post.authorName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (canDelete)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: AppColors.textHint,
                    onPressed: () => ref.read(lmsRepositoryProvider).deletePost(
                      ref.read(effectiveCohortIdProvider)!,
                      post.id,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              post.content,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
