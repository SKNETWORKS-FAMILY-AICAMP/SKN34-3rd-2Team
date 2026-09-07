import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../shared/models/resume_content.dart';
import '../data/resume_review_api_client.dart';

class JobResumeReviewDialog extends StatefulWidget {
  const JobResumeReviewDialog({
    super.key,
    required this.client,
    required this.cohortId,
    required this.resumeId,
    required this.jobId,
    required this.draft,
    required this.onChanged,
  });
  final ResumeReviewApiClient client;
  final String cohortId, resumeId, jobId;
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
  bool _busy = false, _changed = false, _undone = false;
  bool _mutationPending = false;
  String? _error;
  String _id() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 30)}';
  Map<String, dynamic> get _identity => {
    'cohort_id': widget.cohortId,
    'resume_id': widget.resumeId,
  };

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
  });

  Future<void> _reload() async {
    final snapshot = await widget.client.context(
      widget.cohortId,
      widget.resumeId,
    );
    widget.onChanged(
      ResumeContent.fromMap(
        Map<String, dynamic>.from(snapshot['content'] as Map),
      ),
    );
    _changed = true;
    _mutationPending = false;
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

  Future<Map<String, dynamic>> _mutate(Future<Map<String, dynamic>> Function() action) async {
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
    final edits = (_result?['sentence_reviews'] as List? ?? []).cast<Map>();
    final questions = (_result?['questions'] as List? ?? []).cast<Map>();
    return PopScope(
      canPop: !_busy && !_mutationPending,
      child: AlertDialog(
        title: const Text('선택 공고 맞춤 이력서 첨삭'),
        content: SizedBox(
          width: 680,
          height: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '저장된 본인 이력서와 서버의 공고 원문을 사용합니다. 첨삭 실행 시 LLM API 비용이 발생하며, 선택 적용 전에는 원문이 바뀌지 않습니다.',
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                if (_result != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${(_result!['job_source'] as Map?)?['company'] ?? ''} · ${(_result!['job_source'] as Map?)?['title'] ?? ''}',
                  ),
                  Text(_result!['summary'] as String? ?? ''),
                  SelectableText('공고 출처: ${(_result!['job_source'] as Map?)?['source_url'] ?? ''}'),
                  for (var i = 0; i < edits.length; i++)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${edits[i]['field_path']} · ${_label(edits[i]['edit_type'])}',
                            ),
                            Text('원문: ${edits[i]['original_quote']}'),
                            if (edits[i]['suggested_revision'] != null)
                              Text('수정안: ${edits[i]['suggested_revision']}'),
                            Text('이유: ${edits[i]['reason']}'),
                            Text(
                              '근거: ${(edits[i]['evidence_quotes'] as List? ?? []).join(' / ')}',
                            ),
                            if (edits[i]['confirmation_question'] != null)
                              Text('확인: ${edits[i]['confirmation_question']}'),
                            if (edits[i]['suggested_revision'] != null &&
                                [
                                  'formatting',
                                  'improved',
                                ].contains(edits[i]['status']) &&
                                (edits[i]['validation_issues'] as List? ?? [])
                                    .isEmpty)
                              CheckboxListTile(
                                title: const Text('이 수정안 적용'),
                                value: _selected.contains(i),
                                onChanged: _busy || _applyRequest != null
                                    ? null
                                    : (value) => setState(() {
                                        if (value == true) {
                                          _selected.add(i);
                                        } else {
                                          _selected.remove(i);
                                        }
                                      }),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (edits.isEmpty)
                    const Text('적용할 문장 수정안이 없습니다. 아래 확인 질문과 진단을 확인해 주세요.'),
                  for (final q in questions) Text('확인 질문: ${q['question']}'),
                  for (final section
                      in (_result!['section_reviews'] as List? ?? [])
                          .cast<Map>())
                    for (final issue in (section['issues'] as List? ?? []))
                      Text('보완점: $issue'),
                  for (final warning
                      in _result!['grounding_warnings'] as List? ?? [])
                    Text('검증 안내: $warning'),
                  if (_application != null)
                    Text(_undone ? '원본으로 되돌렸습니다.' : '선택한 수정안이 서버에 적용되었습니다.'),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (_result == null)
            FilledButton(
              onPressed: _busy ? null : _review,
              child: const Text('첨삭 실행 / 재시도'),
            ),
          if (_result != null && _application == null)
            FilledButton(
              onPressed: _busy || _selected.isEmpty ? null : _apply,
              child: const Text('선택 수정안 저장 / 재시도'),
            ),
          if (_application != null && !_undone)
            TextButton(
              onPressed: _busy ? null : _undo,
              child: const Text('적용 되돌리기'),
            ),
          if (_application != null && !_changed)
            TextButton(
              onPressed: _busy ? null : () => _run(_reload),
              child: const Text('저장 결과 다시 불러오기'),
            ),
          TextButton(
            onPressed: _busy || _mutationPending
                ? null
                : () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  String _label(Object? value) => switch (value) {
    'spelling' => '맞춤법·띄어쓰기',
    'tone' => '말투',
    'clarity' => '가독성',
    'none' => '유지',
    _ => '내용 보완',
  };
}
