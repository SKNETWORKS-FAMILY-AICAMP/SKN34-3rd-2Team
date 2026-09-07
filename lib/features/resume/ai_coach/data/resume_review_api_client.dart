import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../shared/models/resume_content.dart';
import 'job_recommend_api_client.dart';

Object? _sorted(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _sorted(value[key])};
  }
  if (value is List) return value.map(_sorted).toList();
  return value;
}

bool sameResumeContent(ResumeContent draft, Map<String, dynamic> stored) =>
    jsonEncode(_sorted(draft.toMap())) ==
    jsonEncode(_sorted(ResumeContent.fromMap(stored).toMap()));

class ResumeReviewApiException extends FormatException {
  const ResumeReviewApiException(super.message, this.statusCode);
  final int statusCode;
}

class ResumeReviewApiClient {
  ResumeReviewApiClient({
    required this.token,
    String? baseUrl,
    http.Client? client,
  }) : _baseUrl =
           (baseUrl ??
                   const String.fromEnvironment(
                     'RESUME_REVIEW_API_URL',
                     defaultValue:
                         '${JobRecommendApiConfig.baseUrl}/resume-review',
                   ))
               .replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client();

  final Future<String?> Function() token;
  final String _baseUrl;
  final http.Client _client;

  void close() => _client.close();

  Future<Map<String, dynamic>> context(
    String cohort,
    String resume, {
    String? job,
  }) => _request(
    'GET',
    '/api/v1/resumes/review-context',
    query: {
      'cohort_id': cohort,
      'resume_id': resume,
      'job_id': ?job,
    },
  );

  Future<Map<String, dynamic>> review(Map<String, dynamic> body) =>
      _request('POST', '/api/v1/resumes/reviews', body: body);
  Future<Map<String, dynamic>> apply(Map<String, dynamic> body) =>
      _request('POST', '/api/v1/resumes/reviews/apply', body: body);
  Future<Map<String, dynamic>> undo(Map<String, dynamic> body) =>
      _request('POST', '/api/v1/resumes/reviews/undo', body: body);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final credential = await token();
    if (credential == null || credential.isEmpty) {
      throw const FormatException('실제 Firebase 로그인이 필요합니다. 데모 계정은 사용할 수 없습니다.');
    }
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $credential',
    };
    final http.Response response;
    try {
      response =
          await (method == 'GET'
                  ? _client.get(uri, headers: headers)
                  : _client.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(const Duration(seconds: 120));
    } on TimeoutException {
      throw const FormatException('응답 시간이 초과됐습니다. 재시도는 같은 요청 ID로 처리됩니다.');
    } on http.ClientException {
      throw const FormatException('첨삭 서버에 연결하지 못했습니다. 서버 주소와 실행 상태를 확인해 주세요.');
    }
    if (response.statusCode != 200) {
      throw ResumeReviewApiException(switch (response.statusCode) {
        401 => '로그인이 만료됐습니다. 다시 로그인해 주세요.',
        403 => '본인 소유 이력서만 첨삭할 수 있습니다.',
        404 => '이력서를 찾을 수 없습니다.',
        409 => '이력서 또는 공고가 변경됐거나 요청이 처리 중입니다. 결과를 확인하고 다시 시도해 주세요.',
        422 => '공고 원문·마감일 또는 선택한 수정안을 확인할 수 없습니다.',
        503 => '첨삭 서버 설정 또는 공고 원문 DB를 사용할 수 없습니다. 서버 로그의 오류 유형을 확인해 주세요.',
        _ => '첨삭 요청에 실패했습니다 (HTTP ${response.statusCode}).',
      }, response.statusCode);
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('첨삭 응답 형식 오류');
    }
    return decoded;
  }
}
