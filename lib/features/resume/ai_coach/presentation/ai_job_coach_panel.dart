import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/resume_content.dart';
import '../../../../shared/providers/cohort_providers.dart';
import '../data/ai_job_coach_repository.dart';
import '../data/job_search.dart';
import '../data/resume_analyzer.dart';
import '../models/ai_job_coach_result.dart';
import '../models/collected_job.dart';
import '../models/resume_readiness.dart';

class AiJobCoachPanel extends ConsumerStatefulWidget {
  const AiJobCoachPanel({
    super.key,
    required this.resumeId,
    required this.draftContent,
    required this.isSidebar,
    required this.onClose,
  });

  final String resumeId;
  final ResumeContent draftContent;
  final bool isSidebar;
  final VoidCallback onClose;

  @override
  ConsumerState<AiJobCoachPanel> createState() => _AiJobCoachPanelState();
}

/// 챗봇 대화 한 줄.
class _ChatMessage {
  const _ChatMessage.user(this.text) : isUser = true, jobs = const [];
  const _ChatMessage.bot(this.text, {this.jobs = const []}) : isUser = false;

  final String text;
  final bool isUser;
  final List<CollectedJob> jobs;
}

class _AiJobCoachPanelState extends ConsumerState<AiJobCoachPanel> {
  final Set<String> _confirmedMissingSkills = {};
  final TextEditingController _chatController = TextEditingController();
  final List<_ChatMessage> _messages = [
    const _ChatMessage.bot(
      '어떤 채용공고를 찾아드릴까요? "백엔드 신입", "서울 AI 엔지니어"처럼 물어보세요.',
    ),
  ];
  AiJobCoachResult? _result;
  ResumeAnalysis? _resumeAnalysis;
  bool _chatMode = false;
  bool _loading = false;
  String? _error;

  ResumeReadiness get _readiness => ResumeReadiness.of(widget.draftContent);

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  /// 조건을 못 갖춘 기능은 실행하지 않고 이유만 보여준다.
  bool _guard(AiCoachFeature feature) {
    final reason = _readiness.blockedReason(feature);
    if (reason == null) return true;
    setState(() {
      _result = null;
      _resumeAnalysis = null;
      _error = reason;
    });
    return false;
  }

  void _analyzeResumeOnly() {
    if (!_guard(AiCoachFeature.resumeAnalysis)) return;
    setState(() {
      _error = null;
      _result = null;
      _resumeAnalysis = analyzeResume(widget.draftContent);
    });
  }

  void _openChat() {
    setState(() {
      _chatMode = true;
      _error = null;
    });
  }

  void _sendChatMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    final result = searchJobs(text);
    setState(() {
      _messages.add(_ChatMessage.user(text));
      _messages.add(
        result.jobs.isEmpty
            ? _ChatMessage.bot(
                '조건에 맞는 IT 공고를 찾지 못했습니다.\n'
                '검색 조건: ${result.query.summary}',
              )
            : _ChatMessage.bot(
                '${result.jobs.length}건을 찾았습니다.\n'
                '검색 조건: ${result.query.summary}',
                jobs: result.jobs,
              ),
      );
      _chatController.clear();
    });
  }

  Future<void> _run() async {
    if (!_guard(AiCoachFeature.jobRecommendation)) return;
    setState(() => _resumeAnalysis = null);

    final cohortId = ref.read(effectiveCohortIdProvider);
    if (cohortId == null && !AiJobCoachConfig.useLocalFixture) {
      setState(() => _error = '분석할 기수 정보를 찾지 못했습니다.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(aiJobCoachRepositoryProvider)
          .analyzeAndMatch(
            cohortId: cohortId ?? 'local-fixture',
            resumeId: widget.resumeId,
            draftContent: widget.draftContent,
            confirmedMissingSkills: _confirmedMissingSkills,
          );
      if (mounted) setState(() => _result = result);
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        setState(() => _error = error.message ?? 'AI 코치 요청에 실패했습니다.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '분석 실패: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmMissing(String skill) async {
    _confirmedMissingSkills.add(skill);
    await _run();
  }

  void _hasExperience(String skill) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$skill 경험을 기술스택 또는 프로젝트에 반영한 뒤 재분석해주세요.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final panel = Material(
      color: widget.isSidebar
          ? AppColors.surfaceVariant.withValues(alpha: 0.45)
          : AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            onClose: widget.onClose,
            chatMode: _chatMode,
            onToggleChat: () => setState(() => _chatMode = !_chatMode),
          ),
          if (_chatMode)
            Expanded(
              child: _ChatView(
                messages: _messages,
                controller: _chatController,
                onSend: _sendChatMessage,
              ),
            )
          else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                if (AiJobCoachConfig.useLocalFixture) const _TestModeBanner(),
                const SizedBox(height: 10),
                _ReadinessCard(
                  readiness: _readiness,
                  onSearchTap: _openChat,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ActionButton(
                      icon: Icons.description_outlined,
                      label: '이력서 분석',
                      loading: _loading,
                      // 분석할 내용이 하나라도 있으면 실행할 수 있다.
                      enabled: _readiness.canAnalyzeResume,
                      disabledTooltip: _readiness.blockedReason(
                        AiCoachFeature.resumeAnalysis,
                      ),
                      onPressed: _analyzeResumeOnly,
                    ),
                    _ActionButton(
                      icon: Icons.track_changes_outlined,
                      label: '맞춤 공고 추천',
                      loading: _loading,
                      // 필수 항목이 하나라도 비면 추천하지 않는다.
                      enabled: _readiness.canRecommendJobs,
                      disabledTooltip: _readiness.blockedReason(
                        AiCoachFeature.jobRecommendation,
                      ),
                      onPressed: _run,
                    ),
                    _ActionButton(
                      icon: Icons.chat_bubble_outline,
                      label: '채용공고 찾기',
                      loading: false,
                      // 공고 검색은 이력서 상태와 무관하다.
                      enabled: true,
                      disabledTooltip: null,
                      onPressed: _openChat,
                    ),
                  ],
                ),
                if (_loading) ...[
                  const SizedBox(height: 20),
                  const LinearProgressIndicator(minHeight: 3),
                  const SizedBox(height: 8),
                  const Text(
                    '이력서 근거와 채용 조건을 비교하고 있습니다…',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _ErrorCard(message: _error!),
                ],
                if (_resumeAnalysis case final analysis?) ...[
                  const SizedBox(height: 18),
                  _ResumeAnalysisSection(analysis: analysis),
                ],
                if (_result == null &&
                    _resumeAnalysis == null &&
                    !_loading &&
                    _error == null) ...[
                  const SizedBox(height: 26),
                  const _EmptyState(),
                ],
                if (_result case final result?) ...[
                  const SizedBox(height: 18),
                  _RecommendationSection(result: result),
                  const SizedBox(height: 18),
                  _SkillEvidenceSection(
                    judgements: result.skillJudgements,
                    loading: _loading,
                    onConfirmedMissing: _confirmMissing,
                    onHasExperience: _hasExperience,
                  ),
                  const SizedBox(height: 18),
                  _FeedbackSection(feedback: result.resumeFeedback),
                  const SizedBox(height: 18),
                  _LearningSection(items: result.learningRecommendations),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (widget.isSidebar) return panel;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 430),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: panel,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onClose,
    required this.chatMode,
    required this.onToggleChat,
  });

  final VoidCallback onClose;
  final bool chatMode;
  final VoidCallback onToggleChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFFEDE9FE),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 17,
              color: Color(0xFF7C3AED),
            ),
          ),
          const SizedBox(width: 9),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI 취업 코치',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                Text(
                  '근거 기반 공고 매칭 POC',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: chatMode ? '코치 기능으로 돌아가기' : '챗봇으로 채용공고 찾기',
            visualDensity: VisualDensity.compact,
            onPressed: onToggleChat,
            icon: Icon(
              chatMode ? Icons.arrow_back : Icons.chat_bubble_outline,
              size: 18,
              color: chatMode ? AppColors.textSecondary : const Color(0xFF7C3AED),
            ),
          ),
          IconButton(
            tooltip: 'AI 코치 닫기',
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

class _TestModeBanner extends StatelessWidget {
  const _TestModeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border.all(color: const Color(0xFFFDE68A)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, size: 17, color: AppColors.warning),
          SizedBox(width: 7),
          Expanded(
            child: Text(
              'IT 전용 테스트 모드: 현재 이력서와 IT POC 공고만 비교합니다. 표시 점수는 합격 확률이 아닙니다.',
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: Color(0xFF92400E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.loading,
    required this.enabled,
    required this.disabledTooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool loading;
  final bool enabled;

  /// 왜 지금 누를 수 없는지. 비활성일 때만 쓴다.
  final String? disabledTooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.icon(
      onPressed: (loading || !enabled) ? null : onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      ),
    );
    if (enabled || disabledTooltip == null) return button;
    // 비활성 버튼은 툴팁을 받지 못하므로 감싸서 이유를 보여준다.
    return Tooltip(
      message: disabledTooltip!,
      child: button,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Icon(Icons.hub_outlined, size: 42, color: AppColors.textHint),
        SizedBox(height: 12),
        Text(
          '이력서와 채용공고를 연결해볼까요?',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        SizedBox(height: 6),
        Text(
          '분석 버튼을 누르면 명시 조건, 추천 순위,\nSkill Gap을 한 번에 확인합니다.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _RecommendationSection extends StatelessWidget {
  const _RecommendationSection({required this.result});

  final AiJobCoachResult result;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '맞춤 공고 Ranking',
      subtitle: result.notice,
      child: Column(
        children: [
          for (var index = 0; index < result.recommendations.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RecommendationCard(
                index: index + 1,
                item: result.recommendations[index],
              ),
            ),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.index, required this.item});

  final int index;
  final JobRecommendation item;

  Future<void> _open() async {
    final uri = Uri.tryParse(item.sourceUrl);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLink = item.sourceUrl.startsWith('http');
    return InkWell(
      onTap: hasLink ? _open : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: AppColors.primaryLight,
              child: Text('$index', style: const TextStyle(fontSize: 11)),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${item.company} · ${item.source}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (item.evidence.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      '근거: ${item.evidence.take(5).join(', ')}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.info,
                      ),
                    ),
                  ],
                  if (item.unknownConditions.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '확인 필요: ${item.unknownConditions.join(', ')}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${item.score.toStringAsFixed(1)}점',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  item.grade,
                  style: TextStyle(
                    fontSize: 10,
                    color: item.grade == '높음'
                        ? AppColors.success
                        : AppColors.textSecondary,
                  ),
                ),
                if (hasLink)
                  const Icon(
                    Icons.open_in_new,
                    size: 13,
                    color: AppColors.textHint,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SkillEvidenceSection extends StatelessWidget {
  const _SkillEvidenceSection({
    required this.judgements,
    required this.loading,
    required this.onConfirmedMissing,
    required this.onHasExperience,
  });

  final List<SkillJudgement> judgements;
  final bool loading;
  final Future<void> Function(String skill) onConfirmedMissing;
  final ValueChanged<String> onHasExperience;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Skill Evidence',
      subtitle: '근거 없음은 경험 없음으로 단정하지 않습니다.',
      child: Column(
        children: judgements
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SkillEvidenceCard(
                  item: item,
                  loading: loading,
                  onConfirmedMissing: onConfirmedMissing,
                  onHasExperience: onHasExperience,
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _SkillEvidenceCard extends StatelessWidget {
  const _SkillEvidenceCard({
    required this.item,
    required this.loading,
    required this.onConfirmedMissing,
    required this.onHasExperience,
  });

  final SkillJudgement item;
  final bool loading;
  final Future<void> Function(String skill) onConfirmedMissing;
  final ValueChanged<String> onHasExperience;

  @override
  Widget build(BuildContext context) {
    final color = switch (item.judgement) {
      'EVIDENCED' => AppColors.success,
      'CONFIRMED_MISSING' => AppColors.error,
      _ => AppColors.warning,
    };
    final label = switch (item.judgement) {
      'EVIDENCED' => '근거 확인',
      'CONFIRMED_MISSING' => '경험 없음 확인',
      _ => '근거 불충분',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${item.criterion} · ${_requirementLabel(item.requirementType)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(label, style: TextStyle(fontSize: 9, color: color)),
              ),
            ],
          ),
          if (item.resumeEvidence.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              item.resumeEvidence.join('\n'),
              style: const TextStyle(
                fontSize: 10,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (item.judgement == 'NOT_EVIDENCED') ...[
            const SizedBox(height: 7),
            Text(
              item.confirmationQuestion ?? '',
              style: const TextStyle(fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              children: [
                OutlinedButton(
                  onPressed: loading
                      ? null
                      : () => onHasExperience(item.criterion),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                  ),
                  child: const Text('경험 있음', style: TextStyle(fontSize: 10)),
                ),
                OutlinedButton(
                  onPressed: loading
                      ? null
                      : () => onConfirmedMissing(item.criterion),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                  ),
                  child: const Text('경험 없음', style: TextStyle(fontSize: 10)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FeedbackSection extends StatelessWidget {
  const _FeedbackSection({required this.feedback});

  final List<String> feedback;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Resume Feedback',
      subtitle: 'AI가 이력서를 직접 수정하지 않고 보강 지점만 안내합니다.',
      child: feedback.isEmpty
          ? const _MutedText('현재 자동 피드백이 없습니다.')
          : Column(
              children: feedback
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: _BulletText(item),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _LearningSection extends StatelessWidget {
  const _LearningSection({required this.items});

  final List<LearningRecommendation> items;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Learning Recommendation',
      subtitle: '사용자가 경험 없음으로 확인한 역량만 추천합니다.',
      child: items.isEmpty
          ? const _MutedText('확정된 학습 필요 역량이 없습니다.')
          : Column(
              children: items
                  .map(
                    (item) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.school_outlined, size: 18),
                      title: Text(
                        item.title,
                        style: const TextStyle(fontSize: 11),
                      ),
                      subtitle: Text(
                        '${item.skill} · ${item.level} · ${item.estimatedDuration}\n${item.provider}',
                        style: const TextStyle(fontSize: 10),
                      ),
                      trailing: const Icon(Icons.open_in_new, size: 14),
                      onTap: () async {
                        final uri = Uri.tryParse(item.url);
                        if (uri != null) await launchUrl(uri);
                      },
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 10,
              height: 1.35,
              color: AppColors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 9),
        child,
      ],
    );
  }
}

class _BulletText extends StatelessWidget {
  const _BulletText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 5),
          child: Icon(Icons.circle, size: 5, color: AppColors.info),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 11, height: 1.4)),
        ),
      ],
    );
  }
}

class _MutedText extends StatelessWidget {
  const _MutedText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 17, color: AppColors.error),
          const SizedBox(width: 7),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 11))),
        ],
      ),
    );
  }
}

/// 필수 항목을 얼마나 채웠는지, 지금 무엇을 할 수 있는지 알려준다.
class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.readiness, required this.onSearchTap});

  final ResumeReadiness readiness;
  final VoidCallback onSearchTap;

  @override
  Widget build(BuildContext context) {
    final ready = readiness.canRecommendJobs;
    final progress =
        readiness.completedRequiredCount / readiness.totalRequiredCount;

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: ready
            ? AppColors.success.withValues(alpha: 0.08)
            : AppColors.surfaceVariant.withValues(alpha: 0.6),
        border: Border.all(
          color: ready
              ? AppColors.success.withValues(alpha: 0.35)
              : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ready ? Icons.check_circle_outline : Icons.edit_note,
                size: 16,
                color: ready ? AppColors.success : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ready
                      ? '맞춤 공고 추천을 실행할 수 있습니다.'
                      : '필수 항목 ${readiness.completedRequiredCount}/${readiness.totalRequiredCount} 작성됨',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(
                ready ? AppColors.success : AppColors.primary,
              ),
            ),
          ),
          if (!ready) ...[
            const SizedBox(height: 8),
            Text(
              '남은 항목: ${readiness.missingRequiredSectionLabels.join(', ')}',
              style: const TextStyle(
                fontSize: 11,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            // 이력서를 다 못 채웠어도 공고 검색은 막지 않는다.
            InkWell(
              onTap: onSearchTap,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '먼저 채용공고만 둘러보기 →',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF7C3AED),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 공고 없이 이력서 자체만 본 분석 결과.
class _ResumeAnalysisSection extends StatelessWidget {
  const _ResumeAnalysisSection({required this.analysis});

  final ResumeAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '이력서 분석',
      subtitle: 'AI가 문장을 대신 고치지 않고 보완할 지점만 알려줍니다.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (analysis.strengths.isNotEmpty) ...[
            const _AnalysisLabel('강점', AppColors.success),
            for (final item in analysis.strengths) _BulletText(item),
            const SizedBox(height: 10),
          ],
          if (analysis.improvements.isNotEmpty) ...[
            const _AnalysisLabel('보완 필요', AppColors.warning),
            for (final item in analysis.improvements) _BulletText(item),
            const SizedBox(height: 10),
          ],
          if (analysis.nextSteps.isNotEmpty) ...[
            const _AnalysisLabel('다음 단계', AppColors.primary),
            for (final item in analysis.nextSteps) _BulletText(item),
          ],
        ],
      ),
    );
  }
}

class _AnalysisLabel extends StatelessWidget {
  const _AnalysisLabel(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// 챗봇으로 채용공고를 찾는 화면.
class _ChatView extends StatelessWidget {
  const _ChatView({
    required this.messages,
    required this.controller,
    required this.onSend,
  });

  final List<_ChatMessage> messages;
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: messages.length,
            itemBuilder: (context, index) =>
                _ChatBubble(message: messages[index]),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: '예: 백엔드 신입 공고 찾아줘',
                    hintStyle: TextStyle(fontSize: 12),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: '검색',
                onPressed: onSend,
                icon: const Icon(Icons.send, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: message.isUser
              ? AppColors.primaryLight
              : AppColors.surfaceVariant.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
            for (final job in message.jobs) ...[
              const SizedBox(height: 8),
              _ChatJobCard(job: job),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChatJobCard extends StatelessWidget {
  const _ChatJobCard({required this.job});

  final CollectedJob job;

  Future<void> _open() async {
    final uri = Uri.tryParse(job.sourceUrl);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skills = [...job.requiredSkills, ...job.preferredSkills];
    final hasLink = job.sourceUrl.startsWith('http');
    return InkWell(
      onTap: hasLink ? _open : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              job.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            Text(
              '${job.company} · ${job.region} · ${job.careerLabel}',
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textSecondary,
              ),
            ),
            if (skills.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                skills.take(5).join(' · '),
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.primary,
                ),
              ),
            ],
            if (hasLink) ...[
              const SizedBox(height: 5),
              const Text(
                '공고 보기 →',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF7C3AED),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 요구 유형 라벨. DECLARED는 기업이 공고 등록 때 고른 기술스택 태그라
/// 필수·우대 어느 쪽도 아니다.
String _requirementLabel(String requirementType) {
  switch (requirementType) {
    case 'REQUIRED':
      return '필수';
    case 'PREFERRED':
      return '우대';
    case 'DECLARED':
      return '기술스택';
    default:
      return requirementType;
  }
}
