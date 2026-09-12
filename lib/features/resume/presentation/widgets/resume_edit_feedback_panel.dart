import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../shared/models/resume_model.dart';
import '../../../../shared/providers/cohort_providers.dart';
import '../../../../shared/providers/lms_providers.dart';

/// 이력서 편집 — 피드백 사이드바 (2컬럼) / 하단 패널 (모바일)
class ResumeEditFeedbackPanel extends ConsumerStatefulWidget {
  const ResumeEditFeedbackPanel({
    super.key,
    required this.resumeId,
    required this.isAdmin,
    this.selectedSectionKey,
    this.completedSections = const {},
    this.isSidebar = false,
    this.showSectionSidebar = false,
    this.onSectionChanged,
    this.onClose,
  });

  final String resumeId;
  final bool isAdmin;
  final String? selectedSectionKey;
  final Map<String, bool> completedSections;
  final bool isSidebar;
  final bool showSectionSidebar;
  final ValueChanged<String>? onSectionChanged;

  /// 주면 머리말에 닫기 아이콘이 생긴다. 없으면 닫을 수 없는 자리라는 뜻이다.
  final VoidCallback? onClose;

  @override
  ConsumerState<ResumeEditFeedbackPanel> createState() =>
      _ResumeEditFeedbackPanelState();
}

class _ResumeEditFeedbackPanelState
    extends ConsumerState<ResumeEditFeedbackPanel> {
  final _contentController = TextEditingController();
  final _scrollController = ScrollController();
  late String _sectionKey;
  bool _isSubmitting = false;
  ResumeFeedbackModel? _replyTo;
  final _composerFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _sectionKey = _initialSection();
  }

  @override
  void didUpdateWidget(ResumeEditFeedbackPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedSectionKey != null &&
        widget.selectedSectionKey != oldWidget.selectedSectionKey) {
      _sectionKey = widget.selectedSectionKey!;
      _replyTo = null;
    }
  }

  String _initialSection() {
    if (widget.selectedSectionKey != null &&
        AppConstants.resumeSections.contains(widget.selectedSectionKey)) {
      return widget.selectedSectionKey!;
    }
    return AppConstants.resumeSections.first;
  }

  @override
  void dispose() {
    _contentController.dispose();
    _scrollController.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _contentController.text.trim();
    if (text.isEmpty) return;

    final user = ref.read(currentUserSyncProvider);
    final cohortId = ref.read(effectiveCohortIdProvider);
    if (user == null || cohortId == null) return;

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(lmsRepositoryProvider)
          .addResumeFeedback(
            cohortId: cohortId,
            resumeId: widget.resumeId,
            feedback: ResumeFeedbackModel(
              id: '',
              sectionKey: _sectionKey,
              content: text,
              authorName: user.displayName,
              authorId: user.uid,
              parentId: _replyTo?.id ?? '',
            ),
            authorId: user.uid,
            authorName: user.displayName,
          );
      _contentController.clear();
      if (mounted) setState(() => _replyTo = null);
      ref.invalidate(resumeFeedbackProvider(widget.resumeId));
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _selectSection(String sectionKey) {
    if (_sectionKey != sectionKey) setState(() => _sectionKey = sectionKey);
    widget.onSectionChanged?.call(sectionKey);
  }

  @override
  Widget build(BuildContext context) {
    final feedback = ref.watch(resumeFeedbackProvider(widget.resumeId));

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          isSidebar: widget.isSidebar,
          count: feedback.maybeWhen(
            data: (list) => widget.isAdmin
                ? list.where((item) => item.sectionKey == _sectionKey).length
                : list.length,
            orElse: () => 0,
          ),
          sectionKey: widget.isAdmin ? _sectionKey : null,
          onClose: widget.onClose,
        ),
        Expanded(
          child: feedback.when(
            loading: () => const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('오류: $e', style: const TextStyle(fontSize: 13)),
              ),
            ),
            data: (list) {
              final visible = widget.isAdmin
                  ? list
                        .where((item) => item.sectionKey == _sectionKey)
                        .toList()
                  : list;
              if (visible.isEmpty) {
                return Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      widget.isAdmin
                          ? '이 항목에 아직 피드백이 없습니다.\n아래 입력란에서 첫 피드백을 작성해 주세요.'
                          : '아직 피드백이 없습니다.\n관리자가 코멘트를 남기면 여기에 표시됩니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                );
              }

              final sorted = [...visible]
                ..sort((a, b) {
                  final at =
                      a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                  final bt =
                      b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                  return at.compareTo(bt);
                });
              final roots = threadRoots(sorted);

              return ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                itemCount: roots.length,
                itemBuilder: (_, i) {
                  final root = roots[i];
                  return Column(
                    children: [
                      _FeedbackCommentBubble(
                        feedback: root,
                        onReply: () {
                          setState(() => _replyTo = root);
                          _composerFocus.requestFocus();
                        },
                      ),
                      for (final reply in threadRepliesTo(sorted, root.id))
                        Padding(
                          padding: const EdgeInsets.only(left: 30),
                          child: _FeedbackCommentBubble(feedback: reply),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        if (widget.isAdmin)
          _FeedbackComposer(
            sectionKey: _sectionKey,
            controller: _contentController,
            focusNode: _composerFocus,
            replyTo: _replyTo,
            onCancelReply: () => setState(() => _replyTo = null),
            isSubmitting: _isSubmitting,
            showSectionPicker: !widget.showSectionSidebar,
            onSectionChanged: _selectSection,
            onSubmit: _submit,
          ),
      ],
    );
    final panel = Material(
      color: widget.isSidebar
          ? AppColors.surfaceVariant.withValues(alpha: 0.35)
          : AppColors.surface,
      child: widget.isAdmin && widget.showSectionSidebar
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FeedbackSectionSidebar(
                  selectedSectionKey: _sectionKey,
                  completedSections: widget.completedSections,
                  onSelected: _selectSection,
                ),
                VerticalDivider(width: 1, color: AppColors.border),
                Expanded(child: content),
              ],
            )
          : content,
    );

    if (widget.isSidebar) return panel;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: panel,
      ),
    );
  }
}

class _FeedbackSectionSidebar extends StatelessWidget {
  const _FeedbackSectionSidebar({
    required this.selectedSectionKey,
    required this.completedSections,
    required this.onSelected,
  });

  final String selectedSectionKey;
  final Map<String, bool> completedSections;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final primaryLight = Theme.of(context).colorScheme.primaryContainer;
    return SizedBox(
      width: 138,
      child: ColoredBox(
        color: AppColors.surface,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: Text(
                '이력서 항목',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            for (final key in AppConstants.resumeSections)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: key == selectedSectionKey
                      ? primaryLight
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: () => onSelected(key),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            completedSections[key] == true
                                ? Icons.check
                                : Icons.circle,
                            size: completedSections[key] == true ? 14 : 5,
                            color: completedSections[key] == true
                                ? AppColors.success
                                : (key == selectedSectionKey
                                      ? primary
                                      : AppColors.textHint),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              AppConstants.resumeSectionLabels[key] ?? key,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: key == selectedSectionKey
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: key == selectedSectionKey
                                    ? primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.isSidebar,
    required this.count,
    this.sectionKey,
    this.onClose,
  });

  final bool isSidebar;
  final int count;
  final String? sectionKey;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, isSidebar ? 16 : 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.chat_bubble_outline, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sectionKey == null ? '피드백' : '피드백 작성',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              if (sectionKey != null)
                Text(
                  '현재 항목 · ${AppConstants.resumeSectionLabels[sectionKey] ?? sectionKey}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
          if (onClose != null) ...[
            const Spacer(),
            IconButton(
              tooltip: '피드백 닫기',
              visualDensity: VisualDensity.compact,
              onPressed: onClose,
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeedbackCommentBubble extends StatelessWidget {
  const _FeedbackCommentBubble({required this.feedback, this.onReply});

  final ResumeFeedbackModel feedback;
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) {
    final initial = feedback.authorName.isNotEmpty
        ? feedback.authorName[0]
        : '?';
    final sectionLabel =
        AppConstants.resumeSectionLabels[feedback.sectionKey] ??
        feedback.sectionKey;
    final timeLabel = feedback.createdAt != null
        ? AppDateUtils.formatDateTime(feedback.createdAt!)
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primaryLight,
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      feedback.authorName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (timeLabel.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        timeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(10),
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          sectionLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        feedback.content,
                        style: const TextStyle(fontSize: 13, height: 1.45),
                      ),
                      if (onReply != null) ...[
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: onReply,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(32, 24),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            '답글',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ],
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

class _FeedbackComposer extends StatelessWidget {
  const _FeedbackComposer({
    required this.sectionKey,
    required this.controller,
    required this.focusNode,
    required this.replyTo,
    required this.onCancelReply,
    required this.isSubmitting,
    required this.showSectionPicker,
    required this.onSectionChanged,
    required this.onSubmit,
  });

  final String sectionKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ResumeFeedbackModel? replyTo;
  final VoidCallback onCancelReply;
  final bool isSubmitting;
  final bool showSectionPicker;
  final ValueChanged<String> onSectionChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showSectionPicker) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: AppConstants.resumeSections.map((key) {
                  final selected = key == sectionKey;
                  final label = AppConstants.resumeSectionLabels[key] ?? key;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(label, style: const TextStyle(fontSize: 11)),
                      selected: selected,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => onSectionChanged(key),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (replyTo != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${replyTo!.authorName}님의 피드백에 답글 작성 중',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onCancelReply,
                  child: const Text('취소'),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Focus(
                  onKeyEvent: (_, event) {
                    if (event is! KeyDownEvent ||
                        event.logicalKey != LogicalKeyboardKey.enter ||
                        HardwareKeyboard.instance.isShiftPressed) {
                      return KeyEventResult.ignored;
                    }
                    final composing = controller.value.composing;
                    if (composing.isValid && !composing.isCollapsed) {
                      return KeyEventResult.ignored;
                    }
                    onSubmit();
                    return KeyEventResult.handled;
                  },
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: replyTo == null
                          ? '피드백 입력 · Enter 전송 / Shift+Enter 줄바꿈'
                          : '답글 입력 · Enter 전송 / Shift+Enter 줄바꿈',
                      hintStyle: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textHint,
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceVariant,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: isSubmitting ? null : onSubmit,
                icon: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
