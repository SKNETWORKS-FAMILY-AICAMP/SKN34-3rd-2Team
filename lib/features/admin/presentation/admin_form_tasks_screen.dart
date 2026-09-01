import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/models/form_task_model.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../../shared/providers/lms_providers.dart';
import 'widgets/admin_page_layout.dart';

/// 관리자 — 구글폼 설문 목록
class AdminFormTasksScreen extends ConsumerWidget {
  const AdminFormTasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(allFormTasksAdminProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('설문 · 제출 관리'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: () => context.push(RoutePaths.adminFormTasksCreate),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('설문 등록'),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(allFormTasksAdminProvider),
        child: tasks.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(message: e.toString()),
          data: (list) {
            if (list.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  adminPageWrapper(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 64),
                      child: Column(
                        children: [
                          Icon(
                            Icons.ballot_outlined,
                            size: 48,
                            color: AppColors.textHint.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '등록된 설문이 없습니다',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () =>
                                context.push(RoutePaths.adminFormTasksCreate),
                            icon: const Icon(Icons.add),
                            label: const Text('첫 설문 등록'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final task = list[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primaryLight,
                          child: Icon(
                            task.published
                                ? Icons.description_outlined
                                : Icons.visibility_off_outlined,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          task.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '마감 ${AppDateUtils.formatDisplay(task.dueAt)} · '
                          '제출 ${task.responseCount}명'
                          '${task.published ? '' : ' · 비공개'}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(
                          RoutePaths.adminFormTaskDetailPath(task.id),
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 관리자 — 설문 등록/수정
class AdminFormTaskFormScreen extends ConsumerStatefulWidget {
  const AdminFormTaskFormScreen({super.key, this.taskId});

  final String? taskId;

  bool get isEditing => taskId != null && taskId!.isNotEmpty;

  @override
  ConsumerState<AdminFormTaskFormScreen> createState() =>
      _AdminFormTaskFormScreenState();
}

class _AdminFormTaskFormScreenState extends ConsumerState<AdminFormTaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _formUrlController = TextEditingController();
  final _notionUrlController = TextEditingController();
  DateTime? _dueAt;
  bool _published = true;
  bool _isSaving = false;
  bool _loaded = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _formUrlController.dispose();
    _notionUrlController.dispose();
    super.dispose();
  }

  void _load(FormTaskModel task) {
    if (_loaded) return;
    _loaded = true;
    _titleController.text = task.title;
    _descController.text = task.description;
    _formUrlController.text = task.formUrl;
    _notionUrlController.text = task.notionGuideUrl ?? '';
    _dueAt = task.dueAt;
    _published = task.published;
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueAt ?? picked.add(const Duration(hours: 18))),
    );
    if (time == null) return;
    setState(() {
      _dueAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dueAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('마감 일시를 선택해 주세요.')),
      );
      return;
    }

    final cohortId = ref.read(effectiveCohortIdProvider);
    final user = ref.read(currentUserSyncProvider);
    if (cohortId == null || user == null) return;

    setState(() => _isSaving = true);
    try {
      final task = FormTaskModel(
        id: widget.taskId ?? '',
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        formUrl: _formUrlController.text.trim(),
        notionGuideUrl: _notionUrlController.text.trim().isEmpty
            ? null
            : _notionUrlController.text.trim(),
        dueAt: _dueAt!,
        published: _published,
      );

      if (widget.isEditing) {
        await ref.read(lmsRepositoryProvider).updateFormTask(
              cohortId: cohortId,
              taskId: widget.taskId!,
              task: task,
              authorId: user.uid,
            );
      } else {
        final id = await ref.read(lmsRepositoryProvider).createFormTask(
              cohortId: cohortId,
              task: task,
              authorId: user.uid,
            );
        if (mounted) {
          context.go(RoutePaths.adminFormTaskDetailPath(id));
          return;
        }
      }

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

  @override
  Widget build(BuildContext context) {
    if (widget.isEditing) {
      final taskAsync = ref.watch(formTaskDetailProvider(widget.taskId!));
      return taskAsync.when(
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(body: ErrorView(message: e.toString())),
        data: (task) {
          if (task == null) {
            return const Scaffold(body: Center(child: Text('설문을 찾을 수 없습니다.')));
          }
          _load(task);
          return _buildForm(context);
        },
      );
    }
    return _buildForm(context);
  }

  Widget _buildForm(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? '설문 수정' : '설문 등록'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(labelText: '제목 *'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '제목을 입력하세요' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descController,
                    decoration: const InputDecoration(labelText: '설명'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _formUrlController,
                    decoration: const InputDecoration(
                      labelText: '구글폼 URL *',
                      hintText: 'https://docs.google.com/forms/...',
                    ),
                    validator: (v) {
                      final url = v?.trim() ?? '';
                      if (url.isEmpty) return 'URL을 입력하세요';
                      if (!url.startsWith('http')) return 'http(s) URL을 입력하세요';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notionUrlController,
                    decoration: const InputDecoration(
                      labelText: '노션 가이드 URL',
                      hintText: 'https://notion.so/...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('마감 일시 *'),
                    subtitle: Text(
                      _dueAt == null
                          ? '선택 안 됨'
                          : AppDateUtils.formatDateTime(_dueAt!),
                    ),
                    trailing: OutlinedButton(
                      onPressed: _pickDueDate,
                      child: const Text('선택'),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('학생에게 공개'),
                    value: _published,
                    onChanged: (v) => setState(() => _published = v),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(widget.isEditing ? '저장' : '등록'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 관리자 — 제출 현황 + Apps Script 연동 안내
class AdminFormTaskDetailScreen extends ConsumerWidget {
  const AdminFormTaskDetailScreen({super.key, required this.taskId});

  final String taskId;

  static const webhookUrl =
      'https://asia-northeast3-skn34-3rd-2team.cloudfunctions.net/googleFormWebhook';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskAsync = ref.watch(formTaskDetailProvider(taskId));
    final responses = ref.watch(formTaskResponsesProvider(taskId));
    final students = ref.watch(cohortStudentsProvider);
    final cohortId = ref.watch(effectiveCohortIdProvider);

    return taskAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(body: ErrorView(message: e.toString())),
      data: (task) {
        if (task == null) {
          return const Scaffold(body: Center(child: Text('설문을 찾을 수 없습니다.')));
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(task.title),
            actions: [
              IconButton(
                tooltip: '수정',
                onPressed: () =>
                    context.push(RoutePaths.adminFormTaskEditPath(taskId)),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (task.description.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              task.description,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          _MetaRow(
                            label: '마감',
                            value: AppDateUtils.formatDateTime(task.dueAt),
                          ),
                          _MetaRow(label: '구글폼', value: task.formUrl),
                          if (task.notionGuideUrl != null)
                            _MetaRow(
                              label: '노션',
                              value: task.notionGuideUrl!,
                            ),
                          _MetaRow(
                            label: '제출',
                            value: '${task.responseCount}명',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '구글폼 자동 연동',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Google Apps Script에 아래 값을 넣고, '
                            '폼 제출 트리거를 설정하면 LMS에 자동 반영됩니다.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _CopyField(label: 'Webhook URL', value: webhookUrl),
                          if (cohortId != null)
                            _CopyField(label: 'cohortId', value: cohortId),
                          _CopyField(label: 'taskId', value: taskId),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(
                                  text: _appsScriptSnippet(cohortId, taskId),
                                ),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Apps Script 코드가 복사되었습니다.'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('Apps Script 코드 복사'),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Secret: firebase functions:secrets:set GOOGLE_FORM_WEBHOOK_SECRET',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textHint.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '제출 현황',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  responses.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('오류: $e'),
                    data: (submitted) {
                      return students.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (e, _) => Text('오류: $e'),
                        data: (studentList) {
                          final submittedIds =
                              submitted.map((r) => r.userId).toSet();
                          final done = studentList
                              .where((s) => submittedIds.contains(s.uid))
                              .toList();
                          final pending = studentList
                              .where((s) => !submittedIds.contains(s.uid))
                              .toList();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ProgressBar(
                                done: done.length,
                                total: studentList.length,
                              ),
                              const SizedBox(height: 12),
                              if (pending.isNotEmpty) ...[
                                const _SubTitle('미제출'),
                                ...pending.map(
                                  (s) => ListTile(
                                    dense: true,
                                    leading: const Icon(
                                      Icons.radio_button_unchecked,
                                      color: AppColors.warning,
                                      size: 18,
                                    ),
                                    title: Text(s.displayName),
                                    subtitle: Text(s.email),
                                  ),
                                ),
                              ],
                              if (done.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                const _SubTitle('제출 완료'),
                                ...done.map((s) {
                                  final r = submitted.firstWhere(
                                    (x) => x.userId == s.uid,
                                  );
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(
                                      Icons.check_circle,
                                      color: AppColors.success,
                                      size: 18,
                                    ),
                                    title: Text(s.displayName),
                                    subtitle: Text(
                                      r.submittedAt != null
                                          ? AppDateUtils.formatDateTime(
                                              r.submittedAt!,
                                            )
                                          : s.email,
                                    ),
                                  );
                                }),
                              ],
                            ],
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _appsScriptSnippet(String? cohortId, String taskId) {
    return '''
const WEBHOOK_URL = '$webhookUrl';
const WEBHOOK_SECRET = 'YOUR_SECRET_HERE'; // Firebase Secret과 동일하게!
const COHORT_ID = '${cohortId ?? 'cohort_34'}';
const TASK_ID = '$taskId';

function onFormSubmit(e) {
  const email = extractEmail(e);
  if (!email) {
    console.warn('이메일 없음 — 구글폼 "이메일 수집" 켜기');
    return;
  }
  if (WEBHOOK_SECRET === 'YOUR_SECRET_HERE') {
    console.error('WEBHOOK_SECRET을 Firebase Secret 값으로 바꿔주세요.');
    return;
  }

  const response = UrlFetchApp.fetch(WEBHOOK_URL, {
    method: 'post',
    contentType: 'application/json',
    headers: { 'X-Webhook-Secret': WEBHOOK_SECRET },
    payload: JSON.stringify({
      cohortId: COHORT_ID,
      taskId: TASK_ID,
      email: String(email).trim().toLowerCase(),
      responseId: e.response.getId(),
    }),
    muteHttpExceptions: true,
  });
  console.log('Webhook', response.getResponseCode(), response.getContentText());
}

function extractEmail(e) {
  const respondent = e.response.getRespondentEmail();
  if (respondent) return respondent;
  const items = e.response.getItemResponses();
  for (var i = 0; i < items.length; i++) {
    const title = items[i].getItem().getTitle();
    if (title.includes('이메일') || title.toLowerCase().includes('email')) {
      return items[i].getResponse();
    }
  }
  return null;
}
''';
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _CopyField extends StatelessWidget {
  const _CopyField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 11),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$label 복사됨')),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : done / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '제출률 ${(ratio * 100).toStringAsFixed(0)}% ($done/$total)',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            color: AppColors.primary,
            backgroundColor: AppColors.primaryLight,
          ),
        ),
      ],
    );
  }
}

class _SubTitle extends StatelessWidget {
  const _SubTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
