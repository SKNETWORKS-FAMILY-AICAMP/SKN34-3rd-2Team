import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../shared/models/job_preferences.dart';
import '../../../../shared/models/resume_content.dart';
import '../models/ai_job_coach_result.dart';
import 'local_job_matcher.dart';
import 'resume_text_builder.dart';

/// 채용공고 추천 API(`job_matching_bot`, FastAPI) 접속 설정.
///
/// 기본값은 내 컴퓨터에서 띄운 서버(`127.0.0.1:8000`)다. 다른 주소는 빌드 시
/// `--dart-define=JOB_RECOMMEND_API_URL=http://...` 로 넣는다. 빈 문자열을 넣으면
/// 서버를 부르지 않고 앱 안의 규칙 기반 추천만 쓴다.
///
/// 서버가 없거나 응답하지 못하면 앱은 규칙 기반 추천으로 대신하고 그 이유를
/// 화면에 남긴다(`AiJobCoachRepository`).
abstract final class JobRecommendApiConfig {
  static const baseUrl = String.fromEnvironment(
    'JOB_RECOMMEND_API_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static bool get isConfigured => baseUrl.trim().isNotEmpty;

  /// LLM 재정렬이 평균 30초라 넉넉히 둔다.
  static const timeout = Duration(seconds: 90);

  /// 서버 상한이 20이다. 화면에는 5~10건이면 충분하다.
  static const topK = 10;
}

class JobRecommendApiException implements Exception {
  const JobRecommendApiException(
    this.message, {
    this.statusCode,
    this.isConnectionError = false,
  });

  final String message;
  final int? statusCode;

  /// 서버에 닿지 못했거나 시간 안에 응답이 없었다. 서버 로직 오류가 아니다.
  final bool isConnectionError;

  @override
  String toString() => message;
}

/// `POST /api/v1/jobs/recommend` 요청 본문. 필드 이름은 서버 스키마와 같다.
class JobRecommendRequest {
  const JobRecommendRequest({
    required this.resumeText,
    this.preferredRegions = const [],
    this.preferredEmploymentTypes = const [],
    this.educationLevel = '미기재',
    this.careerYears = 0,
    this.majors = const [],
    this.certifications = const [],
    this.topK = JobRecommendApiConfig.topK,
  });

  /// 이력서 평문. 서버는 여기 있는 문장을 그대로 인용해 근거로 쓰므로 다듬지 않는다.
  final String resumeText;
  final List<String> preferredRegions;
  final List<String> preferredEmploymentTypes;
  final String educationLevel;
  final double careerYears;
  final List<String> majors;
  final List<String> certifications;
  final int topK;

  /// 이력서와 프로필의 희망 조건으로 만든다. 학력·연차·전공·자격증은 앱 안의
  /// 규칙 기반 추천(`LocalResumeProfile`)과 같은 규칙으로 뽑아 두 경로가 어긋나지 않게 한다.
  factory JobRecommendRequest.fromResume(
    ResumeContent content, {
    JobPreferences preferences = const JobPreferences(),
    int topK = JobRecommendApiConfig.topK,
  }) {
    final profile = LocalResumeProfile.fromContent(content);
    return JobRecommendRequest(
      resumeText: buildResumeText(content),
      preferredRegions: preferences.regions,
      preferredEmploymentTypes: preferences.employmentTypes,
      educationLevel: profile.educationLevel,
      careerYears: profile.careerYears,
      majors: profile.majors,
      certifications: profile.certifications,
      topK: topK,
    );
  }

  Map<String, dynamic> toJson() => {
        'resume_text': resumeText,
        'preferred_regions': preferredRegions,
        'preferred_employment_types': preferredEmploymentTypes,
        'education_level': educationLevel,
        'career_years': careerYears,
        'majors': majors,
        'certifications': certifications,
        'top_k': topK,
      };
}

/// `POST /api/v1/jobs/recommend` 응답.
class JobRecommendResponse {
  const JobRecommendResponse({
    required this.recommendations,
    required this.searchQuery,
    required this.profileSummary,
    required this.reranked,
    required this.warnings,
    required this.notice,
  });

  final List<JobRecommendation> recommendations;

  /// 서버가 이력서에서 만든 검색 질의문. 왜 이런 공고가 나왔는지 보여 준다.
  final String searchQuery;
  final String profileSummary;

  /// false면 LLM 재정렬 없이 검색 순서 그대로다.
  final bool reranked;

  /// 근거 검증에서 제거된 내용.
  final List<String> warnings;
  final String notice;

  factory JobRecommendResponse.fromMap(Map<String, dynamic> map) {
    final items = map['recommendations'];
    return JobRecommendResponse(
      recommendations: items is List
          ? items
              .whereType<Map>()
              .map((e) => JobRecommendation.fromRecommendApi(
                    Map<String, dynamic>.from(e),
                  ))
              .toList()
          : const [],
      searchQuery: map['search_query'] as String? ?? '',
      profileSummary: map['profile_summary'] as String? ?? '',
      reranked: map['reranked'] as bool? ?? false,
      warnings: (map['warnings'] as List?)?.whereType<String>().toList() ?? const [],
      notice: map['notice'] as String? ?? '',
    );
  }
}

class JobRecommendApiClient {
  JobRecommendApiClient({String? baseUrl, http.Client? client})
      : _baseUrl = (baseUrl ?? JobRecommendApiConfig.baseUrl)
            .trim()
            .replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  String get baseUrl => _baseUrl;

  Future<JobRecommendResponse> recommend(JobRecommendRequest request) async {
    final uri = Uri.parse('$_baseUrl/api/v1/jobs/recommend');
    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(request.toJson()),
          )
          .timeout(JobRecommendApiConfig.timeout);
    } on http.ClientException catch (error) {
      throw JobRecommendApiException(
        '추천 서버($_baseUrl)에 연결하지 못했습니다: ${error.message}',
        isConnectionError: true,
      );
    } on TimeoutException {
      throw JobRecommendApiException(
        '추천 서버가 ${JobRecommendApiConfig.timeout.inSeconds}초 안에 응답하지 않았습니다.',
        isConnectionError: true,
      );
    } catch (error) {
      // 플랫폼별 소켓 예외 등. 서버 로직 오류가 아니라 닿지 못한 것으로 본다.
      throw JobRecommendApiException(
        '추천 서버($_baseUrl) 요청에 실패했습니다: $error',
        isConnectionError: true,
      );
    }

    if (response.statusCode != 200) {
      final detail = _detail(response);
      final message = switch (response.statusCode) {
        503 => '추천 서버가 검색을 수행하지 못했습니다: $detail',
        422 => '추천 서버가 요청을 거부했습니다(입력 형식): $detail',
        _ => '추천 서버 오류(HTTP ${response.statusCode}): $detail',
      };
      throw JobRecommendApiException(message, statusCode: response.statusCode);
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const JobRecommendApiException('추천 서버 응답 형식이 올바르지 않습니다.');
    }
    return JobRecommendResponse.fromMap(Map<String, dynamic>.from(decoded));
  }

  static String _detail(http.Response response) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map && body['detail'] != null) return body['detail'].toString();
    } catch (_) {
      // 본문이 JSON이 아니면 그대로 보여 준다.
    }
    final text = response.body.trim();
    return text.isEmpty ? '응답 본문 없음' : text;
  }
}
