import 'package:flutter_test/flutter_test.dart';

import 'package:playdata_lms/features/resume/ai_coach/data/local_job_matcher.dart';
import 'package:playdata_lms/features/resume/ai_coach/models/ai_job_coach_result.dart';
import 'package:playdata_lms/features/resume/ai_coach/models/collected_job.dart';
import 'package:playdata_lms/shared/models/resume_content.dart';

CollectedJob _job() => const CollectedJob(
  jobId: 'Q-1',
  company: '테스트',
  title: '백엔드 개발자',
  description: '',
  requiredSkills: [],
  preferredSkills: [],
  techStack: ['Python'],
  requiredMajors: ['컴퓨터·소프트웨어'],
  requiredMajorTerms: ['컴퓨터', '소프트웨어', '전산'],
  requiredCertifications: ['정보처리기사'],
  militaryRequired: true,
  careerType: 'ANY',
  education: '학력무관',
  region: '전국',
  employmentType: '정규직',
  deadline: null,
  source: 'SARAMIN_POC',
  sourceUrl: 'https://example.test/1',
);

void main() {
  test('전공·자격증이 맞으면 통과, 병역은 확인 필요', () {
    const content = ResumeContent(
      education: [ResumeEducationItem(id: 'e', school: '한국대', major: '컴퓨터 소프트웨어공학과')],
      certifications: [ResumeCertificationItem(id: 'c', name: '정보처리기사')],
      techStack: [ResumeTechStackItem(id: 't', name: 'Python')],
    );
    final resume = LocalResumeProfile.fromContent(content);
    expect(resume.majors, ['컴퓨터 소프트웨어공학과']);
    expect(resume.certifications, ['정보처리기사']);

    final result = hardFilter(_job(), resume);
    expect(result.failed, isEmpty);
    expect(result.passed, contains('전공 요건 충족: 컴퓨터 소프트웨어공학과'));
    expect(result.passed, contains('자격증 요건 충족: 정보처리기사'));
    expect(result.unknown, contains('병역 조건 확인 필요 (병역필 또는 면제)'));
  });

  test('맞지 않거나 없으면 탈락이 아니라 확인 필요이고 카드에 요건이 실린다', () {
    const content = ResumeContent(
      education: [ResumeEducationItem(id: 'e', school: '한국대', major: '경영학과')],
      techStack: [ResumeTechStackItem(id: 't', name: 'Python')],
    );
    final resume = LocalResumeProfile.fromContent(content);
    final result = hardFilter(_job(), resume);
    expect(result.failed, isEmpty);
    expect(result.unknown.any((t) => t.startsWith('전공 요건 미확인')), isTrue);
    expect(result.unknown, contains('자격증 확인 필요: 정보처리기사'));

    final item = JobRecommendation.fromMap(rankJobs([_job()], resume).single);
    expect(item.requiredMajors, ['컴퓨터·소프트웨어']);
    expect(item.requiredCertifications, ['정보처리기사']);
    expect(item.militaryRequired, isTrue);
  });
}
