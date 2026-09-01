import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/date_utils.dart';

/// 월말 성취도 평가 (학습실)
class AssessmentModel {
  const AssessmentModel({
    required this.id,
    required this.title,
    required this.tags,
    required this.questionCount,
    required this.maxScore,
    required this.startAt,
    required this.endAt,
    this.problemFileUrl,
    this.problemFileName,
    this.published = false,
    this.createdAt,
  });

  final String id;
  final String title;
  final List<String> tags;
  final int questionCount;
  final int maxScore;
  final DateTime startAt;
  final DateTime endAt;
  final String? problemFileUrl;
  final String? problemFileName;
  final bool published;
  final DateTime? createdAt;

  bool get isEnded => DateTime.now().isAfter(endAt);
  bool get isUpcoming => DateTime.now().isBefore(startAt);
  bool get isActive => !isUpcoming && !isEnded;

  String get periodLabel =>
      '${AppDateUtils.formatDisplay(startAt)} ~ ${AppDateUtils.formatDisplay(endAt)}';

  String get statusLabel {
    if (!published) return '임시저장';
    if (isEnded) return '종료';
    if (isUpcoming) return '예정';
    return '진행중';
  }

  factory AssessmentModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return AssessmentModel(
      id: doc.id,
      title: data['title'] as String? ?? '',
      tags: List<String>.from(data['tags'] as List? ?? []),
      questionCount: data['questionCount'] as int? ?? 0,
      maxScore: data['maxScore'] as int? ?? 100,
      startAt: AppDateUtils.timestampToDateTime(data['startAt']) ?? DateTime.now(),
      endAt: AppDateUtils.timestampToDateTime(data['endAt']) ?? DateTime.now(),
      problemFileUrl: data['problemFileUrl'] as String?,
      problemFileName: data['problemFileName'] as String?,
      published: data['published'] as bool? ?? false,
      createdAt: AppDateUtils.timestampToDateTime(data['createdAt']),
    );
  }

  Map<String, dynamic> toFirestore({bool? published}) => {
        'title': title,
        'tags': tags,
        'questionCount': questionCount,
        'maxScore': maxScore,
        'startAt': Timestamp.fromDate(startAt),
        'endAt': Timestamp.fromDate(endAt),
        if (problemFileUrl != null) 'problemFileUrl': problemFileUrl,
        if (problemFileName != null) 'problemFileName': problemFileName,
        'published': published ?? this.published,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

class AssessmentSubmissionModel {
  const AssessmentSubmissionModel({
    required this.id,
    required this.assessmentId,
    required this.userId,
    required this.userDisplayName,
    required this.completed,
    this.answerFileUrl,
    this.answerFileName,
    this.submittedAt,
  });

  final String id;
  final String assessmentId;
  final String userId;
  final String userDisplayName;
  final bool completed;
  final String? answerFileUrl;
  final String? answerFileName;
  final DateTime? submittedAt;

  factory AssessmentSubmissionModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return AssessmentSubmissionModel(
      id: doc.id,
      assessmentId: data['assessmentId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      userDisplayName: data['userDisplayName'] as String? ?? '',
      completed: data['completed'] as bool? ?? false,
      answerFileUrl: data['answerFileUrl'] as String?,
      answerFileName: data['answerFileName'] as String?,
      submittedAt: AppDateUtils.timestampToDateTime(data['submittedAt']),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'assessmentId': assessmentId,
        'userId': userId,
        'userDisplayName': userDisplayName,
        'completed': completed,
        if (answerFileUrl != null) 'answerFileUrl': answerFileUrl,
        if (answerFileName != null) 'answerFileName': answerFileName,
        'submittedAt': FieldValue.serverTimestamp(),
      };
}
