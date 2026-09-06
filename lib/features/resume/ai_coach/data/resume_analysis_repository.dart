import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/models/resume_content.dart';
import '../../../../shared/providers/firebase_providers.dart';
import '../models/resume_readiness.dart';
import 'cover_letter_rag_client.dart';
import 'resume_analyzer.dart';
import 'resume_text_builder.dart';

/// 이력서 분석: cover_letter_rag 서버가 설정돼 있으면 서버 근거 기반 분석을,
/// 아니면(또는 서버 호출에 실패하면) 앱 안의 규칙 기반 분석을 돌려준다.
///
/// 서버는 별도 "이력서 분석" 엔드포인트가 없고 공고 검색과 자소서 첨삭만
/// 제공한다. 그래서 두 호출을 이어 붙인다.
///
/// 1. `/api/v1/jobs/search` — 이력서와 가까운 공고 Top-k를 찾는다.
/// 2. `/api/v1/reviews` — 찾은 공고들을 하나의 공고 원문으로 묶어 이력서와
///    비교시킨다. 응답의 요구사항 비교(충족/미충족/확인 필요)와 초안 보완점을
///    강점·보완점·확인 질문으로 옮긴다.
class ResumeAnalysisRepository {
  ResumeAnalysisRepository({
    required this._ragClient,
    required this._auth,
    this.topK = 4,
  });

  final CoverLetterRagClient? _ragClient;
  final FirebaseAuth _auth;
  final int topK;

  /// 특정 공고가 아니라 이력서 전체를 점검하게 하는 고정 문항.
  static const analysisQuestion =
      '지원 직무와 관련해 이력서에 드러난 강점과 보완할 점을 근거와 함께 점검해 주세요.';

  bool get usesRagServer => _ragClient != null;

  Future<ResumeAnalysis> analyze(ResumeContent content) async {
    final readiness = ResumeReadiness.of(content);
    if (!readiness.canAnalyzeResume) {
      throw StateError(readiness.blockedReason(AiCoachFeature.resumeAnalysis)!);
    }

    final local = analyzeResume(content);
    final client = _ragClient;
    if (client == null) return local;

    try {
      return await _analyzeWithRag(client, content, local);
    } on CoverLetterRagException catch (error) {
      return local.withFallbackReason(error.message);
    } on Exception catch (error) {
      return local.withFallbackReason('RAG 서버 분석에 실패했습니다: $error');
    }
  }

  Future<ResumeAnalysis> _analyzeWithRag(
    CoverLetterRagClient client,
    ResumeContent content,
    ResumeAnalysis local,
  ) async {
    final resumeText = buildResumeText(content);
    final idToken = await _idToken();

    final jobs = await client.searchJobs(
      resumeText,
      topK: topK,
      idToken: idToken,
    );
    if (jobs.isEmpty) {
      throw const CoverLetterRagException(
        '비교할 공고를 찾지 못했습니다. 서버 인덱스를 확인해주세요.',
      );
    }

    final review = await client.review(
      resumeText: resumeText,
      jobPostingText: jobs.map((job) => job.toPostingText()).join('\n\n'),
      coverLetterQuestion: analysisQuestion,
      draftText: buildAnalysisDraftText(content),
      topK: topK,
      idToken: idToken,
    );
    return ResumeAnalysis.fromRag(local: local, jobs: jobs, review: review);
  }

  Future<String?> _idToken() async {
    try {
      return await _auth.currentUser?.getIdToken();
    } catch (_) {
      // 토큰을 못 얻어도 분석은 진행한다. 서버 검증이 켜지면 401로 돌아온다.
      return null;
    }
  }
}

final coverLetterRagClientProvider = Provider<CoverLetterRagClient?>((ref) {
  if (!CoverLetterRagConfig.isConfigured) return null;
  return CoverLetterRagClient(baseUrl: CoverLetterRagConfig.baseUrl);
});

final resumeAnalysisRepositoryProvider = Provider<ResumeAnalysisRepository>((
  ref,
) {
  return ResumeAnalysisRepository(
    ragClient: ref.watch(coverLetterRagClientProvider),
    auth: ref.watch(firebaseAuthProvider),
  );
});
