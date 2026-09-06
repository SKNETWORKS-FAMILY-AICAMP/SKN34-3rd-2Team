import 'package:flutter_test/flutter_test.dart';

import 'package:playdata_lms/features/resume/ai_coach/data/local_job_matcher.dart';
import 'package:playdata_lms/features/resume/ai_coach/models/ai_job_coach_result.dart';
import 'package:playdata_lms/features/resume/ai_coach/models/collected_job.dart';
import 'package:playdata_lms/shared/models/resume_content.dart';

CollectedJob _job({required bool bodyIsImage}) => CollectedJob(
  jobId: 'IMG-1',
  company: '테스트',
  title: '백엔드 개발자',
  description: '',
  requiredSkills: const [],
  preferredSkills: const [],
  techStack: const ['Python'],
  bodyIsImage: bodyIsImage,
  careerType: 'ANY',
  education: '학력무관',
  region: '전국',
  employmentType: '정규직',
  deadline: null,
  source: 'SARAMIN_POC',
  sourceUrl: 'https://example.test/1',
);

void main() {
  const content = ResumeContent(
    education: [ResumeEducationItem(id: 'e', school: '대학')],
    techStack: [ResumeTechStackItem(id: 't', name: 'Python')],
  );

  test('이미지 공고는 탈락이 아니라 확인 필요로 남고 카드가 알 수 있다', () {
    final resume = LocalResumeProfile.fromContent(content);
    final filter = hardFilter(_job(bodyIsImage: true), resume);
    expect(filter.status, isNot('FAIL'));
    expect(filter.unknown, contains('공고 상세가 이미지라 요구사항 미확인'));

    final ranked = rankJobs([_job(bodyIsImage: true)], resume);
    final item = JobRecommendation.fromMap(ranked.single);
    expect(item.bodyIsImage, isTrue);
    expect(item.unknownConditions, contains('공고 상세가 이미지라 요구사항 미확인'));
  });

  test('텍스트 공고에는 이미지 안내가 붙지 않는다', () {
    final resume = LocalResumeProfile.fromContent(content);
    final item = JobRecommendation.fromMap(rankJobs([_job(bodyIsImage: false)], resume).single);
    expect(item.bodyIsImage, isFalse);
    expect(item.unknownConditions, isNot(contains('공고 상세가 이미지라 요구사항 미확인')));
  });
}
