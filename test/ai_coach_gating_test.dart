import 'package:flutter_test/flutter_test.dart';

import 'package:playdata_lms/features/resume/ai_coach/data/resume_analyzer.dart';
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
      expect(
        ResumeReadiness.of(ResumeContent.empty()).canAnalyzeResume,
        isFalse,
      );
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
      expect(
        analysis.improvements.map((item) => item.text).join(),
        contains('Kubernetes'),
      );
    });
  });

}
