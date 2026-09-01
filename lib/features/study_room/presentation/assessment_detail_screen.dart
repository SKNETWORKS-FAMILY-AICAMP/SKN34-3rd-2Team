import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/models/assessment_model.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../../shared/providers/lms_providers.dart';
import '../data/assessment_file_helper.dart';
import 'widgets/study_room_layout.dart';

/// 성취도 평가 상세 — 문제 다운로드 + 답안 제출
class AssessmentDetailScreen extends ConsumerStatefulWidget {
  const AssessmentDetailScreen({
    super.key,
    required this.assessmentId,
  });

  final String assessmentId;

  @override
  ConsumerState<AssessmentDetailScreen> createState() =>
      _AssessmentDetailScreenState();
}

class _AssessmentDetailScreenState
    extends ConsumerState<AssessmentDetailScreen> {
  bool _isUploading = false;
  double _uploadProgress = 0;

  AssessmentModel? _findAssessment(List<AssessmentModel> list) {
    for (final a in list) {
      if (a.id == widget.assessmentId) return a;
    }
    return null;
  }

  Future<void> _submitAnswer(AssessmentModel assessment) async {
    final user = ref.read(currentUserSyncProvider);
    final cohortId = ref.read(effectiveCohortIdProvider);
    if (user == null || cohortId == null) return;

    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return;

    final file = picked.first;
    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      setState(() => _uploadProgress = 0.5);
      final url = await uploadAssessmentAnswerFile(
        ref: ref,
        cohortId: cohortId,
        assessmentId: assessment.id,
        userId: user.uid,
        file: file,
      );

      await ref.read(lmsRepositoryProvider).submitAssessmentAnswer(
            cohortId: cohortId,
            assessmentId: assessment.id,
            userId: user.uid,
            userDisplayName: user.displayName,
            answerFileUrl: url,
            answerFileName: file.name,
          );

      ref.invalidate(myAssessmentSubmissionsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('답안 제출이 완료되었습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('제출 실패: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final assessments = ref.watch(publishedAssessmentsProvider);
    final submissions = ref.watch(myAssessmentSubmissionsProvider);

    return assessments.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(message: e.toString()),
      ),
      data: (list) {
        final assessment = _findAssessment(list);
        if (assessment == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('평가를 찾을 수 없습니다')),
          );
        }

        final submission = submissions.maybeWhen(
          data: (subs) => subs
              .where((s) => s.assessmentId == widget.assessmentId)
              .firstOrNull,
          orElse: () => null,
        );
        final completed = submission?.completed ?? false;

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go(RoutePaths.studyRoom),
            ),
            title: const Text('성취도 평가'),
          ),
          body: SingleChildScrollView(
            child: studyRoomContentWrapper(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: assessment.tags
                        .map(
                          (t) => Chip(
                            label: Text(t, style: const TextStyle(fontSize: 12)),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: AppColors.surfaceVariant,
                            side: BorderSide.none,
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    assessment.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E3A5F),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    assessment.periodLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _InfoRow(
                    icon: Icons.description_outlined,
                    label: '${assessment.questionCount}문제',
                  ),
                  _InfoRow(
                    icon: Icons.emoji_events_outlined,
                    label: '${assessment.maxScore}점',
                  ),
                  _InfoRow(
                    icon: Icons.flag_outlined,
                    label: assessment.statusLabel,
                  ),
                  const SizedBox(height: 24),
                  if (assessment.problemFileUrl != null &&
                      assessment.problemFileUrl!.isNotEmpty) ...[
                    OutlinedButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(assessment.problemFileUrl!),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.download_outlined),
                      label: Text(
                        assessment.problemFileName ?? '문제 파일 다운로드',
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (completed) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '제출 완료',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.success,
                                  ),
                                ),
                                if (submission?.answerFileName != null)
                                  Text(
                                    submission!.answerFileName!,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                if (submission?.submittedAt != null)
                                  Text(
                                    AppDateUtils.formatDisplay(
                                      submission!.submittedAt!,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (assessment.isActive) ...[
                    const Text(
                      '답안 파일 제출',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_isUploading) ...[
                      LinearProgressIndicator(value: _uploadProgress),
                      const SizedBox(height: 8),
                      Text(
                        '${(_uploadProgress * 100).toInt()}% 업로드 중...',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ] else
                      ElevatedButton.icon(
                        onPressed: () => _submitAnswer(assessment),
                        icon: const Icon(Icons.upload_file),
                        label: const Text('파일 제출'),
                      ),
                  ] else if (assessment.isUpcoming)
                    const _NoticeBox(
                      icon: Icons.schedule,
                      message: '아직 평가 기간이 시작되지 않았습니다.',
                    )
                  else
                    const _NoticeBox(
                      icon: Icons.lock_outline,
                      message: '평가 기간이 종료되어 제출할 수 없습니다.',
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeBox extends StatelessWidget {
  const _NoticeBox({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
