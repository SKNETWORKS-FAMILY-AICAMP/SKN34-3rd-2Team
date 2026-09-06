import '../models/ai_job_coach_result.dart';

/// RRF(Reciprocal Rank Fusion)의 완충 상수. 값이 클수록 상위 몇 개의 순위 차이가
/// 덜 극단적으로 반영된다. 60은 원 논문과 검색 엔진들이 쓰는 기본값이다.
const rrfK = 60;

/// 키워드 추천 순위와 cover_letter_rag 임베딩 검색 순위를 RRF로 합쳐 재정렬한다.
///
/// 서버 검색 API는 유사도 점수 없이 순위만 주므로 순위 기반 병합을 쓴다.
/// 각 공고의 합산 점수는 `1/(k+키워드순위) + 1/(k+임베딩순위)`이고, 임베딩 검색에
/// 안 잡힌 공고는 두 번째 항이 0이다. 점수가 같으면 키워드 순위를 유지한다.
///
/// 키워드 점수(`score`)와 등급은 그대로 두고, 임베딩 순위는 `embeddingRank`와
/// 근거 문구("임베딩 유사도 n위")로 남겨 왜 올라왔는지 보이게 한다.
List<JobRecommendation> fuseWithEmbeddingRanks(
  List<JobRecommendation> keywordRanked,
  Map<String, int> embeddingRanks, {
  int k = rrfK,
}) {
  final fused = <(int, JobRecommendation)>[];
  for (var index = 0; index < keywordRanked.length; index++) {
    final item = keywordRanked[index];
    final keywordRank = index + 1;
    final embeddingRank = embeddingRanks[item.jobId];
    var score = 1 / (k + keywordRank);
    if (embeddingRank != null) score += 1 / (k + embeddingRank);
    fused.add((
      index,
      item.copyWith(
        fusedScore: score,
        embeddingRank: embeddingRank,
        evidence: embeddingRank == null
            ? item.evidence
            : [...item.evidence, '임베딩 유사도 $embeddingRank위'],
      ),
    ));
  }
  fused.sort((a, b) {
    final byScore = b.$2.fusedScore!.compareTo(a.$2.fusedScore!);
    return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
  });
  return [for (final entry in fused) entry.$2];
}
