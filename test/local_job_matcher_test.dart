import 'package:flutter_test/flutter_test.dart';

import 'package:playdata_lms/features/resume/ai_coach/data/generated/collected_jobs.g.dart';
import 'package:playdata_lms/features/resume/ai_coach/data/generated/resume_mocks.g.dart';
import 'package:playdata_lms/features/resume/ai_coach/data/local_job_matcher.dart';
import 'package:playdata_lms/features/resume/ai_coach/models/ai_job_coach_result.dart';
import 'package:playdata_lms/features/resume/ai_coach/models/collected_job.dart';
import 'package:playdata_lms/shared/models/resume_content.dart';

CollectedJob _job({
  String jobId = 'T-1',
  String careerType = 'ANY',
  int? minCareerYears,
  String education = '학력무관',
  String region = '서울',
  String? employmentType = '정규직',
  List<String> techStack = const [],
  List<String> requiredSkills = const [],
  String title = '개발자',
}) =>
    CollectedJob(
      jobId: jobId,
      company: '테스트',
      title: title,
      description: '',
      requiredSkills: requiredSkills,
      preferredSkills: const [],
      techStack: techStack,
      careerType: careerType,
      minCareerYears: minCareerYears,
      education: education,
      region: region,
      employmentType: employmentType,
      deadline: null,
      source: 'TEST',
      sourceUrl: 'test://1',
    );

ResumeContent _content({
  List<String> techStack = const [],
  bool withEducation = false,
  List<ResumeExperienceItem> experience = const [],
}) =>
    ResumeContent(
      techStack: [for (final name in techStack) ResumeTechStackItem(id: name, name: name)],
      education: withEducation
          ? const [ResumeEducationItem(id: 'e', school: '한국대학교', major: '컴퓨터공학')]
          : const [],
      experience: experience,
    );

void main() {
  group('로컬 Hard Filter', () {
    test('학력을 채우면 "학력 근거 미입력"이 사라진다', () {
      final job = _job(education: '대졸');
      final empty = LocalResumeProfile.fromContent(_content());
      final filled = LocalResumeProfile.fromContent(_content(withEducation: true));
      expect(hardFilter(job, empty).unknown, contains('이력서 학력 근거 미입력'));
      final result = hardFilter(job, filled);
      expect(result.unknown, isNot(contains('이력서 학력 근거 미입력')));
      expect(result.passed, contains('학력 조건 충족'));
    });

    test('경력 공고는 재직기간으로 판정한다', () {
      final job = _job(careerType: 'EXPERIENCED', minCareerYears: 3);
      final threeYears = LocalResumeProfile.fromContent(
        _content(
          experience: const [
            ResumeExperienceItem(id: 'x', company: '회사', startDate: '2023-03', endDate: '2026-03'),
          ],
        ),
      );
      final none = LocalResumeProfile.fromContent(_content());
      expect(hardFilter(job, threeYears).passed, contains('경력 조건 충족'));
      expect(hardFilter(job, none).unknown, contains('이력서 경력 근거 미입력'));
    });

    test('희망 지역·고용형태를 안 넣으면 탈락이 아니라 확인 필요다', () {
      final result = hardFilter(_job(), LocalResumeProfile.fromContent(_content()));
      expect(result.status, 'CHECK_REQUIRED');
      expect(result.unknown, containsAll(['희망 근무지역 미입력', '희망 고용형태 미입력']));
      expect(result.failed, isEmpty);
    });
  });

  group('로컬 Ranking', () {
    test('표기 변형이 기술스택 태그와 맞는다', () {
      final job = _job(techStack: const ['SpringBoot', 'PostgreSQL', 'Kotlin']);
      final resume = LocalResumeProfile.fromContent(
        _content(techStack: const ['Spring Boot', 'Postgres']),
      );
      final [result] = rankJobs([job], resume);
      final evidence = result['evidence'] as Map<String, dynamic>;
      expect(evidence['matchedSkills'], ['PostgreSQL', 'SpringBoot']);
      // 태그 3개는 분모 하한(4)에 걸린다: 2/4
      expect((result['scoreDetail'] as Map)['skills'], closeTo(0.5, 0.001));
    });

    test('필수와 기술스택에 같은 기술이 있어도 한 번만 센다', () {
      final job = _job(requiredSkills: const ['Python'], techStack: const ['Python', 'Go']);
      final (pool, sources) = declaredSkills(job);
      expect(pool.length, 2);
      expect(sources, ['required_skills', 'tech_stack']);
    });

    test('경력 미달 공고는 랭킹에서 빠진다', () {
      final senior = _job(jobId: 'senior', careerType: 'EXPERIENCED', minCareerYears: 5);
      final entry = _job(jobId: 'entry');
      final resume = LocalResumeProfile.fromContent(
        _content(
          experience: const [
            ResumeExperienceItem(id: 'x', company: '회사', startDate: '2024-01', endDate: '2026-01'),
          ],
        ),
      );
      final ids = rankJobs([senior, entry], resume).map((r) => r['jobId']).toList();
      expect(ids, ['entry']);
    });
  });

  group('로컬 코치 전체', () {
    test('결과가 Functions 응답 모델로 읽힌다', () {
      final persona = resumeMockPersonas.firstWhere((p) => p.key == 'backend_entry');
      final content = persona.toContent(name: '테스트', email: 't@example.com');
      final map = runLocalJobCoach(jobs: collectedJobs, content: content);
      final result = AiJobCoachResult.fromMap(map);
      expect(result.testMode, isTrue);
      expect(result.recommendations, isNotEmpty);
      // 학력을 채운 이력서라 어떤 추천에도 학력 근거 미입력이 남지 않는다.
      for (final item in result.recommendations) {
        expect(item.unknownConditions, isNot(contains('이력서 학력 근거 미입력')), reason: item.jobId);
      }
      expect(result.selectedJob, isNotNull);
    });

    test('기술스택만 있는 공고도 판정 대상이 된다', () {
      final job = _job(techStack: const ['Python', 'Docker']);
      final resume = LocalResumeProfile.fromContent(_content(techStack: const ['Python']));
      final analysis = analyzeSkills(job, resume);
      final judgements = (analysis['judgements'] as List).cast<Map<String, dynamic>>();
      expect(judgements.map((j) => j['requirementType']).toSet(), {'DECLARED'});
      final byName = {for (final j in judgements) j['criterion']: j['judgement']};
      expect(byName['Python'], 'EVIDENCED');
      expect(byName['Docker'], 'NOT_EVIDENCED');
    });
  });
}
