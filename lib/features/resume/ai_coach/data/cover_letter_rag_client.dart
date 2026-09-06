import 'dart:convert';

import 'package:http/http.dart' as http;

/// cover_letter_rag(FastAPI) 서버 접속 설정.
///
/// 서버 주소는 빌드 시 `--dart-define=COVER_LETTER_RAG_URL=http://127.0.0.1:8001`
/// 처럼 넣는다. 비어 있으면 서버를 호출하지 않고 규칙 기반 분석만 사용한다.
/// OpenAI 키는 서버에만 두며 앱은 알지 못한다.
abstract final class CoverLetterRagConfig {
  static const baseUrl = String.fromEnvironment(
    'COVER_LETTER_RAG_URL',
    defaultValue: '',
  );

  static bool get isConfigured => baseUrl.trim().isNotEmpty;
}

class CoverLetterRagException implements Exception {
  const CoverLetterRagException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// `POST /api/v1/jobs/search` 결과 한 건.
class RagJobSearchResult {
  const RagJobSearchResult({
    required this.rank,
    required this.jobId,
    required this.company,
    required this.title,
    required this.location,
    required this.employmentType,
    required this.summary,
    required this.source,
  });

  final int rank;
  final String jobId;
  final String company;
  final String title;
  final String? location;
  final String? employmentType;
  final String summary;
  final String source;

  factory RagJobSearchResult.fromMap(Map<String, dynamic> map) {
    return RagJobSearchResult(
      rank: (map['rank'] as num?)?.toInt() ?? 0,
      jobId: map['job_id'] as String? ?? '',
      company: map['company'] as String? ?? '',
      title: map['title'] as String? ?? '',
      location: map['location'] as String?,
      employmentType: map['employment_type'] as String?,
      summary: map['summary'] as String? ?? '',
      source: map['source'] as String? ?? '',
    );
  }

  /// 첨삭 API의 `job_posting_text`에 넣을 공고 원문 형태.
  String toPostingText() {
    final meta = [
      if ((location ?? '').trim().isNotEmpty) location!.trim(),
      if ((employmentType ?? '').trim().isNotEmpty) employmentType!.trim(),
    ].join(' · ');
    return '[$company - $title]${meta.isEmpty ? '' : ' ($meta)'}\n$summary';
  }
}

/// 이력서 인용 근거. 서버가 원문 대조를 마친 뒤 돌려준 것만 담긴다.
class RagResumeEvidence {
  const RagResumeEvidence({
    required this.resumeQuote,
    required this.explanation,
  });

  final String resumeQuote;
  final String explanation;

  factory RagResumeEvidence.fromMap(Map<String, dynamic> map) {
    return RagResumeEvidence(
      resumeQuote: map['resume_quote'] as String? ?? '',
      explanation: map['explanation'] as String? ?? '',
    );
  }
}

/// 공고 요구사항 하나와 이력서 근거 비교 결과.
class RagRequirementComparison {
  const RagRequirementComparison({
    required this.requirement,
    required this.requirementType,
    required this.sourceId,
    required this.status,
    required this.resumeEvidence,
    required this.gap,
    required this.confirmationQuestion,
  });

  final String requirement;

  /// 필수 · 우대 · 업무 · 기타
  final String requirementType;
  final String sourceId;

  /// 충족 · 부분 충족 · 미충족 · 확인 필요
  final String status;
  final List<RagResumeEvidence> resumeEvidence;
  final String? gap;
  final String? confirmationQuestion;

  bool get isMet => status == '충족' || status == '부분 충족';
  bool get isNotMet => status == '미충족';
  bool get needsConfirmation => status == '확인 필요';

  factory RagRequirementComparison.fromMap(Map<String, dynamic> map) {
    return RagRequirementComparison(
      requirement: map['requirement'] as String? ?? '',
      requirementType: map['requirement_type'] as String? ?? '기타',
      sourceId: map['source_id'] as String? ?? '',
      status: map['status'] as String? ?? '확인 필요',
      resumeEvidence: _mapList(
        map['resume_evidence'],
      ).map(RagResumeEvidence.fromMap).toList(),
      gap: map['gap'] as String?,
      confirmationQuestion: map['confirmation_question'] as String?,
    );
  }
}

class RagDraftImprovement {
  const RagDraftImprovement({
    required this.issue,
    required this.suggestion,
    required this.groundedResumeQuote,
  });

  final String issue;
  final String suggestion;
  final String? groundedResumeQuote;

  factory RagDraftImprovement.fromMap(Map<String, dynamic> map) {
    return RagDraftImprovement(
      issue: map['issue'] as String? ?? '',
      suggestion: map['suggestion'] as String? ?? '',
      groundedResumeQuote: map['grounded_resume_quote'] as String?,
    );
  }
}

/// `POST /api/v1/reviews` 응답.
class RagReviewResponse {
  const RagReviewResponse({
    required this.questionIntent,
    required this.requirements,
    required this.improvements,
    required this.confirmationQuestions,
    required this.revisedDraft,
    required this.groundingWarnings,
    required this.notice,
  });

  final String questionIntent;
  final List<RagRequirementComparison> requirements;
  final List<RagDraftImprovement> improvements;
  final List<String> confirmationQuestions;
  final String revisedDraft;
  final List<String> groundingWarnings;
  final String notice;

  factory RagReviewResponse.fromMap(Map<String, dynamic> map) {
    return RagReviewResponse(
      questionIntent: map['question_intent'] as String? ?? '',
      requirements: _mapList(
        map['requirements'],
      ).map(RagRequirementComparison.fromMap).toList(),
      improvements: _mapList(
        map['improvements'],
      ).map(RagDraftImprovement.fromMap).toList(),
      confirmationQuestions: _stringList(map['confirmation_questions']),
      revisedDraft: map['revised_draft'] as String? ?? '',
      groundingWarnings: _stringList(map['grounding_warnings']),
      notice: map['notice'] as String? ?? '',
    );
  }
}

/// cover_letter_rag 서버의 기존 엔드포인트만 호출하는 얇은 클라이언트.
///
/// 서버 쪽 요청 스키마는 `extra="forbid"`라 정의된 필드만 보내야 하고,
/// 텍스트 길이 하한(이력서·공고 20자, 문항 3자, 초안 1자)도 그대로 따른다.
class CoverLetterRagClient {
  CoverLetterRagClient({
    required String baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 120),
  }) : _baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
       _http = httpClient ?? http.Client();

  final String _baseUrl;
  final http.Client _http;
  final Duration timeout;

  static const minResumeLength = 20;
  static const minJobPostingLength = 20;

  Future<List<RagJobSearchResult>> searchJobs(
    String resumeText, {
    int topK = 4,
    String? idToken,
  }) async {
    _requireLength(resumeText, minResumeLength, '이력서');
    final body = await _post('/api/v1/jobs/search', {
      'resume_text': resumeText,
      'top_k': topK.clamp(1, 10),
    }, idToken: idToken);
    return _mapList(body['results']).map(RagJobSearchResult.fromMap).toList();
  }

  Future<RagReviewResponse> review({
    required String resumeText,
    required String jobPostingText,
    required String coverLetterQuestion,
    required String draftText,
    int topK = 4,
    String? idToken,
  }) async {
    _requireLength(resumeText, minResumeLength, '이력서');
    _requireLength(jobPostingText, minJobPostingLength, '공고');
    _requireLength(coverLetterQuestion, 3, '문항');
    _requireLength(draftText, 1, '초안');
    final body = await _post('/api/v1/reviews', {
      'resume_text': resumeText,
      'job_posting_text': jobPostingText,
      'cover_letter_question': coverLetterQuestion,
      'draft_text': draftText,
      'top_k': topK.clamp(1, 10),
    }, idToken: idToken);
    return RagReviewResponse.fromMap(body);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> payload, {
    String? idToken,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    late final http.Response response;
    try {
      response = await _http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
              // 서버의 Firebase 토큰 검증은 아직 계획 단계라 지금은 무시되지만,
              // 검증이 켜졌을 때 앱을 다시 고치지 않도록 미리 보낸다.
              if (idToken != null && idToken.isNotEmpty)
                'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode(payload),
          )
          .timeout(timeout);
    } on Exception catch (error) {
      throw CoverLetterRagException('RAG 서버에 연결하지 못했습니다: $error');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CoverLetterRagException(
        _describeError(response),
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const CoverLetterRagException('RAG 서버 응답 형식이 올바르지 않습니다.');
    }
    return decoded;
  }

  static String _describeError(http.Response response) {
    String detail = '';
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded['detail'] != null) {
        detail = decoded['detail'].toString();
      }
    } catch (_) {
      // 본문이 JSON이 아니면 상태 코드만 보여준다.
    }
    return 'RAG 서버 오류 (${response.statusCode})'
        '${detail.isEmpty ? '' : ': $detail'}';
  }

  static void _requireLength(String value, int min, String label) {
    if (value.trim().length < min) {
      throw CoverLetterRagException('$label 내용이 $min자 이상이어야 합니다.');
    }
  }
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList();
}
