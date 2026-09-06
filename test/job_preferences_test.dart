import 'package:flutter_test/flutter_test.dart';

import 'package:playdata_lms/features/resume/ai_coach/data/generated/collected_jobs.g.dart';
import 'package:playdata_lms/features/resume/ai_coach/data/local_job_matcher.dart';
import 'package:playdata_lms/shared/models/job_preferences.dart';
import 'package:playdata_lms/shared/models/resume_content.dart';

void main() {
  group('JobPreferences', () {
    test('Firestore 맵과 왕복하며 빈 문자열은 버린다', () {
      final prefs = JobPreferences.fromMap({
        'targetRoles': ['백엔드 개발자', ' '],
        'regions': ['서울', 'x'],
        'employmentTypes': null,
      });
      expect(prefs.targetRoles, ['백엔드 개발자']);
      expect(prefs.regions, ['서울', 'x']);
      expect(prefs.employmentTypes, isEmpty);
      expect(JobPreferences.fromMap(prefs.toMap()).summary, prefs.summary);
    });

    test('요약은 채운 항목만 이어 붙인다', () {
      expect(const JobPreferences().summary, '');
      expect(
        const JobPreferences(regions: ['서울', '경기'], employmentTypes: ['정규직']).summary,
        '서울, 경기 · 정규직',
      );
    });

    test('선택지의 직무는 매처 ROLE_TERMS 키와 같아 점수에 반영된다', () {
      const content = ResumeContent(
        basicInfo: ResumeBasicInfo(name: '홍길동', email: 'a@b.c'),
        coreCompetencies: ResumeCoreCompetencies(text: '백엔드'),
        education: [ResumeEducationItem(id: 'e', school: '대학')],
        techStack: [ResumeTechStackItem(id: 't', name: 'Python')],
        projects: [ResumeProjectItem(id: 'p', name: 'API', techStack: 'Python')],
      );
      for (final role in JobPreferenceOptions.roles) {
        final result = runLocalJobCoach(
          jobs: collectedJobs,
          content: content,
          targetRoles: [role],
        );
        expect(result['recommendations'], isA<List>());
      }
    });

    test('희망 지역·고용형태는 하드 필터에 그대로 전달된다', () {
      const content = ResumeContent(
        education: [ResumeEducationItem(id: 'e', school: '대학')],
        techStack: [ResumeTechStackItem(id: 't', name: 'Python')],
      );
      final none = runLocalJobCoach(jobs: collectedJobs, content: content);
      final seoul = runLocalJobCoach(
        jobs: collectedJobs,
        content: content,
        preferredRegions: ['서울'],
        preferredEmploymentTypes: ['정규직'],
      );
      final all = (none['recommendations'] as List).length;
      final filtered = (seoul['recommendations'] as List).length;
      expect(filtered, lessThan(all));
      for (final rec in seoul['recommendations'] as List) {
        final hardFilter = (rec as Map)['hardFilter'] as Map;
        expect(hardFilter['status'], isNot('FAIL'));
      }
    });
  });
}
