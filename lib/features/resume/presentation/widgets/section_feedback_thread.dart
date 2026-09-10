import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../shared/models/resume_model.dart';
import '../../../../shared/providers/cohort_providers.dart';
import '../../../../shared/providers/lms_providers.dart';

/// 이력서 항목 아래에 붙는 댓글.
///
/// 옆에 붙은 사이드바 대신 **그 항목 바로 밑에서** 읽고 쓴다. 어느 대목에 대한 말인지
/// 눈을 옮겨 맞출 필요가 없고, 강사가 섹션을 고를 일도 없다 — 연 자리가 곧 섹션이다.
///
/// 읽음은 **펼쳐서 화면에 보인 것만** 넘어간다. 접힌 채로는 줄지 않는다.
class SectionFeedbackThread extends ConsumerStatefulWidget {
  const SectionFeedbackThread({
    super.key,
    required this.resume,
    required this.sectionKey,
    required this.expanded,
    required this.onToggle,
  });

  final ResumeModel resume;
  final String sectionKey;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  ConsumerState<SectionFeedbackThread> createState() =>
      _SectionFeedbackThreadState();
}

class _SectionFeedbackThreadState extends ConsumerState<SectionFeedbackThread> {
  final _input = TextEditingController();
  bool _sending = false;

  /// 이미 읽음으로 넘긴 피드백. 다시 넘기지 않는다.
  ///
  /// 읽음 처리는 그리는 중에 예약된다. 쓰기가 막히거나(권한) 스트림이 늦으면 안 읽음이
  /// 그대로 남아, 다시 그릴 때마다 같은 쓰기를 또 보낸다. 이력서 편집 화면은 키 입력마다
  /// 다시 그리므로 글자 하나에 쓰기 한 번이 나간다.
  final Set<String> _marked = {};

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _markRead(List<ResumeFeedbackModel> unread) async {
    final ids = [
      for (final f in unread)
        if (_marked.add(f.id)) f.id,
    ];
    if (ids.isEmpty) return;
    final cohortId = ref.read(effectiveCohortIdProvider);
    if (cohortId == null) return;
    await ref.read(lmsRepositoryProvider).markResumeFeedbackRead(
          cohortId: cohortId,
          resumeId: widget.resume.id,
          feedbackIds: ids,
          asReviewer: ref.read(canReviewResumesProvider),
        );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final user = ref.read(currentUserSyncProvider);
    final cohortId = ref.read(effectiveCohortIdProvider);
    if (user == null || cohortId == null) return;

    setState(() => _sending = true);
    try {
      await ref.read(lmsRepositoryProvider).addResumeFeedback(
            cohortId: cohortId,
            resumeId: widget.resume.id,
            authorId: user.uid,
            authorName: user.displayName,
            feedback: ResumeFeedbackModel(
              id: '',
              sectionKey: widget.sectionKey,
              content: text,
              authorName: user.displayName,
              authorId: user.uid,
            ),
          );
      _input.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('등록 실패: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(resumeFeedbackProvider(widget.resume.id)).maybeWhen(
          data: (list) => list,
          orElse: () => const <ResumeFeedbackModel>[],
        );
    final items = [
      for (final f in all)
        if (f.sectionKey == widget.sectionKey) f,
    ];
    final asReviewer = ref.watch(canReviewResumesProvider);
    final unread =
        unreadFeedback(items, widget.resume,
            asReviewer: asReviewer,
            viewerId: ref.watch(currentUserSyncProvider)?.uid);

    if (widget.expanded && unread.isNotEmpty) {
      // 화면에 보였으니 읽은 것이다. 그리는 중에 쓰지 않도록 프레임 뒤로 미룬다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _markRead(unread);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _ThreadChip(
          count: items.length,
          unread: unread.length,
          open: widget.expanded,
          onTap: widget.onToggle,
        ),
        if (widget.expanded) ...[
          const SizedBox(height: 8),
          _panel(items, unread, asReviewer),
        ],
      ],
    );
  }

  Widget _panel(
    List<ResumeFeedbackModel> items,
    List<ResumeFeedbackModel> unread,
    bool asReviewer,
  ) {
    final unreadIds = {for (final f in unread) f.id};
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFE),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (items.isEmpty)
            const Text(
              '아직 이 항목에 남긴 피드백이 없습니다.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textHint),
            )
          else
            for (final item in items)
              _Comment(
                item: item,
                isNew: unreadIds.contains(item.id),
                mine: item.isReplyOn(widget.resume) != asReviewer,
              ),
          const SizedBox(height: 10),
          _composer(asReviewer),
        ],
      ),
    );
  }

  Widget _composer(bool asReviewer) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _input,
            minLines: 1,
            maxLines: 4,
            enabled: !_sending,
            textInputAction: TextInputAction.newline,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              hintText: asReviewer ? '이 항목에 대한 피드백을 적어 주세요' : '답글을 적어 주세요',
              hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.textHint),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: '등록',
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send, size: 17),
        ),
      ],
    );
  }
}

/// 항목 머리에 붙는 알약. 접혀 있을 때 여기만 보인다.
class _ThreadChip extends StatelessWidget {
  const _ThreadChip({
    required this.count,
    required this.unread,
    required this.open,
    required this.onTap,
  });

  final int count;
  final int unread;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final has = count > 0;
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: has ? const Color(0xFFF4F8FF) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: has ? const Color(0xFFC9DBFF) : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (unread > 0) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Icon(
                  Icons.mode_comment_outlined,
                  size: 14,
                  color: has ? AppColors.primary : AppColors.textSecondary,
                ),
                const SizedBox(width: 5),
                Text(
                  has ? '피드백 $count' : '피드백',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: has ? FontWeight.w500 : FontWeight.w400,
                    color: has ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  open ? Icons.expand_less : Icons.expand_more,
                  size: 15,
                  color: has ? AppColors.primary : AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Comment extends StatelessWidget {
  const _Comment({required this.item, required this.isNew, required this.mine});

  final ResumeFeedbackModel item;
  final bool isNew;

  /// 내가 쓴 글인가. 내 글은 안 읽음 표시가 붙지 않는다.
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final initial = item.authorName.characters.isEmpty
        ? '?'
        : item.authorName.characters.last;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: mine ? const Color(0xFFEAF7EE) : AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: mine ? AppColors.success : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.authorName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    if (item.createdAt != null)
                      Text(
                        AppDateUtils.formatDateTime(item.createdAt!),
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textHint,
                        ),
                      ),
                    if (isNew) ...[
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDECEC),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '새 글',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  item.content,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.55,
                    color: Color(0xFF374151),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
