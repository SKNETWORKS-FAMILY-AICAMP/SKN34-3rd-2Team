import 'package:flutter_test/flutter_test.dart';

import 'package:playdata_lms/features/resume/ai_coach/data/generated/collected_jobs.g.dart';
import 'package:playdata_lms/features/resume/ai_coach/data/local_job_matcher.dart';
import 'package:playdata_lms/features/resume/ai_coach/models/ai_job_coach_result.dart';
import 'package:playdata_lms/shared/models/resume_content.dart';

void main() {
  const content = ResumeContent(
    basicInfo: ResumeBasicInfo(name: '홍길동', email: 'a@b.c'),
    coreCompetencies: ResumeCoreCompetencies(text: '백엔드'),
    education: [ResumeEducationItem(id: 'e', school: '대학')],
    techStack: [
      ResumeTechStackItem(id: 't1', name: 'Python'),
      ResumeTechStackItem(id: 't2', name: 'Java'),
    ],
    projects: [
      ResumeProjectItem(id: 'p', name: 'API', techStack: 'Python, FastAPI'),
    ],
  );

  test('추천 결과에 점수 구성·통과 조건·근거 없는 요구 기술이 남는다', () {
    final result = AiJobCoachResult.fromMap(
      runLocalJobCoach(jobs: collectedJobs, content: content, targetRoles: ['백엔드 개발자']),
    );
    expect(result.recommendations, isNotEmpty);

    final withSkills = result.recommendations.firstWhere(
      (item) => item.scoreDetail != null && item.scoreDetail!.skillsTotal > 0,
    );
    final detail = withSkills.scoreDetail!;
    // 기술스택 일치 ∪ 프로젝트 근거 ∪ 근거 없음 = 공고가 언급한 기술 전체.
    // 프로젝트 설명에만 적힌 기술은 프로젝트 근거로 잡히고 근거 없음에서 빠진다.
    final covered = {
      ...withSkills.matchedSkills,
      ...withSkills.projectSkills,
      ...withSkills.unmatchedSkills,
    };
    expect(covered.length, detail.skillsTotal);
    expect(
      withSkills.unmatchedSkills.toSet().intersection({
        ...withSkills.matchedSkills,
        ...withSkills.projectSkills,
      }),
      isEmpty,
    );
    expect(withSkills.passedConditions, isNotEmpty);
    // 점수는 네 항목 기여분의 합과 같다.
    final expected = (detail.role * recommendationWeights.role +
            detail.skills * recommendationWeights.skills +
            detail.project * recommendationWeights.project +
            detail.conditions * recommendationWeights.conditions) *
        100;
    expect(withSkills.score, closeTo(expected, 0.11));
  });

  test('출처별(필수·우대·태그) 기술 근거를 합치면 공고 기술 전체이고 공고 조건이 실린다', () {
    final result = AiJobCoachResult.fromMap(
      runLocalJobCoach(jobs: collectedJobs, content: content),
    );
    for (final item in result.recommendations) {
      final detail = item.scoreDetail!;
      final buckets = [
        item.matchedRequired,
        item.matchedPreferred,
        item.matchedTags,
        item.unmatchedRequired,
        item.unmatchedPreferred,
        item.unmatchedTags,
      ];
      expect(buckets.expand((e) => e).toSet().length, detail.skillsTotal);
      expect(buckets.expand((e) => e).length, detail.skillsTotal, reason: '출처가 겹치면 안 된다');
      expect(item.region, isNotEmpty);
      expect(item.careerLabel, isNotEmpty);
    }
    // MOCK 공고는 필수·우대가 나뉘어 있어 필수 버킷이 채워진다.
    final mock = result.recommendations.firstWhere((e) => e.jobId.startsWith('MOCK'));
    expect(mock.matchedRequired.length + mock.unmatchedRequired.length, greaterThan(0));
  });

  test('scoreDetail이 없는 예전 응답도 읽힌다', () {
    final item = JobRecommendation.fromMap({
      'jobId': 'J',
      'recommendationScore': 50,
      'hardFilter': {'status': 'PASS', 'passed': ['학력 조건 충족'], 'unknown': []},
      'evidence': {'roleTerms': ['backend'], 'requiredSkills': ['Python']},
    });
    expect(item.scoreDetail, isNull);
    expect(item.passedConditions, ['학력 조건 충족']);
    expect(item.evidence, ['backend', 'Python']);
    expect(item.unmatchedSkills, isEmpty);
  });
}
