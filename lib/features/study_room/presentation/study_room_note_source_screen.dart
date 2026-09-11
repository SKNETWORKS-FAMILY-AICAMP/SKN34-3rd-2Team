import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/models/study_source_model.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../../shared/providers/lms_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/study_note_service.dart';
import 'widgets/study_note_markdown.dart';
import 'widgets/study_room_layout.dart';

class StudyRoomNoteSourceScreen extends ConsumerStatefulWidget {
  const StudyRoomNoteSourceScreen({super.key, required this.sourceId});

  final String sourceId;

  @override
  ConsumerState<StudyRoomNoteSourceScreen> createState() =>
      _StudyRoomNoteSourceScreenState();
}

class _StudyRoomNoteSourceScreenState
    extends ConsumerState<StudyRoomNoteSourceScreen> {
  static const _maxFiles = 8;

  String _mode = 'date';
  StudySourceTree? _tree;
  bool _loadingTree = true;
  String? _treeError;
  String? _selectedDate;
  String? _selectedFolder;
  final Set<String> _checked = {};
  List<String> _pickerFiles = const [];
  bool _busy = false;
  String? _actionError;
  StudyNoteModel? _note;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadTree);
  }

  Future<void> _loadTree() async {
    final cohortId = ref.read(effectiveCohortIdProvider);
    if (cohortId == null) return;
    setState(() {
      _loadingTree = true;
      _treeError = null;
    });
    try {
      final tree = await ref.read(studyNoteServiceProvider).listTree(
            cohortId: cohortId,
            sourceId: widget.sourceId,
          );
      if (!mounted) return;
      setState(() {
        _tree = tree;
        _loadingTree = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingTree = false;
        _treeError = _message(e);
      });
    }
  }

  Future<void> _openExisting(String noteId) async {
    final cohortId = ref.read(effectiveCohortIdProvider);
    if (cohortId == null) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      final note = await ref.read(studyNoteServiceProvider).getNote(
            cohortId: cohortId,
            noteId: noteId,
          );
      if (!mounted) return;
      setState(() {
        _note = note;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _actionError = _message(e);
      });
    }
  }

  Future<void> _generate(String scopeType, Object scopeValue) async {
    final cohortId = ref.read(effectiveCohortIdProvider);
    if (cohortId == null) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      final note = await ref.read(studyNoteServiceProvider).generate(
            cohortId: cohortId,
            sourceId: widget.sourceId,
            scopeType: scopeType,
            scopeValue: scopeValue,
          );
      if (!mounted) return;
      if (note.isTooBroad) {
        setState(() {
          _busy = false;
          _mode = 'file';
          _pickerFiles = note.files.map((f) => f.path).toList();
          _checked
            ..clear()
            ..addAll(_pickerFiles.take(_maxFiles));
          _actionError = note.message ?? '파일을 선택하세요.';
        });
        return;
      }
      setState(() {
        _note = note;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _actionError = _message(e);
      });
    }
  }

  String _message(Object error) {
    if (error is FirebaseFunctionsException) {
      final raw = error.message?.trim() ?? '';
      if (error.code == 'not-found' ||
          raw.isEmpty ||
          raw == 'internal' ||
          raw == '[O]' ||
          raw == 'internal [O]') {
        return '수업 목록 기능을 아직 쓸 수 없습니다. 잠시 후 다시 시도해 주세요.';
      }
      return raw;
    }
    return '요청에 실패했습니다.';
  }

  List<String> get _fileChoices {
    if (_pickerFiles.isNotEmpty) return _pickerFiles;
    return _tree?.entries ?? const [];
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final cohortName = ref.watch(effectiveCohortNameProvider);
    final sources = ref.watch(activeStudySourcesProvider);
    final notes = ref.watch(readyStudyNotesProvider);

    return userAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (user) {
        if (user == null) return const SizedBox.shrink();
        final source = sources.asData?.value
            .where((item) => item.id == widget.sourceId)
            .firstOrNull;
        return SingleChildScrollView(
          child: studyRoomContentWrapper(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => context.go(RoutePaths.studyRoomNotes),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('공부방'),
                  ),
                ),
                StudyRoomPageHeader(
                  user: user,
                  cohortName: cohortName,
                  title: '공부방',
                  subtitle: source == null
                      ? '범위를 고른 뒤 수업 노트를 만듭니다.'
                      : '${source.title} · ${source.repoLabel}',
                ),
                const SizedBox(height: 16),
                notes.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (list) {
                    final mine = list
                        .where((note) => note.sourceId == widget.sourceId)
                        .toList();
                    if (mine.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '이미 만든 노트',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final note in mine)
                              ActionChip(
                                label: Text(note.scopeLabel),
                                onPressed: _busy ? null : () => _openExisting(note.id),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'date', label: Text('날짜')),
                    ButtonSegment(value: 'folder', label: Text('폴더')),
                    ButtonSegment(value: 'file', label: Text('파일')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: _busy
                      ? null
                      : (value) => setState(() {
                            _mode = value.first;
                            _pickerFiles = const [];
                            _actionError = null;
                          }),
                ),
                const SizedBox(height: 16),
                if (_loadingTree)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_treeError != null)
                  ErrorView(message: _treeError!, onRetry: _loadTree)
                else
                  _ScopePanel(
                    mode: _mode,
                    dates: _tree?.dates ?? const [],
                    folders: _folders(source),
                    files: _fileChoices,
                    selectedDate: _selectedDate,
                    selectedFolder: _selectedFolder,
                    checked: _checked,
                    maxFiles: _maxFiles,
                    truncated: _tree?.truncated == true,
                    busy: _busy,
                    onDate: (value) => setState(() => _selectedDate = value),
                    onFolder: (value) => setState(() => _selectedFolder = value),
                    onToggleFile: (path, selected) {
                      setState(() {
                        if (selected) {
                          if (_checked.length >= _maxFiles) return;
                          _checked.add(path);
                        } else {
                          _checked.remove(path);
                        }
                      });
                    },
                    onGenerate: _onGenerate,
                  ),
                if (_busy) ...[
                  const SizedBox(height: 20),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text(
                    '선택한 범위만 정리하는 중입니다. 잠시만 기다려 주세요.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
                if (_actionError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _actionError!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ],
                if (_note?.isReady == true) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: StudyNoteMarkdown(data: _note!.reportMarkdown),
                  ),
                  const SizedBox(height: 12),
                  StudyReviewPanel(markdown: _note!.reviewMarkdown),
                ] else if (_note?.isFailed == true) ...[
                  const SizedBox(height: 12),
                  Text(
                    _note?.errorMessage ?? '노트 생성에 실패했습니다.',
                    style: const TextStyle(color: AppColors.error),
                  ),
                ] else if (_note?.isGenerating == true) ...[
                  const SizedBox(height: 12),
                  Text(
                    _note?.message ?? '정리 중입니다.',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  List<String> _folders(StudySourceModel? source) {
    final fromTree = _tree?.folders() ?? const <String>[];
    final allowed = source?.allowedPrefixes ?? const <String>[];
    return {...allowed, ...fromTree}.toList()..sort();
  }

  void _onGenerate() {
    if (_mode == 'date') {
      if (_selectedDate == null) return;
      _generate('date', _selectedDate!);
      return;
    }
    if (_mode == 'folder') {
      if (_selectedFolder == null) return;
      final files = _tree?.filesUnder(_selectedFolder!) ?? const [];
      if (files.length >= 9) {
        setState(() {
          _mode = 'file';
          _pickerFiles = files;
          _checked
            ..clear()
            ..addAll(files.take(_maxFiles));
          _actionError = '파일을 선택하세요. 한 번에 최대 8개까지 정리할 수 있습니다.';
        });
        return;
      }
      _generate('prefix', _selectedFolder!);
      return;
    }
    if (_checked.isEmpty) {
      setState(() => _actionError = '파일을 1개 이상 선택하세요.');
      return;
    }
    _generate('files', _checked.toList()..sort());
  }
}

class _ScopePanel extends StatelessWidget {
  const _ScopePanel({
    required this.mode,
    required this.dates,
    required this.folders,
    required this.files,
    required this.selectedDate,
    required this.selectedFolder,
    required this.checked,
    required this.maxFiles,
    required this.truncated,
    required this.busy,
    required this.onDate,
    required this.onFolder,
    required this.onToggleFile,
    required this.onGenerate,
  });

  final String mode;
  final List<String> dates;
  final List<String> folders;
  final List<String> files;
  final String? selectedDate;
  final String? selectedFolder;
  final Set<String> checked;
  final int maxFiles;
  final bool truncated;
  final bool busy;
  final ValueChanged<String> onDate;
  final ValueChanged<String> onFolder;
  final void Function(String path, bool selected) onToggleFile;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (truncated) {
      children.add(
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            '파일이 많아 일부만 표시합니다. 폴더를 더 좁혀 주세요.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    if (mode == 'date') {
      if (dates.isEmpty) {
        children.add(const Text('최근 30일 수업일이 없습니다.'));
      } else {
        children.add(
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final date in dates)
                ChoiceChip(
                  label: Text(date),
                  selected: selectedDate == date,
                  onSelected: busy ? null : (_) => onDate(date),
                ),
            ],
          ),
        );
      }
      children.add(const SizedBox(height: 16));
      children.add(
        FilledButton(
          onPressed: busy || selectedDate == null ? null : onGenerate,
          child: const Text('이 날짜 정리'),
        ),
      );
    } else if (mode == 'folder') {
      if (folders.isEmpty) {
        children.add(const Text('선택할 폴더가 없습니다.'));
      } else {
        children.add(
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final folder in folders)
                ChoiceChip(
                  label: Text(folder),
                  selected: selectedFolder == folder,
                  onSelected: busy ? null : (_) => onFolder(folder),
                ),
            ],
          ),
        );
      }
      children.add(const SizedBox(height: 16));
      children.add(
        FilledButton(
          onPressed: busy || selectedFolder == null ? null : onGenerate,
          child: const Text('이 폴더 정리'),
        ),
      );
    } else {
      children.add(
        Text(
          '${checked.length}/$maxFiles개 선택',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
      children.add(const SizedBox(height: 8));
      if (files.isEmpty) {
        children.add(const Text('선택할 파일이 없습니다.'));
      } else {
        children.add(
          Column(
            children: [
              for (final path in files)
                CheckboxListTile(
                  value: checked.contains(path),
                  onChanged: busy
                      ? null
                      : (value) => onToggleFile(path, value == true),
                  title: Text(path, style: const TextStyle(fontSize: 13)),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        );
      }
      children.add(const SizedBox(height: 8));
      children.add(
        FilledButton(
          onPressed: busy || checked.isEmpty ? null : onGenerate,
          child: const Text('선택한 파일 정리'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
