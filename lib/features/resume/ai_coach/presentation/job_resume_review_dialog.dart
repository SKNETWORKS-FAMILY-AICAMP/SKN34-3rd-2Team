import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/models/resume_content.dart';
import '../data/resume_review_api_client.dart';

class JobResumeReviewDialog extends StatefulWidget {
  const JobResumeReviewDialog({
    super.key,
    required this.client,
    required this.cohortId,
    required this.resumeId,
    required this.jobId,
    required this.jobCompany,
    required this.jobTitle,
    required this.draft,
    required this.onChanged,
  });
  final ResumeReviewApiClient client;
  final String cohortId, resumeId, jobId, jobCompany, jobTitle;
  final ResumeContent draft;
  final ValueChanged<ResumeContent> onChanged;

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
  final TextEditingController _answerController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final List<_ReviewChatMessage> _messages = [];
  final Set<String> _answeredQuestionIds = {};
  final Map<String, GlobalKey> _previewSectionKeys = {};
  bool _busy = false, _changed = false, _undone = false;
  bool _mutationPending = false;
  String? _error;
  String? _focusedFieldPath;
  late ResumeContent _preview;
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
  }

  @override
  void dispose() {
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
    if (_reviewRequest == null) {
      final snapshot = await widget.client.context(
        widget.cohortId,
        widget.resumeId,
        job: widget.jobId,
      );
      final content = Map<String, dynamic>.from(snapshot['content'] as Map);
      if (!sameResumeContent(widget.draft, content)) {
        throw const FormatException(
          '화면과 저장된 이력서가 다릅니다. 창을 닫고 저장 또는 새로고침한 뒤 다시 추천해 주세요.',
        );
      }
      _reviewRequest = {
        ..._identity,
        'request_id': _id(),
        'selected_job_id': widget.jobId,
        'expected_input_hash': snapshot['input_hash'],
        'expected_job_hash': (snapshot['job_source'] as Map)['snapshot_hash'],
      };
    }
    _result = await widget.client.review(_reviewRequest!);
    _appendReview(_result!, isFirstReview: _messages.isEmpty);
  });

  Future<void> _reload() async {
    final snapshot = await widget.client.context(
      widget.cohortId,
      widget.resumeId,
    );
    final content = ResumeContent.fromMap(
      Map<String, dynamic>.from(snapshot['content'] as Map),
    );
    widget.onChanged(content);
    if (mounted) {
      setState(() {
        _preview = content;
        _changed = true;
        _mutationPending = false;
        _messages.add(
          const _ReviewChatMessage.assistant(
            '수정안이 왼쪽 이력서 미리보기에 반영되었습니다. 최종 저장 전 내용을 확인해 주세요.',
          ),
        );
      });
    }
  }

  void _appendReview(
    Map<String, dynamic> review, {
    required bool isFirstReview,
    String? answeredFieldPath,
  }) {
    if (isFirstReview) {
      _messages.add(
        _ReviewChatMessage.assistant(
          review['summary'] as String? ?? '이력서와 선택 공고를 비교했습니다.',
        ),
      );
    }
    final reviews = (review['sentence_reviews'] as List? ?? []).cast<Map>();
    final job = Map<String, dynamic>.from(
      review['job_source'] as Map? ??
          {'company': widget.jobCompany, 'title': widget.jobTitle},
    );
    var displayedSuggestions = 0;
    for (var index = 0; index < reviews.length; index++) {
      final sentence = Map<String, dynamic>.from(reviews[index]);
      if (answeredFieldPath != null &&
          sentence['field_path'] != answeredFieldPath) {
        continue;
      }
      if (sentence['suggested_revision'] is String &&
          (sentence['suggested_revision'] as String).trim().isNotEmpty) {
        sentence['_index'] = index;
        if (_isIdentityPlaceholderSuggestion(sentence)) {
          sentence['_company'] = job['company'] ?? widget.jobCompany;
          sentence['_title'] = job['title'] ?? widget.jobTitle;
          _messages.add(_ReviewChatMessage.identityConfirmation(sentence));
          _focusPreviewField(sentence['field_path'] as String?);
        } else {
          _messages.add(_ReviewChatMessage.suggestion(sentence));
        }
        displayedSuggestions++;
      }
    }
    if (!isFirstReview && displayedSuggestions == 0) {
      _messages.add(
        const _ReviewChatMessage.assistant(
          '방금 답한 항목에서 수정안에 사용할 새로운 사실을 확인하지 못했습니다. 없는 내용은 만들어 넣지 않습니다.',
        ),
      );
    }
    final questions = (review['questions'] as List? ?? []).cast<Map>();
    if (questions.isNotEmpty) {
      final question = Map<String, dynamic>.from(questions.first);
      _messages.add(_ReviewChatMessage.question(question));
      _focusPreviewField(question['field_path'] as String?);
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

  bool _isIdentityPlaceholderSuggestion(Map<String, dynamic> sentence) {
    final original = sentence['original_quote'] as String? ?? '';
    return original.contains('[회사명]') || original.contains('[직무명]');
  }

  String _sectionForFieldPath(String fieldPath) =>
      fieldPath.split(RegExp(r'[.\[]')).first;

  GlobalKey _previewKeyFor(String fieldPath) => _previewSectionKeys.putIfAbsent(
    _sectionForFieldPath(fieldPath),
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
        'selected_job_id': widget.jobId,
        'expected_job_hash': (previous['job_source'] as Map?)?['snapshot_hash'],
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
      _appendReview(
        _result!,
        isFirstReview: false,
        answeredFieldPath: question['field_path'] as String?,
      );
    });
  }

  Future<void> _applySuggestion(int index) async {
    if (_busy || _application != null) return;
    setState(() {
      _selected
        ..clear()
        ..add(index);
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
    };
    _application = await _mutate(() => widget.client.apply(_applyRequest!));
    await _reload();
  });

  Future<void> _undo() => _run(() async {
    _mutationPending = true;
    _changed = false;
    _undoRequest ??= {
      ..._identity,
      'request_id': _id(),
      'application_id': _application!['operation_id'],
      'expected_input_hash': _application!['input_hash'],
    };
    await _mutate(() => widget.client.undo(_undoRequest!));
    _undone = true;
    await _reload();
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
                    _result?['job_source'] as Map? ??
                    {
                      'company': widget.jobCompany,
                      'title': widget.jobTitle,
                    },
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
                      answerController: _answerController,
                      scrollController: _chatScrollController,
                      activeQuestion: activeQuestion,
                      applicationDone: _application != null,
                      onStart: _review,
                      onAnswer: activeQuestion == null
                          ? null
                          : () => _submitAnswer(activeQuestion!),
                      onApply: _applySuggestion,
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
    required this.canUndo,
    required this.busy,
    required this.onUndo,
    required this.onClose,
  });

  final Map? job;
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
                const Text(
                  '공고 맞춤 이력서 첨삭',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                if (jobLabel.isNotEmpty)
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
                if (_render(map[entry.key]).isNotEmpty)
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
    required this.answerController,
    required this.scrollController,
    required this.activeQuestion,
    required this.applicationDone,
    required this.onStart,
    required this.onAnswer,
    required this.onApply,
  });

  final List<_ReviewChatMessage> messages;
  final bool busy;
  final String? error;
  final bool resultAvailable;
  final TextEditingController answerController;
  final ScrollController scrollController;
  final Map<String, dynamic>? activeQuestion;
  final bool applicationDone;
  final Future<void> Function() onStart;
  final VoidCallback? onAnswer;
  final ValueChanged<int> onApply;

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
          child: const Row(
            children: [
              Icon(
                Icons.smart_toy_outlined,
                size: 18,
                color: Color(0xFF16A34A),
              ),
              SizedBox(width: 7),
              Text('AI 첨삭 대화', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(width: 8),
              Text(
                '근거가 부족한 내용은 질문으로 확인합니다.',
                style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(18),
            children: [
              if (!resultAvailable && !busy && error == null)
                _ChatIntro(onStart: onStart),
              for (final message in messages)
                _ReviewChatBubble(
                  message: message,
                  applicationDone: applicationDone,
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
            ],
          ),
        ),
        if (resultAvailable)
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
                      ? '현재 추가 확인 질문이 없습니다.'
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

class _ChatIntro extends StatelessWidget {
  const _ChatIntro({required this.onStart});

  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.only(top: 72),
      child: Column(
        children: [
          const Icon(Icons.auto_awesome, size: 34, color: Color(0xFF16A34A)),
          const SizedBox(height: 12),
          const Text(
            '선택 공고 기준으로 이력서를 확인합니다.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            '부족한 사실은 AI가 질문하고, 답변을 근거로 수정안을 제시합니다.',
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
    required this.applicationDone,
    required this.onApply,
  });

  final _ReviewChatMessage message;
  final bool applicationDone;
  final ValueChanged<int> onApply;

  @override
  Widget build(BuildContext context) {
    if (message.identitySuggestion != null) {
      final item = message.identitySuggestion!;
      final index = item['_index'] as int;
      final company = item['_company'] as String? ?? '';
      final title = item['_title'] as String? ?? '';
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
                '회사명을 $company, 직무명을 $title(으)로 변경할까요?',
                style: const TextStyle(fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 9),
              FilledButton.icon(
                onPressed: applicationDone ? null : () => onApply(index),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.check, size: 15),
                label: const Text('네, 변경할게요'),
              ),
            ],
          ),
        ),
      );
    }
    if (message.suggestion != null) {
      final item = message.suggestion!;
      final index = item['_index'] as int;
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
              Text(
                '원문  ${item['original_quote'] ?? ''}',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 5),
              Text(
                '수정안  ${item['suggested_revision'] ?? ''}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
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
                onPressed: applicationDone ? null : () => onApply(index),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.check, size: 15),
                label: const Text('이 문장으로 바꾸기'),
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
