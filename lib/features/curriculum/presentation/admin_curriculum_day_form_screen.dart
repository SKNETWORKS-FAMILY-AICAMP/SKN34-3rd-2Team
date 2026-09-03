import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/models/form_task_model.dart';
import '../../../shared/models/inflearn_package_model.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../../shared/providers/lms_providers.dart';
import '../../study_room/presentation/widgets/study_room_layout.dart';
import '../data/curriculum_repository.dart';
import '../models/curriculum_attachment_model.dart';
import '../models/curriculum_day_model.dart';
import '../models/curriculum_link_model.dart';
import '../providers/curriculum_providers.dart';
import 'widgets/curriculum_day_card.dart';

/// 관리자 — 일수 상세 편집 (링크, PDF)
class AdminCurriculumDayFormScreen extends ConsumerStatefulWidget {
  const AdminCurriculumDayFormScreen({super.key, required this.dayId});

  final String dayId;

  @override
  ConsumerState<AdminCurriculumDayFormScreen> createState() =>
      _AdminCurriculumDayFormScreenState();
}

class _AdminCurriculumDayFormScreenState
    extends ConsumerState<AdminCurriculumDayFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _dayNumberController = TextEditingController();
  final _subjectController = TextEditingController();
  final _contentController = TextEditingController();
  final _orderController = TextEditingController();

  DateTime? _classDate;
  bool _published = true;
  bool _loaded = false;
  bool _isSaving = false;
  bool _isUploading = false;

  final List<CurriculumLinkModel> _links = [];
  List<CurriculumAttachmentModel> _attachments = [];

  @override
  void dispose() {
    _dayNumberController.dispose();
    _subjectController.dispose();
    _contentController.dispose();
    _orderController.dispose();
    super.dispose();
  }

  void _loadDay(CurriculumDayModel day) {
    if (_loaded) return;
    _loaded = true;
    _dayNumberController.text = '${day.dayNumber}';
    _subjectController.text = day.subject;
    _contentController.text = day.content;
    _orderController.text = '${day.order}';
    _classDate = day.classDate;
    _published = day.published;
    _links
      ..clear()
      ..addAll(day.links);
    _attachments = List.from(day.attachments);
  }

  Future<void> _pickClassDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _classDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() => _classDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_classDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('수업일자를 선택하세요.')),
      );
      return;
    }

    final cohortId = ref.read(effectiveCohortIdProvider);
    if (cohortId == null) return;

    final day = CurriculumDayModel(
      id: widget.dayId,
      dayNumber: int.tryParse(_dayNumberController.text.trim()) ?? 0,
      classDate: _classDate!,
      subject: _subjectController.text.trim(),
      content: _contentController.text.trim(),
      published: _published,
      order: int.tryParse(_orderController.text.trim()) ?? 0,
      links: _links,
      attachments: _attachments,
    );

    setState(() => _isSaving = true);
    try {
      await ref.read(curriculumRepositoryProvider).saveDay(
            cohortId: cohortId,
            day: day,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장되었습니다.')),
        );
        context.pop();
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

  Future<void> _uploadAttachment() async {
    final cohortId = ref.read(effectiveCohortIdProvider);
    if (cohortId == null) return;

    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (picked.isEmpty) return;
    final file = picked.first;
    final bytes = await file.readAsBytes();

    setState(() => _isUploading = true);
    try {
      final url = await ref.read(curriculumRepositoryProvider).uploadPdf(
            cohortId: cohortId,
            scopeId: widget.dayId,
            fileName: file.name,
            bytes: bytes,
          );
      setState(() {
        _attachments = [
          ..._attachments,
          CurriculumAttachmentModel(
            title: file.name,
            fileUrl: url,
            fileName: file.name,
          ),
        ];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('업로드 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _addLink() async {
    final packages = ref.read(inflearnPackagesProvider).asData?.value ?? [];
    final formTasks = ref.read(allFormTasksAdminProvider).asData?.value ?? [];

    final result = await showDialog<CurriculumLinkModel>(
      context: context,
      builder: (ctx) => _DayLinkEditorDialog(
        packages: packages,
        formTasks: formTasks,
      ),
    );
    if (result == null) return;
    setState(() => _links.add(result));
  }

  @override
  Widget build(BuildContext context) {
    final dayAsync = ref.watch(curriculumDayProvider(widget.dayId));

    return dayAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (day) {
        if (day != null) _loadDay(day);

        return SingleChildScrollView(
          child: studyRoomContentWrapper(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => context.go(RoutePaths.adminCurriculum),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const Expanded(
                        child: Text(
                          '일수 편집',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                      FilledButton(
                        onPressed: _isSaving ? null : _save,
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('저장'),
                      ),
                    ],
                  ),
                  if (day != null) ...[
                    const SizedBox(height: 8),
                    CurriculumDayCard(day: day, onTap: () {}),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _dayNumberController,
                    decoration: const InputDecoration(
                      labelText: '일수',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _pickClassDate,
                    child: Text(
                      _classDate == null
                          ? '수업일자 선택'
                          : '${AppDateUtils.formatDisplay(_classDate!)} (${weekdayLabelKo(_classDate!)})',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _subjectController,
                    decoration: const InputDecoration(
                      labelText: '교과목',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _contentController,
                    decoration: const InputDecoration(
                      labelText: '내용',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _orderController,
                    decoration: const InputDecoration(
                      labelText: '정렬 순서',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('학생에게 공개'),
                    value: _published,
                    onChanged: (v) => setState(() => _published = v),
                  ),
                  const Divider(height: 32),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('연결 리소스', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      TextButton.icon(
                        onPressed: _addLink,
                        icon: const Icon(Icons.link, size: 18),
                        label: const Text('링크 추가'),
                      ),
                    ],
                  ),
                  ..._links.asMap().entries.map((entry) {
                    final i = entry.key;
                    final link = entry.value;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.link),
                      title: Text(link.label.isNotEmpty ? link.label : link.type.label),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _links.removeAt(i)),
                      ),
                    );
                  }),
                  const Divider(height: 32),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('PDF 첨부', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      TextButton.icon(
                        onPressed: _isUploading ? null : _uploadAttachment,
                        icon: const Icon(Icons.upload_file, size: 18),
                        label: const Text('PDF 추가'),
                      ),
                    ],
                  ),
                  ..._attachments.map(
                    (a) => ListTile(
                      leading: const Icon(Icons.picture_as_pdf, color: AppColors.error),
                      title: Text(a.title),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DayLinkEditorDialog extends StatefulWidget {
  const _DayLinkEditorDialog({
    required this.packages,
    required this.formTasks,
  });

  final List<InflearnPackageModel> packages;
  final List<FormTaskModel> formTasks;

  @override
  State<_DayLinkEditorDialog> createState() => _DayLinkEditorDialogState();
}

class _DayLinkEditorDialogState extends State<_DayLinkEditorDialog> {
  CurriculumLinkType _type = CurriculumLinkType.inflearnPackage;
  String? _refId;
  final _labelController = TextEditingController();
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _labelController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('리소스 연결'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<CurriculumLinkType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: '유형', border: OutlineInputBorder()),
              items: [
                CurriculumLinkType.inflearnPackage,
                CurriculumLinkType.formTask,
                CurriculumLinkType.external,
              ].map((t) => DropdownMenuItem(value: t, child: Text(t.label))).toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _type = v;
                  _refId = null;
                });
              },
            ),
            const SizedBox(height: 12),
            if (_type == CurriculumLinkType.external)
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(labelText: 'URL', border: OutlineInputBorder()),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _refId,
                decoration: InputDecoration(
                  labelText: _type == CurriculumLinkType.inflearnPackage ? '학습실 패키지' : '설문 · 제출',
                  border: const OutlineInputBorder(),
                ),
                items: (_type == CurriculumLinkType.inflearnPackage
                        ? widget.packages.map((p) => DropdownMenuItem(value: p.id, child: Text(p.title)))
                        : widget.formTasks.map((t) => DropdownMenuItem(value: t.id, child: Text(t.title))))
                    .toList(),
                onChanged: (v) => setState(() => _refId = v),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(labelText: '표시 라벨', border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(
          onPressed: () {
            if (_type == CurriculumLinkType.external) {
              if (_urlController.text.trim().isEmpty) return;
            } else if (_refId == null) return;
            Navigator.pop(
              context,
              CurriculumLinkModel(
                type: _type,
                label: _labelController.text.trim(),
                refId: _refId,
                url: _type == CurriculumLinkType.external ? _urlController.text.trim() : null,
              ),
            );
          },
          child: const Text('추가'),
        ),
      ],
    );
  }
}
