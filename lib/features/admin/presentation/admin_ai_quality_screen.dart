import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/constants/ai_ops_types.dart';
import '../../../shared/models/ai_ops_models.dart';
import '../../../shared/providers/ai_ops_providers.dart';
import '../../../shared/providers/lms_providers.dart';

/// 관리자 — LLM 기능 운영 (로그·지연·피드백·버전)
class AdminAiQualityScreen extends ConsumerWidget {
  const AdminAiQualityScreen({super.key});

  static const _filters = <(String?, String)>[
    (null, '전체'),
    ('assessment', '문제생성'),
    (AiOpsTypes.jobChat, '공고챗봇'),
    (AiOpsTypes.jobRecommend, '추천'),
    (AiOpsTypes.resumeReview, '첨삭'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cohortName = ref.watch(effectiveCohortNameProvider);
    final logsAsync = ref.watch(aiGenerationLogsProvider);
    final stats = ref.watch(aiQualityStatsProvider);
    final typeFilter = ref.watch(aiQualityTypeFilterProvider);
    final feedback =
        ref.watch(aiQuestionFeedbackProvider).asData?.value ?? const [];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(aiGenerationLogsProvider);
          ref.invalidate(aiQuestionFeedbackProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              'AI 품질 · ${cohortName ?? '기수 미선택'}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'LLM 기능 운영 — 생성 로그 · 지연 · 피드백 · 프롬프트 버전 비교\n'
              '문제생성 · 공고챗봇 · 맞춤 추천 · 이력서 첨삭',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (value, label) in _filters)
                  ChoiceChip(
                    label: Text(label),
                    selected: typeFilter == value,
                    onSelected: (_) {
                      ref
                          .read(aiQualityTypeFilterProvider.notifier)
                          .select(value);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _StatChip(label: '요청수', value: '${stats.totalRuns}'),
                _StatChip(
                  label: '성공률',
                  value: '${(stats.successRate * 100).toStringAsFixed(1)}%',
                ),
                _StatChip(
                  label: '평균 지연',
                  value: '${stats.avgLatencyMs.toStringAsFixed(0)}ms',
                ),
                _StatChip(
                  label: 'p95 지연',
                  value: '${stats.p95LatencyMs.toStringAsFixed(0)}ms',
                ),
                if (typeFilter == null || typeFilter == 'assessment') ...[
                  _StatChip(
                    label: '생성 문항',
                    value: '${stats.totalGenerated}',
                  ),
                  _StatChip(
                    label: '채택률',
                    value: '${(stats.adoptionRate * 100).toStringAsFixed(1)}%',
                  ),
                  _StatChip(
                    label: '수정률',
                    value: '${(stats.editRate * 100).toStringAsFixed(1)}%',
                  ),
                ],
                _StatChip(
                  label: '유용률',
                  value: '${(stats.usefulnessRate * 100).toStringAsFixed(1)}%',
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '프롬프트 버전별',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 8),
            if (stats.byPromptVersion.isEmpty)
              Text(
                '아직 버전별 데이터가 없습니다.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              )
            else
              ...stats.byPromptVersion.entries.map((e) {
                final g = e.value.generated;
                final a = e.value.adopted + e.value.edited;
                final useful = e.value.useful;
                final rate = g <= 0 ? 0.0 : a / g;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      e.key,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '생성 $g · 채택+수정 $a'
                      '${g > 0 ? ' · 채택률 ${(rate * 100).toStringAsFixed(1)}%' : ''}'
                      ' · 유용 피드백 $useful',
                    ),
                  ),
                );
              }),
            const SizedBox(height: 16),
            const Text(
              '최근 생성 로그',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 8),
            logsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => ErrorView(message: '$e'),
              data: (allLogs) {
                final logs = filterLogsByType(allLogs, typeFilter);
                if (logs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      '아직 AI 생성 로그가 없습니다.\n'
                      '문제 생성 AI · 취업 코치(챗봇/추천/첨삭)를 실행해 보세요.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  );
                }
                return Column(
                  children: logs.map((log) {
                    final fb = feedback.where((f) => f.logId == log.id);
                    final adopted =
                        fb.where((f) => f.outcome == 'adopted').length;
                    final edited =
                        fb.where((f) => f.outcome == 'edited').length;
                    final discarded =
                        fb.where((f) => f.outcome == 'discarded').length;
                    final useful = fb
                        .where(
                          (f) => AiOpsOutcomes.isUseful(log.type, f.outcome),
                        )
                        .length;
                    return _LogCard(
                      log: log,
                      adopted: adopted,
                      edited: edited,
                      discarded: discarded,
                      useful: useful,
                      feedbackCount: fb.length,
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({
    required this.log,
    required this.adopted,
    required this.edited,
    required this.discarded,
    required this.useful,
    required this.feedbackCount,
  });

  final AiGenerationLogModel log;
  final int adopted;
  final int edited;
  final int discarded;
  final int useful;
  final int feedbackCount;

  @override
  Widget build(BuildContext context) {
    final when = log.createdAt?.toString().substring(0, 16) ?? '-';
    final ok = log.status == 'success';
    final metaBits = <String>[
      if (log.mode != null && log.mode!.isNotEmpty) 'mode=${log.mode}',
      if (log.jobCount != null) 'jobs=${log.jobCount}',
      if (log.appliedCount != null) 'applied=${log.appliedCount}',
      if (log.topK != null) 'topK=${log.topK}',
      if (log.reviewMode != null && log.reviewMode!.isNotEmpty)
        'review=${log.reviewMode}',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    AiOpsTypes.label(log.type),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: ok
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    ok ? 'success' : 'error',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: ok
                          ? const Color(0xFF166534)
                          : const Color(0xFF991B1B),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    when,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  '${log.latencyMs}ms',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              log.isAssessment
                  ? '${log.promptVersion} · ${log.model} · '
                        '일수 ${log.dayFrom ?? '-'}~${log.dayTo ?? '-'} · '
                        '생성 ${log.generatedCount}'
                  : '${log.promptVersion} · ${log.model}'
                        '${metaBits.isEmpty ? '' : ' · ${metaBits.join(' · ')}'}',
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 4),
            Text(
              log.isAssessment
                  ? '피드백 채택 $adopted · 수정 $edited · 폐기 $discarded'
                  : '피드백 $feedbackCount · 유용 $useful'
                        '${adopted + edited + discarded > 0 ? ' · 채택 $adopted · 수정 $edited · 폐기 $discarded' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            if (log.errorMessage != null && log.errorMessage!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                log.errorMessage!,
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
