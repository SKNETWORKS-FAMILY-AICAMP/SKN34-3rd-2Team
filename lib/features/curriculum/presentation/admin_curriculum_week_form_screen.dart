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
import '../models/curriculum_link_model.dart';
import '../models/curriculum_topic_model.dart';
import '../models/curriculum_week_model.dart';
import '../providers/curriculum_providers.dart';

/// 관리자 — 주차 상세 편집 (주제, 링크, PDF)
class AdminCurriculumWeekFormScreen extends ConsumerStatefulWidget {
  const AdminCurriculumWeekFormScreen({super.key, required this.weekId});

  final String weekId;

  @override
  ConsumerState<AdminCurriculumWeekFormScreen> createState() =>
      _AdminCurriculumWeekFormScreenState();
}

class _TopicField {
  _TopicField({
    String id = '',
    String title = '',
    String description = '',
    String tags = '',
  })  : id = id.isNotEmpty ? id : 'topic-${DateTime.now().microsecondsSinceEpoch}',
        title = TextEditingController(text: title),
        description = TextEditingController(text: description),
        tags = TextEditingController(text: tags);

  final String id;
  final TextEditingController title;
  final TextEditingController description;
  final TextEditingController tags;

  void dispose() {
    title.dispose();
    description.dispose();
    tags.dispose();
  }
}

class _AdminCurriculumWeekFormScreenState
    extends ConsumerState<AdminCurriculumWeekFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _weekNumberController = TextEditingController();
  final _titleController = TextEditingController();
  final _summaryController = TextEditingController();
  final _orderController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  bool _published = true;
  bool _loaded = false;
  bool _isSaving = false;
  bool _isUploading = false;

  final List<_TopicField> _topics = [];
  final List<CurriculumLinkModel> _links = [];
  List<CurriculumAttachmentModel> _attachments = [];

  @override
  void dispose() {
    _weekNumberController.dispose();
    _titleController.dispose();
    _summaryController.dispose();
    _orderController.dispose();
    for (final t in _topics) {
      t.dispose();
    }
    super.dispose();
  }

  void _loadWeek(CurriculumWeekModel week) {
    if (_loaded) return;
    _loaded = true;
    _weekNumberController.text = '${week.weekNumber}';
    _titleController.text = week.title;
    _summaryController.text = week.summary;
    _orderController.text = '${week.order}';
    _startDate = week.startDate;
    _endDate = week.endDate;
    _published = week.published;
    _topics.clear();
    for (final t in week.topics) {
      _topics.add(
        _TopicField(
          id: t.id,
          title: t.title,
          description: t.description,
          tags: t.tags.join(', '),
        ),
      );
    }
    _links
      ..clear()
      ..addAll(week.links);
    _attachments = List.from(week.attachments);
  }

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
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final cohortId = ref.read(effectiveCohortIdProvider);
    if (cohortId == null) return;

    final weekNumber = int.tryParse(_weekNumberController.text.trim()) ?? 0;
    final order = int.tryParse(_orderController.text.trim()) ?? weekNumber;

    final week = CurriculumWeekModel(
      id: widget.weekId,
      weekNumber: weekNumber,
      title: _titleController.text.trim(),
      summary: _summaryController.text.trim(),
      startDate: _startDate,
      endDate: _endDate,
      published: _published,
      order: order,
      topics: _topics
          .where((t) => t.title.text.trim().isNotEmpty)
          .map(
            (t) => CurriculumTopicModel(
              id: t.id,
              title: t.title.text.trim(),
              description: t.description.text.trim(),
              tags: t.tags.text
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList(),
            ),
          )
          .toList(),
      links: _links,
      attachments: _attachments,
    );

    setState(() => _isSaving = true);
    try {
      await ref.read(curriculumRepositoryProvider).saveWeek(
            cohortId: cohortId,
            week: week,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('주차가 저장되었습니다.')),
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

    final title = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('첨부 제목'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: '예: 1주차 슬라이드'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('다음'),
            ),
          ],
        );
      },
    );
    if (title == null) return;

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
            scopeId: widget.weekId,
            fileName: file.name,
            bytes: bytes,
          );
      setState(() {
        _attachments = [
          ..._attachments,
          CurriculumAttachmentModel(
            title: title.isNotEmpty ? title : file.name,
            fileUrl: url,
            fileName: file.name,
          ),
        ];
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF가 첨부되었습니다. 저장 버튼을 눌러 반영하세요.')),
        );
      }
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
      builder: (ctx) => _LinkEditorDialog(
        packages: packages,
        formTasks: formTasks,
      ),
    );
    if (result == null) return;
    setState(() => _links.add(result));
  }

  @override
  Widget build(BuildContext context) {
    final weekAsync = ref.watch(curriculumWeekProvider(widget.weekId));

    return weekAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (week) {
        if (week != null) _loadWeek(week);

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
                          '주차 편집',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
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
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _weekNumberController,
                    decoration: const InputDecoration(
                      labelText: '주차 번호',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) =>
                        int.tryParse(v?.trim() ?? '') == null ? '숫자를 입력하세요' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: '제목',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '제목을 입력하세요' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _summaryController,
                    decoration: const InputDecoration(
                      labelText: '요약',
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
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickDate(isStart: true),
                          child: Text(
                            _startDate == null
                                ? '시작일'
                                : AppDateUtils.formatDisplay(_startDate!),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickDate(isStart: false),
                          child: Text(
                            _endDate == null
                                ? '종료일'
                                : AppDateUtils.formatDisplay(_endDate!),
                          ),
                        ),
                      ),
                    ],
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
                        child: Text(
                          '학습 주제',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() => _topics.add(_TopicField())),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('주제 추가'),
                      ),
                    ],
                  ),
                  ..._topics.asMap().entries.map((entry) {
                    final i = entry.key;
                    final t = entry.value;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            TextFormField(
                              controller: t.title,
                              decoration: const InputDecoration(
                                labelText: '주제 제목',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: t.description,
                              decoration: const InputDecoration(
                                labelText: '설명',
                                border: OutlineInputBorder(),
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: t.tags,
                              decoration: const InputDecoration(
                                labelText: '태그 (쉼표 구분)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => setState(() {
                                  t.dispose();
                                  _topics.removeAt(i);
                                }),
                                child: const Text(
                                  '삭제',
                                  style: TextStyle(color: AppColors.error),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const Divider(height: 32),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '연결 리소스',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
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
                      subtitle: Text(link.type.label),
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
                        child: Text(
                          'PDF 첨부',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _isUploading ? null : _uploadAttachment,
                        icon: _isUploading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.upload_file, size: 18),
                        label: const Text('PDF 추가'),
                      ),
                    ],
                  ),
                  ..._attachments.asMap().entries.map((entry) {
                    final i = entry.key;
                    final a = entry.value;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.picture_as_pdf, color: AppColors.error),
                      title: Text(a.title),
                      subtitle: Text(a.fileName),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            setState(() => _attachments = List.from(_attachments)..removeAt(i)),
                      ),
                    );
                  }),
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

class _LinkEditorDialog extends StatefulWidget {
  const _LinkEditorDialog({
    required this.packages,
    required this.formTasks,
  });

  final List<InflearnPackageModel> packages;
  final List<FormTaskModel> formTasks;

  @override
  State<_LinkEditorDialog> createState() => _LinkEditorDialogState();
}

class _LinkEditorDialogState extends State<_LinkEditorDialog> {
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

  void _onRefChanged(String? id) {
    setState(() {
      _refId = id;
      if (_labelController.text.trim().isEmpty && id != null) {
        switch (_type) {
          case CurriculumLinkType.inflearnPackage:
            final pkg = widget.packages.where((p) => p.id == id).firstOrNull;
            if (pkg != null) _labelController.text = pkg.title;
          case CurriculumLinkType.formTask:
            final task = widget.formTasks.where((t) => t.id == id).firstOrNull;
            if (task != null) _labelController.text = task.title;
          default:
            break;
        }
      }
    });
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
              value: _type,
              decoration: const InputDecoration(
                labelText: '유형',
                border: OutlineInputBorder(),
              ),
              items: [
                CurriculumLinkType.inflearnPackage,
                CurriculumLinkType.formTask,
                CurriculumLinkType.external,
              ]
                  .map(
                    (t) => DropdownMenuItem(value: t, child: Text(t.label)),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _type = v;
                  _refId = null;
                });
              },
            ),
            const SizedBox(height: 12),
            if (_type == CurriculumLinkType.inflearnPackage)
              DropdownButtonFormField<String>(
                value: _refId,
                decoration: const InputDecoration(
                  labelText: '학습실 패키지',
                  border: OutlineInputBorder(),
                ),
                items: widget.packages
                    .map(
                      (p) => DropdownMenuItem(value: p.id, child: Text(p.title)),
                    )
                    .toList(),
                onChanged: _onRefChanged,
              )
            else if (_type == CurriculumLinkType.formTask)
              DropdownButtonFormField<String>(
                value: _refId,
                decoration: const InputDecoration(
                  labelText: '설문 · 제출',
                  border: OutlineInputBorder(),
                ),
                items: widget.formTasks
                    .map(
                      (t) => DropdownMenuItem(value: t.id, child: Text(t.title)),
                    )
                    .toList(),
                onChanged: _onRefChanged,
              )
            else
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  border: OutlineInputBorder(),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: '표시 라벨',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            if (_type == CurriculumLinkType.external) {
              if (_urlController.text.trim().isEmpty) return;
            } else if (_refId == null || _refId!.isEmpty) {
              return;
            }
            Navigator.pop(
              context,
              CurriculumLinkModel(
                type: _type,
                label: _labelController.text.trim(),
                refId: _refId,
                url: _type == CurriculumLinkType.external
                    ? _urlController.text.trim()
                    : null,
              ),
            );
          },
          child: const Text('추가'),
        ),
      ],
    );
  }
}
