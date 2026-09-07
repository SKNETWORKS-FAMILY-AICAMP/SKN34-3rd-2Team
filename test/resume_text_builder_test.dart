import 'package:flutter_test/flutter_test.dart';

import 'package:playdata_lms/features/resume/ai_coach/data/resume_text_builder.dart';
import 'package:playdata_lms/shared/models/resume_content.dart';

ResumeContent _resume() => const ResumeContent(
  basicInfo: ResumeBasicInfo(name: '홍길동', email: 'hong@example.com'),
  coreCompetencies: ResumeCoreCompetencies(text: 'Python 백엔드 개발자입니다.'),
  techStack: [
    ResumeTechStackItem(id: 't1', name: 'Python', level: '중급'),
    ResumeTechStackItem(id: 't2', name: 'FastAPI'),
  ],
  projects: [
    ResumeProjectItem(
      id: 'p1',
      name: '추천 서비스',
      startDate: '2026.01',
      endDate: '2026.03',
      role: '백엔드 개발',
      techStack: 'Python, FastAPI',
      description: 'FastAPI로 추천 API를 개발하고 응답 속도를 개선했습니다.',
    ),
  ],
  selfIntroduction: ResumeSelfIntroduction(
    motivation: ResumeIntroSection(subtitle: '왜 지원하나', body: '교육 서비스에 기여하고 싶습니다.'),
  ),
);

void main() {
  group('이력서 평문 변환', () {
    test('사용자 문장을 그대로 담아 서버가 인용을 대조할 수 있게 한다', () {
      final text = buildResumeText(_resume());
      expect(text, contains('[핵심역량]\nPython 백엔드 개발자입니다.'));
      expect(text, contains('Python (중급)'));
      expect(text, contains('- 추천 서비스 (2026.01 ~ 2026.03)'));
      expect(text, contains('FastAPI로 추천 API를 개발하고 응답 속도를 개선했습니다.'));
      expect(text, contains('[자기소개서]'));
      expect(text, contains('(지원동기) 왜 지원하나\n교육 서비스에 기여하고 싶습니다.'));
    });

    test('빈 항목은 섹션 자체를 만들지 않는다', () {
      final text = buildResumeText(
        const ResumeContent(
          techStack: [ResumeTechStackItem(id: 't1', name: 'Dart')],
        ),
      );
      expect(text, '[기술스택]\nDart');
    });
  });
}
