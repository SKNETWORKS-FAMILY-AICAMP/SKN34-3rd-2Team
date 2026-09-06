import 'package:flutter_test/flutter_test.dart';

import 'package:playdata_lms/features/resume/ai_coach/data/embedding_rerank.dart';
import 'package:playdata_lms/features/resume/ai_coach/data/resume_text_builder.dart';
import 'package:playdata_lms/features/resume/ai_coach/models/ai_job_coach_result.dart';
import 'package:playdata_lms/shared/models/resume_content.dart';

JobRecommendation _rec(String id, double score) => JobRecommendation(
  jobId: id,
  source: 'TEST',
  sourceUrl: '',
  company: '회사 $id',
  title: '직무 $id',
  score: score,
  grade: '보통',
  hardFilterStatus: 'PASS',
  unknownConditions: const [],
  evidence: const ['python'],
);

void main() {
  group('fuseWithEmbeddingRanks', () {
    final keyword = [_rec('A', 0.9), _rec('B', 0.8), _rec('C', 0.7), _rec('D', 0.6)];

    test('임베딩 상위 공고가 키워드 하위에 있으면 위로 올라온다', () {
      final fused = fuseWithEmbeddingRanks(keyword, {'D': 1, 'A': 2});
      expect(fused.map((e) => e.jobId).take(2), ['A', 'D']);
      expect(fused.first.embeddingRank, 2);
      expect(fused[1].evidence, contains('임베딩 유사도 1위'));
      // 키워드 점수와 등급은 손대지 않는다.
      expect(fused[1].score, 0.6);
      expect(fused[1].grade, '보통');
    });

    test('임베딩 검색에 아무것도 안 잡히면 키워드 순위를 그대로 유지한다', () {
      final fused = fuseWithEmbeddingRanks(keyword, const {});
      expect(fused.map((e) => e.jobId), ['A', 'B', 'C', 'D']);
      expect(fused.every((e) => e.embeddingRank == null), isTrue);
      expect(fused.every((e) => e.fusedScore != null), isTrue);
    });

    test('점수가 같으면 키워드 순위가 앞선다', () {
      // B와 C가 임베딩에서 서로 순위를 바꿔 잡히면 합산이 같아진다.
      final fused = fuseWithEmbeddingRanks(keyword, {'B': 3, 'C': 2});
      expect(fused.map((e) => e.jobId).toList().indexOf('B'), lessThan(
        fused.map((e) => e.jobId).toList().indexOf('C'),
      ));
    });
  });

  group('buildEmbeddingQueryText', () {
    test('프로젝트 경험과 자기소개서만 담고 기술스택 목록은 뺀다', () {
      const content = ResumeContent(
        techStack: [ResumeTechStackItem(id: 't', name: 'Kubernetes')],
        projects: [
          ResumeProjectItem(id: 'p', name: '추천 API', role: '백엔드', description: 'FastAPI로 만들었다'),
        ],
        selfIntroduction: ResumeSelfIntroduction(
          motivation: ResumeIntroSection(body: '교육 서비스에 기여하고 싶다'),
        ),
      );
      final text = buildEmbeddingQueryText(content);
      expect(text, contains('[프로젝트 경험]\n- 추천 API'));
      expect(text, contains('FastAPI로 만들었다'));
      expect(text, contains('[자기소개서]'));
      expect(text, isNot(contains('Kubernetes')));
    });

    test('둘 다 비어 있으면 빈 문자열', () {
      expect(buildEmbeddingQueryText(const ResumeContent()), '');
    });
  });
}
