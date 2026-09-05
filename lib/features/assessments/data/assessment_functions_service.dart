import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/assessment_model.dart';

/// 성취도 평가 Callable Functions
class AssessmentFunctionsService {
  AssessmentFunctionsService({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> getAssessmentForTake({
    required String cohortId,
    required String assessmentId,
  }) async {
    final result = await _functions.httpsCallable('getAssessmentForTake').call({
      'cohortId': cohortId,
      'assessmentId': assessmentId,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<Map<String, dynamic>> submitAssessment({
    required String cohortId,
    required String assessmentId,
    required Map<String, dynamic> answers,
  }) async {
    final result = await _functions.httpsCallable('submitAssessment').call({
      'cohortId': cohortId,
      'assessmentId': assessmentId,
      'answers': answers,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// 제출 후 리뷰용 — 정답 포함 문항 + 제출 답안
  Future<Map<String, dynamic>> getAssessmentReview({
    required String cohortId,
    required String assessmentId,
    String? submissionId,
  }) async {
    final result = await _functions.httpsCallable('getAssessmentReview').call({
      'cohortId': cohortId,
      'assessmentId': assessmentId,
      if (submissionId != null) 'submissionId': submissionId,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<Map<String, dynamic>> adjustAssessmentScores({
    required String cohortId,
    required String submissionId,
    required List<Map<String, dynamic>> adjustments,
    String? note,
  }) async {
    final result =
        await _functions.httpsCallable('adjustAssessmentScores').call({
      'cohortId': cohortId,
      'submissionId': submissionId,
      'adjustments': adjustments,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<List<AssessmentQuestionModel>> generateAssessmentQuestions({
    required String cohortId,
    required String sheetId,
    required int dayFrom,
    required int dayTo,
    int mcCount = 5,
    int saCount = 3,
    String? subjectFilter,
  }) async {
    final result = await _functions
        .httpsCallable(
          'generateAssessmentQuestions',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 300)),
        )
        .call({
      'cohortId': cohortId,
      'sheetId': sheetId,
      'dayFrom': dayFrom,
      'dayTo': dayTo,
      'mcCount': mcCount,
      'saCount': saCount,
      if (subjectFilter != null && subjectFilter.isNotEmpty)
        'subjectFilter': subjectFilter,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final raw = data['questions'] as List? ?? [];
    return raw.asMap().entries.map((e) {
      final m = Map<String, dynamic>.from(e.value as Map);
      return AssessmentQuestionModel.fromMap(
        m['id'] as String? ?? 'draft_${e.key}',
        m,
      );
    }).toList();
  }
}

final assessmentFunctionsServiceProvider =
    Provider<AssessmentFunctionsService>((ref) {
  return AssessmentFunctionsService();
});
