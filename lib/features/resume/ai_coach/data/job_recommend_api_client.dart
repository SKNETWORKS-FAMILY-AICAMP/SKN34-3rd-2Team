import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../shared/models/job_preferences.dart';
import '../../../../shared/models/resume_content.dart';
import '../models/ai_job_coach_result.dart';
import 'resume_profile.dart';
import 'resume_text_builder.dart';

/// 채용공고 추천 API(`job_matching_bot`, FastAPI) 접속 설정.
///
/// 기본값은 내 컴퓨터에서 띄운 서버(`127.0.0.1:8000`)다. 다른 주소는 빌드 시
/// `--dart-define=JOB_RECOMMEND_API_URL=http://...` 로 넣는다. 빈 문자열을 넣으면
/// 추천 버튼이 안내 오류를 낸다.
///
/// 서버가 없거나 응답하지 못하면 추천하지 않는다. 이유는 예외 메시지로 화면에
/// 그대로 보인다(`AiJobCoachRepository`).
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

  /// 이력서와 프로필의 희망 조건으로 만든다. 학력·연차·전공·자격증은
  /// `RecommendResumeProfile`이 이력서에서 뽑는다.
  factory JobRecommendRequest.fromResume(
    ResumeContent content, {
    JobPreferences preferences = const JobPreferences(),
    int topK = JobRecommendApiConfig.topK,
  }) {
    final profile = RecommendResumeProfile.fromContent(content);
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

/// `POST /api/v1/jobs/feedback` 결과의 한 항목.
///
/// 공고가 원하는 것 하나와, 그것이 이력서에서 확인되는지를 원문 인용으로 보여 준다.
class JobFeedbackPoint {
  const JobFeedbackPoint({
    required this.kind,
    required this.topic,
    required this.jobQuote,
    required this.status,
    required this.resumeQuote,
    required this.advice,
  });

  /// 인재상 · 요구역량 · 주요업무 · 우대사항.
  final String kind;
  final String topic;

  /// 공고 원문에 그대로 있는 문장.
  final String jobQuote;

  /// '드러남' 또는 '확인 안 됨'. 확인 안 됨은 경험이 없다는 뜻이 아니다.
  final String status;

  /// 드러남일 때만 채워진다. 이력서 원문에 그대로 있는 문장.
  final String resumeQuote;
  final String advice;

  bool get isShown => status == '드러남';

  factory JobFeedbackPoint.fromMap(Map<String, dynamic> map) => JobFeedbackPoint(
        kind: map['kind'] as String? ?? '',
        topic: map['topic'] as String? ?? '',
        jobQuote: map['job_quote'] as String? ?? '',
        status: map['status'] as String? ?? '확인 안 됨',
        resumeQuote: map['resume_quote'] as String? ?? '',
        advice: map['advice'] as String? ?? '',
      );
}

/// 고른 공고 하나를 기준으로 받은 이력서 피드백. 이력서를 저장하거나 고치지 않는다.
class JobFeedbackResponse {
  const JobFeedbackResponse({
    required this.jobId,
    required this.company,
    required this.title,
    required this.sourceUrl,
    required this.wanted,
    required this.points,
    required this.warnings,
    required this.notice,
  });

  final String jobId;
  final String company;
  final String title;
  final String sourceUrl;

  /// 이 공고가 원하는 사람. 공고에 적힌 범위 안에서만 쓰인다.
  final String wanted;
  final List<JobFeedbackPoint> points;
  final List<String> warnings;
  final String notice;

  List<JobFeedbackPoint> get shown => points.where((p) => p.isShown).toList();
  List<JobFeedbackPoint> get missing => points.where((p) => !p.isShown).toList();

  factory JobFeedbackResponse.fromMap(Map<String, dynamic> map) {
    final items = map['points'];
    return JobFeedbackResponse(
      jobId: map['job_id'] as String? ?? '',
      company: map['company'] as String? ?? '',
      title: map['title'] as String? ?? '',
      sourceUrl: map['source_url'] as String? ?? '',
      wanted: map['wanted'] as String? ?? '',
      points: items is List
          ? items
              .whereType<Map>()
              .map((e) => JobFeedbackPoint.fromMap(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
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
    return JobRecommendResponse.fromMap(
      await _post('/api/v1/jobs/recommend', request.toJson()),
    );
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_baseUrl$path');
    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
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
        404 => '서버 저장소에서 이 공고를 찾지 못했습니다: $detail',
        503 => '추천 서버가 검색을 수행하지 못했습니다: $detail',
        422 => '요청을 처리하지 못했습니다: $detail',
        _ => '추천 서버 오류(HTTP ${response.statusCode}): $detail',
      };
      throw JobRecommendApiException(message, statusCode: response.statusCode);
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const JobRecommendApiException('추천 서버 응답 형식이 올바르지 않습니다.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  /// 고른 공고 하나로 이력서 피드백을 받는다.
  ///
  /// 서버가 공고 원문을 저장소에서 읽으므로 앱은 공고 id만 보낸다. 이력서는 저장 전
  /// 초안이어도 된다. 서버가 이력서를 저장하거나 고치지 않는다.
  Future<JobFeedbackResponse> feedback({
    required String jobId,
    required String resumeText,
  }) async {
    final decoded = await _post('/api/v1/jobs/feedback', {
      'job_id': jobId,
      'resume_text': resumeText,
    });
    return JobFeedbackResponse.fromMap(decoded);
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
