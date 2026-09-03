import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../../shared/providers/lms_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../study_room/presentation/widgets/study_room_layout.dart';
import '../data/curriculum_pdf_parser_service.dart';
import '../data/curriculum_repository.dart';
import '../models/curriculum_day_model.dart';
import '../models/curriculum_meta_model.dart';
import '../providers/curriculum_providers.dart';
import '../utils/curriculum_day_draft_generator.dart';
import 'widgets/curriculum_day_card.dart';

/// 관리자 — 커리큘럼 메타 + 일수 관리 (초안 → 일괄 저장)
class AdminCurriculumScreen extends ConsumerStatefulWidget {
  const AdminCurriculumScreen({super.key});

  @override
  ConsumerState<AdminCurriculumScreen> createState() =>
      _AdminCurriculumScreenState();
}

class _AdminCurriculumScreenState extends ConsumerState<AdminCurriculumScreen> {
  static final _compactOutlined = OutlinedButton.styleFrom(
    minimumSize: const Size(0, 36),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    textStyle: const TextStyle(fontSize: 13),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  static final _compactFilled = FilledButton.styleFrom(
    minimumSize: const Size(0, 36),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    textStyle: const TextStyle(fontSize: 13),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  static const _tableInputDecoration = InputDecoration(
    isDense: true,
    border: OutlineInputBorder(),
    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
  );

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _defaultSubjectController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  bool _published = false;
  bool _isSaving = false;
  bool _isParsing = false;
  bool _dirty = false;

  String? _initializedCohortId;
  String? _savedPdfUrl;
  String? _savedPdfFileName;
  Uint8List? _pendingPdfBytes;
  String? _pendingPdfFileName;

  List<CurriculumDayModel> _draftDays = [];
  final Set<String> _deletedDayIds = {};

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _defaultSubjectController.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _loadFromRemote(
    String cohortId,
    CurriculumMetaModel? meta,
    List<CurriculumDayModel> days,
  ) {
    if (_initializedCohortId == cohortId) return;
    _initializedCohortId = cohortId;
    _dirty = false;
    _deletedDayIds.clear();
    _pendingPdfBytes = null;
    _pendingPdfFileName = null;

    if (meta != null) {
      _titleController.text = meta.title;
      _descriptionController.text = meta.description;
      _startDate = meta.startDate;
      _endDate = meta.endDate;
      _published = meta.published;
      _savedPdfUrl = meta.fullPdfUrl;
      _savedPdfFileName = meta.fullPdfFileName;
      _defaultSubjectController.text = meta.title;
    } else {
      _titleController.clear();
      _descriptionController.clear();
      _defaultSubjectController.clear();
      _startDate = null;
      _endDate = null;
      _published = false;
      _savedPdfUrl = null;
      _savedPdfFileName = null;
    }

    _draftDays = List.from(days);
  }

  String? get _displayPdfName => _pendingPdfFileName ?? _savedPdfFileName;

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? _startDate ?? DateTime.now());
    final firstDate = isStart ? DateTime(2020) : (_startDate ?? DateTime(2020));
    var initialDate = initial;
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      _dirty = true;
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _parsePdfAndFillDays() async {
    if (!_formKey.currentState!.validate()) return;

    if (_draftDays.isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('일수 초안 재생성'),
          content: Text(
            '기존 ${_draftDays.length}일을 PDF 파싱 결과로 교체할까요?\n'
            '저장 전까지 Firestore에는 반영되지 않습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('재생성'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }

    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (picked.isEmpty || !mounted) return;

    final file = picked.first;
    final bytes = await file.readAsBytes();

    if (bytes.length > 10 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF 파싱은 10MB 이하 파일만 지원합니다.')),
      );
      return;
    }

    setState(() => _isParsing = true);
    try {
      final result =
          await ref.read(curriculumPdfParserServiceProvider).parsePdf(bytes);

      if (result.days.isEmpty) {
        throw StateError('파싱된 일수가 없습니다.');
      }

      final sorted = result.days.toList()
        ..sort((a, b) => a.dayNumber.compareTo(b.dayNumber));

      setState(() {
        _pendingPdfBytes = bytes;
        _pendingPdfFileName = file.name;
        _draftDays = sorted;
        _deletedDayIds.clear();
        _dirty = true;
        _startDate = sorted.first.classDate;
        _endDate = sorted.last.classDate;
        if (_defaultSubjectController.text.trim().isEmpty &&
            sorted.first.subject.isNotEmpty) {
          _defaultSubjectController.text = sorted.first.subject;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'PDF에서 ${result.parsedCount}일을 불러왔습니다. 확인 후 [저장]하세요.',
            ),
          ),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF 파싱 실패: ${e.message ?? e.code}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF 파싱 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isParsing = false);
    }
  }

  Future<void> _generateDays() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('빈 일수 생성은 시작일과 종료일이 필요합니다.')),
      );
      return;
    }

    if (_draftDays.isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('일수 초안 재생성'),
          content: Text(
            '기존 ${_draftDays.length}일을 새 일수 초안으로 교체할까요?\n'
            '저장 전까지 Firestore에는 반영되지 않습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('재생성'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }

    final days = generateCurriculumDayDrafts(
      startDate: _startDate!,
      endDate: _endDate!,
      defaultSubject: _defaultSubjectController.text.trim(),
    );

    if (days.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('선택한 기간에 평일 수업일이 없습니다.')),
      );
      return;
    }

    setState(() {
      _draftDays = days;
      _deletedDayIds.clear();
      _dirty = true;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${days.length}일 빈 초안이 생성되었습니다. 내용을 입력한 뒤 [저장]하세요.',
          ),
        ),
      );
    }
  }

  void _updateDay(int index, CurriculumDayModel day) {
    _draftDays[index] = day;
    _markDirty();
  }

  void _removeDay(int index) {
    final day = _draftDays[index];
    if (!day.id.startsWith('draft-')) {
      _deletedDayIds.add(day.id);
    }
    setState(() {
      _draftDays = List.from(_draftDays)..removeAt(index);
      _dirty = true;
    });
  }

  Future<void> _pickClassDate(int index) async {
    final day = _draftDays[index];
    final picked = await showDatePicker(
      context: context,
      initialDate: day.classDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      _updateDay(index, day.copyWith(classDate: picked));
    });
  }

  Future<void> _saveAll() async {
    if (!_formKey.currentState!.validate()) return;
    final cohortId = ref.read(effectiveCohortIdProvider);
    final uid = ref.read(currentUserProvider).asData?.value?.uid;
    if (cohortId == null || uid == null) return;

    if (_draftDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('일수 목록이 비어 있습니다. 먼저 일수를 생성하세요.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      var pdfUrl = _savedPdfUrl;
      var pdfFileName = _savedPdfFileName;

      if (_pendingPdfBytes != null && _pendingPdfFileName != null) {
        pdfUrl = await ref.read(curriculumRepositoryProvider).uploadPdf(
              cohortId: cohortId,
              scopeId: 'meta',
              fileName: _pendingPdfFileName!,
              bytes: _pendingPdfBytes!,
            );
        pdfFileName = _pendingPdfFileName;
      }

      final existing = ref.read(curriculumMetaProvider).asData?.value;
      final meta = CurriculumMetaModel(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        totalDays: _draftDays.length,
        totalWeeks: existing?.totalWeeks ?? 0,
        startDate: _startDate,
        endDate: _endDate,
        published: _published,
        version: existing?.version ?? 1,
        fullPdfUrl: pdfUrl,
        fullPdfFileName: pdfFileName,
      );

      await ref.read(curriculumRepositoryProvider).saveCurriculumDaysBundle(
            cohortId: cohortId,
            meta: meta,
            updatedBy: uid,
            days: _draftDays,
            deleteDayIds: _deletedDayIds.toList(),
          );

      ref.invalidate(curriculumMetaProvider);
      ref.invalidate(curriculumDaysProvider);

      setState(() {
        _dirty = false;
        _deletedDayIds.clear();
        _pendingPdfBytes = null;
        _pendingPdfFileName = null;
        _savedPdfUrl = pdfUrl;
        _savedPdfFileName = pdfFileName;
        _initializedCohortId = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('커리큘럼이 저장되었습니다.')),
        );
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

  Widget _buildDayRow(int index) {
    final day = _draftDays[index];
    final canEditDetail = !day.id.startsWith('draft-');

    return Card(
      key: ValueKey('${day.id}-${day.dayNumber}'),
      margin: const EdgeInsets.only(bottom: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 36,
                  child: Center(
                    child: Text(
                      '${day.dayNumber}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: InkWell(
                    onTap: () => _pickClassDate(index),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.border,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${AppDateUtils.formatDisplay(day.classDate)} (${weekdayLabelKo(day.classDate)})',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    initialValue: day.subject,
                    textAlign: TextAlign.center,
                    decoration: _tableInputDecoration,
                    style: const TextStyle(fontSize: 12),
                    onChanged: (v) => _updateDay(
                      index,
                      day.copyWith(subject: v),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    initialValue: day.content,
                    textAlign: TextAlign.center,
                    decoration: _tableInputDecoration,
                    style: const TextStyle(fontSize: 12),
                    onChanged: (v) => _updateDay(
                      index,
                      day.copyWith(content: v),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: AppColors.error,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () => _removeDay(index),
                ),
              ],
            ),
            if (canEditDetail)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.push(
                    RoutePaths.adminCurriculumDayEditPath(day.id),
                  ),
                  child: const Text('링크·첨부 편집'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final cohortName = ref.watch(effectiveCohortNameProvider);
    final cohortId = ref.watch(effectiveCohortIdProvider);
    final metaAsync = ref.watch(curriculumMetaProvider);
    final daysAsync = ref.watch(curriculumDaysProvider);

    return userAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (user) {
        if (user == null) return const SizedBox.shrink();

        if (cohortId != null &&
            metaAsync.hasValue &&
            daysAsync.hasValue &&
            !_dirty &&
            _initializedCohortId != cohortId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _dirty || _initializedCohortId == cohortId) return;
            setState(() {
              _loadFromRemote(cohortId, metaAsync.value, daysAsync.value ?? []);
            });
          });
        }

        return Stack(
          children: [
            RefreshIndicator(
              onRefresh: () async {
                if (_dirty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('저장하지 않은 변경사항이 있습니다.')),
                  );
                  return;
                }
                _initializedCohortId = null;
                ref.invalidate(curriculumMetaProvider);
                ref.invalidate(curriculumDaysProvider);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 88),
                child: studyRoomContentWrapper(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      StudyRoomPageHeader(
                        user: user,
                        cohortName: cohortName,
                        subtitle: 'PDF를 파싱해 일수·교과목·내용을 자동 채우고 저장하세요.',
                        showProfile: false,
                      ),
                      if (_dirty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '저장하지 않은 변경사항이 있습니다.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  '커리큘럼 정보',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _titleController,
                                  decoration: const InputDecoration(
                                    labelText: '제목',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (_) => _markDirty(),
                                  validator: (v) => (v == null || v.trim().isEmpty)
                                      ? '제목을 입력하세요'
                                      : null,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _descriptionController,
                                  decoration: const InputDecoration(
                                    labelText: '설명',
                                    border: OutlineInputBorder(),
                                  ),
                                  maxLines: 2,
                                  onChanged: (_) => _markDirty(),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _defaultSubjectController,
                                  decoration: const InputDecoration(
                                    labelText: '기본 교과목',
                                    border: OutlineInputBorder(),
                                    helperText: 'PDF 파싱 시 비어 있으면 첫 행 교과목을 사용합니다.',
                                  ),
                                  onChanged: (_) => _markDirty(),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => _pickDate(isStart: true),
                                        style: _compactOutlined,
                                        child: Text(
                                          _startDate == null
                                              ? '시작일 (자동)'
                                              : AppDateUtils.formatDisplay(_startDate!),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => _pickDate(isStart: false),
                                        style: _compactOutlined,
                                        child: Text(
                                          _endDate == null
                                              ? '종료일 (자동)'
                                              : AppDateUtils.formatDisplay(_endDate!),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        FilledButton.icon(
                                          onPressed: _isParsing ? null : _parsePdfAndFillDays,
                                          style: _compactFilled,
                                          icon: _isParsing
                                              ? const SizedBox(
                                                  width: 14,
                                                  height: 14,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              : const Icon(Icons.auto_fix_high, size: 18),
                                          label: Text(
                                            _isParsing ? 'PDF 파싱 중…' : 'PDF 파싱 + 일수 채우기',
                                          ),
                                        ),
                                        OutlinedButton(
                                          onPressed: _generateDays,
                                          style: _compactOutlined,
                                          child: const Text('빈 일수 생성'),
                                        ),
                                      ],
                                    ),
                                    const Spacer(),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                          '학생에게 공개',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        Transform.scale(
                                          scale: 0.72,
                                          child: Switch(
                                            value: _published,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize.shrinkWrap,
                                            onChanged: (v) => setState(() {
                                              _published = v;
                                              _dirty = true;
                                            }),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                if (_displayPdfName != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    _pendingPdfFileName != null
                                        ? '선택된 PDF: $_displayPdfName'
                                        : '저장된 PDF: $_displayPdfName',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '일수 목록 (${_draftDays.length}일)',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_draftDays.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              '시작일·종료일을 선택한 뒤 「빈 일수 생성」을 누르거나,\n'
                              '스프레드시트 PDF로 「PDF 파싱 + 일수 채우기」를 사용하세요.',
                              style: TextStyle(color: AppColors.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          color: AppColors.surfaceVariant,
                          child: const Row(
                            children: [
                              SizedBox(
                                width: 36,
                                child: Text(
                                  '일수',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '수업일자',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '교과목',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '내용',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                              SizedBox(width: 32),
                            ],
                          ),
                        ),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _draftDays.length,
                          itemBuilder: (context, index) => _buildDayRow(index),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                elevation: 8,
                color: Colors.white,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Align(
                      alignment: Alignment.center,
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _saveAll,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(_isSaving ? '저장 중…' : '커리큘럼 저장'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
