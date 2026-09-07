import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_ops_models.dart';
import '../providers/cohort_providers.dart';
import '../providers/firebase_providers.dart';

class AiQualityStats {
  const AiQualityStats({
    required this.totalRuns,
    required this.totalGenerated,
    required this.adopted,
    required this.edited,
    required this.discarded,
    required this.avgLatencyMs,
    required this.byPromptVersion,
  });

  final int totalRuns;
  final int totalGenerated;
  final int adopted;
  final int edited;
  final int discarded;
  final double avgLatencyMs;
  final Map<String, ({int generated, int adopted, int edited})> byPromptVersion;

  double get adoptionRate {
    if (totalGenerated <= 0) return 0;
    return (adopted + edited) / totalGenerated;
  }

  double get editRate {
    final denom = adopted + edited;
    if (denom <= 0) return 0;
    return edited / denom;
  }
}

final aiGenerationLogsProvider =
    StreamProvider.autoDispose<List<AiGenerationLogModel>>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value(const []);
  return ref
      .watch(firestoreProvider)
      .collection('aiGenerationLogs')
      .where('cohortId', isEqualTo: cohortId)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map(
        (s) => s.docs.map(AiGenerationLogModel.fromFirestore).toList(),
      );
});

final aiQuestionFeedbackProvider =
    StreamProvider.autoDispose<List<AiQuestionFeedbackModel>>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value(const []);
  return ref
      .watch(firestoreProvider)
      .collection('aiQuestionFeedback')
      .where('cohortId', isEqualTo: cohortId)
      .limit(500)
      .snapshots()
      .map(
        (s) => s.docs.map(AiQuestionFeedbackModel.fromFirestore).toList(),
      );
});

final aiQualityStatsProvider = Provider.autoDispose<AiQualityStats>((ref) {
  final logs = ref.watch(aiGenerationLogsProvider).asData?.value ?? const [];
  final feedback =
      ref.watch(aiQuestionFeedbackProvider).asData?.value ?? const [];

  var totalGenerated = 0;
  var latencySum = 0;
  var latencyN = 0;
  final byVersion = <String, ({int generated, int adopted, int edited})>{};

  for (final log in logs) {
    if (log.status != 'success') continue;
    totalGenerated += log.generatedCount;
    if (log.latencyMs > 0) {
      latencySum += log.latencyMs;
      latencyN++;
    }
    final key = log.promptVersion.isEmpty ? '(unknown)' : log.promptVersion;
    final cur = byVersion[key] ?? (generated: 0, adopted: 0, edited: 0);
    byVersion[key] = (
      generated: cur.generated + log.generatedCount,
      adopted: cur.adopted,
      edited: cur.edited,
    );
  }

  var adopted = 0;
  var edited = 0;
  var discarded = 0;
  for (final f in feedback) {
    switch (f.outcome) {
      case 'adopted':
        adopted++;
        break;
      case 'edited':
        edited++;
        break;
      case 'discarded':
        discarded++;
        break;
    }
    final key =
        (f.promptVersion == null || f.promptVersion!.isEmpty)
            ? '(unknown)'
            : f.promptVersion!;
    final cur = byVersion[key] ?? (generated: 0, adopted: 0, edited: 0);
    byVersion[key] = (
      generated: cur.generated,
      adopted: cur.adopted + (f.outcome == 'adopted' ? 1 : 0),
      edited: cur.edited + (f.outcome == 'edited' ? 1 : 0),
    );
  }

  return AiQualityStats(
    totalRuns: logs.length,
    totalGenerated: totalGenerated,
    adopted: adopted,
    edited: edited,
    discarded: discarded,
    avgLatencyMs: latencyN == 0 ? 0 : latencySum / latencyN,
    byPromptVersion: byVersion,
  );
});
