import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/constants/ai_ops_types.dart';
import '../../../../shared/models/job_preferences.dart';
import '../../../../shared/models/resume_content.dart';
import '../../../../shared/providers/firebase_providers.dart';
import '../../../../shared/providers/cohort_providers.dart';
import '../../../../shared/services/ai_ops_service.dart';
import '../data/resume_review_api_client.dart';
import 'job_resume_review_dialog.dart';
import '../../../auth/providers/auth_providers.dart';
import '../data/ai_job_coach_repository.dart';
import '../data/job_recommend_api_client.dart';
import '../data/resume_text_builder.dart';
import '../models/ai_job_coach_result.dart';
import '../models/resume_readiness.dart';

class AiJobCoachPanel extends ConsumerStatefulWidget {
  const AiJobCoachPanel({
    super.key,
    required this.resumeId,
    required this.draftContent,
    required this.isSidebar,
    required this.onClose,
    this.hasUnsavedChanges = false,
    this.onResumeChanged,
    this.onSaveRequested,
  });

  final String resumeId;
  final ResumeContent draftContent;
  final bool isSidebar;
  final VoidCallback onClose;
  final bool hasUnsavedChanges;
  final ValueChanged<ResumeContent>? onResumeChanged;

  /// 이력서를 저장한다. 저장에 성공하면 true.
  ///
  /// 첨삭은 서버가 Firestore의 저장본을 읽고 그 자리에 고쳐 쓰므로, 저장 안 된 초안으로는
  /// 시작할 수 없다. 사용자가 저장 버튼을 따로 누르게 하는 대신 여기서 대신 저장한다.
  final Future<bool> Function()? onSaveRequested;

  @override
  ConsumerState<AiJobCoachPanel> createState() => _AiJobCoachPanelState();
}

/// 챗봇 대화 한 줄.
class _ChatMessage {
  const _ChatMessage.user(this.text)
    : isUser = true,
      jobs = const [],
      suggestions = const [],
      recommendations = const [],
      mode = '검색';
  const _ChatMessage.bot(
    this.text, {
    this.jobs = const [],
    this.suggestions = const [],
    this.mode = '검색',
    this.recommendations = const [],
  }) : isUser = false;

  final String text;
  final bool isUser;

  /// 서버가 어떤 갈래로 답했는지. 답이 목록인지 글인지가 달라진다.
  final String mode;

  /// 질문에 답한 경우 이 목록은 **답의 근거**다. 찾아 준 결과가 아니다.
  final List<JobChatJob> jobs;

  /// 이력서를 읽고 고른 공고. 조건 검색 결과와 달리 적합도와 근거가 붙는다.
  final List<JobRecommendation> recommendations;

  /// 다음에 좁힐 거리. 누르면 그대로 질문이 된다.
  final List<String> suggestions;
}

class _AiJobCoachPanelState extends ConsumerState<AiJobCoachPanel> {
  /// 저장 안 된 변경이 있으면 사용자에게 묻고 대신 저장한다. 이어가도 되면 true.
  Future<bool> _saveBeforeReview() async {
    final save = widget.onSaveRequested;
    if (save == null) {
      setState(() => _error = '이력서를 먼저 저장한 뒤 다시 추천하고 첨삭해 주세요.');
      return false;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('이력서 저장'),
        content: const Text(
          '첨삭은 저장된 이력서를 기준으로 합니다. 지금 저장하고 첨삭을 시작할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('저장하고 첨삭'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    if (!await save()) {
      if (mounted) setState(() => _error = '이력서 저장에 실패해 첨삭을 시작하지 못했습니다.');
      return false;
    }
    return true;
  }

  Future<void> _reviewJob(JobRecommendation job) async {
    if (job.bodyIsImage) {
      setState(
        () =>
            _error = '이 공고는 상세 내용이 이미지뿐이라 원문 근거 첨삭을 할 수 없습니다. 텍스트 공고를 선택해 주세요.',
      );
      return;
    }
    // 저장하는 동안 사용자가 패널을 닫을 수 있다. 그러면 대화창을 띄우지 않는다.
    if (widget.hasUnsavedChanges && !await _saveBeforeReview()) return;
    if (!mounted) return;
    final cohort = ref.read(effectiveCohortIdProvider);
    final user = ref.read(firebaseAuthProvider).currentUser;
    if (cohort == null || user == null) {
      setState(() => _error = '첨삭에는 실제 Firebase 로그인이 필요합니다.');
      return;
    }
    final client = ResumeReviewApiClient(token: () => user.getIdToken());
    final ops = ref.read(aiOpsServiceProvider);
    final recommendLogId = _recommendLogId;
    if (recommendLogId != null) {
      unawaited(
        ops.recordOutcome(
          cohortId: cohort,
          logId: recommendLogId,
          outcome: AiOpsOutcomes.selectedForReview,
          draftId: job.jobId,
          promptVersion: _recommendPromptVersion,
          type: AiOpsTypes.jobRecommend,
        ),
      );
    }
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => JobResumeReviewDialog(
          client: client,
          cohortId: cohort,
          resumeId: widget.resumeId,
          jobId: job.jobId,
          jobCompany: job.company,
          jobTitle: job.title,
          draft: widget.draftContent,
          aiOps: ops,
          onChanged: (_) {
            // 공고별 사본은 서버에서 자동 저장한다. 기본 이력서 편집 상태에는
            // 전달하지 않아 다른 공고용 자리표시자가 바뀌지 않게 한다.
            if (mounted)
              setState(() {
                _result = null;
              });
          },
        ),
      );
    } finally {
      client.close();
    }
  }

  @override
  void didUpdateWidget(covariant AiJobCoachPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 이력서가 그대로면 견줄 것도 없다. 아래 비교는 이력서 전체를 JSON으로 두 번
    // 직렬화하는데, 편집 화면은 키 입력마다 다시 만들어지므로 그때마다 치르면 안 된다.
    // 글자를 고치면 `copyWith`가 새 객체를 만들므로 이 지름길로는 안 빠진다.
    if (identical(widget.draftContent, oldWidget.draftContent)) return;
    if (!sameResumeContent(
      widget.draftContent,
      oldWidget.draftContent.toMap(),
    )) {
      _result = null;
    }
  }

  final TextEditingController _chatController = TextEditingController();
  final List<_ChatMessage> _messages = [
    const _ChatMessage.bot(
      '채용에 대해 물어보세요. 공고를 찾아드리고, 궁금한 것에도 답해드려요.\n'
      '답은 지금 열려 있는 공고를 직접 세어 드립니다.',
      suggestions: [
        '서울 백엔드 신입',
        '백엔드 신입은 뭘 준비해야 해?',
        '요즘 많이 요구하는 기술이 뭐야?',
      ],
    ),
  ];

  /// 직전 검색 조건. 서버가 대화를 저장하지 않으므로 앱이 들고 이어 보낸다.
  JobChatFilters? _chatFilters;

  /// 공고 하나를 놓고 묻는 중이면 그 공고. 비어 있으면 평소 대화다.
  ///
  /// 이걸 들고 있는 동안의 말은 전부 이 공고에 대한 물음으로 간다. 그래야 "신입도
  /// 돼?"처럼 짧은 말이 어느 공고 이야기인지 흐려지지 않는다.
  JobChatJob? _askingAbout;
  bool _chatBusy = false;

  /// 기다리는 동안 보여줄 말. 추천은 11초쯤 걸리므로 무엇을 하는 중인지 밝힌다.
  String? _chatBusyLabel;
  AiJobCoachResult? _result;
  bool _chatMode = false;
  bool _loading = false;
  String? _error;

  /// 지금 진행 중인 추천 단계의 이름. 서버가 알려 준다. 아직 안 왔으면 null이다.
  String? _stage;

  /// 끝난 단계가 남긴 결과 한 줄. {단계 이름: "열린 공고에서 40건을 추렸어요"}
  final Map<String, String> _stageResults = {};

  /// LLMOps: 직전 생성 로그 id (outcome 연결용)
  String? _chatLogId;
  String? _chatPromptVersion;
  String? _recommendLogId;
  String? _recommendPromptVersion;

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
      _error = reason;
    });
    return false;
  }

  /// 공고와 무관하게 문장 자체의 맞춤법·문법·표현을 다듬는다.
  Future<void> _reviewResume() async {
    if (!_guard(AiCoachFeature.resumeAnalysis)) return;
    if (widget.hasUnsavedChanges && !await _saveBeforeReview()) return;
    if (!mounted) return;
    final cohort = ref.read(effectiveCohortIdProvider);
    final user = ref.read(firebaseAuthProvider).currentUser;
    if (cohort == null || user == null) {
      setState(() => _error = '첨삭에는 실제 Firebase 로그인이 필요합니다.');
      return;
    }
    final client = ResumeReviewApiClient(token: () => user.getIdToken());
    final ops = ref.read(aiOpsServiceProvider);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => JobResumeReviewDialog(
          client: client,
          cohortId: cohort,
          resumeId: widget.resumeId,
          draft: widget.draftContent,
          generalReview: true,
          aiOps: ops,
          onChanged: (content) {
            widget.onResumeChanged?.call(content);
            if (mounted) setState(() => _result = null);
          },
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '이력서 첨삭을 시작하지 못했습니다: $error');
    } finally {
      client.close();
    }
  }

  void _openChat() {
    setState(() {
      _chatMode = true;
      _error = null;
    });
  }

  /// 챗봇에서 "내 이력서로 맞는 공고"를 물으면 **바로 추천을 돌려 대화창에 답한다.**
  ///
  /// 서버 챗봇은 이력서를 받지 않는다. 하지만 앱은 들고 있으므로 앱이 돌리면 된다.
  /// 버튼을 한 번 더 누르게 하면 "골라 드릴게요"라는 말만 오가고 답이 안 나온다.
  ///
  /// 결과는 `_result`에도 넣는다. 근거 전체(이력서 문장 ↔ 공고 문장)는 코치 화면이
  /// 보여주므로, 대화에서 "자세한 근거 보기"로 그쪽으로 넘어갈 수 있어야 한다.
  Future<void> _recommendInChat([String scope = '전체']) async {
    final blocked = _readiness.blockedReason(AiCoachFeature.jobRecommendation);
    if (blocked != null) {
      // 이력서가 덜 찼을 때만 이렇게 답한다. 이때는 "채워 주세요"가 사실이다.
      setState(() => _messages.add(_ChatMessage.bot(blocked)));
      return;
    }

    final requestedContent = widget.draftContent;
    final missing = _emptyScopeReason(scope, requestedContent);
    if (missing != null) {
      setState(() => _messages.add(_ChatMessage.bot(missing)));
      return;
    }

    setState(() {
      _chatBusy = true;
      _chatBusyLabel = switch (scope) {
        '프로젝트' => '프로젝트 경험을 읽고 공고를 고르는 중…',
        '기술스택' => '기술스택을 읽고 공고를 고르는 중…',
        '자기소개서' => '자기소개서를 읽고 공고를 고르는 중…',
        '경력' => '경력을 읽고 공고를 고르는 중…',
        _ => '이력서를 읽고 공고를 고르는 중…',
      };
    });
    final cohort = ref.read(effectiveCohortIdProvider);
    final ops = ref.read(aiOpsServiceProvider);
    final watch = Stopwatch()..start();
    try {
      final result = await ref
          .read(aiJobCoachRepositoryProvider)
          .analyzeAndMatch(
            draftContent: requestedContent,
            preferences: _preferences,
            // 읽을 글만 좁힌다. 검증과 조건은 이력서 원본 그대로다.
            focus: scope == '전체' ? null : _scopedResume(scope),
          );
      if (cohort != null) {
        final logId = await ops.recordCoachLog(
          type: AiOpsTypes.jobRecommend,
          cohortId: cohort,
          watch: watch,
          success: true,
          promptVersion: result.promptVersion,
          model: result.model,
          generatedCount: result.recommendations.length,
          meta: {
            'jobCount': result.recommendations.length,
            'reranked': result.reranked,
            'mode': 'chat_$scope',
          },
        );
        _recommendLogId = logId;
        _recommendPromptVersion = result.promptVersion.isEmpty
            ? AiOpsPromptVersions.jobRecommend
            : result.promptVersion;
      }
      if (!mounted) return;
      setState(() {
        _result = result;
        final hint = _readiness.weakEvidenceHint;
        _messages.add(
          _ChatMessage.bot(
            _recommendSummary(result.recommendations, scope) +
                (hint == null ? '' : '\n\n$hint'),
            mode: '추천',
            recommendations: result.recommendations.take(3).toList(),
          ),
        );
      });
    } on JobRecommendApiException catch (error) {
      if (cohort != null) {
        await ops.recordCoachLog(
          type: AiOpsTypes.jobRecommend,
          cohortId: cohort,
          watch: watch,
          success: false,
          error: error.message,
          meta: {'mode': 'chat_$scope'},
        );
      }
      if (mounted)
        setState(() => _messages.add(_ChatMessage.bot(error.message)));
    } catch (error) {
      if (cohort != null) {
        await ops.recordCoachLog(
          type: AiOpsTypes.jobRecommend,
          cohortId: cohort,
          watch: watch,
          success: false,
          error: error,
          meta: {'mode': 'chat_$scope'},
        );
      }
      if (mounted) {
        setState(
          () => _messages.add(_ChatMessage.bot('공고를 고르지 못했습니다: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _chatBusy = false;
          _chatBusyLabel = null;
        });
      }
    }
  }

  /// 서버가 **읽을 글**만 남긴 이력서. 조건 판정에는 쓰지 않는다.
  ///
  /// 이걸 원본 대신 넘기면 필수 항목 검증에 걸린다. 실제로 그랬다 — 이력서가 멀쩡한데
  /// "핵심역량·기술스택·자기소개서를 작성해 주세요"로 막혔다. 학력·연차·전공·자격증은
  /// `analyzeAndMatch`가 원본에서 따로 뽑으므로 여기서 지워도 조건은 그대로다.
  ResumeContent _scopedResume(String scope) {
    final content = widget.draftContent;
    const emptyCore = ResumeCoreCompetencies();
    const emptyIntro = ResumeSelfIntroduction();
    return switch (scope) {
      // 물어본 그대로 그 부분만 남긴다. 경력 기술까지 섞으면 "프로젝트 경험만"이 아니다.
      '프로젝트' => content.copyWith(
        experience: const [],
        techStack: const [],
        awards: const [],
        trainingExperience: const [],
        otherActivities: const [],
        coreCompetencies: emptyCore,
        selfIntroduction: emptyIntro,
      ),
      '기술스택' => content.copyWith(
        experience: const [],
        projects: const [],
        awards: const [],
        trainingExperience: const [],
        otherActivities: const [],
        coreCompetencies: emptyCore,
        selfIntroduction: emptyIntro,
      ),
      // 자기소개서에는 핵심역량을 함께 남긴다. 둘 다 "내가 어떤 사람인가"를 쓰는
      // 칸이고, 자기소개서만으로는 글이 너무 짧아 검색이 흐려진다.
      '자기소개서' => content.copyWith(
        experience: const [],
        projects: const [],
        techStack: const [],
        awards: const [],
        trainingExperience: const [],
        otherActivities: const [],
      ),
      '경력' => content.copyWith(
        projects: const [],
        techStack: const [],
        awards: const [],
        trainingExperience: const [],
        otherActivities: const [],
        coreCompetencies: emptyCore,
        selfIntroduction: emptyIntro,
      ),
      _ => content,
    };
  }

  /// 좁힌 곳이 비어 있으면 추천이 근거 없이 돈다. 먼저 알린다.
  static String? _emptyScopeReason(String scope, ResumeContent content) {
    if (scope == '프로젝트' && content.projects.isEmpty) {
      return '이력서에 프로젝트가 아직 없어요. 하나 적어 주시면 그걸 기준으로 찾아드릴게요.';
    }
    if (scope == '기술스택' && content.techStack.isEmpty) {
      return '이력서에 기술스택이 아직 없어요. 쓸 줄 아는 기술을 넣어 주시면 그걸 기준으로 찾아드릴게요.';
    }
    if (scope == '자기소개서' &&
        !content.selfIntroduction.isFilled &&
        !content.coreCompetencies.isFilled) {
      return '이력서에 자기소개서가 아직 없어요. 한 항목이라도 적어 주시면 그걸 기준으로 찾아드릴게요.';
    }
    if (scope == '경력' && content.experience.where((e) => e.isFilled).isEmpty) {
      return '이력서에 경력이 아직 없어요. 신입이시라면 "내 프로젝트 경험만 보고 추천해줘"라고 해보세요.';
    }
    return null;
  }

  /// 몇 건을 골랐고 그중 몇 건이 잘 맞는지. 등급은 서버가 매긴 그대로 센다.
  static String _recommendSummary(List<JobRecommendation> found, String scope) {
    final source = switch (scope) {
      '프로젝트' => '프로젝트 경험',
      '기술스택' => '기술스택',
      '자기소개서' => '자기소개서',
      '경력' => '경력',
      _ => '이력서',
    };
    if (found.isEmpty) {
      return '$source을 읽었지만 조건에 맞는 공고를 찾지 못했어요.\n'
          '희망 지역이나 고용형태를 넓혀 보시겠어요?';
    }
    return '$source을 읽고 ${found.length}건을 골랐어요.';
  }

  /// 공고 하나를 놓고 묻기 시작한다. 그만둘 때까지 모든 말이 이 공고로 간다.
  void _askAbout(JobChatJob job) {
    final cohort = ref.read(effectiveCohortIdProvider);
    final logId = _chatLogId;
    if (cohort != null && logId != null) {
      ref.read(aiOpsServiceProvider).recordOutcome(
            cohortId: cohort,
            logId: logId,
            outcome: AiOpsOutcomes.clickedJob,
            draftId: job.jobId,
            promptVersion: _chatPromptVersion,
            type: AiOpsTypes.jobChat,
          );
    }
    setState(() {
      _askingAbout = job;
      _messages.add(
        _ChatMessage.bot(
          '"${job.title}" 공고에 대해 물어보세요. 공고에 적힌 것만 근거로 답해드려요.',
          mode: '공고',
          suggestions: const [
            '자격요건이 뭐야?',
            '신입도 지원할 수 있어?',
            '어떤 일을 하는 자리야?',
          ],
        ),
      );
    });
  }

  /// 채용에 대해 묻고 답을 받는다. 서버가 조건 해석·검색·집계를 모두 한다.
  ///
  /// 앱에 박힌 공고 파일을 쓰지 않으므로 밤마다 모은 새 공고가 바로 나온다.
  Future<void> _sendChatMessage([String? preset]) async {
    final text = (preset ?? _chatController.text).trim();
    if (text.isEmpty || _chatBusy) return;

    final client = ref.read(jobRecommendApiClientProvider);
    final cohort = ref.read(effectiveCohortIdProvider);
    final ops = ref.read(aiOpsServiceProvider);
    final fromSuggestion = preset != null;
    if (fromSuggestion && cohort != null && _chatLogId != null) {
      unawaited(
        ops.recordOutcome(
          cohortId: cohort,
          logId: _chatLogId!,
          outcome: AiOpsOutcomes.followedUp,
          draftId: 'followup',
          promptVersion: _chatPromptVersion,
          type: AiOpsTypes.jobChat,
        ),
      );
    }

    setState(() {
      _messages.add(_ChatMessage.user(text));
      _chatController.clear();
      _chatBusy = true;
    });

    if (client == null) {
      setState(() {
        _chatBusy = false;
        _messages.add(
          const _ChatMessage.bot('공고 검색 서버 주소가 비어 있어 찾을 수 없습니다.'),
        );
      });
      return;
    }

    final watch = Stopwatch()..start();
    try {
      final result = await client.chat(
        message: text,
        filters: _chatFilters,
        jobId: _askingAbout?.jobId,
        // 공고를 놓고 물을 때만 보낸다. 공고를 안 고른 검색·질문은 이력서가
        // 필요 없고, 보내 봐야 쓰이지 않는다.
        resumeText: _askingAbout == null
            ? null
            : buildResumeText(widget.draftContent),
      );
      if (!mounted) return;
      if (cohort != null) {
        final logId = await ops.recordCoachLog(
          type: AiOpsTypes.jobChat,
          cohortId: cohort,
          watch: watch,
          success: true,
          promptVersion: result.promptVersion,
          model: result.model,
          generatedCount: result.jobs.isEmpty ? 1 : result.jobs.length,
          meta: {
            'mode': result.mode,
            'jobCount': result.jobs.length,
            'topK': result.total,
            'messageLength': text.length,
            'resumeLength': _askingAbout == null
                ? 0
                : buildResumeText(widget.draftContent).length,
          },
        );
        _chatLogId = logId;
        _chatPromptVersion = result.promptVersion.isEmpty
            ? AiOpsPromptVersions.jobChat
            : result.promptVersion;
      }
      setState(() {
        _chatFilters = result.filters;
        _messages.add(
          _ChatMessage.bot(
            result.reply,
            jobs: result.jobs,
            suggestions: result.suggestions,
            mode: result.mode,
          ),
        );
      });
      // 이력서로 골라 달라는 말이었다. 말만 하고 끝내지 않고 바로 돌린다.
      if (result.mode == '추천') {
        await _recommendInChat(result.resumeScope);
      }
    } on JobRecommendApiException catch (error) {
      if (cohort != null) {
        await ops.recordCoachLog(
          type: AiOpsTypes.jobChat,
          cohortId: cohort,
          watch: watch,
          success: false,
          error: error.message,
          meta: {'messageLength': text.length},
        );
      }
      if (!mounted) return;
      setState(() => _messages.add(_ChatMessage.bot(error.message)));
    } catch (error) {
      if (cohort != null) {
        await ops.recordCoachLog(
          type: AiOpsTypes.jobChat,
          cohortId: cohort,
          watch: watch,
          success: false,
          error: error,
          meta: {'messageLength': text.length},
        );
      }
      if (!mounted) return;
      setState(() => _messages.add(_ChatMessage.bot('공고를 찾지 못했습니다: $error')));
    } finally {
      if (mounted) setState(() => _chatBusy = false);
    }
  }

  Future<void> _run() async {
    if (!_guard(AiCoachFeature.jobRecommendation)) return;
    final requestedContent = widget.draftContent;
    final cohort = ref.read(effectiveCohortIdProvider);
    final ops = ref.read(aiOpsServiceProvider);
    setState(() {
      _loading = true;
      _error = null;
      _stage = null;
      _stageResults.clear();
    });
    final watch = Stopwatch()..start();
    try {
      final result = await ref
          .read(aiJobCoachRepositoryProvider)
          .analyzeAndMatch(
            draftContent: requestedContent,
            preferences: _preferences,
            onProgress: (stage, detail) {
              if (!mounted) return;
              setState(() {
                if (detail == null) {
                  _stage = stage;
                } else {
                  _stageResults[stage] = detail;
                }
              });
            },
          );
      if (cohort != null) {
        final logId = await ops.recordCoachLog(
          type: AiOpsTypes.jobRecommend,
          cohortId: cohort,
          watch: watch,
          success: true,
          promptVersion: result.promptVersion,
          model: result.model,
          generatedCount: result.recommendations.length,
          meta: {
            'jobCount': result.recommendations.length,
            'topK': result.recommendations.length,
            'reranked': result.reranked,
            'resumeLength': buildResumeText(requestedContent).length,
          },
        );
        _recommendLogId = logId;
        _recommendPromptVersion = result.promptVersion.isEmpty
            ? AiOpsPromptVersions.jobRecommend
            : result.promptVersion;
      }
      if (mounted) {
        setState(() {
          if (sameResumeContent(
            widget.draftContent,
            requestedContent.toMap(),
          )) {
            _result = result;
          } else {
            _result = null;
            _error = '추천 중 이력서가 변경됐습니다. 저장 후 다시 추천해 주세요.';
          }
        });
      }
    } on JobRecommendApiException catch (error) {
      if (cohort != null) {
        await ops.recordCoachLog(
          type: AiOpsTypes.jobRecommend,
          cohortId: cohort,
          watch: watch,
          success: false,
          error: error.message,
        );
      }
      // 서버가 없거나 실패하면 추천하지 않는다. 이유를 그대로 보여 준다.
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (cohort != null) {
        await ops.recordCoachLog(
          type: AiOpsTypes.jobRecommend,
          cohortId: cohort,
          watch: watch,
          success: false,
          error: error,
        );
      }
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
                onOpenDetail: () => setState(() => _chatMode = false),
                askingAbout: _askingAbout,
                onStopAsking: () => setState(() => _askingAbout = null),
                onAskAbout: _askAbout,
                messages: _messages,
                controller: _chatController,
                onSend: _sendChatMessage,
                onSuggestion: _sendChatMessage,
                busy: _chatBusy,
                busyLabel: _chatBusyLabel,
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
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
                        icon: Icons.spellcheck_outlined,
                        label: '이력서 첨삭',
                        loading: false,
                        // 첨삭할 내용이 하나라도 있으면 실행할 수 있다.
                        enabled: _readiness.canAnalyzeResume,
                        disabledTooltip: _readiness.blockedReason(
                          AiCoachFeature.resumeAnalysis,
                        ),
                        onPressed: _reviewResume,
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
                    _RecommendProgress(
                      current: _stage,
                      results: _stageResults,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    _ErrorCard(message: _error!),
                  ],
                  if (_result == null &&
                      !_loading &&
                      _error == null) ...[
                    const SizedBox(height: 26),
                    const _EmptyState(),
                  ],
                  if (_result case final result?) ...[
                    const SizedBox(height: 18),
                    // 기술 근거·이력서 피드백·학습 추천 섹션은 팀원의 첨삭 모듈(S32-17)이 맡기로 해 제거했다.
                    _RecommendationSection(
                      result: result,
                      onReview: widget.onResumeChanged == null
                          ? null
                          : _reviewJob,
                    ),
                    const SizedBox(height: 20),
                  ],
                ],
              ),
            ),
        ],
      ),
    );

    if (widget.isSidebar) return panel;
    // 높이는 편집 화면이 정한다. 좁은 화면에서는 손잡이로 끌어 조절하므로 여기서
    // 상한을 박으면 아무리 끌어도 그 위로 못 커진다.
    return SizedBox(
      height: double.infinity,
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
              color: chatMode
                  ? AppColors.textSecondary
                  : const Color(0xFF7C3AED),
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

/// 추천이 어디까지 갔는지 보여준다.
///
/// 추천은 15초쯤 걸린다. 막대 하나만 돌리면 멈춘 것과 구별되지 않고, 기다리는 사람은
/// 무엇을 기다리는지 모른다. 서버가 단계마다 알려 주므로 그대로 세워 놓고, 끝난 단계에는
/// 서버가 준 결과 한 줄을 남긴다.
///
/// 서버가 옛 버전이라 알림이 오지 않으면 [current]가 계속 null이다. 그때는 줄만 흐리게
/// 서 있고 맨 위 막대가 돈다 — 예전과 같은 모습이라 나빠지지 않는다.
class _RecommendProgress extends StatelessWidget {
  const _RecommendProgress({required this.current, required this.results});

  /// 진행 중인 단계 이름. 서버의 `RECOMMEND_STAGES`와 같은 값이다.
  final String? current;

  /// 끝난 단계가 남긴 결과 한 줄.
  final Map<String, String> results;

  /// 서버가 보내는 이름과 화면에 쓸 말. 순서가 곧 표시 순서다.
  static const _steps = <(String, String)>[
    ('resume', '이력서 읽기'),
    ('search', '공고 찾기'),
    ('filter', '조건 맞춰 보기'),
    ('judge', '근거 맞대어 보기'),
  ];

  @override
  Widget build(BuildContext context) {
    final index = current == null
        ? -1
        : _steps.indexWhere((step) => step.$1 == current);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (index < 0) ...[
          const LinearProgressIndicator(minHeight: 3),
          const SizedBox(height: 10),
        ],
        const Text(
          '공고를 고르고 있어요',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        const Text(
          '보통 15초 정도 걸려요. 잠시만 기다려 주세요.',
          style: TextStyle(fontSize: 11, color: AppColors.textHint),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _steps.length; i++)
          _ProgressStep(
            label: _steps[i].$2,
            detail: results[_steps[i].$1],
            // 진행 중인 것보다 앞이면 끝난 것이다. 알림이 안 오면 전부 대기 상태다.
            state: index < 0
                ? _StepState.waiting
                : i < index
                ? _StepState.done
                : i == index
                ? (results.containsKey(_steps[i].$1)
                      ? _StepState.done
                      : _StepState.running)
                : _StepState.waiting,
            last: i == _steps.length - 1,
          ),
      ],
    );
  }
}

enum _StepState { done, running, waiting }

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({
    required this.label,
    required this.detail,
    required this.state,
    required this.last,
  });

  final String label;
  final String? detail;
  final _StepState state;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _StepState.done => AppColors.success,
      _StepState.running => AppColors.primary,
      _StepState.waiting => AppColors.textHint,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: switch (state) {
                _StepState.done => Icon(
                  Icons.check_circle,
                  size: 16,
                  color: color,
                ),
                _StepState.running => const Padding(
                  padding: EdgeInsets.all(1.5),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                _StepState.waiting => Icon(
                  Icons.circle_outlined,
                  size: 16,
                  color: color,
                ),
              },
            ),
            if (!last)
              Container(
                width: 2,
                height: detail == null ? 14 : 26,
                margin: const EdgeInsets.symmetric(vertical: 2),
                color: state == _StepState.done
                    ? AppColors.success
                    : AppColors.border,
              ),
          ],
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: state == _StepState.waiting
                        ? AppColors.textHint
                        : AppColors.textPrimary,
                  ),
                ),
                if (detail case final line?) ...[
                  const SizedBox(height: 2),
                  Text(
                    line,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
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
  const _RecommendationSection({required this.result, this.onReview});

  final AiJobCoachResult result;
  final ValueChanged<JobRecommendation>? onReview;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '맞춤 공고 Ranking',
      subtitle: result.notice,
      child: Column(
        children: [
          if (result.searchQuery.isNotEmpty) ...[
            _ServerQueryNote(
              searchQuery: result.searchQuery,
              profileSummary: result.profileSummary,
            ),
            const SizedBox(height: 8),
          ],
          if (result.fromServer && result.recommendations.isEmpty)
            const Text(
              '조건에 맞는 공고를 찾지 못했습니다. 희망 지역·고용형태를 넓히거나 이력서에 기술과 프로젝트를 더 적어 보세요.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          for (var index = 0; index < result.recommendations.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RecommendationCard(
                index: index + 1,
                item: result.recommendations[index],
                onReview: onReview,
              ),
            ),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatefulWidget {
  const _RecommendationCard({
    required this.index,
    required this.item,
    this.onReview,
  });

  final int index;
  final JobRecommendation item;
  final ValueChanged<JobRecommendation>? onReview;

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

  /// 접힌 상태에서 이 공고가 어떤 자리인지 한 줄로 보이게 한다.
  ///
  /// 근거 건수·확인할 요건 건수·조건 통과 여부는 뺐다. 펼치면 근거와 우려가 그대로
  /// 나오므로 숫자로 미리 말할 이유가 없고, "조건 통과"는 걸러진 것만 보여주는 목록에서
  /// 늘 참이라 정보가 되지 않는다. 지원할지 정할 때 먼저 보는 것은 근무지·고용형태·경력이다.
  String _summary() {
    if (item.isFromServer) {
      return [
        if (item.region.isNotEmpty) item.region,
        ?item.employmentType,
        item.careerLabel,
      ].join(' · ');
    }
    String bucket(String label, List<String> matched, List<String> unmatched) =>
        '$label ${matched.length}/${matched.length + unmatched.length}';
    final hasBuckets =
        item.matchedRequired.isNotEmpty ||
        item.unmatchedRequired.isNotEmpty ||
        item.matchedPreferred.isNotEmpty ||
        item.unmatchedPreferred.isNotEmpty ||
        item.matchedTags.isNotEmpty ||
        item.unmatchedTags.isNotEmpty;
    final detail = item.scoreDetail;
    final parts = <String>[
      if (hasBuckets) ...[
        if (item.matchedRequired.isNotEmpty ||
            item.unmatchedRequired.isNotEmpty)
          bucket('필수', item.matchedRequired, item.unmatchedRequired),
        if (item.matchedPreferred.isNotEmpty ||
            item.unmatchedPreferred.isNotEmpty)
          bucket('우대', item.matchedPreferred, item.unmatchedPreferred),
        if (item.matchedTags.isNotEmpty || item.unmatchedTags.isNotEmpty)
          bucket('태그', item.matchedTags, item.unmatchedTags),
      ] else if (detail != null && detail.skillsTotal > 0)
        '요구 기술 ${item.matchedSkills.length}/${detail.skillsTotal} 일치',
      if (item.projectSkills.isNotEmpty)
        '프로젝트 근거 ${item.projectSkills.length}건',
      if (item.roleTerms.isNotEmpty) '직무 키워드 ${item.roleTerms.length}개',
      if (item.region.isNotEmpty) item.region,
      ?item.employmentType,
      item.hardFilterStatus == 'PASS' ? '조건 통과' : '조건 확인 필요',
      if (item.embeddingRank case final rank?) '임베딩 유사도 $rank위',
    ];
    return parts.join(' · ');
  }

  Widget _reviewButton() {
    final unavailable = item.bodyIsImage;
    return Tooltip(
      message: unavailable
          ? '상세 공고가 이미지뿐이라 원문 근거 첨삭을 할 수 없습니다.'
          : '선택 공고와 이력서를 비교해 첨삭합니다.',
      child: FilledButton.icon(
        onPressed: unavailable ? null : () => widget.onReview!(item),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.success,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        icon: const Icon(Icons.auto_fix_high, size: 14),
        label: Text(
          unavailable ? '원문 확인 불가' : '공고 맞춤 첨삭',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    );
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
                child: Text(
                  '${widget.index}',
                  style: const TextStyle(fontSize: 11),
                ),
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
                        item.source.isEmpty
                            ? item.company
                            : '${item.company} · ${item.source}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (item.bodyIsImage) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '상세 이미지 공고 · 기술 태그로만 비교',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: AppColors.warning,
                              fontWeight: FontWeight.w600,
                            ),
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
                  // 서버 추천은 점수가 아니라 적합도(높음/보통/낮음)만 준다.
                  if (!item.isFromServer)
                    Text(
                      '${item.score.toStringAsFixed(1)}점',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  // 서버 적합도는 사람 정답으로 검증된 적이 없다. 순서에만 쓰고
                  // 화면에는 내지 않는다. 근거 문장이 그 자리를 대신한다.
                  if (!item.isFromServer)
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
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
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
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.info,
              height: 1.4,
            ),
          ),
          // 마감은 조건 표 안쪽이 아니라 여기 있어야 한다. 지원할지 정할 때
          // 근무지·고용형태 다음으로 보는 것이 언제까지냐인데, 표는 펼쳐야 보인다.
          if (item.deadline case final deadline?)
            Text(
              '~ ${_deadlineDate(deadline)}',
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          if (item.unknownConditions.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              '확인 필요: ${item.unknownConditions.join(', ')}',
              style: const TextStyle(fontSize: 10, color: AppColors.warning),
            ),
          ],
          if (_expanded && item.isFromServer && widget.onReview != null) ...[
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: _reviewButton(),
            ),
          ],
          const SizedBox(height: 4),
          if (_expanded) ...[
            const SizedBox(height: 6),
            _RecommendationRationale(item: item),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
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
              ),
              if (!_expanded && item.isFromServer && widget.onReview != null)
                _reviewButton(),
            ],
          ),
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
          if (item.reasons.isNotEmpty) ...[
            const _AnalysisLabel('추천 근거 — 이력서 문장 ↔ 공고 문장', AppColors.success),
            for (final reason in item.reasons) _ReasonTile(reason: reason),
            const SizedBox(height: 6),
          ],
          if (item.concerns.isNotEmpty) ...[
            const _AnalysisLabel(
              '공고 자격요건 중 이력서에서 확인되지 않는 것',
              AppColors.warning,
            ),
            for (final concern in item.concerns)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '• $concern',
                  style: const TextStyle(fontSize: 10.5, height: 1.4),
                ),
              ),
            const Text(
              '경험이 없다는 판단이 아닙니다. 경험이 있다면 이력서에 적어 주세요.',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
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
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          if (item.bodyIsImage) ...[
            const SizedBox(height: 8),
            const Text(
              '이 공고는 상세 내용이 이미지로만 올라와 있어 필수·우대 요건을 텍스트로 확인하지 못했습니다. '
              '기업이 등록 때 고른 기술 태그와 조건만으로 비교했으니 공고 원문을 직접 확인해 주세요.',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          if (item.embeddingRank case final rank?) ...[
            const SizedBox(height: 8),
            Text(
              '자기소개서·프로젝트 문장과 공고 내용의 임베딩 유사도 $rank위로 순위에 반영됨',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
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
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (note != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                note!,
                style: TextStyle(fontSize: 10, color: color),
                overflow: TextOverflow.ellipsis,
              ),
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
            total == 0
                ? '$label · 공고에 없음'
                : '$label ${matched.length}/$total 일치',
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
          ),
          if (total > 0) ...[
            const SizedBox(height: 3),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final text in matched)
                  _SkillChip(text: text, color: AppColors.success),
                for (final text in unmatched)
                  _SkillChip(text: text, color: AppColors.textHint),
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
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
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
            child: Text(
              text,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
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
    required this.onSuggestion,
    required this.busy,
    required this.askingAbout,
    required this.onStopAsking,
    required this.onAskAbout,
    required this.onOpenDetail,
    this.busyLabel,
  });

  final List<_ChatMessage> messages;
  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<String> onSuggestion;

  /// 서버 응답을 기다리는 중. 그동안 같은 질문을 다시 보내지 못하게 한다.
  final bool busy;

  /// 공고 하나를 놓고 묻는 중이면 그 공고. 무엇에 대해 묻는 중인지 늘 보여야 한다.
  final JobChatJob? askingAbout;
  final VoidCallback onStopAsking;
  final ValueChanged<JobChatJob> onAskAbout;

  /// 근거 전체를 보러 코치 화면으로 넘어간다.
  final VoidCallback onOpenDetail;

  /// 무엇을 기다리는 중인지. 비어 있으면 기본 문구를 쓴다.
  final String? busyLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: messages.length,
            itemBuilder: (context, index) => _ChatBubble(
              message: messages[index],
              onAskAbout: busy ? null : onAskAbout,
              // 넘어가기는 마지막 답에서만. 지나간 답의 버튼을 누르면 그때 물어본
              // 것이 아니라 지금 이력서로 돌아 혼란스럽다.
              onOpenDetail: busy ? null : onOpenDetail,
              // 제안은 마지막 답에서만 누를 수 있다. 지나간 답의 제안을 누르면 그때가
              // 아니라 지금 조건에 붙어 엉뚱한 결과가 나온다.
              onSuggestion: index == messages.length - 1 && !busy
                  ? onSuggestion
                  : null,
            ),
          ),
        ),
        if (busy)
          Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  busyLabel ?? '답을 찾는 중…',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        // 무엇에 대해 묻는 중인지. 이게 없으면 짧은 말이 어디로 가는지 알 수 없다.
        if (askingAbout case final job?)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            color: AppColors.primaryLight.withValues(alpha: 0.4),
            child: Row(
              children: [
                const Icon(
                  Icons.help_outline,
                  size: 14,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '"${job.title}"에 대해 묻는 중',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '그만 묻기',
                  onPressed: onStopAsking,
                  icon: const Icon(Icons.close, size: 14),
                  visualDensity: VisualDensity.compact,
                ),
              ],
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
                  decoration: InputDecoration(
                    hintText: askingAbout == null
                        ? '공고를 찾거나, 채용에 대해 물어보세요'
                        : '이 공고에 대해 물어보세요',
                    hintStyle: const TextStyle(fontSize: 12),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: busy ? null : (_) => onSend(),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: '보내기',
                onPressed: busy ? null : onSend,
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
  const _ChatBubble({
    required this.message,
    this.onSuggestion,
    this.onAskAbout,
    this.onOpenDetail,
  });

  final _ChatMessage message;
  final ValueChanged<String>? onSuggestion;
  final ValueChanged<JobChatJob>? onAskAbout;
  final VoidCallback? onOpenDetail;

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
            // 이력서를 읽고 고른 공고. 적합도와 근거가 붙는다.
            for (final job in message.recommendations) ...[
              const SizedBox(height: 8),
              _ChatRecommendCard(job: job),
            ],
            if (message.recommendations.isNotEmpty && onOpenDetail != null) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: onOpenDetail,
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '근거 전체 보기 →',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7C3AED),
                    ),
                  ),
                ),
              ),
            ],
            // 질문에 답한 경우 목록은 찾아 준 결과가 아니라 **답의 근거**다.
            // 그렇게 적어 두지 않으면 "이게 추천인가?"로 읽힌다.
            if (message.mode == '질문' && message.jobs.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                '이 숫자를 센 공고들이에요',
                style: TextStyle(fontSize: 10.5, color: AppColors.textHint),
              ),
            ],
            for (final job in message.jobs) ...[
              const SizedBox(height: 8),
              _ChatJobCard(
                job: job,
                onAsk: onAskAbout == null ? null : () => onAskAbout!(job),
              ),
            ],
            if (message.suggestions.isNotEmpty && onSuggestion != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final suggestion in message.suggestions)
                    ActionChip(
                      label: Text(
                        suggestion,
                        style: const TextStyle(fontSize: 11),
                      ),
                      onPressed: () => onSuggestion!(suggestion),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 이력서를 읽고 고른 공고 한 건. 조건 검색 카드와 달리 **왜 맞는지**를 함께 보여준다.
class _ChatRecommendCard extends StatelessWidget {
  const _ChatRecommendCard({required this.job});

  final JobRecommendation job;

  Future<void> _open() async {
    final uri = Uri.tryParse(job.sourceUrl);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLink = job.sourceUrl.startsWith('http');
    // 근거 한 줄. 주장(claim)만 보여주고, 인용 원문은 코치 화면에 있다.
    final reason = job.reasons.isNotEmpty
        ? job.reasons.first.claim
        : job.evidence.join(' · ');
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
              job.company,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              job.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            if (job.region.isNotEmpty || job.careerText.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                [
                  job.region,
                  job.careerText,
                ].where((v) => v.isNotEmpty).join(' · '),
                style: const TextStyle(fontSize: 10, color: AppColors.textHint),
              ),
            ],
            // 왜 맞는지 한 줄. 전체 근거는 코치 화면에 있다.
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                reason,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
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

class _ChatJobCard extends StatelessWidget {
  const _ChatJobCard({required this.job, this.onAsk});

  final JobChatJob job;

  /// 이 공고를 놓고 물어보기. 목록에서 바로 이어 물을 수 있어야 한다.
  final VoidCallback? onAsk;

  Future<void> _open() async {
    final uri = Uri.tryParse(job.sourceUrl);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skills = job.techStack;
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
              '${job.company} · ${job.region} · ${job.career}',
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textSecondary,
              ),
            ),
            if (job.deadline case final deadline?)
              Text(
                '마감 ${_deadlineDate(deadline)}',
                style: const TextStyle(fontSize: 10, color: AppColors.textHint),
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
            const SizedBox(height: 5),
            Row(
              children: [
                if (hasLink)
                  const Text(
                    '공고 보기 →',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7C3AED),
                    ),
                  ),
                const Spacer(),
                if (onAsk != null)
                  InkWell(
                    onTap: onAsk,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        '이 공고 물어보기',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 서버가 이력서에서 만든 검색 질의문. 어떤 기준으로 찾았는지 사용자가 볼 수 있게 한다.
class _ServerQueryNote extends StatelessWidget {
  const _ServerQueryNote({
    required this.searchQuery,
    required this.profileSummary,
  });

  final String searchQuery;
  final String profileSummary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '이력서에서 뽑은 검색 기준',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            searchQuery,
            style: const TextStyle(fontSize: 10.5, height: 1.4),
          ),
          if (profileSummary.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              profileSummary,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 추천 근거 하나. 주장 한 줄과 그 근거인 이력서·공고 원문 인용.
class _ReasonTile extends StatelessWidget {
  const _ReasonTile({required this.reason});

  final RecommendReason reason;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reason.claim,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          if (reason.resumeQuote.isNotEmpty)
            _QuoteLine(
              label: '이력서',
              text: reason.resumeQuote,
              color: AppColors.success,
            ),
          if (reason.jobQuote.isNotEmpty)
            _QuoteLine(
              label: '공고',
              text: reason.jobQuote,
              color: AppColors.info,
            ),
        ],
      ),
    );
  }
}

class _QuoteLine extends StatelessWidget {
  const _QuoteLine({
    required this.label,
    required this.text,
    required this.color,
  });

  final String label;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // 공고 원문 인용은 HTML/문단 경계에서 줄바꿈을 포함할 수 있다. 근거 값 자체는
    // 보존하고, 카드에서는 라벨 뒤에 자연스럽게 이어지도록 표시만 한 줄로 정리한다.
    final displayText = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (displayText.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '“$displayText”',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 마감은 날짜까지만 보여준다. 서버는 `2026-10-08T23:59:59+09:00` 처럼 시각과
/// 시간대를 붙여 주는데, 마감은 그 날 하루가 통째로 남았느냐의 문제라 뒤쪽은
/// 읽는 사람에게 쓸모가 없다. 시간대를 옮기지 않고 앞 열 글자만 쓴다 —
/// 한국 공고의 마감일은 한국 날짜 그대로 보여야 한다.
String _deadlineDate(String value) {
  final date = RegExp(r'^\d{4}-\d{2}-\d{2}').stringMatch(value);
  return date ?? value;
}
