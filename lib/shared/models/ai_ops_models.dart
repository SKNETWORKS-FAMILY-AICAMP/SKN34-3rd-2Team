import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/date_utils.dart';

/// 루트 `aiGenerationLogs` — type discriminator
/// assessment_questions | assessment_questions_regen |
/// job_chat | job_recommend | resume_review
class AiGenerationLogModel {
  const AiGenerationLogModel({
    required this.id,
    required this.type,
    required this.promptVersion,
    required this.model,
    required this.cohortId,
    this.sheetId,
    this.dayFrom,
    this.dayTo,
    this.mcCount = 0,
    this.saCount = 0,
    this.generatedCount = 0,
    this.rowCount = 0,
    this.latencyMs = 0,
    this.status = 'success',
    this.errorMessage,
    this.createdBy,
    this.createdByName,
    this.createdAt,
    this.drafts = const [],
    this.reasoningEffort,
    this.tokenIn,
    this.tokenOut,
    this.mode,
    this.intent,
    this.topK,
    this.jobCount,
    this.appliedCount,
    this.requestIdHash,
    this.reviewMode,
  });

  final String id;
  final String type;
  final String promptVersion;
  final String model;
  final String cohortId;
  final String? sheetId;
  final int? dayFrom;
  final int? dayTo;
  final int mcCount;
  final int saCount;
  final int generatedCount;
  final int rowCount;
  final int latencyMs;
  final String status;
  final String? errorMessage;
  final String? createdBy;
  final String? createdByName;
  final DateTime? createdAt;
  final List<AiGenerationDraftPreview> drafts;
  final String? reasoningEffort;
  final int? tokenIn;
  final int? tokenOut;
  final String? mode;
  final String? intent;
  final int? topK;
  final int? jobCount;
  final int? appliedCount;
  final String? requestIdHash;
  final String? reviewMode;

  bool get isAssessment =>
      type == 'assessment_questions' || type == 'assessment_questions_regen';

  factory AiGenerationLogModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? 0;
    }

    int? toIntOrNull(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v');
    }

    final rawDrafts = data['drafts'] as List? ?? const [];
    return AiGenerationLogModel(
      id: doc.id,
      type: data['type']?.toString() ?? 'assessment_questions',
      promptVersion: data['promptVersion']?.toString() ?? '',
      model: data['model']?.toString() ?? '',
      cohortId: data['cohortId']?.toString() ?? '',
      sheetId: data['sheetId']?.toString(),
      dayFrom: data['dayFrom'] == null ? null : toInt(data['dayFrom']),
      dayTo: data['dayTo'] == null ? null : toInt(data['dayTo']),
      mcCount: toInt(data['mcCount']),
      saCount: toInt(data['saCount']),
      generatedCount: toInt(data['generatedCount']),
      rowCount: toInt(data['rowCount']),
      latencyMs: toInt(data['latencyMs']),
      status: data['status']?.toString() ?? 'success',
      errorMessage: data['errorMessage']?.toString(),
      createdBy: data['createdBy']?.toString(),
      createdByName: data['createdByName']?.toString(),
      createdAt: AppDateUtils.timestampToDateTime(data['createdAt']),
      drafts: rawDrafts
          .whereType<Map>()
          .map(
            (e) => AiGenerationDraftPreview.fromMap(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(),
      reasoningEffort: data['reasoningEffort']?.toString(),
      tokenIn: toIntOrNull(data['tokenIn']),
      tokenOut: toIntOrNull(data['tokenOut']),
      mode: data['mode']?.toString(),
      intent: data['intent']?.toString(),
      topK: toIntOrNull(data['topK']),
      jobCount: toIntOrNull(data['jobCount']),
      appliedCount: toIntOrNull(data['appliedCount']),
      requestIdHash: data['requestIdHash']?.toString(),
      reviewMode: data['reviewMode']?.toString(),
    );
  }
}

class AiGenerationDraftPreview {
  const AiGenerationDraftPreview({
    required this.draftId,
    required this.type,
    this.sourceDay,
    this.sourceTopic,
    this.promptPreview,
  });

  final String draftId;
  final String type;
  final int? sourceDay;
  final String? sourceTopic;
  final String? promptPreview;

  factory AiGenerationDraftPreview.fromMap(Map<String, dynamic> data) {
    int? toInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v');
    }

    return AiGenerationDraftPreview(
      draftId: data['draftId']?.toString() ?? '',
      type: data['type']?.toString() ?? 'mc',
      sourceDay: toInt(data['sourceDay']),
      sourceTopic: data['sourceTopic']?.toString(),
      promptPreview: data['promptPreview']?.toString(),
    );
  }
}

/// 루트 `aiQuestionFeedback`
/// outcome: adopted|edited|discarded|
/// clicked_job|followed_up|ignored|
/// opened|selected_for_review|dismissed|
/// applied|partial_apply|undone|abandoned
class AiQuestionFeedbackModel {
  const AiQuestionFeedbackModel({
    required this.id,
    required this.logId,
    required this.draftId,
    required this.cohortId,
    required this.outcome,
    this.promptVersion,
    this.assessmentId,
    this.questionId,
    this.sourceDay,
    this.sourceTopic,
    this.actorUid,
    this.createdAt,
    this.updatedAt,
    this.type,
  });

  final String id;
  final String logId;
  final String draftId;
  final String cohortId;
  final String outcome;
  final String? promptVersion;
  final String? assessmentId;
  final String? questionId;
  final int? sourceDay;
  final String? sourceTopic;
  final String? actorUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? type;

  factory AiQuestionFeedbackModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    int? toInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v');
    }

    return AiQuestionFeedbackModel(
      id: doc.id,
      logId: data['logId']?.toString() ?? '',
      draftId: data['draftId']?.toString() ?? '',
      cohortId: data['cohortId']?.toString() ?? '',
      outcome: data['outcome']?.toString() ?? '',
      promptVersion: data['promptVersion']?.toString(),
      assessmentId: data['assessmentId']?.toString(),
      questionId: data['questionId']?.toString(),
      sourceDay: toInt(data['sourceDay']),
      sourceTopic: data['sourceTopic']?.toString(),
      actorUid: data['actorUid']?.toString(),
      createdAt: AppDateUtils.timestampToDateTime(data['createdAt']),
      updatedAt: AppDateUtils.timestampToDateTime(data['updatedAt']),
      type: data['type']?.toString(),
    );
  }
}
