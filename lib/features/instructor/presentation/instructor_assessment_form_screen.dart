import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/demo/demo_accounts.dart';
import '../../../shared/models/assessment_model.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../../shared/providers/lms_providers.dart';
import '../../../shared/services/storage_service.dart';
import '../../assessments/data/assessment_functions_service.dart';
import '../../assessments/presentation/widgets/assessment_question_view.dart';

/// 강사 — 평가 생성/수정 + 문제 편집 + 문제 생성 AI
class InstructorAssessmentFormScreen extends ConsumerStatefulWidget {
  const InstructorAssessmentFormScreen({super.key, this.assessmentId});

  final String? assessmentId;

  @override
  ConsumerState<InstructorAssessmentFormScreen> createState() =>
      _InstructorAssessmentFormScreenState();
}

class _InstructorAssessmentFormScreenState
    extends ConsumerState<InstructorAssessmentFormScreen> {
  final _title = TextEditingController();
  final _tags = TextEditingController();
  DateTime _startAt = DateTime.now();
  DateTime _endAt = DateTime.now().add(const Duration(days: 7));
  String? _thumbnailUrl;
  String? _thumbnailPath;
  Uint8List? _pendingThumbBytes;
  String? _pendingThumbName;
  var _published = false;
  var _loading = false;
  var _initialized = false;
  final List<AssessmentQuestionModel> _questions = [];

  bool get _isEdit => widget.assessmentId != null;

  @override
  void dispose() {
    _title.dispose();
    _tags.dispose();
    super.dispose();
  }

  void _hydrate(AssessmentModel a, List<AssessmentQuestionModel> qs) {
    if (_initialized) return;
    _title.text = a.title;
    _tags.text = a.tags.join(', ');
    _startAt = a.startAt;
    _endAt = a.endAt;
    _thumbnailUrl = a.thumbnailUrl;
    _thumbnailPath = a.thumbnailPath;
    _published = a.published;
    _questions
      ..clear()
      ..addAll(qs);
    _initialized = true;
  }

  Future<void> _pickThumbnail() async {
    final picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked.isEmpty) return;
    final f = picked.first;
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pendingThumbBytes = bytes;
      _pendingThumbName = f.name;
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startAt : _endAt;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startAt = dt;
      } else {
        _endAt = dt;
      }
    });
  }

  Future<String> _ensureAssessmentId() async {
    if (widget.assessmentId != null) return widget.assessmentId!;
    final cohortId = ref.read(effectiveCohortIdProvider)!;
    final user = ref.read(currentUserSyncProvider)!;
    final tags = _tags.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return ref.read(lmsRepositoryProvider).createAssessment(
          cohortId: cohortId,
          assessment: AssessmentModel(
            id: '',
            title: _title.text.trim().isEmpty ? '새 성취도평가' : _title.text.trim(),
            tags: tags,
            questionCount: 0,
            maxScore: 0,
            startAt: _startAt,
            endAt: _endAt,
            published: false,
            createdBy: user.uid,
          ),
        );
  }

  Future<void> _save({bool publish = false}) async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목을 입력해 주세요.')),
      );
      return;
    }
    if (_questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('문제를 1개 이상 추가해 주세요.')),
      );
      return;
    }

    final cohortId = ref.read(effectiveCohortIdProvider);
    final user = ref.read(currentUserSyncProvider);
    if (cohortId == null || user == null) return;

    setState(() => _loading = true);
    try {
      final id = await _ensureAssessmentId();
      var thumbUrl = _thumbnailUrl;
      var thumbPath = _thumbnailPath;

      if (_pendingThumbBytes != null) {
        if (DemoConfig.enabled) {
          thumbUrl = 'demo://thumb/${_pendingThumbName ?? 'thumb.png'}';
          thumbPath = thumbUrl;
        } else {
          final name = _pendingThumbName ?? 'thumb.jpg';
          final path = StorageService.assessmentThumbnailPath(
            cohortId: cohortId,
            assessmentId: id,
            fileName: name,
          );
          final contentType = name.toLowerCase().endsWith('.png')
              ? 'image/png'
              : name.toLowerCase().endsWith('.webp')
                  ? 'image/webp'
                  : 'image/jpeg';
          thumbUrl = await ref.read(storageServiceProvider).uploadAndGetUrl(
                storagePath: path,
                bytes: _pendingThumbBytes!,
                contentType: contentType,
              );
          thumbPath = path;
        }
      }

      final tags = _tags.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      await ref.read(lmsRepositoryProvider).updateAssessment(
            cohortId: cohortId,
            assessmentId: id,
            updates: {
              'title': title,
              'tags': tags,
              'startAt': _startAt,
              'endAt': _endAt,
              if (thumbUrl != null) 'thumbnailUrl': thumbUrl,
              if (thumbPath != null) 'thumbnailPath': thumbPath,
              'published': publish || _published,
            },
          );

      await ref.read(lmsRepositoryProvider).replaceAssessmentQuestions(
            cohortId: cohortId,
            assessmentId: id,
            questions: _questions,
          );

      if (publish) {
        await ref.read(lmsRepositoryProvider).publishAssessment(
              cohortId: cohortId,
              assessmentId: id,
            );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(publish ? '발행되었습니다.' : '저장되었습니다.'),
        ),
      );
      if (!_isEdit) {
        context.go(RoutePaths.instructorAssessmentDetailPath(id));
      } else {
        context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editQuestion([AssessmentQuestionModel? existing, int? index]) async {
    final result = await showDialog<AssessmentQuestionModel>(
      context: context,
      builder: (ctx) => _QuestionEditorDialog(initial: existing),
    );
    if (result == null) return;
    setState(() {
      if (index != null) {
        _questions[index] = result.copyWith(order: index);
      } else {
        _questions.add(result.copyWith(order: _questions.length));
      }
    });
  }

  Future<void> _openCurriculumAi() async {
    final drafts = await showDialog<List<AssessmentQuestionModel>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _CurriculumAiDialog(),
    );
    if (drafts == null || drafts.isEmpty) return;
    setState(() {
      for (final q in drafts) {
        _questions.add(q.copyWith(order: _questions.length));
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.listenManual(
          assessmentProvider(widget.assessmentId!),
          (prev, next) {
            next.whenData((a) {
              if (a == null || _initialized) return;
              final qs = ref
                      .read(assessmentQuestionsProvider(widget.assessmentId!))
                      .asData
                      ?.value ??
                  [];
              setState(() => _hydrate(a, qs));
            });
          },
          fireImmediately: true,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceVariant,
      appBar: AppBar(
        title: Text(_isEdit ? '평가 수정' : '평가 만들기'),
        actions: [
          TextButton(
            onPressed: _loading ? null : () => _save(publish: false),
            child: const Text('저장'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _loading ? null : () => _save(publish: true),
              child: const Text('발행'),
            ),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _title,
                      decoration: const InputDecoration(
                        labelText: '제목',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _tags,
                      decoration: const InputDecoration(
                        labelText: '태그 (쉼표 구분)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickDate(isStart: true),
                            child: Text(
                              '시작: ${_startAt.toString().substring(0, 16)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickDate(isStart: false),
                            child: Text(
                              '종료: ${_endAt.toString().substring(0, 16)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (_pendingThumbBytes != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              _pendingThumbBytes!,
                              width: 96,
                              height: 54,
                              fit: BoxFit.cover,
                            ),
                          )
                        else if (_thumbnailUrl != null &&
                            _thumbnailUrl!.startsWith('http'))
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              _thumbnailUrl!,
                              width: 96,
                              height: 54,
                              fit: BoxFit.cover,
                            ),
                          )
                        else
                          Container(
                            width: 96,
                            height: 54,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.image_outlined),
                          ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _pickThumbnail,
                          icon: const Icon(Icons.upload),
                          label: const Text('썸네일'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '문제',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _openCurriculumAi,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.auto_awesome, size: 20),
                        label: const Text(
                          '문제 생성 AI',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () => _editQuestion(),
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('수동 추가'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_questions.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 36,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.quiz_outlined,
                        size: 40,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '아직 문제가 없습니다',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '문제 생성 AI로 초안을 만들거나\n수동으로 추가해 보세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ..._questions.asMap().entries.map((e) {
                  final q = e.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: AssessmentQuestionView(
                      number: e.key + 1,
                      prompt: q.prompt,
                      points: q.points,
                      type: q.type.value,
                      choices: q.choices,
                      correctIndex: q.correctIndex,
                      acceptedAnswers: q.acceptedAnswers,
                      explanation: q.explanation,
                      mode: AssessmentQuestionViewMode.preview,
                      footer: Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => _editQuestion(q, e.key),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('수정'),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _questions.removeAt(e.key)),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.error,
                            ),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('삭제'),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestionEditorDialog extends StatefulWidget {
  const _QuestionEditorDialog({this.initial});

  final AssessmentQuestionModel? initial;

  @override
  State<_QuestionEditorDialog> createState() => _QuestionEditorDialogState();
}

class _QuestionEditorDialogState extends State<_QuestionEditorDialog> {
  late AssessmentQuestionType _type;
  late final TextEditingController _prompt;
  late final TextEditingController _points;
  late final TextEditingController _choices;
  late final TextEditingController _accepted;
  late final TextEditingController _explanation;
  int _correctIndex = 0;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _type = i?.type ?? AssessmentQuestionType.multipleChoice;
    _prompt = TextEditingController(text: i?.prompt ?? '');
    _points = TextEditingController(text: '${i?.points ?? 4}');
    _choices = TextEditingController(text: (i?.choices ?? const []).join('\n'));
    _accepted =
        TextEditingController(text: (i?.acceptedAnswers ?? const []).join('\n'));
    _explanation = TextEditingController(text: i?.explanation ?? '');
    _correctIndex = i?.correctIndex ?? 0;
  }

  @override
  void dispose() {
    _prompt.dispose();
    _points.dispose();
    _choices.dispose();
    _accepted.dispose();
    _explanation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '문제 추가' : '문제 수정'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<AssessmentQuestionType>(
                value: _type,
                items: const [
                  DropdownMenuItem(
                    value: AssessmentQuestionType.multipleChoice,
                    child: Text('객관식'),
                  ),
                  DropdownMenuItem(
                    value: AssessmentQuestionType.shortAnswer,
                    child: Text('단답'),
                  ),
                ],
                onChanged: (v) => setState(() => _type = v!),
                decoration: const InputDecoration(labelText: '유형'),
              ),
              TextField(
                controller: _prompt,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '문제'),
              ),
              TextField(
                controller: _points,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '배점'),
              ),
              if (_type == AssessmentQuestionType.multipleChoice) ...[
                TextField(
                  controller: _choices,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '선택지 (줄바꿈 구분)',
                  ),
                ),
                TextField(
                  decoration: const InputDecoration(
                    labelText: '정답 인덱스 (0부터)',
                  ),
                  keyboardType: TextInputType.number,
                  controller: TextEditingController(text: '$_correctIndex'),
                  onChanged: (v) =>
                      _correctIndex = int.tryParse(v) ?? _correctIndex,
                ),
              ] else
                TextField(
                  controller: _accepted,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '정답 후보 (줄바꿈 구분)',
                  ),
                ),
              TextField(
                controller: _explanation,
                decoration: const InputDecoration(labelText: '해설 (선택)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            final choices = _choices.text
                .split('\n')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
            final accepted = _accepted.text
                .split('\n')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
            Navigator.pop(
              context,
              AssessmentQuestionModel(
                id: widget.initial?.id ?? 'draft_${DateTime.now().millisecondsSinceEpoch}',
                order: widget.initial?.order ?? 0,
                type: _type,
                prompt: _prompt.text.trim(),
                points: int.tryParse(_points.text.trim()) ?? 4,
                choices: choices,
                correctIndex: _type == AssessmentQuestionType.multipleChoice
                    ? _correctIndex
                    : null,
                acceptedAnswers: accepted,
                explanation: _explanation.text.trim().isEmpty
                    ? null
                    : _explanation.text.trim(),
              ),
            );
          },
          child: const Text('확인'),
        ),
      ],
    );
  }
}

class _CurriculumAiDialog extends ConsumerStatefulWidget {
  const _CurriculumAiDialog();

  @override
  ConsumerState<_CurriculumAiDialog> createState() =>
      _CurriculumAiDialogState();
}

class _CurriculumAiDialogState extends ConsumerState<_CurriculumAiDialog> {
  var _generating = false;
  String? _error;
  late final TextEditingController _dayFromCtrl;
  late final TextEditingController _dayToCtrl;
  late final TextEditingController _mcCtrl;
  late final TextEditingController _saCtrl;
  var _rangeSeeded = false;

  @override
  void initState() {
    super.initState();
    _dayFromCtrl = TextEditingController(text: '1');
    _dayToCtrl = TextEditingController(text: '7');
    _mcCtrl = TextEditingController(text: '5');
    _saCtrl = TextEditingController(text: '3');
  }

  @override
  void dispose() {
    _dayFromCtrl.dispose();
    _dayToCtrl.dispose();
    _mcCtrl.dispose();
    _saCtrl.dispose();
    super.dispose();
  }

  void _seedRangeIfNeeded(int minDay, int maxDay) {
    if (_rangeSeeded) return;
    _rangeSeeded = true;
    _dayFromCtrl.text = '$minDay';
    _dayToCtrl.text = '${(minDay + 6).clamp(minDay, maxDay)}';
  }

  Future<void> _generate() async {
    final sheet = ref.read(latestCurriculumSheetProvider).asData?.value;
    if (sheet == null) {
      setState(() => _error = '먼저 커리큘럼 CSV를 등록하세요.');
      return;
    }

    final cohortId = ref.read(effectiveCohortIdProvider);
    if (cohortId == null) {
      setState(() => _error = '기수 정보가 없습니다.');
      return;
    }

    final dayFrom = int.tryParse(_dayFromCtrl.text.trim()) ?? 1;
    final dayTo = int.tryParse(_dayToCtrl.text.trim()) ?? dayFrom;
    final mcCount = int.tryParse(_mcCtrl.text.trim()) ?? 5;
    final saCount = int.tryParse(_saCtrl.text.trim()) ?? 3;

    setState(() {
      _generating = true;
      _error = null;
    });

    try {
      final qs = await ref
          .read(assessmentFunctionsServiceProvider)
          .generateAssessmentQuestions(
            cohortId: cohortId,
            sheetId: sheet.id,
            dayFrom: dayFrom,
            dayTo: dayTo,
            mcCount: mcCount,
            saCount: saCount,
          );
      if (!mounted) return;
      Navigator.pop(context, qs);
    } catch (e) {
      setState(() {
        _generating = false;
        _error = '$e';
      });
    }
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sheetAsync = ref.watch(latestCurriculumSheetProvider);
    final sheet = sheetAsync.asData?.value;
    final minDay = sheet?.rows.isEmpty ?? true
        ? 1
        : sheet!.rows.map((r) => r.dayIndex).reduce((a, b) => a < b ? a : b);
    final maxDay = sheet?.rows.isEmpty ?? true
        ? 7
        : sheet!.rows.map((r) => r.dayIndex).reduce((a, b) => a > b ? a : b);

    if (sheet != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _seedRangeIfNeeded(minDay, maxDay);
      });
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: sheetAsync.isLoading
              ? const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '문제 생성 AI',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (sheet == null)
                      const Text(
                        '등록된 커리큘럼이 없습니다.\n커리큘럼 메뉴에서 CSV를 업로드하세요.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      )
                    else ...[
                      Text(
                        sheet.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${sheet.rowCount}행 · 일수 $minDay~$maxDay',
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '선택한 커리큘럼 구간을 바탕으로 문제를 생성합니다.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _dayFromCtrl,
                              decoration: _fieldDecoration('일수 From'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _dayToCtrl,
                              decoration: _fieldDecoration('일수 To'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _mcCtrl,
                              decoration: _fieldDecoration('객관식 수'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _saCtrl,
                              decoration: _fieldDecoration('단답 수'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed:
                              _generating ? null : () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          child: const Text(
                            '취소',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed:
                              _generating || sheet == null ? null : _generate,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 14,
                            ),
                            shape: const StadiumBorder(),
                          ),
                          child: _generating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  '문제 생성',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
