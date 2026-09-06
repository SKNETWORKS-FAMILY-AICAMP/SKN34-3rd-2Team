import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/models/job_preferences.dart';
import '../../../../shared/models/resume_content.dart';
import '../../../../shared/providers/firebase_providers.dart';
import '../models/ai_job_coach_result.dart';
import '../models/resume_readiness.dart';
import 'cover_letter_rag_client.dart';
import 'embedding_rerank.dart';
import 'generated/collected_jobs.g.dart';
import 'local_job_matcher.dart';
import 'resume_analysis_repository.dart';
import 'resume_text_builder.dart';

abstract final class AiJobCoachConfig {
  static const useLocalFixture = bool.fromEnvironment(
    'AI_COACH_LOCAL_FIXTURE',
    defaultValue: true,
  );

  /// 임베딩 검색에서 받아 올 공고 수. 서버 상한이 10이다.
  static const embeddingTopK = 10;
}

/// 맞춤 공고 추천.
///
/// 1. 키워드 추천: 하드 필터(학력·경력·희망 지역·고용형태) 뒤 직무·기술·프로젝트
///    점수로 정렬한다. 로컬 fixture 모드와 Functions 모드가 같은 규칙이다.
/// 2. 임베딩 재정렬: cover_letter_rag 서버가 설정돼 있으면 자기소개서와 프로젝트
///    경험 문장으로 공고를 검색해, 그 순위를 키워드 순위와 RRF로 합친다.
///    서버가 없거나 실패하면 키워드 순위를 그대로 쓰고 안내 문구만 남긴다.
class AiJobCoachRepository {
  AiJobCoachRepository(
    this._functions, {
    this._ragClient,
    this._auth,
  });

  final FirebaseFunctions _functions;
  final CoverLetterRagClient? _ragClient;
  final FirebaseAuth? _auth;

  Future<AiJobCoachResult> analyzeAndMatch({
    required String cohortId,
    required String resumeId,
    required ResumeContent draftContent,
    required Set<String> confirmedMissingSkills,
    JobPreferences preferences = const JobPreferences(),
  }) async {
    // 로컬 fixture 모드와 배포 모드가 같은 조건으로 막히도록 여기서도 확인한다.
    // 서버 쪽 같은 규칙: functions/src/jobCoach.ts 의 missingRequiredSections
    final readiness = ResumeReadiness.of(draftContent);
    if (!readiness.canRecommendJobs) {
      throw StateError(
        readiness.blockedReason(AiCoachFeature.jobRecommendation)!,
      );
    }

    final keywordResult = AiJobCoachConfig.useLocalFixture
        ? _runLocal(draftContent, confirmedMissingSkills, preferences)
        : await _runFunctions(
            cohortId: cohortId,
            resumeId: resumeId,
            draftContent: draftContent,
            confirmedMissingSkills: confirmedMissingSkills,
            preferences: preferences,
          );
    return rerankWithEmbedding(keywordResult, draftContent);
  }

  AiJobCoachResult _runLocal(
    ResumeContent draftContent,
    Set<String> confirmedMissingSkills,
    JobPreferences preferences,
  ) {
    // 고정 응답이 아니라 수집 공고와 이력서로 실제 계산한다. 서버와 같은 규칙.
    return AiJobCoachResult.fromMap(
      runLocalJobCoach(
        jobs: collectedJobs,
        content: draftContent,
        confirmedMissingSkills: confirmedMissingSkills,
        targetRoles: preferences.targetRoles,
        preferredRegions: preferences.regions,
        preferredEmploymentTypes: preferences.employmentTypes,
      ),
    );
  }

  Future<AiJobCoachResult> _runFunctions({
    required String cohortId,
    required String resumeId,
    required ResumeContent draftContent,
    required Set<String> confirmedMissingSkills,
    required JobPreferences preferences,
  }) async {
    final callable = _functions.httpsCallable(
      'analyzeResumeAndMatch',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
    );
    final response = await callable.call<Map<String, dynamic>>({
      'cohortId': cohortId,
      'resumeId': resumeId,
      'draftContent': draftContent.toMap(),
      'targetRoles': preferences.targetRoles,
      'preferredRegions': preferences.regions,
      'preferredEmploymentTypes': preferences.employmentTypes,
      'confirmedMissingSkills': confirmedMissingSkills.toList(),
    });
    return AiJobCoachResult.fromMap(response.data);
  }

  /// 자기소개서·프로젝트 경험으로 임베딩 검색을 돌려 키워드 순위와 합친다.
  ///
  /// 서버가 설정되지 않았으면 결과를 그대로 돌려준다. 검색 결과의 `job_id`가
  /// 수집 공고 id와 같아야 조인되므로, 서버 인덱스에 수집 공고가 올라가 있어야
  /// 실제로 순위가 바뀐다(SETUP.md "수집 공고를 임베딩 인덱스에 올리기").
  Future<AiJobCoachResult> rerankWithEmbedding(
    AiJobCoachResult result,
    ResumeContent content,
  ) async {
    final client = _ragClient;
    if (client == null || result.recommendations.length < 2) return result;

    final query = buildEmbeddingQueryText(content);
    if (query.length < CoverLetterRagClient.minResumeLength) {
      return result.copyWith(
        notice: '${result.notice} · 자기소개서·프로젝트 내용이 짧아 임베딩 재정렬을 건너뛰었습니다.',
      );
    }

    try {
      String? idToken;
      try {
        idToken = await _auth?.currentUser?.getIdToken();
      } catch (_) {
        idToken = null;
      }
      final hits = await client.searchJobs(
        query,
        topK: AiJobCoachConfig.embeddingTopK,
        idToken: idToken,
      );
      final ranks = {for (final hit in hits) hit.jobId: hit.rank};
      final fused = fuseWithEmbeddingRanks(result.recommendations, ranks);
      final matched = fused.where((item) => item.embeddingRank != null).length;
      return result.copyWith(
        recommendations: fused,
        notice: '${result.notice} · 자기소개서·프로젝트 임베딩 유사도로 재정렬했습니다 '
            '(검색 ${hits.length}건 중 $matched건 일치).',
      );
    } on Exception catch (error) {
      return result.copyWith(
        notice: '${result.notice} · 임베딩 재정렬에 실패해 키워드 순위만 표시합니다: $error',
      );
    }
  }
}

final aiJobCoachRepositoryProvider = Provider<AiJobCoachRepository>((ref) {
  return AiJobCoachRepository(
    FirebaseFunctions.instanceFor(region: 'asia-northeast3'),
    ragClient: ref.watch(coverLetterRagClientProvider),
    auth: ref.watch(firebaseAuthProvider),
  );
});
