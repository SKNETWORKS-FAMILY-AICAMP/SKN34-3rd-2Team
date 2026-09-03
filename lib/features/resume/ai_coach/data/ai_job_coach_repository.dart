import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/models/resume_content.dart';
import '../models/ai_job_coach_result.dart';
import '../models/resume_readiness.dart';
import 'generated/collected_jobs.g.dart';
import 'local_job_matcher.dart';

abstract final class AiJobCoachConfig {
  static const useLocalFixture = bool.fromEnvironment(
    'AI_COACH_LOCAL_FIXTURE',
    defaultValue: true,
  );
}

class AiJobCoachRepository {
  AiJobCoachRepository(this._functions);

  final FirebaseFunctions _functions;

  Future<AiJobCoachResult> analyzeAndMatch({
    required String cohortId,
    required String resumeId,
    required ResumeContent draftContent,
    required Set<String> confirmedMissingSkills,
  }) async {
    // 로컬 fixture 모드와 배포 모드가 같은 조건으로 막히도록 여기서도 확인한다.
    // 서버 쪽 같은 규칙: functions/src/jobCoach.ts 의 missingRequiredSections
    final readiness = ResumeReadiness.of(draftContent);
    if (!readiness.canRecommendJobs) {
      throw StateError(
        readiness.blockedReason(AiCoachFeature.jobRecommendation)!,
      );
    }

    if (AiJobCoachConfig.useLocalFixture) {
      // 고정 응답이 아니라 수집 공고와 이력서로 실제 계산한다. 서버와 같은 규칙.
      return AiJobCoachResult.fromMap(
        runLocalJobCoach(
          jobs: collectedJobs,
          content: draftContent,
          confirmedMissingSkills: confirmedMissingSkills,
        ),
      );
    }

    final callable = _functions.httpsCallable(
      'analyzeResumeAndMatch',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
    );
    final response = await callable.call<Map<String, dynamic>>({
      'cohortId': cohortId,
      'resumeId': resumeId,
      'draftContent': draftContent.toMap(),
      'targetRoles': <String>[],
      'preferredRegions': <String>[],
      'preferredEmploymentTypes': <String>[],
      'confirmedMissingSkills': confirmedMissingSkills.toList(),
    });
    return AiJobCoachResult.fromMap(response.data);
  }

}

final aiJobCoachRepositoryProvider = Provider<AiJobCoachRepository>((ref) {
  return AiJobCoachRepository(
    FirebaseFunctions.instanceFor(region: 'asia-northeast3'),
  );
});
