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

/// 대화에서 뽑아낸 검색 조건.
///
/// 서버가 대화를 저장하지 않는다. 응답으로 받은 조건을 앱이 들고 있다가 다음 질문에
/// 그대로 실어 보내야 "서울만" 같은 말이 앞말을 이어받는다.
class JobChatFilters {
  const JobChatFilters({
    this.roles = const [],
    this.skills = const [],
    this.regions = const [],
    this.career = '무관',
    this.employmentTypes = const [],
    this.deadlineWithinDays,
    this.keywords = const [],
  });

  final List<String> roles;
  final List<String> skills;
  final List<String> regions;
  final String career;
  final List<String> employmentTypes;
  final int? deadlineWithinDays;
  final List<String> keywords;

  bool get isEmpty =>
      roles.isEmpty &&
      skills.isEmpty &&
      regions.isEmpty &&
      career == '무관' &&
      employmentTypes.isEmpty &&
      deadlineWithinDays == null &&
      keywords.isEmpty;

  /// 무엇으로 걸렀는지 사용자에게 그대로 보여주기 위한 요약.
  String get summary {
    final parts = [
      ...roles,
      ...skills,
      ...regions,
      ...employmentTypes,
      if (career != '무관') career,
      if (deadlineWithinDays != null) '$deadlineWithinDays일 내 마감',
      ...keywords,
    ];
    return parts.isEmpty ? '조건 없음' : parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
        'roles': roles,
        'skills': skills,
        'regions': regions,
        'career': career,
        'employment_types': employmentTypes,
        'deadline_within_days': deadlineWithinDays,
        'keywords': keywords,
      };

  static List<String> _strings(dynamic value) =>
      value is List ? value.whereType<String>().toList() : const [];

  factory JobChatFilters.fromMap(Map<String, dynamic> map) => JobChatFilters(
        roles: _strings(map['roles']),
        skills: _strings(map['skills']),
        regions: _strings(map['regions']),
        career: map['career'] as String? ?? '무관',
        employmentTypes: _strings(map['employment_types']),
        deadlineWithinDays: (map['deadline_within_days'] as num?)?.toInt(),
        keywords: _strings(map['keywords']),
      );
}

/// 챗봇이 찾아 준 공고 한 건. 저장소에서 온 것이라 앱에 박힌 파일보다 최신이다.
class JobChatJob {
  const JobChatJob({
    required this.jobId,
    required this.company,
    required this.title,
    required this.sourceUrl,
    required this.region,
    required this.career,
    required this.employmentType,
    this.deadline,
    this.techStack = const [],
  });

  final String jobId;
  final String company;
  final String title;
  final String sourceUrl;
  final String region;
  final String career;
  final String employmentType;
  final String? deadline;
  final List<String> techStack;

  factory JobChatJob.fromMap(Map<String, dynamic> map) => JobChatJob(
        jobId: map['job_id'] as String? ?? '',
        company: map['company'] as String? ?? '',
        title: map['title'] as String? ?? '',
        sourceUrl: map['source_url'] as String? ?? '',
        region: map['region'] as String? ?? '미기재',
        career: map['career'] as String? ?? '미기재',
        employmentType: map['employment_type'] as String? ?? '미기재',
        deadline: map['deadline'] as String?,
        techStack: JobChatFilters._strings(map['tech_stack']),
      );
}

class JobChatResponse {
  const JobChatResponse({
    required this.mode,
    required this.reply,
    required this.filters,
    required this.jobs,
    required this.total,
    required this.suggestions,
  });

  /// 서버가 어떤 갈래로 답했는지. 검색 / 질문 / 공고 / 안내.
  ///
  /// 답을 어떻게 보여줄지가 달라진다. 검색은 목록이 본문이고, 질문은 글이 본문이며
  /// 공고 목록은 근거로 붙는 것이다.
  final String mode;

  final String reply;
  final JobChatFilters filters;
  final List<JobChatJob> jobs;

  /// 조건에 맞는 전체 건수. `jobs`는 그중 일부다.
  final int total;

  /// 다음에 좁힐 거리. 사용자가 그대로 눌러 보낼 수 있는 말이다.
  final List<String> suggestions;

  factory JobChatResponse.fromMap(Map<String, dynamic> map) {
    final items = map['jobs'];
    return JobChatResponse(
      mode: map['mode'] as String? ?? '검색',
      reply: map['reply'] as String? ?? '',
      filters: JobChatFilters.fromMap(
        Map<String, dynamic>.from(map['filters'] as Map? ?? const {}),
      ),
      jobs: items is List
          ? items
              .whereType<Map>()
              .map((e) => JobChatJob.fromMap(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      total: (map['total'] as num?)?.toInt() ?? 0,
      suggestions: JobChatFilters._strings(map['suggestions']),
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

  /// 채용에 대해 묻고 답을 받는다. 서버가 세 갈래로 나눠 처리한다.
  ///
  /// - 직전 조건(`filters`)을 함께 보내야 "서울만" 같은 말이 이어진다.
  /// - [jobId]를 주면 그 공고 하나에 대한 물음이 된다. 서버는 조건 해석을 건너뛰고
  ///   그 공고 원문만 근거로 답한다.
  Future<JobChatResponse> chat({
    required String message,
    JobChatFilters? filters,
    int topK = 5,
    String? jobId,
  }) async {
    final decoded = await _post('/api/v1/jobs/chat', {
      'message': message,
      'filters': filters?.toJson(),
      'top_k': topK,
      'job_id': jobId,
    });
    return JobChatResponse.fromMap(decoded);
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
