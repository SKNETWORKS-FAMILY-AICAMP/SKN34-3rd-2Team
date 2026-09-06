import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:playdata_lms/features/resume/ai_coach/data/cover_letter_rag_client.dart';
import 'package:playdata_lms/features/resume/ai_coach/data/resume_analyzer.dart';
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

    test('초안은 자기소개서 → 핵심역량 → 이력서 전체 순으로 고른다', () {
      expect(buildAnalysisDraftText(_resume()), contains('교육 서비스에 기여하고'));

      const noIntro = ResumeContent(
        coreCompetencies: ResumeCoreCompetencies(text: '핵심역량만 있음'),
      );
      expect(buildAnalysisDraftText(noIntro), '핵심역량만 있음');

      const onlyTech = ResumeContent(
        techStack: [ResumeTechStackItem(id: 't1', name: 'Dart')],
      );
      expect(buildAnalysisDraftText(onlyTech), '[기술스택]\nDart');
    });
  });

  group('cover_letter_rag 클라이언트', () {
    test('기존 서버 스키마에 맞는 필드만 보내고 응답을 읽는다', () async {
      final requests = <http.Request>[];
      final client = CoverLetterRagClient(
        baseUrl: 'http://rag.test/',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/api/v1/jobs/search') {
            return http.Response(
              jsonEncode({
                'results': [
                  {
                    'rank': 1,
                    'job_id': 'j1',
                    'company': '샘플',
                    'title': '백엔드',
                    'location': '서울',
                    'employment_type': '정규직',
                    'summary': 'Python API 개발 경험 필수',
                    'source': 'data/jobs/sample.json',
                  },
                ],
                'notice': '검색 순위는 공고 관련도입니다.',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'question_intent': '강점 확인',
              'requirements': [
                {
                  'requirement': 'Python API 개발',
                  'requirement_type': '필수',
                  'source_id': 'provided_job_posting',
                  'status': '충족',
                  'resume_evidence': [
                    {
                      'resume_quote': 'FastAPI로 추천 API를 개발하고',
                      'explanation': 'API 개발 경험',
                    },
                  ],
                },
                {
                  'requirement': 'AWS 운영',
                  'requirement_type': '우대',
                  'source_id': 'provided_job_posting',
                  'status': '미충족',
                  'resume_evidence': [],
                  'gap': '클라우드 운영 경험이 드러나지 않습니다.',
                },
                {
                  'requirement': '테스트 자동화',
                  'requirement_type': '우대',
                  'source_id': 'provided_job_posting',
                  'status': '확인 필요',
                  'resume_evidence': [],
                  'confirmation_question': '테스트 코드를 작성한 경험이 있나요?',
                },
              ],
              'improvements': [
                {
                  'issue': '추상적 표현',
                  'suggestion': '기여하고 싶은 기능을 구체적으로 적으세요.',
                  'grounded_resume_quote': null,
                },
              ],
              'confirmation_questions': ['테스트 코드를 작성한 경험이 있나요?'],
              'revised_draft': '고쳐 쓴 초안',
              'sources': [],
              'grounding_warnings': ['이력서 원문에서 확인되지 않은 근거를 제거했습니다: X'],
              'notice': '합격 가능성 판단이 아닙니다.',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final resumeText = buildResumeText(_resume());
      final jobs = await client.searchJobs(resumeText, topK: 3, idToken: 'tok');
      expect(jobs, hasLength(1));
      expect(jobs.first.toPostingText(), '[샘플 - 백엔드] (서울 · 정규직)\nPython API 개발 경험 필수');

      final review = await client.review(
        resumeText: resumeText,
        jobPostingText: jobs.first.toPostingText(),
        coverLetterQuestion: '강점을 점검해 주세요.',
        draftText: buildAnalysisDraftText(_resume()),
        topK: 3,
        idToken: 'tok',
      );

      // 요청 검증: 서버는 extra="forbid"라 정의된 키만 보내야 한다.
      final searchBody = jsonDecode(requests[0].body) as Map<String, dynamic>;
      expect(searchBody.keys.toSet(), {'resume_text', 'top_k'});
      expect(requests[0].headers['Authorization'], 'Bearer tok');
      final reviewBody = jsonDecode(requests[1].body) as Map<String, dynamic>;
      expect(reviewBody.keys.toSet(), {
        'resume_text',
        'job_posting_text',
        'cover_letter_question',
        'draft_text',
        'top_k',
      });

      // 응답 → 분석 결과 매핑
      final local = analyzeResume(_resume());
      final analysis = ResumeAnalysis.fromRag(
        local: local,
        jobs: jobs,
        review: review,
      );
      expect(analysis.isFromRag, isTrue);
      expect(analysis.strengths, hasLength(1));
      expect(analysis.strengths.first.quote, 'FastAPI로 추천 API를 개발하고');
      expect(
        analysis.improvements.map((e) => e.text),
        containsAll([
          'AWS 운영 (우대): 클라우드 운영 경험이 드러나지 않습니다.',
          '추상적 표현: 기여하고 싶은 기능을 구체적으로 적으세요.',
        ]),
      );
      // 확인 필요 항목은 보완점이 아니라 질문으로 간다.
      expect(analysis.improvements.map((e) => e.text).join(), isNot(contains('테스트 자동화')));
      expect(analysis.confirmationQuestions, ['테스트 코드를 작성한 경험이 있나요?']);
      expect(analysis.relatedJobs.single.company, '샘플');
      expect(analysis.warnings, isNotEmpty);
      expect(analysis.nextSteps, local.nextSteps);
    });

    test('서버 오류는 상태 코드와 detail을 담은 예외로 바꾼다', () async {
      final client = CoverLetterRagClient(
        baseUrl: 'http://rag.test',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({'detail': 'Chroma index is not ready'}),
            503,
          ),
        ),
      );
      expect(
        () => client.searchJobs('충분히 긴 이력서 본문입니다. 스무 자를 넘깁니다.'),
        throwsA(
          isA<CoverLetterRagException>()
              .having((e) => e.statusCode, 'statusCode', 503)
              .having((e) => e.message, 'message', contains('Chroma index')),
        ),
      );
    });

    test('서버 하한보다 짧은 이력서는 요청 전에 막는다', () async {
      var called = false;
      final client = CoverLetterRagClient(
        baseUrl: 'http://rag.test',
        httpClient: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        () => client.searchJobs('짧음'),
        throwsA(isA<CoverLetterRagException>()),
      );
      expect(called, isFalse);
    });
  });
}
