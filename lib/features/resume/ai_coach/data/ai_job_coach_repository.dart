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
import 'job_recommend_api_client.dart';
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
/// 1. 추천 서버(`job_matching_bot` API): 이력서 평문과 희망 조건을 보내면 벡터 검색 →
///    하드 필터 → LLM 재정렬 → 근거 검증을 거친 공고를 근거 인용과 함께 돌려준다.
///    서버가 설정돼 있으면 이 경로가 기본이다.
/// 2. 서버에 닿지 못하거나 실패하면 예전 경로로 대신한다. 키워드 추천(하드 필터 뒤
///    직무·기술·프로젝트 점수)에, cover_letter_rag 서버가 있으면 임베딩 재정렬을 더한다.
///    화면에는 왜 대신했는지 남긴다.
class AiJobCoachRepository {
  AiJobCoachRepository(
    this._functions, {
    this._ragClient,
    this._auth,
    this._apiClient,
  });

  final FirebaseFunctions? _functions;
  final CoverLetterRagClient? _ragClient;
  final FirebaseAuth? _auth;
  final JobRecommendApiClient? _apiClient;

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

    final api = _apiClient;
    if (api != null) {
      try {
        return await _runApi(api, draftContent, preferences);
      } on JobRecommendApiException catch (error) {
        // 서버 없이도 앱이 동작해야 한다. 규칙 기반으로 대신하고 이유를 남긴다.
        final fallback = await _runKeyword(
          cohortId: cohortId,
          resumeId: resumeId,
          draftContent: draftContent,
          confirmedMissingSkills: confirmedMissingSkills,
          preferences: preferences,
        );
        return fallback.copyWith(
          notice: '${fallback.notice} · 추천 서버를 쓰지 못해 앱 안의 규칙 기반 추천을 '
              '표시합니다: ${error.message}',
        );
      }
    }
    return _runKeyword(
      cohortId: cohortId,
      resumeId: resumeId,
      draftContent: draftContent,
      confirmedMissingSkills: confirmedMissingSkills,
      preferences: preferences,
    );
  }

  Future<AiJobCoachResult> _runApi(
    JobRecommendApiClient api,
    ResumeContent draftContent,
    JobPreferences preferences,
  ) async {
    final response = await api.recommend(
      JobRecommendRequest.fromResume(draftContent, preferences: preferences),
    );
    return AiJobCoachResult(
      testMode: false,
      notice: response.reranked
          ? response.notice
          : '${response.notice} · LLM 재정렬 없이 검색 순서대로 표시했습니다.',
      recommendations: response.recommendations,
      selectedJob: null,
      skillJudgements: const [],
      resumeFeedback: const [],
      learningRecommendations: const [],
      analysisId: '',
      fromServer: true,
      searchQuery: response.searchQuery,
      profileSummary: response.profileSummary,
      warnings: response.warnings,
    );
  }

  Future<AiJobCoachResult> _runKeyword({
    required String cohortId,
    required String resumeId,
    required ResumeContent draftContent,
    required Set<String> confirmedMissingSkills,
    required JobPreferences preferences,
  }) async {
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
    final functions = _functions;
    if (functions == null) {
      throw StateError('Firebase Functions가 설정되지 않아 서버 추천을 부를 수 없습니다.');
    }
    final callable = functions.httpsCallable(
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

/// 추천 서버 클라이언트. 주소가 비어 있으면 null이고 앱은 규칙 기반 추천만 쓴다.
final jobRecommendApiClientProvider = Provider<JobRecommendApiClient?>((ref) {
  return JobRecommendApiConfig.isConfigured ? JobRecommendApiClient() : null;
});

final aiJobCoachRepositoryProvider = Provider<AiJobCoachRepository>((ref) {
  return AiJobCoachRepository(
    FirebaseFunctions.instanceFor(region: 'asia-northeast3'),
    ragClient: ref.watch(coverLetterRagClientProvider),
    auth: ref.watch(firebaseAuthProvider),
    apiClient: ref.watch(jobRecommendApiClientProvider),
  );
});
