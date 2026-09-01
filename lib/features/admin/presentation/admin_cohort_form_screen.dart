import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/cohort_status.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/models/cohort_model.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../../shared/providers/lms_providers.dart';
import 'widgets/admin_page_layout.dart';

/// 관리자 — 기수 생성 / 수정
class AdminCohortFormScreen extends ConsumerStatefulWidget {
  const AdminCohortFormScreen({super.key, this.cohortId});

  final String? cohortId;

  bool get isEditing => cohortId != null && cohortId!.isNotEmpty;

  @override
  ConsumerState<AdminCohortFormScreen> createState() =>
      _AdminCohortFormScreenState();
}

class _AdminCohortFormScreenState extends ConsumerState<AdminCohortFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _termController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _classroomController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  CohortStatus _status = CohortStatus.upcoming;
  CohortModel? _existing;
  bool _loaded = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _termController.dispose();
    _descriptionController.dispose();
    _classroomController.dispose();
    super.dispose();
  }

  void _load(CohortModel c) {
    if (_loaded) return;
    _loaded = true;
    _existing = c;
    _nameController.text = c.name;
    _termController.text = (_termOf(c)?.toString()) ?? '';
    _descriptionController.text = c.description ?? '';
    _classroomController.text = c.classroomName ?? '';
    _startDate = c.startDate;
    _endDate = c.endDate;
    _status = c.status;
  }

  int? _termOf(CohortModel c) {
    if (c.termNumber != null) return c.termNumber;
    final idMatch = RegExp(r'(\d+)$').firstMatch(c.cohortId);
    if (idMatch != null) return int.tryParse(idMatch.group(1)!);
    final nameMatch = RegExp(r'(\d+)기').firstMatch(c.name);
    return nameMatch != null ? int.tryParse(nameMatch.group(1)!) : null;
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? _startDate ?? DateTime.now());
    final firstDate = isStart
        ? DateTime(2020)
        : (_startDate ?? DateTime(2020));
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
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('시작일과 종료일을 선택해주세요.')),
      );
      return;
    }
    if (_endDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('종료일은 시작일 이후여야 합니다.')),
      );
      return;
    }

    final term = widget.isEditing
        ? (_existing != null ? _termOf(_existing!) : null) ??
            int.tryParse(_termController.text.trim())
        : int.tryParse(_termController.text.trim());
    if (term == null || term <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('유효한 기수 번호를 입력하세요.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repo = ref.read(lmsRepositoryProvider);
      final description = _descriptionController.text.trim();
      final classroom = _classroomController.text.trim();
      final base = _existing ??
          CohortModel(
            cohortId: 'cohort_$term',
            name: _nameController.text.trim(),
            termNumber: term,
          );
      final cohort = base.copyWith(
        name: _nameController.text.trim(),
        description: description.isEmpty ? null : description,
        startDate: _startDate,
        endDate: _endDate,
        status: _status,
        termNumber: term,
        classroomName: classroom.isEmpty ? null : classroom,
      );

      if (widget.isEditing) {
        await repo.updateCohort(cohort);
      } else {
        await repo.createCohort(cohort);
        selectCohort(ref, cohort.cohortId);
      }

      ref.invalidate(allCohortsAdminProvider);
      ref.invalidate(cohortsStreamProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isEditing ? '기수 정보가 수정되었습니다.' : '기수가 생성되었습니다.'),
          ),
        );
        context.go(RoutePaths.adminCohorts);
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
      final cohorts = ref.watch(allCohortsAdminProvider);
      return cohorts.when(
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          appBar: AppBar(),
          body: ErrorView(message: e.toString()),
        ),
        data: (list) {
          final c = list.where((x) => x.cohortId == widget.cohortId).firstOrNull;
          if (c == null) {
            return Scaffold(
              appBar: AppBar(),
              body: const Center(child: Text('기수를 찾을 수 없습니다')),
            );
          }
          _load(c);
          return _buildForm();
        },
      );
    }
    return _buildForm();
  }

  Widget _buildForm() {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(RoutePaths.adminCohorts),
        ),
        title: Text(widget.isEditing ? '기수 수정' : '기수 생성'),
        actions: [
          if (!_isSaving)
            TextButton(
              onPressed: _save,
              child: Text(widget.isEditing ? '저장' : '생성'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: adminPageWrapper(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.isEditing ? '기수 정보 수정' : '새 기수 등록',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E3A5F),
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _termController,
                  keyboardType: TextInputType.number,
                  enabled: !widget.isEditing,
                  decoration: InputDecoration(
                    labelText: '기수 번호 *',
                    hintText: '예: 36',
                    helperText: widget.isEditing
                        ? '기수 번호는 수정할 수 없습니다'
                        : 'cohort_36 형식으로 ID가 생성됩니다',
                  ),
                  validator: (v) {
                    if (widget.isEditing) return null;
                    final n = int.tryParse(v ?? '');
                    if (n == null || n <= 0) {
                      return '유효한 기수 번호를 입력하세요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '기수명 *',
                    hintText: 'SK네트웍스 Family AI 캠프 36기',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '기수명을 입력하세요' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _classroomController,
                  decoration: const InputDecoration(
                    labelText: '강의실 (선택)',
                    hintText: '예: 3층 A실',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '설명 (선택)',
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '운영 기간',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _DateTile(
                        label: '시작일',
                        value: _startDate,
                        onTap: () => _pickDate(isStart: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateTile(
                        label: '종료일',
                        value: _endDate,
                        onTap: () => _pickDate(isStart: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  '운영 상태',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                SegmentedButton<CohortStatus>(
                  segments: const [
                    ButtonSegment(
                      value: CohortStatus.upcoming,
                      label: Text('예정'),
                    ),
                    ButtonSegment(
                      value: CohortStatus.active,
                      label: Text('진행중'),
                    ),
                    ButtonSegment(
                      value: CohortStatus.archived,
                      label: Text('종료'),
                    ),
                  ],
                  selected: {_status},
                  onSelectionChanged: (s) => setState(() => _status = s.first),
                ),
                const SizedBox(height: 8),
                Text(
                  switch (_status) {
                    CohortStatus.upcoming =>
                      '예정: 학생 등록·세팅 가능, 드롭다운에서 선택 가능',
                    CohortStatus.active => '진행중: 현재 운영 기수',
                    CohortStatus.archived =>
                      '종료: 조회 전용, 드롭다운에서 숨김',
                  },
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 32),
                if (_isSaving)
                  const Center(child: CircularProgressIndicator())
                else
                  FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(widget.isEditing ? '저장' : '기수 생성'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
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
                  fontWeight: FontWeight.w600,
                  color: value != null
                      ? AppColors.textPrimary
                      : AppColors.textHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
