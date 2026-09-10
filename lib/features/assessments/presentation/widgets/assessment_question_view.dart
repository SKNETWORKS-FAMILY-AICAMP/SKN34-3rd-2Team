import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

enum AssessmentQuestionViewMode {
  /// 응시 — 선택 가능
  take,

  /// 결과/채점 — 선택·정답 표시
  review,

  /// 강사 미리보기 — 정답만 하이라이트
  preview,
}

/// 첨부 이미지 스타일의 문제 카드 (Q뱃지 + 보기 카드)
class AssessmentQuestionView extends StatelessWidget {
  const AssessmentQuestionView({
    super.key,
    required this.number,
    required this.prompt,
    required this.points,
    required this.type,
    this.choices = const [],
    this.correctIndex,
    this.acceptedAnswers = const [],
    this.explanation,
    this.selectedIndex,
    this.shortAnswer,
    this.onSelectChoice,
    this.onShortAnswerChanged,
    this.mode = AssessmentQuestionViewMode.take,
    this.earnedScore,
    this.isCorrect,
    this.footer,
  });

  final int number;
  final String prompt;
  final int points;
  final String type; // mc | sa
  final List<String> choices;
  final int? correctIndex;
  final List<String> acceptedAnswers;
  final String? explanation;
  final int? selectedIndex;
  final String? shortAnswer;
  final ValueChanged<int>? onSelectChoice;
  final ValueChanged<String>? onShortAnswerChanged;
  final AssessmentQuestionViewMode mode;
  final int? earnedScore;
  final bool? isCorrect;
  final Widget? footer;

  bool get _isMc => type == 'mc' || type == 'multipleChoice';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PromptCard(
          number: number,
          prompt: prompt,
          points: points,
          typeLabel: _isMc ? '객관식' : '단답',
          earnedScore: earnedScore,
          isCorrect: isCorrect,
          mode: mode,
        ),
        const SizedBox(height: 10),
        if (_isMc)
          ...List.generate(choices.length, (i) {
            return Padding(
              padding: EdgeInsets.only(bottom: i == choices.length - 1 ? 0 : 8),
              child: _ChoiceCard(
                letter: String.fromCharCode(65 + i),
                text: choices[i],
                state: _choiceState(i),
                onTap: mode == AssessmentQuestionViewMode.take &&
                        onSelectChoice != null
                    ? () => onSelectChoice!(i)
                    : null,
              ),
            );
          })
        else
          _ShortAnswerBlock(
            mode: mode,
            value: shortAnswer ?? '',
            acceptedAnswers: acceptedAnswers,
            isCorrect: isCorrect,
            onChanged: onShortAnswerChanged,
          ),
        if (explanation != null &&
            explanation!.trim().isNotEmpty &&
            mode != AssessmentQuestionViewMode.take) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline,
                    size: 16, color: Color(0xFFCA8A04)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    explanation!,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (footer != null) ...[
          const SizedBox(height: 10),
          footer!,
        ],
      ],
    );
  }

  _ChoiceVisualState _choiceState(int index) {
    switch (mode) {
      case AssessmentQuestionViewMode.take:
        return selectedIndex == index
            ? _ChoiceVisualState.selected
            : _ChoiceVisualState.idle;
      case AssessmentQuestionViewMode.preview:
        return correctIndex == index
            ? _ChoiceVisualState.correct
            : _ChoiceVisualState.idle;
      case AssessmentQuestionViewMode.review:
        final isCorrectChoice = correctIndex == index;
        final isSelected = selectedIndex == index;
        if (isCorrectChoice) return _ChoiceVisualState.correct;
        if (isSelected) return _ChoiceVisualState.wrong;
        return _ChoiceVisualState.idle;
    }
  }
}

enum _ChoiceVisualState { idle, selected, correct, wrong }

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.number,
    required this.prompt,
    required this.points,
    required this.typeLabel,
    required this.mode,
    this.earnedScore,
    this.isCorrect,
  });

  final int number;
  final String prompt;
  final int points;
  final String typeLabel;
  final AssessmentQuestionViewMode mode;
  final int? earnedScore;
  final bool? isCorrect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Q$number',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$typeLabel · $points점',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (mode == AssessmentQuestionViewMode.review &&
                  earnedScore != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isCorrect ?? earnedScore! > 0)
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$earnedScore / $points점',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: (isCorrect ?? earnedScore! > 0)
                          ? const Color(0xFF166534)
                          : const Color(0xFF991B1B),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            prompt,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.letter,
    required this.text,
    required this.state,
    this.onTap,
  });

  final String letter;
  final String text;
  final _ChoiceVisualState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, border, letterBg, letterFg, trailing) = switch (state) {
      _ChoiceVisualState.idle => (
          const Color(0xFFF9FAFB),
          AppColors.border,
          const Color(0xFFE5E7EB),
          AppColors.textSecondary,
          null as Widget?,
        ),
      _ChoiceVisualState.selected => (
          const Color(0xFFF0FDF4),
          const Color(0xFF22C55E),
          const Color(0xFF16A34A),
          Colors.white,
          const Icon(Icons.check, size: 20, color: Color(0xFF16A34A)),
        ),
      _ChoiceVisualState.correct => (
          const Color(0xFFF0FDF4),
          const Color(0xFF22C55E),
          const Color(0xFF16A34A),
          Colors.white,
          const Icon(Icons.check, size: 20, color: Color(0xFF16A34A)),
        ),
      _ChoiceVisualState.wrong => (
          const Color(0xFFFEF2F2),
          const Color(0xFFEF4444),
          const Color(0xFFDC2626),
          Colors.white,
          const Icon(Icons.close, size: 20, color: Color(0xFFDC2626)),
        ),
    };

    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: letterBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              letter,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: letterFg,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
                height: 1.35,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );

    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: child,
      ),
    );
  }
}

class _ShortAnswerBlock extends StatelessWidget {
  const _ShortAnswerBlock({
    required this.mode,
    required this.value,
    required this.acceptedAnswers,
    this.isCorrect,
    this.onChanged,
  });

  final AssessmentQuestionViewMode mode;
  final String value;
  final List<String> acceptedAnswers;
  final bool? isCorrect;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final reviewBorder = mode == AssessmentQuestionViewMode.review
        ? (isCorrect == true
            ? const Color(0xFF22C55E)
            : const Color(0xFFEF4444))
        : AppColors.border;
    final reviewBg = mode == AssessmentQuestionViewMode.review
        ? (isCorrect == true
            ? const Color(0xFFF0FDF4)
            : const Color(0xFFFEF2F2))
        : const Color(0xFFF9FAFB);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mode == AssessmentQuestionViewMode.take)
          TextField(
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: '답을 입력하세요',
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: reviewBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: reviewBorder, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mode == AssessmentQuestionViewMode.preview
                      ? '정답 후보'
                      : '내 답',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  mode == AssessmentQuestionViewMode.preview
                      ? (acceptedAnswers.isEmpty
                          ? '-'
                          : acceptedAnswers.join(', '))
                      : (value.trim().isEmpty ? '(미응답)' : value),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (mode == AssessmentQuestionViewMode.review &&
                    acceptedAnswers.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '정답: ${acceptedAnswers.join(', ')}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF166534),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
