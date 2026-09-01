import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/models/notice_model.dart';
import '../../../shared/models/post_model.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../../shared/providers/lms_providers.dart';

/// 게시판 — 공지 + 소통 피드 탭
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
    final isAdmin = ref.watch(isAdminProvider);

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '공지사항'),
            Tab(text: '소통 피드'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _NoticesTab(isAdmin: isAdmin),
              _FeedTab(controller: _postController),
            ],
          ),
        ),
      ],
    );
  }
}

class _NoticesTab extends ConsumerWidget {
  const _NoticesTab({required this.isAdmin});
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(noticesStreamProvider);

    return notices.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('공지사항이 없습니다'),
                if (isAdmin) ...[
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _showNoticeDialog(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('공지 작성'),
                  ),
                ],
              ],
            ),
          );
        }
        return Column(
          children: [
            if (isAdmin)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextButton.icon(
                    onPressed: () => _showNoticeDialog(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('공지 작성'),
                  ),
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                itemBuilder: (_, i) => _NoticeTile(notice: list[i]),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showNoticeDialog(BuildContext context, WidgetRef ref) async {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    var isPinned = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('공지 작성'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: '제목'),
                ),
                TextField(
                  controller: contentCtrl,
                  decoration: const InputDecoration(labelText: '내용'),
                  maxLines: 4,
                ),
                CheckboxListTile(
                  value: isPinned,
                  title: const Text('필독 공지 고정'),
                  onChanged: (v) => setState(() => isPinned = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
            ElevatedButton(
              onPressed: () async {
                final user = ref.read(currentUserSyncProvider)!;
                final cohortId = ref.read(effectiveCohortIdProvider)!;
                await ref.read(lmsRepositoryProvider).createNotice(
                  cohortId: cohortId,
                  notice: NoticeModel(
                    id: '',
                    title: titleCtrl.text,
                    content: contentCtrl.text,
                    authorName: user.displayName,
                    isPinned: isPinned,
                  ),
                  authorId: user.uid,
                  authorName: user.displayName,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('등록'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeTile extends StatelessWidget {
  const _NoticeTile({required this.notice});
  final NoticeModel notice;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: notice.isPinned
            ? const Icon(Icons.push_pin, color: AppColors.primary)
            : Icon(
                notice.isFromDiscord
                    ? Icons.discord
                    : Icons.campaign_outlined,
                color: notice.isFromDiscord
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                notice.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (notice.channelLabel != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  notice.channelLabel!,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          notice.content,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
      ),
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
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: '무엇이든 물어보세요...',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: AppColors.primary),
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
                return const Center(child: Text('게시글이 없습니다'));
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
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
                    style: const TextStyle(color: AppColors.primary, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Text(post.authorName, style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                if (canDelete)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => ref.read(lmsRepositoryProvider).deletePost(
                      ref.read(effectiveCohortIdProvider)!,
                      post.id,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(post.content),
          ],
        ),
      ),
    );
  }
}
