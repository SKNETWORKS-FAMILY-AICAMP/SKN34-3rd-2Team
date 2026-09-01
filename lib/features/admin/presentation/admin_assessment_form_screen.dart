import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/models/assessment_model.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../../shared/providers/lms_providers.dart';
import '../../study_room/data/assessment_file_helper.dart';
import '../../study_room/presentation/widgets/study_room_layout.dart';

/// 관리자 — 성취도 평가 생성/수정 (파일 업로드 + 날짜 선택)
class AdminAssessmentFormScreen extends ConsumerStatefulWidget {
  const AdminAssessmentFormScreen({
    super.key,
    this.assessmentId,
  });

  final String? assessmentId;

  bool get isEditing => assessmentId != null && assessmentId!.isNotEmpty;

  @override
  ConsumerState<AdminAssessmentFormScreen> createState() =>
      _AdminAssessmentFormScreenState();
}

class _AdminAssessmentFormScreenState
    extends ConsumerState<AdminAssessmentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _tagsController = TextEditingController();
  final _questionCountController = TextEditingController(text: '25');
  final _maxScoreController = TextEditingController(text: '100');

  DateTime? _startAt;
  DateTime? _endAt;
  PlatformFile? _problemFile;
  String? _existingProblemFileName;
  String? _existingProblemFileUrl;
  bool _isSaving = false;
  bool _loaded = false;

  @override
  void dispose() {
    _titleController.dispose();
    _tagsController.dispose();
    _questionCountController.dispose();
    _maxScoreController.dispose();
    super.dispose();
  }

  void _loadAssessment(AssessmentModel a) {
    if (_loaded) return;
    _loaded = true;
    _titleController.text = a.title;
    _tagsController.text = a.tags.join(', ');
    _questionCountController.text = '${a.questionCount}';
    _maxScoreController.text = '${a.maxScore}';
    _startAt = a.startAt;
    _endAt = a.endAt;
    _existingProblemFileName = a.problemFileName;
    _existingProblemFileUrl = a.problemFileUrl;
  }

  List<String> _parseTags() {
    return _tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_startAt ?? DateTime.now())
        : (_endAt ?? _startAt ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startAt = picked;
        if (_endAt != null && _endAt!.isBefore(picked)) {
          _endAt = picked.add(const Duration(days: 7));
        }
      } else {
        _endAt = picked;
      }
    });
  }

  Future<void> _pickProblemFile() async {
    final result = await FilePicker.pickFiles();
    if (result.isEmpty) return;
    setState(() => _problemFile = result.first);
  }

  Future<void> _save({required bool publish}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_startAt == null || _endAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('시작일과 종료일을 선택해주세요.')),
      );
      return;
    }
    if (_endAt!.isBefore(_startAt!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('종료일은 시작일 이후여야 합니다.')),
      );
      return;
    }

    final cohortId = ref.read(effectiveCohortIdProvider);
    if (cohortId == null) return;

    setState(() => _isSaving = true);

    try {
      final repo = ref.read(lmsRepositoryProvider);
      final questionCount = int.parse(_questionCountController.text.trim());
      final maxScore = int.parse(_maxScoreController.text.trim());
      final tags = _parseTags();

      var assessmentId = widget.assessmentId;

      if (widget.isEditing && assessmentId != null) {
        await repo.updateAssessment(
          cohortId: cohortId,
          assessmentId: assessmentId,
          updates: {
            'title': _titleController.text.trim(),
            'tags': tags,
            'questionCount': questionCount,
            'maxScore': maxScore,
            'startAt': _startAt,
            'endAt': _endAt,
          },
        );
      } else {
        assessmentId = await repo.createAssessment(
          cohortId: cohortId,
          assessment: AssessmentModel(
            id: '',
            title: _titleController.text.trim(),
            tags: tags,
            questionCount: questionCount,
            maxScore: maxScore,
            startAt: _startAt!,
            endAt: _endAt!,
            published: false,
          ),
        );
      }

      if (_problemFile != null && assessmentId != null) {
        final url = await uploadAssessmentProblemFile(
          ref: ref,
          cohortId: cohortId,
          assessmentId: assessmentId,
          file: _problemFile!,
        );
        await repo.updateAssessment(
          cohortId: cohortId,
          assessmentId: assessmentId,
          updates: {
            'problemFileUrl': url,
            'problemFileName': _problemFile!.name,
          },
        );
      }

      if (publish) {
        await repo.publishAssessment(
          cohortId: cohortId,
          assessmentId: assessmentId!,
        );
      }

      ref.invalidate(assessmentsProvider);
      ref.invalidate(publishedAssessmentsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(publish ? '평가가 게시되었습니다.' : '임시 저장되었습니다.'),
          ),
        );
        context.go(RoutePaths.adminStudyRoom);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isEditing) {
      final assessments = ref.watch(assessmentsProvider);
      return assessments.when(
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          appBar: AppBar(),
          body: ErrorView(message: e.toString()),
        ),
        data: (list) {
          final a = list.where((x) => x.id == widget.assessmentId).firstOrNull;
          if (a == null) {
            return Scaffold(
              appBar: AppBar(),
              body: const Center(child: Text('평가를 찾을 수 없습니다')),
            );
          }
          _loadAssessment(a);
          return _buildScaffold(published: a.published);
        },
      );
    }
    return _buildScaffold(published: false);
  }

  Widget _buildScaffold({required bool published}) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(RoutePaths.adminStudyRoom),
        ),
        title: Text(widget.isEditing ? '평가 수정' : '평가 생성'),
      ),
      body: SingleChildScrollView(
        child: studyRoomContentWrapper(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.isEditing ? '성취도 평가 수정' : '새 성취도 평가',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E3A5F),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  published ? '게시됨 · 학생에게 노출 중' : '임시저장 · 게시 전',
                  style: TextStyle(
                    fontSize: 12,
                    color: published ? AppColors.success : AppColors.textSecondary,
                    fontWeight: published ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: '평가 제목',
                    hintText: '예) 34기 2차 성취도평가',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '제목을 입력하세요' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _tagsController,
                  decoration: const InputDecoration(
                    labelText: '태그 (쉼표로 구분)',
                    hintText: '데이터 분석, 머신러닝/딥러닝',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _questionCountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '문항 수'),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          if (n == null || n <= 0) return '유효한 숫자';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _maxScoreController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '만점'),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          if (n == null || n <= 0) return '유효한 숫자';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  '평가 기간',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _DatePickerTile(
                        label: '시작일',
                        value: _startAt,
                        onTap: () => _pickDate(isStart: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DatePickerTile(
                        label: '종료일',
                        value: _endAt,
                        onTap: () => _pickDate(isStart: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  '문제 파일',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _isSaving ? null : _pickProblemFile,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.border,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.cloud_upload_outlined,
                          size: 36,
                          color: AppColors.textHint.withValues(alpha: 0.8),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _problemFile?.name ??
                              _existingProblemFileName ??
                              'PDF, ZIP, IPYNB 등 파일을 선택하세요',
                          style: TextStyle(
                            fontSize: 13,
                            color: (_problemFile != null ||
                                    _existingProblemFileName != null)
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (_existingProblemFileUrl != null &&
                            _problemFile == null) ...[
                          const SizedBox(height: 4),
                          const Text(
                            '기존 파일 유지 · 새 파일 선택 시 교체',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                if (_isSaving)
                  const Center(child: CircularProgressIndicator())
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _save(publish: false),
                          child: const Text('임시저장'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _save(publish: true),
                          child: const Text('게시하기'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DatePickerTile extends StatelessWidget {
  const _DatePickerTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      value != null
                          ? AppDateUtils.formatDisplay(value!)
                          : '날짜 선택',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: value != null
                            ? AppColors.textPrimary
                            : AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
