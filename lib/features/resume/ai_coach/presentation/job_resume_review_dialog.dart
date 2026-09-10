import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/constants/ai_ops_types.dart';
import '../../../../shared/models/resume_content.dart';
import '../../../../shared/services/ai_ops_service.dart';
import '../data/resume_review_api_client.dart';

class JobResumeReviewDialog extends StatefulWidget {
  const JobResumeReviewDialog({
    super.key,
    required this.client,
    required this.cohortId,
    required this.resumeId,
    required this.draft,
    required this.onChanged,
    this.jobId = '',
    this.jobCompany = '',
    this.jobTitle = '',
    this.tailoredResumeId = '',
    this.generalReview = false,
    this.aiOps,
  });
  final ResumeReviewApiClient client;
  final String cohortId, resumeId, jobId, jobCompany, jobTitle, tailoredResumeId;
  final ResumeContent draft;
  final ValueChanged<ResumeContent> onChanged;
  final bool generalReview;
  final AiOpsService? aiOps;

  @override
  State<JobResumeReviewDialog> createState() => _JobResumeReviewDialogState();
}

class _JobResumeReviewDialogState extends State<JobResumeReviewDialog> {
  Map<String, dynamic>? _result,
      _reviewRequest,
      _applyRequest,
      _undoRequest,
      _application;
  final Set<int> _selected = {};
  final Set<int> _appliedSuggestionIndices = {};
  final TextEditingController _answerController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final List<_ReviewChatMessage> _messages = [];
  final Set<String> _answeredQuestionIds = {};
  final List<Map<String, dynamic>> _questionQueue = [];
  final Map<String, GlobalKey> _previewSectionKeys = {};
  bool _busy = false, _changed = false, _undone = false;
  bool _mutationPending = false;
  Map<String, dynamic>? _pendingQuestion;
  String? _error;
  String? _focusedFieldPath;
  String? _tailoredResumeId;
  late ResumeContent _preview;
  String? _reviewLogId;
  String? _reviewPromptVersion;
  bool _hadApply = false;
  String _id() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 30)}';
  Map<String, dynamic> get _identity => {
    'cohort_id': widget.cohortId,
    'resume_id': widget.resumeId,
  };

  @override
  void initState() {
    super.initState();
    _preview = widget.draft;
    _tailoredResumeId = widget.tailoredResumeId.isEmpty
        ? null
        : widget.tailoredResumeId;
  }

  @override
  void dispose() {
    final ops = widget.aiOps;
    final logId = _reviewLogId;
    if (ops != null && logId != null && !_hadApply && !_undone) {
      ops.recordOutcome(
        cohortId: widget.cohortId,
        logId: logId,
        outcome: AiOpsOutcomes.abandoned,
        draftId: 'session',
        promptVersion: _reviewPromptVersion,
        type: AiOpsTypes.resumeReview,
      );
    }
    _answerController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() => _run(() async {
    final watch = Stopwatch()..start();
    try {
      await _ensureTailoredResume();
      if (_reviewRequest == null) {
        final snapshot = await widget.client.context(
          widget.cohortId,
          widget.resumeId,
          job: widget.generalReview ? null : widget.jobId,
          tailoredResumeId: widget.generalReview ? null : _tailoredResumeId,
        );
        final content = Map<String, dynamic>.from(snapshot['content'] as Map);
        if (!sameResumeContent(_preview, content)) {
          throw const FormatException(
            '화면과 저장된 이력서가 다릅니다. 창을 닫고 저장 또는 새로고침한 뒤 다시 추천해 주세요.',
          );
        }
        _reviewRequest = {
          ..._identity,
          'request_id': _id(),
          'expected_input_hash': snapshot['input_hash'],
          'review_mode': widget.generalReview ? 'general' : 'job',
          if (!widget.generalReview && _tailoredResumeId != null)
            'tailored_resume_id': _tailoredResumeId,
          if (!widget.generalReview) ...{
            'selected_job_id': widget.jobId,
            'expected_job_hash': (snapshot['job_source'] as Map)['snapshot_hash'],
          },
        };
      }
      _result = await widget.client.review(_reviewRequest!);
      _appendReview(_result!, isFirstReview: _messages.isEmpty);
      final ops = widget.aiOps;
      if (ops != null) {
        final suggestions = (_result!['suggestions'] as List?)?.length ?? 0;
        final logId = await ops.recordCoachLog(
          type: AiOpsTypes.resumeReview,
          cohortId: widget.cohortId,
          watch: watch,
          success: true,
          promptVersion: AiOpsPromptVersions.resumeReview,
          generatedCount: suggestions == 0 ? 1 : suggestions,
          meta: {
            'reviewMode': widget.generalReview ? 'general' : 'job',
            'jobCount': widget.generalReview ? 0 : 1,
            'requestIdHash': (_reviewRequest?['request_id'] as String? ?? '')
                .hashCode
                .toRadixString(16),
          },
        );
        _reviewLogId = logId;
        _reviewPromptVersion = AiOpsPromptVersions.resumeReview;
      }
    } catch (error) {
      final ops = widget.aiOps;
      if (ops != null) {
        await ops.recordCoachLog(
          type: AiOpsTypes.resumeReview,
          cohortId: widget.cohortId,
          watch: watch,
          success: false,
          error: error,
          meta: {
            'reviewMode': widget.generalReview ? 'general' : 'job',
          },
        );
      }
      rethrow;
    }
  });

  Future<void> _ensureTailoredResume() async {
    if (widget.generalReview || _tailoredResumeId != null) return;
    final tailored = await widget.client.createTailoredResume({
      'cohort_id': widget.cohortId,
      'resume_id': widget.resumeId,
      'selected_job_id': widget.jobId,
    });
    final tailoredId = tailored['tailored_resume_id'] as String?;
    final rawContent = tailored['content'] as Map?;
    if (tailoredId == null || tailoredId.isEmpty || rawContent == null) {
      throw const FormatException('공고별 이력서를 준비하지 못했습니다. 다시 시도해 주세요.');
    }
    final tailoredContent = ResumeContent.fromMap(
      Map<String, dynamic>.from(rawContent),
    );
    _tailoredResumeId = tailoredId;
    if (mounted) {
      setState(() => _preview = tailoredContent);
    } else {
      _preview = tailoredContent;
    }
  }

  Future<void> _reload() async {
    final snapshot = await widget.client.context(
      widget.cohortId,
      widget.resumeId,
      job: widget.generalReview ? null : widget.jobId,
      tailoredResumeId: widget.generalReview ? null : _tailoredResumeId,
    );
    final content = ResumeContent.fromMap(
      Map<String, dynamic>.from(snapshot['content'] as Map),
    );
    // 공고 맞춤본은 기본 이력서와 분리되어 서버에 자동 저장된다.
    if (widget.generalReview) widget.onChanged(content);
    if (mounted) {
      setState(() {
        _preview = content;
        _changed = true;
        _mutationPending = false;
      });
    }
  }

  void _appendReview(
    Map<String, dynamic> review, {
    required bool isFirstReview,
    String? answeredFieldPath,
  }) {
    _pendingQuestion = null;
    if (isFirstReview) {
      _messages.add(
        _ReviewChatMessage.assistant(
          review['summary'] as String? ??
              (widget.generalReview
                  ? '이력서 문장을 검토했습니다.'
                  : '이력서와 선택 공고를 비교했습니다.'),
        ),
      );
    }
    final reviews = (review['sentence_reviews'] as List? ?? []).cast<Map>();
    final job = Map<String, dynamic>.from(
      review['job_source'] as Map? ??
          {'company': widget.jobCompany, 'title': widget.jobTitle},
    );
    var displayedSuggestions = 0;
    final identitySuggestions = <Map<String, dynamic>>[];
    for (var index = 0; index < reviews.length; index++) {
      final sentence = Map<String, dynamic>.from(reviews[index]);
      if (answeredFieldPath != null &&
          sentence['field_path'] != answeredFieldPath) {
        continue;
      }
      if (sentence['suggested_revision'] is String &&
          (sentence['suggested_revision'] as String).trim().isNotEmpty) {
        sentence['_index'] = index;
        if (!widget.generalReview && _isIdentityPlaceholderSuggestion(sentence)) {
          sentence['_company'] = job['company'] ?? widget.jobCompany;
          sentence['_title'] =
              job['role_title'] ?? job['title'] ?? widget.jobTitle;
          identitySuggestions.add(sentence);
        } else {
          _messages.add(_ReviewChatMessage.suggestion(sentence));
        }
        displayedSuggestions++;
      }
    }
    if (identitySuggestions.isNotEmpty) {
      // 회사명·직무명 자리표시자는 같은 선택 공고의 확정값으로 바뀝니다.
      // 항목마다 같은 질문을 반복하지 않고 한 번의 확인으로 묶어 적용합니다.
      final groupedIdentitySuggestion = Map<String, dynamic>.from(
        identitySuggestions.first,
      )..['_indices'] = identitySuggestions
          .map((suggestion) => suggestion['_index'] as int)
          .toList();
      _messages.add(
        _ReviewChatMessage.identityConfirmation(groupedIdentitySuggestion),
      );
      _focusPreviewField(
        groupedIdentitySuggestion['field_path'] as String?,
      );
    }
    if (!isFirstReview && displayedSuggestions == 0) {
      _messages.add(
        const _ReviewChatMessage.assistant(
          '방금 답변을 반영한 안전한 수정안을 만들지 못했습니다. 확인되지 않은 내용은 넣지 않고 다음 항목을 살펴봅니다.',
        ),
      );
    }
    final questions = (review['questions'] as List? ?? []).cast<Map>();
    _enqueueQuestions(questions);
    final nextQuestion = _takeNextQuestion();
    if (nextQuestion != null) {
      if (displayedSuggestions > 0) {
        // The user should decide whether to apply the current revision before
        // moving on. Show the next unanswered question after the revised
        // resume is reloaded.
        _pendingQuestion = nextQuestion;
      } else {
        _messages.add(_ReviewChatMessage.question(nextQuestion));
        _focusPreviewField(nextQuestion['field_path'] as String?);
      }
    } else if (!isFirstReview && displayedSuggestions > 0) {
      _messages.add(
        const _ReviewChatMessage.assistant(
          '방금 답한 항목을 기준으로 수정안을 만들었습니다. 적용 전 내용을 확인해 주세요.',
        ),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _questionKey(Map<String, dynamic> question) {
    // A follow-up response gets a new question_id.  Deduplicate by the target
    // and intent instead, so wording changes cannot ask the same thing again.
    return '${question['field_path']}|${question['topic']}';
  }

  bool _hasQuestionKey(String key) {
    if (_pendingQuestion != null && _questionKey(_pendingQuestion!) == key) {
      return true;
    }
    return _questionQueue.any((question) => _questionKey(question) == key) ||
        _messages.any(
          (message) =>
              message.question != null && _questionKey(message.question!) == key,
        );
  }

  void _enqueueQuestions(List<Map> questions) {
    for (final rawQuestion in questions) {
      final question = Map<String, dynamic>.from(rawQuestion);
      final questionId = question['question_id'] as String?;
      if (questionId != null && _answeredQuestionIds.contains(questionId)) {
        continue;
      }
      if ((question['field_path'] as String? ?? '').isEmpty ||
          (question['question'] as String? ?? '').trim().isEmpty) {
        continue;
      }
      final key = _questionKey(question);
      if (!_hasQuestionKey(key)) _questionQueue.add(question);
    }
  }

  Map<String, dynamic>? _takeNextQuestion() {
    while (_questionQueue.isNotEmpty) {
      final question = _questionQueue.removeAt(0);
      final questionId = question['question_id'] as String?;
      if (questionId == null || !_answeredQuestionIds.contains(questionId)) {
        return question;
      }
    }
    return null;
  }

  bool _isIdentityPlaceholderSuggestion(Map<String, dynamic> sentence) {
    final original = sentence['original_quote'] as String? ?? '';
    return original.contains('[회사명]') || original.contains('[직무명]');
  }

  String _previewTargetForFieldPath(String fieldPath) {
    final parts = fieldPath.split('.');
    // 자기소개서는 하나의 긴 본문이 아니라 문항별 카드로 표시한다.
    // 따라서 body·subtitle 어느 필드를 질문해도 해당 문항 카드에 맞춘다.
    if (parts.length >= 2 && parts.first == 'selfIntroduction') {
      return '${parts[0]}.${parts[1]}';
    }
    return fieldPath.split(RegExp(r'[.\[]')).first;
  }

  GlobalKey _previewKeyFor(String fieldPath) => _previewSectionKeys.putIfAbsent(
    _previewTargetForFieldPath(fieldPath),
    GlobalKey.new,
  );

  void _focusPreviewField(String? fieldPath) {
    if (fieldPath == null || fieldPath == _focusedFieldPath) return;
    _focusedFieldPath = fieldPath;
    final key = _previewKeyFor(fieldPath);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = key.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: 0.18,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _submitAnswer(Map<String, dynamic> question) async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty || _busy || _result == null) return;
    final previous = _result!;
    _answerController.clear();
    setState(() {
      final questionId = question['question_id'] as String?;
      if (questionId != null) _answeredQuestionIds.add(questionId);
      _messages.add(_ReviewChatMessage.user(answer));
    });
    await _run(() async {
      final nextRequest = <String, dynamic>{
        ..._identity,
        'request_id': _id(),
        'review_mode': widget.generalReview ? 'general' : 'job',
        if (!widget.generalReview && _tailoredResumeId != null)
          'tailored_resume_id': _tailoredResumeId,
        if (!widget.generalReview) ...{
          'selected_job_id': widget.jobId,
          'expected_job_hash': (previous['job_source'] as Map?)?['snapshot_hash'],
        },
        'previous_review_id': previous['review_id'],
        'expected_input_hash': previous['input_hash'],
        'answers': [
          {
            'question_id': question['question_id'],
            'field_path': question['field_path'],
            'question': question['question'],
            'answer': answer,
          },
        ],
      };
      _result = await widget.client.review(nextRequest);
      // The server rebases the previous review after an applied edit.  This
      // new review now owns the latest resume snapshot and can accept another
      // selected revision in the same chat flow.
      if (mounted) {
        setState(() {
          _application = null;
          _appliedSuggestionIndices.clear();
          _applyRequest = null;
          _undoRequest = null;
          _undone = false;
        });
      }
      _appendReview(
        _result!,
        isFirstReview: false,
        answeredFieldPath: question['field_path'] as String?,
      );
    });
  }

  Future<void> _applySuggestion(List<int> indices) async {
    if (_busy || indices.isEmpty || indices.every(_appliedSuggestionIndices.contains)) {
      return;
    }
    setState(() {
      _selected
        ..clear()
        ..addAll(indices);
      _applyRequest = null;
    });
    await _apply();
  }

  Future<void> _apply() => _run(() async {
    _mutationPending = true;
    _changed = false;
    _applyRequest ??= {
      ..._identity,
      'request_id': _id(),
      'review_id': _result!['review_id'],
      'expected_input_hash': _result!['input_hash'],
      'selected_indices': _selected.toList()..sort(),
      if (_tailoredResumeId != null)
        'tailored_resume_id': _tailoredResumeId,
    };
    _application = await _mutate(() => widget.client.apply(_applyRequest!));
    // The server has rebased this review to the persisted content.  Keep the
    // next answer on the current snapshot rather than the pre-apply hash.
    _result!['input_hash'] = _application!['input_hash'];
    _hadApply = true;
    final ops = widget.aiOps;
    final logId = _reviewLogId;
    if (ops != null && logId != null) {
      final selected = _selected.length;
      final total = (_result!['suggestions'] as List?)?.length ?? selected;
      await ops.recordOutcome(
        cohortId: widget.cohortId,
        logId: logId,
        outcome: selected < total
            ? AiOpsOutcomes.partialApply
            : AiOpsOutcomes.applied,
        draftId: 'apply',
        promptVersion: _reviewPromptVersion,
        type: AiOpsTypes.resumeReview,
      );
    }
    if (mounted) {
      setState(() => _appliedSuggestionIndices.addAll(_selected));
    }
    await _reload();
    if (mounted && _pendingQuestion != null) {
      final question = _pendingQuestion!;
      setState(() {
        _pendingQuestion = null;
        _messages.add(_ReviewChatMessage.question(question));
      });
      _focusPreviewField(question['field_path'] as String?);
    }
  });

  Future<void> _undo() => _run(() async {
    _mutationPending = true;
    _changed = false;
    _undoRequest ??= {
      ..._identity,
      'request_id': _id(),
      'application_id': _application!['operation_id'],
      'expected_input_hash': _application!['input_hash'],
      if (_tailoredResumeId != null)
        'tailored_resume_id': _tailoredResumeId,
    };
    await _mutate(() => widget.client.undo(_undoRequest!));
    final ops = widget.aiOps;
    final logId = _reviewLogId;
    if (ops != null && logId != null) {
      await ops.recordOutcome(
        cohortId: widget.cohortId,
        logId: logId,
        outcome: AiOpsOutcomes.undone,
        draftId: 'undo',
        promptVersion: _reviewPromptVersion,
        type: AiOpsTypes.resumeReview,
      );
    }
    await _reload();
    if (mounted) {
      setState(() {
        // The restored resume no longer matches the rebased review. Start a
        // fresh review instead of sending an answer with the applied hash.
        _result = null;
        _reviewRequest = null;
        _applyRequest = null;
        _application = null;
        _undone = true;
        _pendingQuestion = null;
        _questionQueue.clear();
        _messages.add(
          const _ReviewChatMessage.assistant(
            '수정안을 되돌렸습니다. 현재 이력서 기준으로 첨삭을 다시 시작할 수 있습니다.',
          ),
        );
      });
    }
  });

  Future<Map<String, dynamic>> _mutate(
    Future<Map<String, dynamic>> Function() action,
  ) async {
    try {
      return await action();
    } on ResumeReviewApiException catch (error) {
      if (error.statusCode < 500) {
        _mutationPending = false;
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? activeQuestion;
    for (final message in _messages.reversed) {
      final questionId = message.question?['question_id'] as String?;
      if (message.question != null &&
          (questionId == null || !_answeredQuestionIds.contains(questionId))) {
        activeQuestion = message.question;
        break;
      }
    }
    final reviewCompleted =
        _result != null &&
        !_busy &&
        _error == null &&
        activeQuestion == null &&
        _pendingQuestion == null &&
        _questionQueue.isEmpty;
    return PopScope(
      canPop: !_busy && !_mutationPending,
      child: Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 1180,
          height: 760,
          child: Column(
            children: [
              _ReviewDialogHeader(
                job:
                    widget.generalReview
                        ? null
                        : _result?['job_source'] as Map? ??
                    {
                      'company': widget.jobCompany,
                      'title': widget.jobTitle,
                    },
                generalReview: widget.generalReview,
                canUndo: _application != null && !_undone,
                busy: _busy,
                onUndo: _undo,
                onClose: () => Navigator.pop(context),
              ),
              const Divider(height: 1),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontal = constraints.maxWidth >= 820;
                    final preview = _ResumeDraftPreview(
                      content: _preview,
                      changed: _changed,
                      highlightedFieldPath:
                          activeQuestion?['field_path'] as String?,
                      sectionKeys: _previewSectionKeys,
                    );
                    final chat = _ReviewChatPane(
                      messages: _messages,
                      busy: _busy,
                      error: _error,
                      resultAvailable: _result != null,
                      reviewCompleted: reviewCompleted,
                      awaitingSuggestionApply: _pendingQuestion != null,
                      generalReview: widget.generalReview,
                      answerController: _answerController,
                      scrollController: _chatScrollController,
                      activeQuestion: activeQuestion,
                      appliedSuggestionIndices: _appliedSuggestionIndices,
                      onStart: _review,
                      onAnswer: activeQuestion == null
                          ? null
                          : () => _submitAnswer(activeQuestion!),
                      onApply: _applySuggestion,
                      onClose: () => Navigator.pop(context),
                    );
                    if (!horizontal) {
                      return Column(
                        children: [
                          Expanded(child: preview),
                          const Divider(height: 1),
                          Expanded(child: chat),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: preview),
                        const VerticalDivider(width: 1),
                        Expanded(child: chat),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewDialogHeader extends StatelessWidget {
  const _ReviewDialogHeader({
    required this.job,
    required this.generalReview,
    required this.canUndo,
    required this.busy,
    required this.onUndo,
    required this.onClose,
  });

  final Map? job;
  final bool generalReview;
  final bool canUndo;
  final bool busy;
  final Future<void> Function() onUndo;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final jobLabel = '${job?['company'] ?? ''} ${job?['title'] ?? ''}'.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Color(0xFF16A34A), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  generalReview ? '이력서 첨삭' : '공고 맞춤 이력서 첨삭',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                if (generalReview)
                  const Text(
                    '문장 표현과 이력서 근거를 검토해 수정안을 제시합니다.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                  )
                else if (jobLabel.isNotEmpty)
                  Text(
                    jobLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                    ),
                  ),
              ],
            ),
          ),
          if (canUndo)
            TextButton.icon(
              onPressed: busy ? null : () => onUndo(),
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('되돌리기'),
            ),
          IconButton(
            tooltip: '닫기',
            onPressed: busy ? null : onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _ResumeDraftPreview extends StatelessWidget {
  const _ResumeDraftPreview({
    required this.content,
    required this.changed,
    required this.highlightedFieldPath,
    required this.sectionKeys,
  });

  final ResumeContent content;
  final bool changed;
  final String? highlightedFieldPath;
  final Map<String, GlobalKey> sectionKeys;

  static const _labels = {
    'coreCompetencies': '핵심 역량',
    'experience': '경력',
    'education': '학력',
    'techStack': '기술 스택',
    'certifications': '자격증',
    'awards': '수상 내역',
    'trainingExperience': '교육 경험',
    'otherActivities': '기타 활동',
    'projects': '프로젝트',
    'selfIntroduction': '자기소개서',
  };

  @override
  Widget build(BuildContext context) {
    final map = content.toMap();
    final info = Map<String, dynamic>.from(map['basicInfo'] as Map);
    return ColoredBox(
      color: const Color(0xFFF8FAFC),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      (info['name'] as String? ?? '').trim().isEmpty
                          ? '작성 중인 이력서'
                          : info['name'] as String,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (changed) const _PreviewUpdatedBadge(),
                ],
              ),
              if ((info['email'] as String? ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  info['email'] as String,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              for (final entry in _labels.entries)
                if (entry.key == 'selfIntroduction')
                  _SelfIntroductionPreview(
                    key: sectionKeys[entry.key],
                    sections: Map<String, dynamic>.from(
                      map[entry.key] as Map? ?? const <String, dynamic>{},
                    ),
                    highlightedFieldPath: highlightedFieldPath,
                    itemKeys: sectionKeys,
                  )
                else if (_render(map[entry.key]).isNotEmpty)
                  _PreviewSection(
                    key: sectionKeys[entry.key],
                    title: entry.value,
                    text: _render(map[entry.key]),
                    highlighted:
                        highlightedFieldPath?.startsWith('${entry.key}.') ==
                            true ||
                        highlightedFieldPath?.startsWith('${entry.key}[') ==
                            true,
                  ),
            ],
          ),
        ),
      ),
    );
  }

  static String _render(Object? value) {
    if (value is String) return value.trim();
    if (value is List) {
      return value.map(_render).where((text) => text.isNotEmpty).join('\n\n');
    }
    if (value is Map) {
      const ignored = {'id', 'url', 'githubUrl', 'blogUrl', 'isCurrent'};
      return value.entries
          .where((entry) => !ignored.contains(entry.key))
          .map((entry) => _render(entry.value))
          .where((text) => text.isNotEmpty)
          .join('\n');
    }
    return '';
  }
}

class _SelfIntroductionPreview extends StatelessWidget {
  const _SelfIntroductionPreview({
    super.key,
    required this.sections,
    required this.highlightedFieldPath,
    required this.itemKeys,
  });

  final Map<String, dynamic> sections;
  final String? highlightedFieldPath;
  final Map<String, GlobalKey> itemKeys;

  @override
  Widget build(BuildContext context) {
    final filled = ResumeSelfIntroLabels.keys
        .map((key) {
          final raw = sections[key];
          final section = raw is Map
              ? Map<String, dynamic>.from(raw)
              : const <String, dynamic>{};
          final body = (section['body'] as String? ?? '').trim();
          return (key: key, body: body);
        })
        .where((entry) => entry.body.isNotEmpty)
        .toList();
    if (filled.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            '자기소개서',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1D4ED8),
            ),
          ),
        ),
        for (final entry in filled)
          _PreviewSection(
            key: itemKeys['selfIntroduction.${entry.key}'],
            title: ResumeSelfIntroLabels.labels[entry.key] ?? entry.key,
            text: entry.body,
            highlighted:
                highlightedFieldPath?.startsWith(
                      'selfIntroduction.${entry.key}.',
                    ) ==
                    true ||
                highlightedFieldPath == 'selfIntroduction.${entry.key}',
          ),
      ],
    );
  }
}

class _PreviewUpdatedBadge extends StatelessWidget {
  const _PreviewUpdatedBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFFDCFCE7),
      borderRadius: BorderRadius.circular(99),
    ),
    child: const Text(
      '수정 반영됨',
      style: TextStyle(fontSize: 10, color: Color(0xFF15803D)),
    ),
  );
}

class _PreviewSection extends StatelessWidget {
  const _PreviewSection({
    super.key,
    required this.title,
    required this.text,
    required this.highlighted,
  });

  final String title;
  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 18),
    padding: highlighted ? const EdgeInsets.all(10) : EdgeInsets.zero,
    decoration: highlighted
        ? BoxDecoration(
            color: const Color(0xFFFFFBEA),
            border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
            borderRadius: BorderRadius.circular(8),
          )
        : null,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1D4ED8),
              ),
            ),
            if (highlighted) ...[
              const SizedBox(width: 7),
              const Text(
                'AI 질문 대상',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB45309),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 7),
        Text(text, style: const TextStyle(fontSize: 12, height: 1.55)),
      ],
    ),
  );
}

class _ReviewChatPane extends StatelessWidget {
  const _ReviewChatPane({
    required this.messages,
    required this.busy,
    required this.error,
    required this.resultAvailable,
    required this.reviewCompleted,
    required this.awaitingSuggestionApply,
    required this.generalReview,
    required this.answerController,
    required this.scrollController,
    required this.activeQuestion,
    required this.appliedSuggestionIndices,
    required this.onStart,
    required this.onAnswer,
    required this.onApply,
    required this.onClose,
  });

  final List<_ReviewChatMessage> messages;
  final bool busy;
  final String? error;
  final bool resultAvailable;
  final bool reviewCompleted;
  final bool awaitingSuggestionApply;
  final bool generalReview;
  final TextEditingController answerController;
  final ScrollController scrollController;
  final Map<String, dynamic>? activeQuestion;
  final Set<int> appliedSuggestionIndices;
  final Future<void> Function() onStart;
  final VoidCallback? onAnswer;
  final ValueChanged<List<int>> onApply;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.smart_toy_outlined,
                size: 18,
                color: Color(0xFF16A34A),
              ),
              const SizedBox(width: 7),
              const Text(
                'AI 첨삭 대화',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Text(
                generalReview
                    ? '문장 표현과 경험 근거를 함께 검토합니다.'
                    : '근거가 부족한 내용은 질문으로 확인합니다.',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SelectionArea(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(18),
              children: [
                if (!resultAvailable && !busy && error == null)
                  _ChatIntro(onStart: onStart, generalReview: generalReview),
                for (final message in messages)
                  _ReviewChatBubble(
                    message: message,
                    appliedSuggestionIndices: appliedSuggestionIndices,
                    onApply: onApply,
                  ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: LinearProgressIndicator(),
                  ),
                if (error != null)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Color(0xFFB91C1C)),
                    ),
                  ),
                if (reviewCompleted)
                  _ReviewCompletedNotice(
                    hasSuggestions: messages.any(
                      (message) =>
                          message.suggestion != null ||
                          message.identitySuggestion != null,
                    ),
                    onClose: onClose,
                  ),
              ],
            ),
          ),
        ),
        if (resultAvailable && !reviewCompleted)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Focus(
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.enter &&
                    !HardwareKeyboard.instance.isShiftPressed) {
                  onAnswer?.call();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: answerController,
                enabled: !busy && activeQuestion != null,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: activeQuestion == null
                      ? awaitingSuggestionApply
                          ? '수정안을 반영하면 다음 질문을 이어갑니다.'
                          : '현재 추가 확인 질문이 없습니다.'
                      : '답변을 입력하세요. (Enter 전송 · Shift+Enter 줄바꿈)',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixIcon: IconButton(
                    tooltip: '답변 보내기',
                    onPressed: onAnswer,
                    icon: const Icon(Icons.send, color: Color(0xFF2563EB)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReviewCompletedNotice extends StatelessWidget {
  const _ReviewCompletedNotice({
    required this.hasSuggestions,
    required this.onClose,
  });

  final bool hasSuggestions;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF0FDF4),
      border: Border.all(color: const Color(0xFF86EFAC)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 22),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '첨삭 완료',
                style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF166534)),
              ),
              const SizedBox(height: 2),
              Text(
                hasSuggestions
                    ? '추가 확인 질문이 없습니다. 표시된 수정안은 원하는 것만 반영한 뒤 마칠 수 있습니다.'
                    : '추가 확인 질문과 적용할 수정안이 없습니다. 첨삭을 마칠 수 있습니다.',
                style: const TextStyle(fontSize: 11, height: 1.4, color: Color(0xFF166534)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: onClose,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF16A34A),
            foregroundColor: Colors.white,
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('첨삭 완료'),
        ),
      ],
    ),
  );
}

class _ChatIntro extends StatelessWidget {
  const _ChatIntro({required this.onStart, required this.generalReview});

  final Future<void> Function() onStart;
  final bool generalReview;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.only(top: 72),
      child: Column(
        children: [
          const Icon(Icons.auto_awesome, size: 34, color: Color(0xFF16A34A)),
          const SizedBox(height: 12),
          Text(
            generalReview
                ? '이력서 문장과 경험 근거를 확인합니다.'
                : '선택 공고 기준으로 이력서를 확인합니다.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            generalReview
                ? '필요한 사실은 질문으로 확인하고, 맞춤법·문법·표현도 함께 다듬습니다.'
                : '부족한 사실은 AI가 질문하고, 답변을 근거로 수정안을 제시합니다.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => onStart(),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('첨삭 시작'),
          ),
        ],
      ),
    ),
  );
}

class _ReviewChatBubble extends StatelessWidget {
  const _ReviewChatBubble({
    required this.message,
    required this.appliedSuggestionIndices,
    required this.onApply,
  });

  final _ReviewChatMessage message;
  final Set<int> appliedSuggestionIndices;
  final ValueChanged<List<int>> onApply;

  static const _revisionTextStyle = TextStyle(
    fontSize: 12,
    height: 1.5,
    color: Color(0xFF1F2937),
  );

  /// 수정안에 실제로 새로 들어간 글자만 굵게 표시한다.
  /// 원문과 수정안을 LCS로 비교하므로 앞·뒤에 여러 수정이 있어도
  /// 변경되지 않은 중간 문장이 함께 굵어지지 않는다.
  static List<InlineSpan> _changedRevisionSpans(String original, String revision) {
    if (original == revision) return [TextSpan(text: revision)];
    final before = original.runes.toList();
    final after = revision.runes.toList();
    if (before.isEmpty) {
      return [TextSpan(text: revision, style: const TextStyle(fontWeight: FontWeight.w700))];
    }
    if (after.isEmpty) return const [];

    // 긴 문장을 여러 장 보여도 화면이 무거워지지 않도록 안전한 상한을 둔다.
    if (before.length * after.length > 300000) {
      return _fallbackChangedRevisionSpans(before, after);
    }

    final table = List<Uint16List>.generate(
      before.length + 1,
      (_) => Uint16List(after.length + 1),
    );
    for (var i = before.length - 1; i >= 0; i--) {
      for (var j = after.length - 1; j >= 0; j--) {
        table[i][j] = before[i] == after[j]
            ? table[i + 1][j + 1] + 1
            : max(table[i + 1][j], table[i][j + 1]);
      }
    }

    final characters = <String>[];
    final changed = <bool>[];
    var i = 0;
    var j = 0;
    while (i < before.length && j < after.length) {
      if (before[i] == after[j]) {
        characters.add(String.fromCharCode(after[j]));
        changed.add(false);
        i++;
        j++;
      } else if (table[i + 1][j] >= table[i][j + 1]) {
        // 원문에서 삭제된 글자는 수정안에 표시하지 않는다.
        i++;
      } else {
        characters.add(String.fromCharCode(after[j]));
        changed.add(true);
        j++;
      }
    }
    while (j < after.length) {
      characters.add(String.fromCharCode(after[j++]));
      changed.add(true);
    }
    return _buildDiffSpans(characters, changed);
  }

  static List<InlineSpan> _fallbackChangedRevisionSpans(
    List<int> before,
    List<int> after,
  ) {
    var prefix = 0;
    while (prefix < before.length &&
        prefix < after.length &&
        before[prefix] == after[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < before.length - prefix &&
        suffix < after.length - prefix &&
        before[before.length - 1 - suffix] == after[after.length - 1 - suffix]) {
      suffix++;
    }
    final characters = <String>[];
    final changed = <bool>[];
    for (var index = 0; index < after.length; index++) {
      characters.add(String.fromCharCode(after[index]));
      changed.add(index >= prefix && index < after.length - suffix);
    }
    return _buildDiffSpans(characters, changed);
  }

  static List<InlineSpan> _buildDiffSpans(
    List<String> characters,
    List<bool> changed,
  ) {
    final spans = <InlineSpan>[];
    var start = 0;
    while (start < characters.length) {
      final isChanged = changed[start];
      var end = start + 1;
      while (end < characters.length && changed[end] == isChanged) {
        end++;
      }
      spans.add(TextSpan(
        text: characters.sublist(start, end).join(),
        style: isChanged ? const TextStyle(fontWeight: FontWeight.w700) : null,
      ));
      start = end;
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    if (message.identitySuggestion != null) {
      final item = message.identitySuggestion!;
      final indices = (item['_indices'] as List? ?? [item['_index']])
          .whereType<int>()
          .toList();
      final company = item['_company'] as String? ?? '';
      final title = item['_title'] as String? ?? '';
      final applied = indices.isNotEmpty &&
          indices.every(appliedSuggestionIndices.contains);
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          constraints: const BoxConstraints(maxWidth: 410),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFBBF7D0)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                indices.length > 1
                    ? '이력서의 ${indices.length}개 항목에 있는 회사명·직무명 자리표시자를 $company / $title(으)로 한 번에 반영할까요?'
                    : '회사명을 $company, 직무명을 $title(으)로 변경할까요?',
                style: const TextStyle(fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 9),
              FilledButton.icon(
                onPressed: applied ? null : () => onApply(indices),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.check, size: 15),
                label: Text(applied ? '반영됨' : '네, 변경할게요'),
              ),
            ],
          ),
        ),
      );
    }
    if (message.suggestion != null) {
      final item = message.suggestion!;
      final index = item['_index'] as int;
      final applied = appliedSuggestionIndices.contains(index);
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        color: const Color(0xFFF0FDF4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AI 수정안',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF166534),
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                '원문',
                style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 3),
              Text(
                item['original_quote'] as String? ?? '',
                style: _revisionTextStyle,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 9),
                child: Divider(height: 1, thickness: 0.6, color: Color(0x33000000)),
              ),
              const Text(
                '수정안',
                style: TextStyle(fontSize: 11, color: Color(0xFF166534)),
              ),
              const SizedBox(height: 3),
              Text.rich(
                TextSpan(
                  style: _revisionTextStyle,
                  children: _changedRevisionSpans(
                    item['original_quote'] as String? ?? '',
                    item['suggested_revision'] as String? ?? '',
                  ),
                ),
              ),
              if ((item['reason'] as String? ?? '').isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  item['reason'] as String,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF4B5563),
                  ),
                ),
              ],
              const SizedBox(height: 9),
              FilledButton.icon(
                onPressed: applied ? null : () => onApply([index]),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.check, size: 15),
                label: Text(applied ? '반영됨' : '이 문장으로 바꾸기'),
              ),
            ],
          ),
        ),
      );
    }

    final isUser = message.isUser;
    final text = message.question?['question'] as String? ?? message.text;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: const BoxConstraints(maxWidth: 410),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF2563EB) : Colors.white,
          border: isUser ? null : Border.all(color: const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.45,
            color: isUser ? Colors.white : const Color(0xFF1F2937),
          ),
        ),
      ),
    );
  }
}

class _ReviewChatMessage {
  const _ReviewChatMessage.assistant(this.text)
    : isUser = false,
      question = null,
      suggestion = null,
      identitySuggestion = null;
  const _ReviewChatMessage.user(this.text)
    : isUser = true,
      question = null,
      suggestion = null,
      identitySuggestion = null;
  const _ReviewChatMessage.question(this.question)
    : text = '',
      isUser = false,
      suggestion = null,
      identitySuggestion = null;
  const _ReviewChatMessage.suggestion(this.suggestion)
    : text = '',
      isUser = false,
      question = null,
      identitySuggestion = null;
  const _ReviewChatMessage.identityConfirmation(this.identitySuggestion)
    : text = '',
      isUser = false,
      question = null,
      suggestion = null;

  final String text;
  final bool isUser;
  final Map<String, dynamic>? question;
  final Map<String, dynamic>? suggestion;
  final Map<String, dynamic>? identitySuggestion;
}
