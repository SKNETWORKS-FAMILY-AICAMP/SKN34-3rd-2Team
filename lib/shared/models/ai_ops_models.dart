import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/date_utils.dart';

/// 루트 `aiGenerationLogs` — type discriminator로 확장
/// (assessment_questions → wrong_answer_recommend 등)
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

  factory AiGenerationLogModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? 0;
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
/// outcome 확장 예정: clicked | ignored (오답→추천)
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
    );
  }
}
