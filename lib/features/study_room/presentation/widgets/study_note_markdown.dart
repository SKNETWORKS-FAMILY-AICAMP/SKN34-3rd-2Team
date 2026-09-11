import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../../core/theme/app_colors.dart';

class StudyNoteMarkdown extends StatelessWidget {
  const StudyNoteMarkdown({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.textPrimary),
        h1: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        h2: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        h3: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        listBullet: const TextStyle(color: AppColors.textPrimary),
        code: const TextStyle(
          fontSize: 13,
          backgroundColor: AppColors.surfaceVariant,
          color: AppColors.textPrimary,
        ),
        codeblockDecoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        blockquote: const TextStyle(color: AppColors.textSecondary),
        horizontalRuleDecoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
      ),
    );
  }
}

class StudyReviewPanel extends StatelessWidget {
  const StudyReviewPanel({super.key, required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    if (markdown.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ExpansionTile(
        title: const Text(
          '정답 보기',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text('복습 문제와 해설'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: StudyNoteMarkdown(data: markdown),
          ),
        ],
      ),
    );
  }
}
