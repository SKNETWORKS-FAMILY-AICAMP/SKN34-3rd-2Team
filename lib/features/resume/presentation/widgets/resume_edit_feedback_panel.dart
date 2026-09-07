import 'package:flutter/material.dart';
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
    this.isSidebar = false,
  });

  final String resumeId;
  final bool isAdmin;
  final String? selectedSectionKey;
  final bool isSidebar;

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
      setState(() => _sectionKey = widget.selectedSectionKey!);
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
      await ref.read(lmsRepositoryProvider).addResumeFeedback(
            cohortId: cohortId,
            resumeId: widget.resumeId,
            feedback: ResumeFeedbackModel(
              id: '',
              sectionKey: _sectionKey,
              content: text,
              authorName: user.displayName,
            ),
            authorId: user.uid,
            authorName: user.displayName,
          );
      _contentController.clear();
      ref.invalidate(resumeFeedbackProvider(widget.resumeId));
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedback = ref.watch(resumeFeedbackProvider(widget.resumeId));

    final panel = Material(
      color: widget.isSidebar
          ? AppColors.surfaceVariant.withValues(alpha: 0.35)
          : AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            isSidebar: widget.isSidebar,
            count: feedback.maybeWhen(data: (l) => l.length, orElse: () => 0),
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
                if (list.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        '아직 피드백이 없습니다.\n관리자가 코멘트를 남기면 여기에 표시됩니다.',
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

                final sorted = [...list]
                  ..sort((a, b) {
                    final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                    final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                    return bt.compareTo(at);
                  });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  itemCount: sorted.length,
                  itemBuilder: (_, i) => _FeedbackCommentBubble(
                    feedback: sorted[i],
                  ),
                );
              },
            ),
          ),
          if (widget.isAdmin)
            _FeedbackComposer(
              sectionKey: _sectionKey,
              controller: _contentController,
              isSubmitting: _isSubmitting,
              onSectionChanged: (v) => setState(() => _sectionKey = v),
              onSubmit: _submit,
            ),
        ],
      ),
    );

    if (widget.isSidebar) return panel;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: panel,
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.isSidebar, required this.count});

  final bool isSidebar;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, isSidebar ? 16 : 12, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.chat_bubble_outline, size: 18),
          const SizedBox(width: 8),
          const Text(
            '피드백',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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
        ],
      ),
    );
  }
}

class _FeedbackCommentBubble extends StatelessWidget {
  const _FeedbackCommentBubble({required this.feedback});

  final ResumeFeedbackModel feedback;

  @override
  Widget build(BuildContext context) {
    final initial =
        feedback.authorName.isNotEmpty ? feedback.authorName[0] : '?';
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
                        style: const TextStyle(
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
                          style: const TextStyle(
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
    required this.isSubmitting,
    required this.onSectionChanged,
    required this.onSubmit,
  });

  final String sectionKey;
  final TextEditingController controller;
  final bool isSubmitting;
  final ValueChanged<String> onSectionChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '피드백을 입력하세요...',
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textHint,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) => onSubmit(),
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
