import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/study_source_model.dart';

/// 학생이 볼 노트에서 git 커밋·빈 메타 문구를 가린다.
String sanitizeStudyNoteMarkdown(String raw) {
  final lines = <String>[];
  var skippingMetaQuote = false;
  final meta = RegExp(
    r'^(?:>\s*)?(\*\*)?(변경\s*커밋|커밋|commit|수업\s*날짜|수업\s*범위)\*?\*?\s*[:：]',
    caseSensitive: false,
  );

  for (final rawLine in raw.replaceAll('\r\n', '\n').split('\n')) {
    final stripped = rawLine.trim();
    final isMeta = meta.hasMatch(stripped);
    final unknown = stripped.contains('확인할 수 없음');
    if (stripped.startsWith('>') && (isMeta || unknown || skippingMetaQuote)) {
      skippingMetaQuote = true;
      continue;
    }
    skippingMetaQuote = false;
    if (isMeta || unknown) continue;
    if (RegExp(r'#+(\s*날짜별)?\s*수업\s*정리\s*$').hasMatch(stripped)) continue;
    lines.add(rawLine);
  }

  return lines
      .join('\n')
      .replaceAll(RegExp(r'`[0-9a-fA-F]{7,40}`'), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

class StudyNoteMarkdown extends StatelessWidget {
  const StudyNoteMarkdown({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final cleaned = sanitizeStudyNoteMarkdown(data);
    if (cleaned.isEmpty) {
      return const Text(
        '표시할 노트 내용이 없습니다.',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }
    return MarkdownBody(
      data: cleaned,
      selectable: true,
      softLineBreak: true,
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(
          fontSize: 15,
          height: 1.7,
          color: AppColors.textPrimary,
        ),
        pPadding: const EdgeInsets.only(bottom: 10),
        h1: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          height: 1.3,
          color: AppColors.textPrimary,
        ),
        h1Padding: const EdgeInsets.only(top: 8, bottom: 16),
        h2: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          height: 1.35,
          color: AppColors.textPrimary,
        ),
        h2Padding: const EdgeInsets.only(top: 28, bottom: 10),
        h3: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          height: 1.4,
          color: AppColors.textPrimary,
        ),
        h3Padding: const EdgeInsets.only(top: 18, bottom: 8),
        strong: const TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        em: const TextStyle(
          fontStyle: FontStyle.italic,
          color: AppColors.textPrimary,
        ),
        listBullet: const TextStyle(
          fontSize: 15,
          color: AppColors.primary,
        ),
        listIndent: 22,
        listBulletPadding: const EdgeInsets.only(right: 8),
        code: const TextStyle(
          fontSize: 13,
          fontFamily: 'Consolas',
          backgroundColor: AppColors.surfaceVariant,
          color: AppColors.textPrimary,
        ),
        codeblockPadding: const EdgeInsets.all(14),
        codeblockDecoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        blockquote: const TextStyle(
          fontSize: 15,
          height: 1.6,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        blockquoteDecoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(10),
          border: const Border(
            left: BorderSide(color: AppColors.primary, width: 3),
          ),
        ),
        horizontalRuleDecoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        tableHead: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        tableBody: const TextStyle(color: AppColors.textPrimary),
        tableBorder: TableBorder.all(color: AppColors.border, width: 0.6),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
      ),
    );
  }
}

class StudyNoteReader extends StatelessWidget {
  const StudyNoteReader({
    super.key,
    required this.note,
    this.sourceTitle,
    required this.onClose,
  });

  final StudyNoteModel note;
  final String? sourceTitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onClose,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('범위 다시 고르기'),
          ),
        ),
        Text(
          note.displayTitle,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1.3,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          [
            if (sourceTitle != null && sourceTitle!.isNotEmpty) sourceTitle,
            note.displaySubtitle,
          ].whereType<String>().join(' · '),
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        if (note.files.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final file in note.files)
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: AppColors.surfaceVariant,
                  side: const BorderSide(color: AppColors.border),
                  avatar: const Icon(
                    Icons.description_outlined,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  label: Text(
                    StudyNoteModel.fileNameOf(file.path),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: StudyNoteMarkdown(data: note.reportMarkdown),
        ),
        const SizedBox(height: 16),
        StudyReviewPanel(markdown: note.reviewMarkdown),
      ],
    );
  }
}

class StudyReviewPanel extends StatelessWidget {
  const StudyReviewPanel({super.key, required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final cleaned = sanitizeStudyNoteMarkdown(markdown);
    if (cleaned.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.quiz_outlined,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          title: const Text(
            '복습 문제로 확인하기',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text(
            '개념·코드 흐름·응용 문제와 해설',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: StudyNoteMarkdown(data: cleaned),
            ),
          ],
        ),
      ),
    );
  }
}
