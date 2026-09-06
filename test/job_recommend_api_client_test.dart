import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:playdata_lms/features/resume/ai_coach/data/ai_job_coach_repository.dart';
import 'package:playdata_lms/features/resume/ai_coach/data/job_recommend_api_client.dart';
import 'package:playdata_lms/shared/models/job_preferences.dart';
import 'package:playdata_lms/shared/models/resume_content.dart';

/// 추천 조건을 갖춘 이력서. 경력 1년, 전공·자격증 있음.
ResumeContent _resume() => const ResumeContent(
  basicInfo: ResumeBasicInfo(name: '홍길동', email: 'hong@example.com'),
  coreCompetencies: ResumeCoreCompetencies(text: 'Python 백엔드 개발자입니다.'),
  education: [ResumeEducationItem(id: 'e1', school: '한국대학교', major: '컴퓨터공학')],
  experience: [
    ResumeExperienceItem(
      id: 'x1',
      company: '테스트컴퍼니',
      role: '백엔드 개발',
      startDate: '2024-01',
      endDate: '2025-01',
      description: 'FastAPI 서비스를 운영했습니다.',
    ),
  ],
  techStack: [ResumeTechStackItem(id: 't1', name: 'Python')],
  certifications: [ResumeCertificationItem(id: 'c1', name: '정보처리기사')],
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

Map<String, dynamic> _serverResponse() => {
  'recommendations': [
    {
      'job_id': 'SARAMIN-1',
      'company': '테스트',
      'title': '백엔드 개발자',
      'source_url': 'https://example.com/jobs/1',
      'fit': '높음',
      'reasons': [
        {
          'claim': 'FastAPI로 API를 만든 경험이 있습니다',
          'resume_quote': 'FastAPI로 추천 API를 개발하고',
          'job_quote': 'FastAPI 기반 API 개발',
        },
      ],
      'concerns': ['Kafka 기반 이벤트 처리 경험이 이력서에서 확인되지 않는다'],
      'conditions': {
        'region': '서울 강남구',
        'employment_type': '정규직',
        'career': '경력무관',
        'education': '학력무관',
        'deadline': '2026-12-31',
      },
      'filter_status': 'PASS',
      'unknown_conditions': [],
      'passed_conditions': ['경력 조건 충족', '학력 조건 충족'],
      'search_rank': 3,
      'body_is_image': false,
    },
  ],
  'search_query': 'Python 백엔드 개발 경험, FastAPI',
  'profile_summary': 'FastAPI 경험이 있는 주니어 백엔드',
  'reranked': true,
  'warnings': [],
  'notice': '추천 순서는 이력서와 공고의 관련도이며 합격 가능성이 아닙니다.',
};

http.Response _json(Map<String, dynamic> body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('추천 API 요청', () {
    test('이력서와 희망 조건을 서버 필드 이름으로 보낸다', () async {
      Map<String, dynamic>? sent;
      Uri? url;
      final client = MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        url = request.url;
        return _json(_serverResponse());
      });
      final api = JobRecommendApiClient(baseUrl: 'http://127.0.0.1:8000/', client: client);

      final response = await api.recommend(
        JobRecommendRequest.fromResume(
          _resume(),
          preferences: const JobPreferences(regions: ['서울'], employmentTypes: ['정규직']),
        ),
      );

      expect(url.toString(), 'http://127.0.0.1:8000/api/v1/jobs/recommend');
      expect(sent!['preferred_regions'], ['서울']);
      expect(sent!['preferred_employment_types'], ['정규직']);
      expect(sent!['education_level'], '대졸');
      expect(sent!['career_years'], 1.0);
      expect(sent!['majors'], ['컴퓨터공학']);
      expect(sent!['certifications'], ['정보처리기사']);
      expect(sent!['top_k'], 10);
      // 서버는 이 평문 안의 문장을 그대로 인용하므로 사용자가 쓴 문장이 변형 없이 들어가야 한다.
      expect(sent!['resume_text'], contains('FastAPI로 추천 API를 개발하고 응답 속도를 개선했습니다.'));

      final item = response.recommendations.single;
      expect(item.jobId, 'SARAMIN-1');
      expect(item.grade, '높음');
      expect(item.isFromServer, isTrue);
      expect(item.reasons.single.resumeQuote, 'FastAPI로 추천 API를 개발하고');
      expect(item.concerns, hasLength(1));
      expect(item.careerLabel, '경력무관');
      expect(item.region, '서울 강남구');
      expect(item.employmentType, '정규직');
      expect(item.deadline, '2026-12-31');
      expect(item.hardFilterStatus, 'PASS');
      expect(item.passedConditions, contains('경력 조건 충족'));
      expect(response.searchQuery, contains('FastAPI'));
      expect(response.reranked, isTrue);
    });

    test('503은 서버 오류 예외, 연결 실패는 연결 오류 예외', () async {
      final unavailable = JobRecommendApiClient(
        baseUrl: 'http://127.0.0.1:8000',
        client: MockClient((_) async => _json({'detail': '검색 실패'}, status: 503)),
      );
      await expectLater(
        unavailable.recommend(JobRecommendRequest.fromResume(_resume())),
        throwsA(
          isA<JobRecommendApiException>()
              .having((e) => e.statusCode, 'statusCode', 503)
              .having((e) => e.isConnectionError, 'isConnectionError', isFalse)
              .having((e) => e.message, 'message', contains('검색 실패')),
        ),
      );

      final unreachable = JobRecommendApiClient(
        baseUrl: 'http://127.0.0.1:1',
        client: MockClient((_) async => throw http.ClientException('Connection refused')),
      );
      await expectLater(
        unreachable.recommend(JobRecommendRequest.fromResume(_resume())),
        throwsA(
          isA<JobRecommendApiException>().having((e) => e.isConnectionError, 'isConnectionError', isTrue),
        ),
      );
    });
  });

  group('저장소', () {
    test('서버 응답을 그대로 추천 결과로 쓴다', () async {
      final repository = AiJobCoachRepository(
        null,
        apiClient: JobRecommendApiClient(
          baseUrl: 'http://127.0.0.1:8000',
          client: MockClient((_) async => _json(_serverResponse())),
        ),
      );
      final result = await repository.analyzeAndMatch(
        cohortId: 'local-fixture',
        resumeId: 'r1',
        draftContent: _resume(),
        confirmedMissingSkills: const {},
      );
      expect(result.fromServer, isTrue);
      expect(result.testMode, isFalse);
      expect(result.recommendations.single.title, '백엔드 개발자');
      expect(result.searchQuery, isNotEmpty);
    });

    test('서버에 닿지 못하면 앱 안의 규칙 기반 추천으로 대신하고 이유를 남긴다', () async {
      final repository = AiJobCoachRepository(
        null,
        apiClient: JobRecommendApiClient(
          baseUrl: 'http://127.0.0.1:1',
          client: MockClient((_) async => throw http.ClientException('Connection refused')),
        ),
      );
      final result = await repository.analyzeAndMatch(
        cohortId: 'local-fixture',
        resumeId: 'r1',
        draftContent: _resume(),
        confirmedMissingSkills: const {},
      );
      expect(result.fromServer, isFalse);
      expect(result.notice, contains('규칙 기반 추천'));
      expect(result.notice, contains('Connection refused'));
      for (final item in result.recommendations) {
        expect(item.isFromServer, isFalse);
      }
    });
  });
}
