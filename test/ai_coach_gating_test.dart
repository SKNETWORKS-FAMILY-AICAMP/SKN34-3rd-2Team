import 'package:flutter_test/flutter_test.dart';

import 'package:playdata_lms/features/resume/ai_coach/data/job_search.dart';
import 'package:playdata_lms/features/resume/ai_coach/data/resume_analyzer.dart';
import 'package:playdata_lms/features/resume/ai_coach/data/text_match.dart';
import 'package:playdata_lms/features/resume/ai_coach/models/resume_readiness.dart';
import 'package:playdata_lms/shared/models/resume_content.dart';

/// 필수 항목을 모두 채운 이력서.
ResumeContent _completeResume() => const ResumeContent(
  basicInfo: ResumeBasicInfo(name: '홍길동', email: 'hong@example.com'),
  coreCompetencies: ResumeCoreCompetencies(text: 'Python 백엔드 개발자입니다.'),
  education: [ResumeEducationItem(id: 'e1', school: '한국대학교', major: '컴퓨터공학')],
  techStack: [ResumeTechStackItem(id: 't1', name: 'Python')],
  projects: [
    ResumeProjectItem(
      id: 'p1',
      name: '추천 서비스',
      role: '백엔드 개발',
      techStack: 'Python, FastAPI',
      description: 'FastAPI로 추천 API를 개발하고 응답 속도를 개선했습니다.',
    ),
  ],
  selfIntroduction: ResumeSelfIntroduction(
    growth: ResumeIntroSection(subtitle: '성장 과정', body: '꾸준히 학습했습니다.'),
  ),
);

void main() {
  group('맞춤 공고 추천 게이트', () {
    test('빈 이력서는 추천을 실행할 수 없다', () {
      final readiness = ResumeReadiness.of(ResumeContent.empty());
      expect(readiness.canRecommendJobs, isFalse);
      expect(
        readiness.missingRequiredSections.length,
        requiredSectionsForRecommendation.length,
      );
    });

    test('필수 항목이 하나라도 비면 추천을 실행할 수 없다', () {
      // 기술스택만 지운다.
      final content = _completeResume().copyWith(techStack: const []);
      final readiness = ResumeReadiness.of(content);
      expect(readiness.canRecommendJobs, isFalse);
      expect(readiness.missingRequiredSectionLabels, contains('기술스택'));
    });

    test('필수 항목을 모두 채우면 추천을 실행할 수 있다', () {
      final readiness = ResumeReadiness.of(_completeResume());
      expect(readiness.canRecommendJobs, isTrue);
      expect(readiness.missingRequiredSections, isEmpty);
      expect(readiness.blockedReason(AiCoachFeature.jobRecommendation), isNull);
    });

    test('경력이 없어도 추천을 막지 않는다', () {
      // 신입 사용자가 영구히 막히면 안 된다.
      final readiness = ResumeReadiness.of(_completeResume());
      expect(readiness.filledSections, isNot(contains('experience')));
      expect(readiness.canRecommendJobs, isTrue);
    });

    test('막힌 이유에 비어 있는 항목 이름이 들어간다', () {
      final content = _completeResume().copyWith(projects: const []);
      final reason = ResumeReadiness.of(
        content,
      ).blockedReason(AiCoachFeature.jobRecommendation);
      expect(reason, contains('프로젝트 경험'));
    });
  });

  group('이력서 분석 게이트', () {
    test('빈 이력서는 분석할 수 없다', () {
      expect(ResumeReadiness.of(ResumeContent.empty()).canAnalyzeResume, isFalse);
    });

    test('기술스택만 있어도 분석할 수 있다', () {
      const content = ResumeContent(
        techStack: [ResumeTechStackItem(id: 't1', name: 'Python')],
      );
      final readiness = ResumeReadiness.of(content);
      expect(readiness.canAnalyzeResume, isTrue);
      // 분석은 되지만 추천은 아직 안 된다.
      expect(readiness.canRecommendJobs, isFalse);
    });

    test('프로젝트 근거가 없는 기술을 보완 항목으로 알려준다', () {
      const content = ResumeContent(
        techStack: [ResumeTechStackItem(id: 't1', name: 'Kubernetes')],
      );
      final analysis = analyzeResume(content);
      expect(analysis.improvements.join(), contains('Kubernetes'));
    });
  });

  group('채용공고 찾기', () {
    test('이력서가 비어 있어도 검색할 수 있다', () {
      expect(ResumeReadiness.of(ResumeContent.empty()).canSearchJobs, isTrue);
    });

    test('키워드로 공고를 찾는다', () {
      final result = searchJobs('백엔드 개발자 공고 찾아줘');
      expect(result.jobs, isNotEmpty);
      expect(result.query.keywords, contains('백엔드'));
    });

    test('신입 조건은 경력직 공고를 제외한다', () {
      final result = searchJobs('신입 백엔드');
      expect(result.query.entryLevelOnly, isTrue);
      expect(result.jobs.every((job) => job.isEntryFriendly != false), isTrue);
    });

    test('지역 조건이 맞지 않는 공고는 제외한다', () {
      final result = searchJobs('부산 개발자');
      expect(result.query.regions, contains('부산'));
      expect(result.jobs.every((job) => job.region.contains('부산')), isTrue);
    });

    test('찾는 공고가 없으면 빈 목록을 준다', () {
      final result = searchJobs('수의사 채용');
      expect(result.jobs, isEmpty);
    });

    test('직무 키워드가 안 맞으면 신입 공고여도 제외한다', () {
      // 신입 보너스 점수만으로 통과해 백엔드·전산행정 공고까지 나오던 버그.
      final result = searchJobs('프론트엔드 신입 공고');
      expect(result.query.keywords, contains('프론트엔드'));
      expect(result.query.entryLevelOnly, isTrue);
      // 건수는 수집 데이터에 따라 달라지므로 고정하지 않는다. 확인할 것은
      // 나온 공고가 전부 프론트엔드를 언급하고, 백엔드 전용 공고는 없다는 것이다.
      expect(result.jobs, isNotEmpty);
      expect(result.jobs.every((job) => job.searchText.contains('프론트엔드')), isTrue);
      expect(result.jobs.any((job) => job.jobId == 'MOCK-BE-001'), isFalse);
      expect(result.jobs.any((job) => job.title.contains('React 프론트엔드')), isTrue);
    });

    test('백엔드로 검색하면 프론트엔드 공고가 나오지 않는다', () {
      final result = searchJobs('백엔드 신입');
      expect(result.jobs, isNotEmpty);
      expect(
        result.jobs.every((job) => !job.title.contains('프론트엔드')),
        isTrue,
      );
    });

    test('조건만 준 질문은 키워드 없이도 결과를 준다', () {
      final result = searchJobs('서울 신입');
      expect(result.query.keywords, isEmpty);
      expect(result.jobs, isNotEmpty);
      expect(result.jobs.every((job) => job.region.contains('서울')), isTrue);
    });

    test('영문 키워드가 다른 단어 안에 걸리지 않는다', () {
      // "ai"가 maintain·email에 걸리면 무관한 공고가 섞인다.
      expect(matchesTerm('maintain the detail email', 'ai'), isFalse);
      expect(matchesTerm('applied ai engineering', 'ai'), isTrue);
      // 한글이 붙어 있어도 영문 키워드를 인식한다.
      expect(matchesTerm('rest api와 db 연동', 'api'), isTrue);
      expect(matchesTerm('fastapi 기반 서버', 'api'), isFalse);
    });

    test('검색 조건 요약에 해석 결과가 드러난다', () {
      final result = searchJobs('서울 백엔드 신입');
      expect(result.query.summary, contains('직무'));
      expect(result.query.summary, contains('경력 신입'));
      expect(result.query.summary, contains('서울'));
    });
  });
}
