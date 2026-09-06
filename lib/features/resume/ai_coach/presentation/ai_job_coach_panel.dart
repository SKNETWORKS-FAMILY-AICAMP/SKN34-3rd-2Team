import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/job_preferences.dart';
import '../../../../shared/models/resume_content.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../../../shared/providers/cohort_providers.dart';
import '../data/ai_job_coach_repository.dart';
import '../data/job_search.dart';
import '../data/local_job_matcher.dart';
import '../data/resume_analysis_repository.dart';
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

  /// 취업 희망 조건은 이력서가 아니라 프로필(`users/{uid}.jobPreferences`)에 있다.
  JobPreferences get _preferences =>
      ref.read(currentUserProvider).value?.jobPreferences ??
      const JobPreferences();

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

  /// 이력서 분석. cover_letter_rag 서버가 설정돼 있으면 서버 근거 기반 분석을,
  /// 아니면 앱 안의 규칙 기반 분석을 보여준다. 서버 실패 시에도 규칙 기반
  /// 결과로 대체하고 그 이유를 함께 표시한다.
  Future<void> _analyzeResumeOnly() async {
    if (!_guard(AiCoachFeature.resumeAnalysis)) return;
    setState(() {
      _error = null;
      _result = null;
      _resumeAnalysis = null;
      _loading = true;
    });
    try {
      final analysis = await ref
          .read(resumeAnalysisRepositoryProvider)
          .analyze(widget.draftContent);
      if (mounted) setState(() => _resumeAnalysis = analysis);
    } catch (error) {
      if (mounted) setState(() => _error = '이력서 분석 실패: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
            preferences: _preferences,
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
                  preferences:
                      ref.watch(currentUserProvider).value?.jobPreferences ??
                      const JobPreferences(),
                  onEditPreferences: () => context.push(RoutePaths.myPage),
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
                  // 기술 근거·이력서 피드백·학습 추천 섹션은 cover_letter_rag
                  // 기반 첨삭으로 대체할 예정이라 제거했다. 데이터는 Functions
                  // 응답에 그대로 남아 있다.
                  _RecommendationSection(result: result),
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

class _RecommendationCard extends StatefulWidget {
  const _RecommendationCard({required this.index, required this.item});

  final int index;
  final JobRecommendation item;

  @override
  State<_RecommendationCard> createState() => _RecommendationCardState();
}

class _RecommendationCardState extends State<_RecommendationCard> {
  bool _expanded = false;

  JobRecommendation get item => widget.item;

  Future<void> _open() async {
    final uri = Uri.tryParse(item.sourceUrl);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// 접힌 상태에서도 왜 이 순위인지 한 줄로 보이게 한다.
  String _summary() {
    String bucket(String label, List<String> matched, List<String> unmatched) =>
        '$label ${matched.length}/${matched.length + unmatched.length}';
    final hasBuckets = item.matchedRequired.isNotEmpty ||
        item.unmatchedRequired.isNotEmpty ||
        item.matchedPreferred.isNotEmpty ||
        item.unmatchedPreferred.isNotEmpty ||
        item.matchedTags.isNotEmpty ||
        item.unmatchedTags.isNotEmpty;
    final detail = item.scoreDetail;
    final parts = <String>[
      if (hasBuckets) ...[
        if (item.matchedRequired.isNotEmpty || item.unmatchedRequired.isNotEmpty)
          bucket('필수', item.matchedRequired, item.unmatchedRequired),
        if (item.matchedPreferred.isNotEmpty || item.unmatchedPreferred.isNotEmpty)
          bucket('우대', item.matchedPreferred, item.unmatchedPreferred),
        if (item.matchedTags.isNotEmpty || item.unmatchedTags.isNotEmpty)
          bucket('태그', item.matchedTags, item.unmatchedTags),
      ] else if (detail != null && detail.skillsTotal > 0)
        '요구 기술 ${item.matchedSkills.length}/${detail.skillsTotal} 일치',
      if (item.projectSkills.isNotEmpty) '프로젝트 근거 ${item.projectSkills.length}건',
      if (item.roleTerms.isNotEmpty) '직무 키워드 ${item.roleTerms.length}개',
      if (item.region.isNotEmpty) item.region,
      ?item.employmentType,
      item.hardFilterStatus == 'PASS' ? '조건 통과' : '조건 확인 필요',
      if (item.embeddingRank case final rank?) '임베딩 유사도 $rank위',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final hasLink = item.sourceUrl.startsWith('http');
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: AppColors.primaryLight,
                child: Text('${widget.index}', style: const TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: InkWell(
                  onTap: hasLink ? _open : null,
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
                      if (item.bodyIsImage) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '상세 이미지 공고 · 기술 태그로만 비교',
                            style: TextStyle(fontSize: 9.5, color: AppColors.warning, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
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
                    IconButton(
                      onPressed: _open,
                      tooltip: '공고 열기',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      icon: const Icon(
                        Icons.open_in_new,
                        size: 13,
                        color: AppColors.textHint,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _summary(),
            style: const TextStyle(fontSize: 10.5, color: AppColors.info, height: 1.4),
          ),
          if (item.unknownConditions.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              '확인 필요: ${item.unknownConditions.join(', ')}',
              style: const TextStyle(fontSize: 10, color: AppColors.warning),
            ),
          ],
          const SizedBox(height: 4),
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _expanded ? '근거 접기' : '추천 근거 보기',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7C3AED),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: const Color(0xFF7C3AED),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 6),
            _RecommendationRationale(item: item),
          ],
        ],
      ),
    );
  }
}

/// 추천 근거 상세. 점수가 어떻게 구성됐고 어떤 문장·기술·조건이 근거였는지 보여준다.
class _RecommendationRationale extends StatelessWidget {
  const _RecommendationRationale({required this.item});

  final JobRecommendation item;

  /// 하드 필터 문구에서 해당 조건의 결과를 찾는다. (통과 여부, 문구)
  (bool?, String?) _condition(List<String> keywords) {
    for (final text in item.passedConditions) {
      if (keywords.any(text.contains)) return (true, text);
    }
    for (final text in item.unknownConditions) {
      if (keywords.any(text.contains)) return (null, text);
    }
    return (null, null);
  }

  @override
  Widget build(BuildContext context) {
    final detail = item.scoreDetail;
    final region = _condition(const ['근무지역', '전국 근무', '희망지역']);
    final employment = _condition(const ['고용형태']);
    final career = _condition(const ['경력']);
    final education = _condition(const ['학력']);
    final major = _condition(const ['전공']);
    final certification = _condition(const ['자격증']);
    final military = _condition(const ['병역']);
    final hasBuckets = [
      item.matchedRequired,
      item.unmatchedRequired,
      item.matchedPreferred,
      item.unmatchedPreferred,
      item.matchedTags,
      item.unmatchedTags,
    ].any((list) => list.isNotEmpty);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AnalysisLabel('공고 조건', AppColors.textSecondary),
          _ConditionRow(
            label: '근무지역',
            value: item.region.isEmpty ? '미기재' : item.region,
            ok: region.$1,
            note: region.$2,
          ),
          _ConditionRow(
            label: '고용형태',
            value: item.employmentType ?? '미기재',
            ok: employment.$1,
            note: employment.$2,
          ),
          _ConditionRow(
            label: '경력',
            value: item.careerLabel,
            ok: career.$1,
            note: career.$2,
          ),
          _ConditionRow(
            label: '학력',
            value: item.education.isEmpty ? '미기재' : item.education,
            ok: education.$1,
            note: education.$2,
          ),
          if (item.requiredMajors.isNotEmpty)
            _ConditionRow(
              label: '전공',
              value: item.requiredMajors.join(', '),
              ok: major.$1,
              note: major.$2,
            ),
          if (item.requiredCertifications.isNotEmpty)
            _ConditionRow(
              label: '자격증',
              value: item.requiredCertifications.join(', '),
              ok: certification.$1,
              note: certification.$2,
            ),
          if (item.militaryRequired)
            _ConditionRow(
              label: '병역',
              value: '병역필 또는 면제',
              ok: military.$1,
              note: military.$2,
            ),
          const SizedBox(height: 8),
          if (detail != null) ...[
            const _AnalysisLabel('점수 구성', AppColors.textSecondary),
            _ScoreBar(
              label: '희망 직무 일치',
              fraction: detail.role,
              weight: recommendationWeights.role,
              note: item.roleTerms.isEmpty
                  ? '공고 제목·본문에서 희망 직무 키워드를 찾지 못함'
                  : '키워드: ${item.roleTerms.join(', ')}',
            ),
            _ScoreBar(
              label: '요구 기술 일치',
              fraction: detail.skills,
              weight: recommendationWeights.skills,
              note: detail.skillsTotal == 0
                  ? '공고에 명시된 기술 없음'
                  : '공고 기술 ${detail.skillsTotal}개 중 ${item.matchedSkills.length}개가 기술스택에 있음',
            ),
            _ScoreBar(
              label: '프로젝트 근거',
              fraction: detail.project,
              weight: recommendationWeights.project,
              note: item.projectSkills.isEmpty
                  ? '프로젝트 설명에서 공고 기술을 찾지 못함'
                  : '프로젝트에서 확인: ${item.projectSkills.join(', ')}',
            ),
            _ScoreBar(
              label: '명시 조건',
              fraction: detail.conditions,
              weight: recommendationWeights.conditions,
              note: item.hardFilterStatus == 'PASS'
                  ? '학력·경력·희망 조건 모두 확인됨'
                  : '확인 안 된 조건이 있어 절반만 반영',
            ),
            const SizedBox(height: 8),
          ],
          if (hasBuckets) ...[
            const _AnalysisLabel('기술 근거', AppColors.textSecondary),
            _SkillBucketRow(
              label: '필수 기술',
              matched: item.matchedRequired,
              unmatched: item.unmatchedRequired,
            ),
            _SkillBucketRow(
              label: '우대 기술',
              matched: item.matchedPreferred,
              unmatched: item.unmatchedPreferred,
            ),
            _SkillBucketRow(
              label: '기업 등록 태그',
              matched: item.matchedTags,
              unmatched: item.unmatchedTags,
            ),
          ] else if (item.matchedSkills.isNotEmpty) ...[
            const _AnalysisLabel('일치한 기술', AppColors.success),
            _ChipRow(items: item.matchedSkills, color: AppColors.success),
          ],
          if (item.unmatchedSkills.isNotEmpty) ...[
            const SizedBox(height: 3),
            const Text(
              '회색 기술은 이력서에 적혀 있지 않다는 뜻이며, 경험이 없다고 판단한 것은 아닙니다. '
              '경험이 있다면 기술스택이나 프로젝트에 적어 주세요.',
              style: TextStyle(fontSize: 10, color: AppColors.textSecondary, height: 1.4),
            ),
          ],
          if (item.bodyIsImage) ...[
            const SizedBox(height: 8),
            const Text(
              '이 공고는 상세 내용이 이미지로만 올라와 있어 필수·우대 요건을 텍스트로 확인하지 못했습니다. '
              '기업이 등록 때 고른 기술 태그와 조건만으로 비교했으니 공고 원문을 직접 확인해 주세요.',
              style: TextStyle(fontSize: 10, color: AppColors.textSecondary, height: 1.4),
            ),
          ],
          if (item.embeddingRank case final rank?) ...[
            const SizedBox(height: 8),
            Text(
              '자기소개서·프로젝트 문장과 공고 내용의 임베딩 유사도 $rank위로 순위에 반영됨',
              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

/// 공고 조건 한 줄: 값과 희망 조건 대비 결과.
class _ConditionRow extends StatelessWidget {
  const _ConditionRow({
    required this.label,
    required this.value,
    required this.ok,
    required this.note,
  });

  final String label;
  final String value;

  /// true 통과, null 확인 필요(희망 조건 미입력 등), false 불일치.
  final bool? ok;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final color = switch (ok) {
      true => AppColors.success,
      false => AppColors.error,
      null => AppColors.textHint,
    };
    final icon = switch (ok) {
      true => Icons.check_circle_outline,
      false => Icons.cancel_outlined,
      null => Icons.help_outline,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 50,
            child: Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
          ),
          if (note != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
            Flexible(
              child: Text(note!, style: TextStyle(fontSize: 10, color: color), overflow: TextOverflow.ellipsis),
            ),
          ],
        ],
      ),
    );
  }
}

/// 출처별 기술 근거 한 줄: 일치는 초록, 근거 없음은 회색으로 나란히 둔다.
class _SkillBucketRow extends StatelessWidget {
  const _SkillBucketRow({
    required this.label,
    required this.matched,
    required this.unmatched,
  });

  final String label;
  final List<String> matched;
  final List<String> unmatched;

  @override
  Widget build(BuildContext context) {
    final total = matched.length + unmatched.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            total == 0 ? '$label · 공고에 없음' : '$label ${matched.length}/$total 일치',
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
          ),
          if (total > 0) ...[
            const SizedBox(height: 3),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final text in matched) _SkillChip(text: text, color: AppColors.success),
                for (final text in unmatched) _SkillChip(text: text, color: AppColors.textHint),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SkillChip extends StatelessWidget {
  const _SkillChip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({
    required this.label,
    required this.fraction,
    required this.weight,
    required this.note,
  });

  final String label;
  final double fraction;
  final double weight;
  final String note;

  @override
  Widget build(BuildContext context) {
    final maxPoints = weight * 100;
    final points = fraction * maxPoints;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
              ),
              Text(
                '${points.toStringAsFixed(1)} / ${maxPoints.toStringAsFixed(0)}점',
                style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction.clamp(0, 1).toDouble(),
              minHeight: 4,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
          const SizedBox(height: 2),
          Text(note, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, height: 1.35)),
        ],
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.items, required this.color});

  final List<String> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final text in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
          ),
      ],
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
  const _ReadinessCard({
    required this.readiness,
    required this.onSearchTap,
    required this.preferences,
    required this.onEditPreferences,
  });

  final ResumeReadiness readiness;
  final VoidCallback onSearchTap;
  final JobPreferences preferences;
  final VoidCallback onEditPreferences;

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
          const SizedBox(height: 8),
          // 희망 조건은 프로필에 있다. 비어 있어도 추천은 막지 않고 필터만 빠진다.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  preferences.isEmpty
                      ? '희망 조건 미입력 — 지역·고용형태 필터 없이 추천합니다.'
                      : '희망 조건: ${preferences.summary}',
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: onEditPreferences,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '수정 →',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7C3AED),
                    ),
                  ),
                ),
              ),
            ],
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
    final subtitle = analysis.isFromRag
        ? '이력서 원문 인용을 근거로 시장 공고와 비교했습니다. '
              'AI가 문장을 대신 고치지 않고 보완할 지점만 알려줍니다.'
        : 'AI가 문장을 대신 고치지 않고 보완할 지점만 알려줍니다.';
    return _Section(
      title: '이력서 분석',
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (analysis.fallbackReason case final reason?) ...[
            _NoteText(
              '서버 분석 대신 규칙 기반 결과를 표시합니다: $reason',
              color: AppColors.warning,
            ),
            const SizedBox(height: 10),
          ],
          if (analysis.strengths.isNotEmpty) ...[
            const _AnalysisLabel('강점', AppColors.success),
            for (final item in analysis.strengths) _AnalysisBullet(item),
            const SizedBox(height: 10),
          ],
          if (analysis.improvements.isNotEmpty) ...[
            const _AnalysisLabel('보완 필요', AppColors.warning),
            for (final item in analysis.improvements) _AnalysisBullet(item),
            const SizedBox(height: 10),
          ],
          if (analysis.confirmationQuestions.isNotEmpty) ...[
            const _AnalysisLabel('확인 질문', AppColors.info),
            for (final item in analysis.confirmationQuestions)
              _BulletText(item),
            const SizedBox(height: 10),
          ],
          if (analysis.nextSteps.isNotEmpty) ...[
            const _AnalysisLabel('다음 단계', AppColors.primary),
            for (final item in analysis.nextSteps) _BulletText(item),
          ],
          if (analysis.relatedJobs.isNotEmpty) ...[
            const SizedBox(height: 10),
            const _AnalysisLabel('비교에 참고한 공고', AppColors.textSecondary),
            for (final job in analysis.relatedJobs)
              _BulletText('${job.company} · ${job.title}'),
          ],
          if (analysis.warnings.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final warning in analysis.warnings)
              _NoteText(warning, color: AppColors.textHint),
          ],
          if (analysis.notice.isNotEmpty) ...[
            const SizedBox(height: 8),
            _NoteText(analysis.notice, color: AppColors.textHint),
          ],
        ],
      ),
    );
  }
}

/// 분석 소견 한 줄. 이력서 원문 인용이 있으면 아래에 작게 보여준다.
class _AnalysisBullet extends StatelessWidget {
  const _AnalysisBullet(this.item);

  final ResumeAnalysisItem item;

  @override
  Widget build(BuildContext context) {
    final quote = item.quote?.trim() ?? '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 5),
          child: Icon(Icons.circle, size: 5, color: AppColors.info),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.text, style: const TextStyle(fontSize: 11, height: 1.4)),
              if (quote.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 4),
                  child: Text(
                    '“$quote”',
                    style: const TextStyle(
                      fontSize: 10.5,
                      height: 1.35,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NoteText extends StatelessWidget {
  const _NoteText(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 10, height: 1.35, color: color),
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
