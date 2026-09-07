import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:playdata_lms/features/resume/ai_coach/data/job_recommend_api_client.dart';

Map<String, dynamic> _response() => {
  'job_id': 'SARAMIN-1',
  'company': '테스트컴퍼니',
  'title': '백엔드 개발자',
  'source_url': 'https://example.com/jobs/1',
  'wanted': '주도적으로 문제를 정의하고 해결하는 백엔드 개발자',
  'points': [
    {
      'kind': '요구역량',
      'topic': 'Python 백엔드 개발',
      'job_quote': 'Python 백엔드 개발 경험',
      'status': '드러남',
      'resume_quote': 'FastAPI로 추천 API를 개발하고',
      'advice': '지금처럼 프로젝트에 도구 이름과 함께 적어 두면 좋습니다.',
    },
    {
      'kind': '인재상',
      'topic': '주도적으로 문제를 정의',
      'job_quote': '주도적으로 문제를 정의하고 해결하는 분',
      'status': '확인 안 됨',
      'resume_quote': '',
      'advice': '스스로 문제를 정한 경험이 있다면 프로젝트 설명에 그 계기를 적어 보세요.',
    },
  ],
  'warnings': ['공고에 없는 인용을 제거했습니다: Kubernetes'],
  'notice': '합격 가능성이나 지원자 평가가 아닙니다.',
};

http.Response _json(Map<String, dynamic> body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('공고 기준 피드백', () {
    test('공고 id와 이력서 평문을 보내고 항목을 상태별로 나눠 읽는다', () async {
      Map<String, dynamic>? sent;
      Uri? url;
      final api = JobRecommendApiClient(
        baseUrl: 'http://127.0.0.1:8000',
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          url = request.url;
          return _json(_response());
        }),
      );

      final result = await api.feedback(
        jobId: 'SARAMIN-1',
        resumeText: '[프로젝트 경험]\nFastAPI로 추천 API를 개발하고 응답 속도를 개선했습니다.',
      );

      expect(url.toString(), 'http://127.0.0.1:8000/api/v1/jobs/feedback');
      expect(sent!['job_id'], 'SARAMIN-1');
      expect(sent!['resume_text'], contains('FastAPI로 추천 API를 개발하고'));
      // 공고 본문은 서버가 저장소에서 읽으므로 앱이 보내지 않는다.
      expect(sent!.containsKey('job_posting_text'), isFalse);

      expect(result.wanted, contains('주도적'));
      expect(result.points, hasLength(2));
      expect(result.shown.single.kind, '요구역량');
      expect(result.shown.single.resumeQuote, 'FastAPI로 추천 API를 개발하고');
      expect(result.missing.single.kind, '인재상');
      expect(result.missing.single.resumeQuote, isEmpty);
      expect(result.warnings, hasLength(1));
    });

    test('저장소에 없는 공고는 안내 가능한 예외로 바뀐다', () async {
      final api = JobRecommendApiClient(
        baseUrl: 'http://127.0.0.1:8000',
        client: MockClient((_) async => _json({'detail': '저장소에 없는 공고입니다.'}, status: 404)),
      );
      await expectLater(
        api.feedback(jobId: '없음', resumeText: '이력서 평문입니다. 최소 길이를 넘겨야 합니다.'),
        throwsA(
          isA<JobRecommendApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', contains('찾지 못했습니다')),
        ),
      );
    });

    test('이미지 공고는 422로 돌아오고 이유가 메시지에 남는다', () async {
      final api = JobRecommendApiClient(
        baseUrl: 'http://127.0.0.1:8000',
        client: MockClient(
          (_) async => _json({'detail': '이 공고는 상세가 이미지뿐이라 대조할 글이 없습니다.'}, status: 422),
        ),
      );
      await expectLater(
        api.feedback(jobId: 'SARAMIN-2', resumeText: '이력서 평문입니다. 최소 길이를 넘겨야 합니다.'),
        throwsA(
          isA<JobRecommendApiException>()
              .having((e) => e.message, 'message', contains('이미지뿐')),
        ),
      );
    });
  });
}
