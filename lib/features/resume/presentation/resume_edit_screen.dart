import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/models/resume_content.dart';
import '../../../shared/models/resume_model.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../../shared/providers/lms_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/basic_info_prefill.dart';
import '../ai_coach/presentation/ai_job_coach_panel.dart';
import '../ai_coach/presentation/resume_mock_menu.dart';
import '../services/resume_pdf_exporter.dart';
import 'widgets/resume_edit_feedback_panel.dart';
import 'widgets/resume_section_nav.dart';
import 'widgets/tech_stack_editor.dart';

enum _ResumeViewMode { edit, doc }

/// 이력서 작성/편집/미리보기 페이지
class ResumeEditScreen extends ConsumerStatefulWidget {
  const ResumeEditScreen({
    super.key,
    required this.resumeId,
    this.initialSection,
    this.cohortId,
  });

  final String resumeId;
  final String? initialSection;
  final String? cohortId;

  @override
  ConsumerState<ResumeEditScreen> createState() => _ResumeEditScreenState();
}

class _ResumeEditScreenState extends ConsumerState<ResumeEditScreen> {
  _ResumeViewMode _viewMode = _ResumeViewMode.edit;
  bool _isSaving = false;
  bool _dirty = false;
  bool _showAiCoach = false;

  String _title = '';
  ResumeContent _content = ResumeContent.empty();
  bool _initialized = false;
  bool _pendingInitialScroll = false;
  bool _profilePrefillTried = false;

  late final ScrollController _scrollController;
  late final Map<String, GlobalKey> _sectionKeys;
  String? _selectedSection;
  bool _isAdmin = false;
  ResumeModel? _resume;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _sectionKeys = {
      for (final k in AppConstants.resumeSections) k: GlobalKey(),
    };
    _selectedSection = widget.initialSection;
    _pendingInitialScroll = widget.initialSection != null;
    if (widget.cohortId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        selectCohort(ref, widget.cohortId!);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _initFromResume(ResumeModel resume) {
    if (_initialized) return;
    _title = resume.title;
    _content = resume.content;
    _initialized = true;
    if (ref.read(isAdminProvider) || resume.isApproved) {
      _viewMode = _ResumeViewMode.doc;
    }
    if (_pendingInitialScroll && widget.initialSection != null) {
      _pendingInitialScroll = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSection(widget.initialSection!);
      });
    }
    if (!ref.read(isAdminProvider) && resume.hasUnreadFeedback) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final cohortId = ref.read(effectiveCohortIdProvider);
        if (cohortId == null) return;
        ref.read(lmsRepositoryProvider).markResumeFeedbackSeen(
              cohortId: cohortId,
              resumeId: widget.resumeId,
              feedbackCount: resume.feedbackCount,
            );
      });
    }
  }

  bool _isReadOnly({required bool isAdmin, required ResumeModel resume}) =>
      isAdmin ||
      _viewMode == _ResumeViewMode.doc ||
      (!isAdmin && resume.isApproved);

  /// 마이페이지 프로필로 기본정보의 빈 칸을 채운다. 학생 본인이 편집할 수 있는
  /// 이력서에서만 동작하고, 이미 적힌 값은 건드리지 않는다.
  ///
  /// [announce]가 true면 채운 항목을 스낵바로 알린다(첫 로드). 프로필 스트림이
  /// 아직 안 왔으면 조용히 건너뛰고, 기본정보 섹션의 버튼으로 다시 시도할 수 있다.
  bool _prefillBasicInfoFromProfile(ResumeModel resume, {required bool announce}) {
    if (ref.read(isAdminProvider) || resume.isApproved) return false;
    final user = ref.read(currentUserProvider).value;
    if (user == null) return false;
    final result = prefillBasicInfoFromProfile(_content.basicInfo, user);
    if (!result.changed) return false;
    _content = _content.copyWith(basicInfo: result.info);
    _dirty = true;
    if (announce) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '마이페이지 정보로 ${result.filledLabels.join(', ')}을(를) 채웠습니다. 저장하면 반영됩니다.',
            ),
          ),
        );
      });
    }
    return true;
  }

  void _markDirty() {
    final resume = _resume;
    if (resume == null || _isReadOnly(isAdmin: _isAdmin, resume: resume)) return;
    setState(() => _dirty = true);
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('저장하지 않은 변경'),
        content: const Text('저장하지 않은 내용이 있습니다. 나가시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('계속 작성')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('나가기')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _goBack() async {
    if (!await _confirmLeave() || !mounted) return;
    context.go(RoutePaths.resume);
  }

  void _scrollToSection(String key) {
    setState(() => _selectedSection = key);
    final ctx = _sectionKeys[key]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.08,
      );
    }
  }

  Widget _section(String key, Widget child) =>
      KeyedSubtree(key: _sectionKeys[key], child: child);

  Future<void> _save({
    required ResumeModel resume,
    String? status,
    bool incrementRevision = true,
  }) async {
    final isAdmin = ref.read(isAdminProvider);
    if (_isReadOnly(isAdmin: isAdmin, resume: resume) && status == null) return;
    setState(() => _isSaving = true);
    try {
      final cohortId = ref.read(effectiveCohortIdProvider)!;
      await ref.read(lmsRepositoryProvider).updateResume(
            cohortId: cohortId,
            resumeId: widget.resumeId,
            title: _title.trim().isEmpty ? '새 이력서' : _title.trim(),
            content: _content,
            status: status,
            incrementRevision: incrementRevision && status == null,
          );
      _dirty = false;
      if (mounted && status == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장되었습니다.')),
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

  Future<void> _submitRequest(ResumeModel resume) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('제출 요청'),
        content: const Text(
          '관리자에게 검토를 요청합니다. 승인 전까지는 계속 수정할 수 있습니다.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('제출 요청')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _save(resume: resume, status: 'submitted', incrementRevision: false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제출 요청이 완료되었습니다.')),
      );
    }
  }

  Future<void> _approve(ResumeModel resume) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이력서 승인'),
        content: const Text('승인 후 학생은 더 이상 수정할 수 없습니다. 승인하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('승인')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(lmsRepositoryProvider).approveResume(
            cohortId: ref.read(effectiveCohortIdProvider)!,
            resumeId: widget.resumeId,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('승인되었습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('승인 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _exportPdf(ResumeModel resume) async {
    try {
      final model = resume.copyWith(
        title: _title.trim().isEmpty ? '새 이력서' : _title.trim(),
        content: _content,
      );
      await ResumePdfExporter.showPrintPreview(model);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF 내보내기 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    final resumeAsync = ref.watch(resumeDetailProvider(widget.resumeId));

    return resumeAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: ErrorView(message: e.toString())),
      data: (resume) {
        if (resume == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('이력서')),
            body: const Center(child: Text('이력서를 찾을 수 없습니다.')),
          );
        }
        _initFromResume(resume);
        // 첫 로드 때 프로필 스트림이 아직 안 왔으면 도착한 뒤 한 번만 자동으로 채운다.
        if (!_profilePrefillTried && ref.watch(currentUserProvider).value != null) {
          _profilePrefillTried = true;
          _prefillBasicInfoFromProfile(resume, announce: true);
        }
        _isAdmin = isAdmin;
        _resume = resume;
        final readOnly = _isReadOnly(isAdmin: isAdmin, resume: resume);
        final liveSections = _content.computeSections();
        final completed = liveSections.values.where((v) => v).length;

        return PopScope(
          canPop: !_dirty,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            if (await _confirmLeave() && context.mounted) {
              context.go(RoutePaths.resume);
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: const SizedBox.shrink(),
              leading: TextButton.icon(
                onPressed: _goBack,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('목록으로'),
              ),
              leadingWidth: 110,
              actions: [
                if (!isAdmin && resume.canStudentEdit && _viewMode == _ResumeViewMode.edit)
                  ResumeMockMenu(
                    onPick: (title, content) {
                      setState(() {
                        _title = title;
                        // 기본정보는 사용자가 적었거나 프로필에서 채워진 값을 지키고,
                        // 목업은 빈 칸과 그 아래 섹션만 채운다.
                        _content = content.copyWith(
                          basicInfo: mergeBasicInfo(_content.basicInfo, content.basicInfo),
                        );
                      });
                      _markDirty();
                    },
                  ),
                FilledButton.tonalIcon(
                  onPressed: () => setState(() => _showAiCoach = !_showAiCoach),
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('AI 취업 코치'),
                ),
                const SizedBox(width: 8),
                if (!resume.isApproved || isAdmin)
                  _ModeToggle(
                    isEdit: _viewMode == _ResumeViewMode.edit,
                    onEdit: () => setState(() => _viewMode = _ResumeViewMode.edit),
                    onDoc: () => setState(() => _viewMode = _ResumeViewMode.doc),
                  ),
                if (_viewMode == _ResumeViewMode.doc) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'PDF 내보내기',
                    onPressed: () => _exportPdf(resume),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                  ),
                ],
                if (!isAdmin && resume.canStudentEdit && _viewMode == _ResumeViewMode.edit) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _isSaving ? null : () => _save(resume: resume),
                    child: const Text('저장'),
                  ),
                  if (!resume.isSubmitted) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : () => _submitRequest(resume),
                      icon: const Icon(Icons.send, size: 16),
                      label: const Text('제출 요청'),
                    ),
                  ],
                  const SizedBox(width: 8),
                ],
                if (isAdmin && resume.isSubmitted && !resume.isApproved) ...[
                  FilledButton.icon(
                    onPressed: _isSaving ? null : () => _approve(resume),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('승인'),
                  ),
                  const SizedBox(width: 8),
                ],
                if (_isSaving)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ResumeProgressHeader(
                  completed: completed,
                  total: AppConstants.resumeSections.length,
                  revisionCount: resume.revisionCount,
                  statusLabel: resume.statusLabel,
                ),
                if (resume.isSubmitted && !resume.isApproved && !isAdmin)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: AppColors.primaryLight,
                    child: const Text(
                      '제출 요청됨 — 승인 전까지 수정 가능합니다.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                if (resume.isApproved)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: AppColors.success.withValues(alpha: 0.12),
                    child: const Text(
                      '승인 완료 — 더 이상 수정할 수 없습니다.',
                      style: TextStyle(fontSize: 12, color: AppColors.success),
                    ),
                  ),
                ResumeSectionNav(
                  sections: AppConstants.resumeSections,
                  completedSections: liveSections,
                  selectedKey: _selectedSection,
                  onSelected: _scrollToSection,
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 1000;

                      final resumeScroll = SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: wide ? double.infinity : 720,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _TitleSection(
                                  title: _title,
                                  readOnly: readOnly,
                                  onChanged: (v) {
                                    setState(() => _title = v);
                                    _markDirty();
                                  },
                                ),
                                const SizedBox(height: 24),
                                _section(
                                  'basicInfo',
                                  _BasicInfoSection(
                                    info: _content.basicInfo,
                                    readOnly: readOnly,
                                    onChanged: (info) {
                                      setState(
                                        () => _content = _content.copyWith(basicInfo: info),
                                      );
                                      _markDirty();
                                    },
                                    onPrefill: readOnly
                                        ? null
                                        : () {
                                            final changed = _prefillBasicInfoFromProfile(
                                              resume,
                                              announce: false,
                                            );
                                            setState(() {});
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  changed
                                                      ? '마이페이지 정보로 빈 칸을 채웠습니다.'
                                                      : '채울 빈 칸이 없거나 마이페이지에 정보가 없습니다.',
                                                ),
                                              ),
                                            );
                                          },
                                  ),
                                ),
                                const SizedBox(height: 24),
                                _section(
                                  'coreCompetencies',
                                  _CoreCompetenciesSection(
                                    data: _content.coreCompetencies,
                                    readOnly: readOnly,
                                    onChanged: (d) {
                                      setState(
                                        () => _content = _content.copyWith(
                                          coreCompetencies: d,
                                        ),
                                      );
                                      _markDirty();
                                    },
                                  ),
                                ),
                                const SizedBox(height: 24),
                                _section(
                                  'experience',
                                  _ExperienceSection(
                                    items: _content.experience,
                                    readOnly: readOnly,
                                    onChanged: (items) {
                                      setState(
                                        () => _content = _content.copyWith(experience: items),
                                      );
                                      _markDirty();
                                    },
                                  ),
                                ),
                                const SizedBox(height: 24),
                                _section(
                                  'education',
                                  _EducationSection(
                                    items: _content.education,
                                    readOnly: readOnly,
                                    onChanged: (items) {
                                      setState(
                                        () => _content = _content.copyWith(education: items),
                                      );
                                      _markDirty();
                                    },
                                  ),
                                ),
                                const SizedBox(height: 24),
                                _section(
                                  'techStack',
                                  _TechStackSection(
                                    items: _content.techStack,
                                    readOnly: readOnly,
                                    onChanged: (items) {
                                      setState(
                                        () => _content = _content.copyWith(techStack: items),
                                      );
                                      _markDirty();
                                    },
                                  ),
                                ),
                                const SizedBox(height: 24),
                                _section(
                                  'certifications',
                                  _CertificationsSection(
                                    items: _content.certifications,
                                    readOnly: readOnly,
                                    onChanged: (items) {
                                      setState(
                                        () => _content = _content.copyWith(
                                          certifications: items,
                                        ),
                                      );
                                      _markDirty();
                                    },
                                  ),
                                ),
                                const SizedBox(height: 24),
                                _section(
                                  'awards',
                                  _AwardsSection(
                                    items: _content.awards,
                                    readOnly: readOnly,
                                    onChanged: (items) {
                                      setState(
                                        () => _content = _content.copyWith(awards: items),
                                      );
                                      _markDirty();
                                    },
                                  ),
                                ),
                                const SizedBox(height: 24),
                                _section(
                                  'trainingExperience',
                                  _TrainingSection(
                                    items: _content.trainingExperience,
                                    readOnly: readOnly,
                                    onChanged: (items) {
                                      setState(
                                        () => _content = _content.copyWith(
                                          trainingExperience: items,
                                        ),
                                      );
                                      _markDirty();
                                    },
                                  ),
                                ),
                                const SizedBox(height: 24),
                                _section(
                                  'otherActivities',
                                  _ActivitiesSection(
                                    items: _content.otherActivities,
                                    readOnly: readOnly,
                                    onChanged: (items) {
                                      setState(
                                        () => _content = _content.copyWith(
                                          otherActivities: items,
                                        ),
                                      );
                                      _markDirty();
                                    },
                                  ),
                                ),
                                const SizedBox(height: 24),
                                _section(
                                  'projects',
                                  _ProjectsSection(
                                    items: _content.projects,
                                    readOnly: readOnly,
                                    onChanged: (items) {
                                      setState(
                                        () => _content = _content.copyWith(projects: items),
                                      );
                                      _markDirty();
                                    },
                                  ),
                                ),
                                const SizedBox(height: 24),
                                _section(
                                  'selfIntroduction',
                                  _SelfIntroSection(
                                    data: _content.selfIntroduction,
                                    readOnly: readOnly,
                                    onChanged: (d) {
                                      setState(
                                        () => _content = _content.copyWith(
                                          selfIntroduction: d,
                                        ),
                                      );
                                      _markDirty();
                                    },
                                  ),
                                ),
                                const SizedBox(height: 32),
                              ],
                            ),
                          ),
                        ),
                      );

                      final rightPanel = _showAiCoach
                          ? AiJobCoachPanel(
                              resumeId: widget.resumeId,
                              draftContent: _content,
                              isSidebar: wide,
                              onClose: () => setState(() => _showAiCoach = false),
                            )
                          : ResumeEditFeedbackPanel(
                              resumeId: widget.resumeId,
                              isAdmin: isAdmin,
                              selectedSectionKey: _selectedSection,
                              isSidebar: wide,
                            );

                      if (!wide) {
                        return Column(
                          children: [
                            Expanded(child: resumeScroll),
                            rightPanel,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: resumeScroll),
                          SizedBox(
                            width: 340,
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                border: Border(
                                  left: BorderSide(color: AppColors.border),
                                ),
                              ),
                              child: rightPanel,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── 공통 위젯 ──

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.isEdit,
    required this.onEdit,
    required this.onDoc,
  });

  final bool isEdit;
  final VoidCallback onEdit;
  final VoidCallback onDoc;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleChip(label: 'Doc', selected: !isEdit, onTap: onDoc),
          _ToggleChip(label: 'Edit', selected: isEdit, onTap: onEdit),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _FlatSection extends StatelessWidget {
  const _FlatSection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Divider(height: 1, color: AppColors.border),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}

class _Field extends StatefulWidget {
  const _Field({
    required this.label,
    this.hint,
    required this.value,
    required this.readOnly,
    required this.onChanged,
    this.maxLines = 1,
    this.keyboardType,
    this.boxed = false,
  });

  final String label;
  final String? hint;
  final String value;
  final bool readOnly;
  final ValueChanged<String> onChanged;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool boxed;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_Field oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.readOnly) {
      final empty = widget.value.trim().isEmpty;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.label.isNotEmpty)
              Text(
                widget.label,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            if (widget.label.isNotEmpty) const SizedBox(height: 2),
            Text(
              empty ? '미작성' : widget.value,
              style: TextStyle(
                color: empty ? AppColors.textHint : AppColors.textPrimary,
                height: widget.maxLines > 1 ? 1.5 : null,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.boxed) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.label.isEmpty ? null : widget.label,
            hintText: widget.hint,
            alignLabelWithHint: widget.maxLines > 1,
          ),
          maxLines: widget.maxLines,
          minLines: widget.maxLines > 1 ? widget.maxLines : 1,
          keyboardType: widget.keyboardType,
          onChanged: widget.onChanged,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: _controller,
        decoration: InputDecoration(
          labelText: widget.label.isEmpty ? null : widget.label,
          hintText: widget.hint,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.border),
          ),
          filled: false,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        maxLines: widget.maxLines,
        keyboardType: widget.keyboardType,
        onChanged: widget.onChanged,
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        alignment: Alignment.centerLeft,
      ),
      icon: const Icon(Icons.add, size: 18),
      label: Text(label),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.index,
    required this.readOnly,
    required this.onDelete,
    required this.child,
  });

  final int index;
  final bool readOnly;
  final VoidCallback onDelete;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('항목 ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (!readOnly)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: onDelete,
                ),
            ],
          ),
          child,
        ],
      ),
    );
  }
}

Future<void> _pickDate(
  BuildContext context,
  String current,
  ValueChanged<String> onPicked,
) async {
  final initial = DateTime.tryParse(current) ?? DateTime(2000);
  final picked = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(1970),
    lastDate: DateTime(2100),
  );
  if (picked != null) {
    onPicked(
      '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
    );
  }
}

// ── 섹션 위젯 ──

class _TitleSection extends StatefulWidget {
  const _TitleSection({
    required this.title,
    required this.readOnly,
    required this.onChanged,
  });

  final String title;
  final bool readOnly;
  final ValueChanged<String> onChanged;

  @override
  State<_TitleSection> createState() => _TitleSectionState();
}

class _TitleSectionState extends State<_TitleSection> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.title);
  }

  @override
  void didUpdateWidget(_TitleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.title != _controller.text) {
      _controller.text = widget.title;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('이력서 제목', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (widget.readOnly)
                Text(
                  widget.title.isEmpty ? '새 이력서' : widget.title,
                  style: const TextStyle(fontSize: 18),
                )
              else
                TextField(
                  controller: _controller,
                  decoration: const InputDecoration(hintText: '새 이력서', border: InputBorder.none),
                  maxLength: 100,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                      null,
                  onChanged: widget.onChanged,
                ),
            ],
          ),
        ),
        if (!widget.readOnly)
          Text(
            '${widget.title.length}/100',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
      ],
    );
  }
}

class _BasicInfoSection extends StatelessWidget {
  const _BasicInfoSection({
    required this.info,
    required this.readOnly,
    required this.onChanged,
    this.onPrefill,
  });

  final ResumeBasicInfo info;
  final bool readOnly;
  final ValueChanged<ResumeBasicInfo> onChanged;

  /// 마이페이지 정보로 빈 칸을 채우는 동작. 읽기 전용이면 null.
  final VoidCallback? onPrefill;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (readOnly)
          Text(
            info.name.isEmpty ? '이름 없음' : info.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          )
        else
          _NameField(
            value: info.name,
            onChanged: (v) => onChanged(info.copyWith(name: v)),
          ),
        if (onPrefill != null) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: onPrefill,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.person_outline, size: 16),
            label: const Text(
              '마이페이지 정보로 빈 칸 채우기',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            _IconField(
              icon: Icons.phone_outlined,
              label: '연락처',
              value: info.phone,
              readOnly: readOnly,
              keyboardType: TextInputType.phone,
              onChanged: (v) => onChanged(info.copyWith(phone: v)),
            ),
            _IconField(
              icon: Icons.email_outlined,
              label: '이메일',
              value: info.email,
              readOnly: readOnly,
              keyboardType: TextInputType.emailAddress,
              onChanged: (v) => onChanged(info.copyWith(email: v)),
            ),
            _IconField(
              icon: Icons.calendar_today_outlined,
              label: '생년월일',
              value: info.birthDate,
              readOnly: readOnly,
              onTap: readOnly
                  ? null
                  : () => _pickDate(
                        context,
                        info.birthDate,
                        (v) => onChanged(info.copyWith(birthDate: v)),
                      ),
              onChanged: (v) => onChanged(info.copyWith(birthDate: v)),
            ),
            _IconField(
              icon: Icons.code,
              label: 'Github URL',
              value: info.githubUrl,
              readOnly: readOnly,
              keyboardType: TextInputType.url,
              onChanged: (v) => onChanged(info.copyWith(githubUrl: v)),
            ),
            _IconField(
              icon: Icons.language,
              label: 'Blog URL',
              value: info.blogUrl,
              readOnly: readOnly,
              keyboardType: TextInputType.url,
              onChanged: (v) => onChanged(info.copyWith(blogUrl: v)),
            ),
          ],
        ),
      ],
    );
  }
}

class _NameField extends StatefulWidget {
  const _NameField({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_NameField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: const InputDecoration(
        hintText: '이름을 입력하세요',
        hintStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: AppColors.textHint,
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: 4),
      ),
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      onChanged: widget.onChanged,
    );
  }
}

class _IconField extends StatefulWidget {
  const _IconField({
    required this.icon,
    required this.label,
    required this.value,
    required this.readOnly,
    required this.onChanged,
    this.keyboardType,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool readOnly;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final VoidCallback? onTap;

  @override
  State<_IconField> createState() => _IconFieldState();
}

class _IconFieldState extends State<_IconField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_IconField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textField = TextField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.onTap != null ? '날짜 선택' : null,
        isDense: true,
      ),
      readOnly: widget.onTap != null,
      keyboardType: widget.keyboardType,
      onChanged: widget.onChanged,
      style: const TextStyle(fontSize: 13),
    );

    return SizedBox(
      width: 200,
      child: Row(
        children: [
          Icon(widget.icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: widget.readOnly
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                      ),
                      Text(
                        widget.value.isEmpty ? '미작성' : widget.value,
                        style: TextStyle(
                          fontSize: 13,
                          color: widget.value.isEmpty
                              ? AppColors.textHint
                              : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  )
                : widget.onTap != null
                    ? InkWell(onTap: widget.onTap, child: textField)
                    : textField,
          ),
        ],
      ),
    );
  }
}

class _CoreCompetenciesSection extends StatelessWidget {
  const _CoreCompetenciesSection({
    required this.data,
    required this.readOnly,
    required this.onChanged,
  });

  final ResumeCoreCompetencies data;
  final bool readOnly;
  final ValueChanged<ResumeCoreCompetencies> onChanged;

  @override
  Widget build(BuildContext context) {
    return _FlatSection(
      title: AppConstants.resumeSectionLabels['coreCompetencies']!,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '채용 담당자들이 가장 먼저 읽게 되는 글입니다.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const Text(
            '경력을 기반으로 나의 역량과 강점을 소개해 주세요.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const Text(
            '5줄 이내로 간결하게 작성하는 것을 권장합니다.',
            style: TextStyle(fontSize: 13, color: AppColors.textHint),
          ),
          const SizedBox(height: 12),
          _Field(
            label: '',
            hint: '역량과 강점을 입력하세요',
            value: data.text,
            readOnly: readOnly,
            maxLines: 5,
            boxed: true,
            onChanged: (v) => onChanged(data.copyWith(text: v)),
          ),
        ],
      ),
    );
  }
}

class _ExperienceSection extends StatelessWidget {
  const _ExperienceSection({
    required this.items,
    required this.readOnly,
    required this.onChanged,
  });

  final List<ResumeExperienceItem> items;
  final bool readOnly;
  final ValueChanged<List<ResumeExperienceItem>> onChanged;

  void _update(int i, ResumeExperienceItem item) {
    final list = [...items];
    list[i] = item;
    onChanged(list);
  }

  @override
  Widget build(BuildContext context) {
    return _FlatSection(
      title: AppConstants.resumeSectionLabels['experience']!,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...items.asMap().entries.map((e) {
            final i = e.key;
            final item = e.value;
            return _ItemCard(
              index: i,
              readOnly: readOnly,
              onDelete: () => onChanged(items.where((x) => x.id != item.id).toList()),
              child: Column(
                children: [
                  _Field(label: '회사명', value: item.company, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(company: v))),
                  _Field(label: '직무', value: item.role, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(role: v))),
                  _Field(label: '시작일', value: item.startDate, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(startDate: v))),
                  _Field(label: '종료일', value: item.endDate, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(endDate: v))),
                  if (!readOnly)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: item.isCurrent,
                      title: const Text('재직 중'),
                      onChanged: (v) => _update(i, item.copyWith(isCurrent: v ?? false)),
                    ),
                  _Field(label: '업무 설명', value: item.description, readOnly: readOnly, maxLines: 3, onChanged: (v) => _update(i, item.copyWith(description: v))),
                ],
              ),
            );
          }),
          if (!readOnly)
            _AddButton(
              label: '항목 추가',
              onPressed: () => onChanged([...items, ResumeExperienceItem.empty()]),
            ),
        ],
      ),
    );
  }
}

class _EducationSection extends StatelessWidget {
  const _EducationSection({
    required this.items,
    required this.readOnly,
    required this.onChanged,
  });

  final List<ResumeEducationItem> items;
  final bool readOnly;
  final ValueChanged<List<ResumeEducationItem>> onChanged;

  void _update(int i, ResumeEducationItem item) {
    final list = [...items];
    list[i] = item;
    onChanged(list);
  }

  @override
  Widget build(BuildContext context) {
    return _FlatSection(
      title: AppConstants.resumeSectionLabels['education']!,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...items.asMap().entries.map((e) {
            final i = e.key;
            final item = e.value;
            return _ItemCard(
              index: i,
              readOnly: readOnly,
              onDelete: () => onChanged(items.where((x) => x.id != item.id).toList()),
              child: Column(
                children: [
                  _Field(label: '학교명', value: item.school, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(school: v))),
                  _Field(label: '전공', value: item.major, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(major: v))),
                  _Field(label: '시작일', value: item.startDate, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(startDate: v))),
                  _Field(label: '종료일', value: item.endDate, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(endDate: v))),
                  _Field(label: '상태 (졸업/재학/수료)', value: item.status, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(status: v))),
                ],
              ),
            );
          }),
          if (!readOnly)
            _AddButton(
              label: '항목 추가',
              onPressed: () => onChanged([...items, ResumeEducationItem.empty()]),
            ),
        ],
      ),
    );
  }
}

class _TechStackSection extends StatelessWidget {
  const _TechStackSection({
    required this.items,
    required this.readOnly,
    required this.onChanged,
  });

  final List<ResumeTechStackItem> items;
  final bool readOnly;
  final ValueChanged<List<ResumeTechStackItem>> onChanged;

  @override
  Widget build(BuildContext context) {
    // 기술은 태그로 고르고 숙련도는 설명이 달린 단계로 정한다.
    // 자유 입력 카드 방식은 표기가 제각각이라 공고 키워드 매칭에 잘 안 잡혔다.
    return _FlatSection(
      title: AppConstants.resumeSectionLabels['techStack']!,
      child: TechStackEditor(
        items: items,
        readOnly: readOnly,
        onChanged: onChanged,
      ),
    );
  }
}

class _CertificationsSection extends StatelessWidget {
  const _CertificationsSection({
    required this.items,
    required this.readOnly,
    required this.onChanged,
  });

  final List<ResumeCertificationItem> items;
  final bool readOnly;
  final ValueChanged<List<ResumeCertificationItem>> onChanged;

  void _update(int i, ResumeCertificationItem item) {
    final list = [...items];
    list[i] = item;
    onChanged(list);
  }

  @override
  Widget build(BuildContext context) {
    return _FlatSection(
      title: AppConstants.resumeSectionLabels['certifications']!,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...items.asMap().entries.map((e) {
            final i = e.key;
            final item = e.value;
            return _ItemCard(
              index: i,
              readOnly: readOnly,
              onDelete: () => onChanged(items.where((x) => x.id != item.id).toList()),
              child: Column(
                children: [
                  _Field(label: '자격명', value: item.name, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(name: v))),
                  _Field(label: '발급기관', value: item.issuer, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(issuer: v))),
                  _Field(label: '취득일', value: item.acquiredDate, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(acquiredDate: v))),
                ],
              ),
            );
          }),
          if (!readOnly)
            _AddButton(
              label: '항목 추가',
              onPressed: () => onChanged([...items, ResumeCertificationItem.empty()]),
            ),
        ],
      ),
    );
  }
}

class _AwardsSection extends StatelessWidget {
  const _AwardsSection({
    required this.items,
    required this.readOnly,
    required this.onChanged,
  });

  final List<ResumeAwardItem> items;
  final bool readOnly;
  final ValueChanged<List<ResumeAwardItem>> onChanged;

  void _update(int i, ResumeAwardItem item) {
    final list = [...items];
    list[i] = item;
    onChanged(list);
  }

  @override
  Widget build(BuildContext context) {
    return _FlatSection(
      title: AppConstants.resumeSectionLabels['awards']!,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...items.asMap().entries.map((e) {
            final i = e.key;
            final item = e.value;
            return _ItemCard(
              index: i,
              readOnly: readOnly,
              onDelete: () => onChanged(items.where((x) => x.id != item.id).toList()),
              child: Column(
                children: [
                  _Field(label: '수상명', value: item.name, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(name: v))),
                  _Field(label: '기관', value: item.organization, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(organization: v))),
                  _Field(label: '날짜', value: item.date, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(date: v))),
                  _Field(label: '설명', value: item.description, readOnly: readOnly, maxLines: 2, onChanged: (v) => _update(i, item.copyWith(description: v))),
                ],
              ),
            );
          }),
          if (!readOnly)
            _AddButton(
              label: '항목 추가',
              onPressed: () => onChanged([...items, ResumeAwardItem.empty()]),
            ),
        ],
      ),
    );
  }
}

class _TrainingSection extends StatelessWidget {
  const _TrainingSection({
    required this.items,
    required this.readOnly,
    required this.onChanged,
  });

  final List<ResumeTrainingItem> items;
  final bool readOnly;
  final ValueChanged<List<ResumeTrainingItem>> onChanged;

  void _update(int i, ResumeTrainingItem item) {
    final list = [...items];
    list[i] = item;
    onChanged(list);
  }

  @override
  Widget build(BuildContext context) {
    return _FlatSection(
      title: AppConstants.resumeSectionLabels['trainingExperience']!,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...items.asMap().entries.map((e) {
            final i = e.key;
            final item = e.value;
            return _ItemCard(
              index: i,
              readOnly: readOnly,
              onDelete: () => onChanged(items.where((x) => x.id != item.id).toList()),
              child: Column(
                children: [
                  _Field(label: '과정명', value: item.course, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(course: v))),
                  _Field(label: '기관', value: item.organization, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(organization: v))),
                  _Field(label: '시작일', value: item.startDate, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(startDate: v))),
                  _Field(label: '종료일', value: item.endDate, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(endDate: v))),
                  _Field(label: '설명', value: item.description, readOnly: readOnly, maxLines: 2, onChanged: (v) => _update(i, item.copyWith(description: v))),
                ],
              ),
            );
          }),
          if (!readOnly)
            _AddButton(
              label: '항목 추가',
              onPressed: () => onChanged([...items, ResumeTrainingItem.empty()]),
            ),
        ],
      ),
    );
  }
}

class _ActivitiesSection extends StatelessWidget {
  const _ActivitiesSection({
    required this.items,
    required this.readOnly,
    required this.onChanged,
  });

  final List<ResumeActivityItem> items;
  final bool readOnly;
  final ValueChanged<List<ResumeActivityItem>> onChanged;

  void _update(int i, ResumeActivityItem item) {
    final list = [...items];
    list[i] = item;
    onChanged(list);
  }

  @override
  Widget build(BuildContext context) {
    return _FlatSection(
      title: AppConstants.resumeSectionLabels['otherActivities']!,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...items.asMap().entries.map((e) {
            final i = e.key;
            final item = e.value;
            return _ItemCard(
              index: i,
              readOnly: readOnly,
              onDelete: () => onChanged(items.where((x) => x.id != item.id).toList()),
              child: Column(
                children: [
                  _Field(label: '활동명', value: item.name, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(name: v))),
                  _Field(label: '시작일', value: item.startDate, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(startDate: v))),
                  _Field(label: '종료일', value: item.endDate, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(endDate: v))),
                  _Field(label: '설명', value: item.description, readOnly: readOnly, maxLines: 2, onChanged: (v) => _update(i, item.copyWith(description: v))),
                ],
              ),
            );
          }),
          if (!readOnly)
            _AddButton(
              label: '항목 추가',
              onPressed: () => onChanged([...items, ResumeActivityItem.empty()]),
            ),
        ],
      ),
    );
  }
}

class _ProjectsSection extends StatelessWidget {
  const _ProjectsSection({
    required this.items,
    required this.readOnly,
    required this.onChanged,
  });

  final List<ResumeProjectItem> items;
  final bool readOnly;
  final ValueChanged<List<ResumeProjectItem>> onChanged;

  void _update(int i, ResumeProjectItem item) {
    final list = [...items];
    list[i] = item;
    onChanged(list);
  }

  @override
  Widget build(BuildContext context) {
    return _FlatSection(
      title: AppConstants.resumeSectionLabels['projects']!,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...items.asMap().entries.map((e) {
            final i = e.key;
            final item = e.value;
            return _ItemCard(
              index: i,
              readOnly: readOnly,
              onDelete: () => onChanged(items.where((x) => x.id != item.id).toList()),
              child: Column(
                children: [
                  _Field(label: '프로젝트명', value: item.name, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(name: v))),
                  _Field(label: '시작일', value: item.startDate, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(startDate: v))),
                  _Field(label: '종료일', value: item.endDate, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(endDate: v))),
                  _Field(label: '역할', value: item.role, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(role: v))),
                  _Field(label: '기술스택', value: item.techStack, readOnly: readOnly, onChanged: (v) => _update(i, item.copyWith(techStack: v))),
                  _Field(label: '설명', value: item.description, readOnly: readOnly, maxLines: 3, onChanged: (v) => _update(i, item.copyWith(description: v))),
                  _Field(label: 'URL (선택)', value: item.url, readOnly: readOnly, keyboardType: TextInputType.url, onChanged: (v) => _update(i, item.copyWith(url: v))),
                ],
              ),
            );
          }),
          if (!readOnly)
            _AddButton(
              label: '프로젝트 추가',
              onPressed: () => onChanged([...items, ResumeProjectItem.empty()]),
            ),
        ],
      ),
    );
  }
}

class _SelfIntroSection extends StatelessWidget {
  const _SelfIntroSection({
    required this.data,
    required this.readOnly,
    required this.onChanged,
  });

  final ResumeSelfIntroduction data;
  final bool readOnly;
  final ValueChanged<ResumeSelfIntroduction> onChanged;

  @override
  Widget build(BuildContext context) {
    return _FlatSection(
      title: AppConstants.resumeSectionLabels['selfIntroduction']!,
      child: Column(
        children: ResumeSelfIntroLabels.keys.map((key) {
          final section = data.sectionByKey(key);
          final label = ResumeSelfIntroLabels.labels[key]!;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _Field(
                  label: '부제목',
                  hint: '부제목을 작성하세요',
                  value: section.subtitle,
                  readOnly: readOnly,
                  onChanged: (v) => onChanged(
                    data.copyWithSection(key, section.copyWith(subtitle: v)),
                  ),
                ),
                _Field(
                  label: '상세 내용',
                  hint: '상세 내용을 작성해주세요.',
                  value: section.body,
                  readOnly: readOnly,
                  maxLines: 5,
                  onChanged: (v) => onChanged(
                    data.copyWithSection(key, section.copyWith(body: v)),
                  ),
                ),
                const Divider(),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
